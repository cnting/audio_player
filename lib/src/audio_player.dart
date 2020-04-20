import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final MethodChannel _channel = const MethodChannel('cnting.com/audio_player')
  ..invokeMethod<void>('init');

class DownloadState {
  static const int UNDOWNLOAD = 0;
  static const int DOWNLOADING = 1;
  static const int COMPLETED = 2;
  static const int ERROR = 3;

  DownloadState(this.state, {this.progress});

  final int state;
  final double progress;
}

class DownloadNotifier extends ValueNotifier<DownloadState> {
  DownloadNotifier(DownloadState value) : super(value);
}


class DurationRange {
  DurationRange(this.start, this.end);

  factory DurationRange.fromValue(dynamic value) {
    List<dynamic> pair = value;
    return DurationRange.fromList(pair);
  }

  factory DurationRange.fromList(List<int> value) {
    assert(value.length >= 1 &&
        value[0] >= 0, 'invalid DurationRange:$value');

    //如果只传入开始时间，则播放到音频末尾
    if (value.length == 1) {
      value.add(-1);
    }

    return DurationRange(
        Duration(milliseconds: value[0]), Duration(milliseconds: value[1]));
  }

  final Duration start;
  final Duration end;

  double startFraction(Duration duration) {
    return start.inMilliseconds / duration.inMilliseconds;
  }

  double endFraction(Duration duration) {
    return end.inMilliseconds / duration.inMilliseconds;
  }

  @override
  String toString() => '$runtimeType(start: $start, end: $end)';

  List<dynamic> toList() {
    return [start.inMilliseconds, end.inMilliseconds];
  }

  static DurationRange toDurationRange(dynamic value) {
    final List<dynamic> pair = value;
    return DurationRange(
      Duration(milliseconds: pair[0]),
      Duration(milliseconds: pair[1]),
    );
  }
}

class AudioPlayerValue {
  AudioPlayerValue({@required this.duration,
    this.position = const Duration(),
    this.buffered = const <DurationRange>[],
    this.isPlaying = false,
    this.isLooping = false,
    this.isBuffering = false,
    this.volume = 1.0,
    this.speed = 1.0,
    this.errorDescription});

  AudioPlayerValue.uninitialized() : this(duration: null);

  AudioPlayerValue.erroneous(Duration duration, String errorDescription)
      : this(duration: null, errorDescription: errorDescription);

  /// The total duration of the audio.
  ///
  /// Is null when [initialized] is false.
  final Duration duration;

  /// The current playback position.
  final Duration position;

  /// The currently buffered ranges.
  final List<DurationRange> buffered;

  /// True if the audio is playing. False if it's paused.
  final bool isPlaying;

  /// True if the audio is looping.
  final bool isLooping;

  /// True if the audio is currently buffering.
  final bool isBuffering;

  /// The current volume of the playback.
  final double volume;

  ///速度
  final double speed;

  /// A description of the error if present.
  ///
  /// If [hasError] is false this is [null].
  final String errorDescription;

  bool get initialized => duration != null;

  bool get hasError => errorDescription != null;

  AudioPlayerValue copyWith({Duration duration,
    Duration position,
    List<DurationRange> buffered,
    bool isPlaying,
    bool isLooping,
    bool isBuffering,
    double volume,
    double speed,
    String errorDescription,
    bool forceSetErrorDescription = false}) {
    return AudioPlayerValue(
      duration: duration ?? this.duration,
      position: position ?? this.position,
      buffered: buffered ?? this.buffered,
      isPlaying: isPlaying ?? this.isPlaying,
      isLooping: isLooping ?? this.isLooping,
      isBuffering: isBuffering ?? this.isBuffering,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      errorDescription: forceSetErrorDescription
          ? errorDescription
          : (errorDescription ?? this.errorDescription),
    );
  }

  @override
  String toString() {
    return '$runtimeType('
        'duration: $duration, '
        'position: $position, '
        'buffered: [${buffered.join(', ')}], '
        'isPlaying: $isPlaying, '
        'isLooping: $isLooping, '
        'isBuffering: $isBuffering,'
        'volume: $volume, '
        'errorDescription: $errorDescription)';
  }
}

class PlayConfig {
  final bool autoInitialize;
  final bool autoPlay;
  final Duration startAt;
  final DurationRange clipRange; //play clip media
  final int loopingTimes;
  final bool autoCache;

  const PlayConfig({
    this.autoPlay = true,
    this.autoInitialize = true,
    this.startAt,
    this.clipRange,
    this.loopingTimes = 0,
    this.autoCache = false
  })
      : assert(startAt == null || clipRange == null,
  'Cannot provide both startAt and clipRange')
  ;
}

enum DataSourceType { asset, network, file }

class DataSource {
  String _sourcePath;
  DataSourceType _dataSourceType;
  String _package;

  DataSource._(this._sourcePath, this._dataSourceType, this._package);

  DataSource.asset(String dataSource, {String package}) :this._(dataSource, DataSourceType.asset, package);

  DataSource.file(String dataSource) :this._(dataSource, DataSourceType.file, null);

  DataSource.network(String dataSource) :this._(dataSource, DataSourceType.network, null);
}

class AudioPlayerController extends ValueNotifier<AudioPlayerValue> {
  String _playerId;
  DataSource _dataSource;
  PlayConfig _playConfig;
  AudioPlayerCallback _audioPlayerCallback;
  Timer _updatePositionTimer;
  bool _isDisposed = false;
  Completer<void> _creatingCompleter;
  Completer<void> _initializingCompleter;
  StreamSubscription<dynamic> _eventSubscription;
  _AudioAppLifeCycleObserver _lifeCycleObserver;
  ValueNotifier<DownloadState> downloadNotifier = ValueNotifier(DownloadState(DownloadState.UNDOWNLOAD));

  String get playerId => _playerId;

  AudioPlayerController(this._dataSource,
      {PlayConfig playConfig = const PlayConfig(), AudioPlayerCallback audioPlayerCallback})
      : super(AudioPlayerValue(duration: null)) {
    this._playConfig = playConfig;
    this._audioPlayerCallback = audioPlayerCallback;
    _tryInitialize();
  }

  Future _tryInitialize() async {
    if ((_playConfig.autoInitialize || _playConfig.autoPlay) &&
        !value.initialized) {
      await initialize();
    }
    if (value.initialized && _playConfig.startAt != null) {
      await seekTo(_playConfig.startAt);
    }
    if (_playConfig.autoPlay == true) {
      await play();
    }
  }

  Future resetDataSource(DataSource dataSource,
      {PlayConfig playConfig = const PlayConfig(), AudioPlayerCallback audioPlayerCallback}) async {
    assert(_playerId != null, 'please call constructor first!');
    // do reset
    this.value = AudioPlayerValue.uninitialized();
    this._dataSource = dataSource;
    this._playConfig = playConfig ?? this._playConfig;
    this._audioPlayerCallback = audioPlayerCallback ?? this._audioPlayerCallback;

    _creatingCompleter = Completer<void>();
    _initializingCompleter = Completer<void>();

    var params = _getDataSourceDescription();
    params.putIfAbsent('playerId', () => _playerId);
    final Map<String, dynamic> response =
    await _channel.invokeMapMethod<String, dynamic>(
      'reset',
      params,
    );
    _creatingCompleter.complete(null);
    await _initializingCompleter.future;

    if (value.initialized && playConfig.startAt != null) {
      await seekTo(playConfig.startAt);
    }
    if (playConfig.autoPlay == true) {
      await play();
    }
  }

  Future<void> initialize() async {
    _lifeCycleObserver = _AudioAppLifeCycleObserver(this);
    _lifeCycleObserver.initialize();
    _creatingCompleter = Completer<void>();

    final Map<String, dynamic> response =
    await _channel.invokeMapMethod<String, dynamic>(
      'create',
      _getDataSourceDescription(),
    );

    _playerId = response['playerId'];
    _creatingCompleter.complete(null);
    _initializingCompleter = Completer<void>();

    void errorListener(Object obj) {
      final PlatformException e = obj;
      if (value == null) {
        value = AudioPlayerValue.erroneous(null, e.message);
      } else {
        value = value.copyWith(isPlaying: false, errorDescription: e.message);
      }

      _cancelUpdatePositionTimer();
    }

    _eventSubscription = _eventChannelFor(_playerId)
        .receiveBroadcastStream()
        .listen(eventListener, onError: errorListener);
    return _initializingCompleter.future;
  }

  void eventListener(dynamic event) {
    if (_isDisposed) {
      return;
    }

    final Map<dynamic, dynamic> map = event;
    switch (map['event']) {
      case 'initialized':
        value = value.copyWith(
            duration: Duration(milliseconds: map['duration']),
            errorDescription: null,
            forceSetErrorDescription: true);
        _initializingCompleter.complete(null);
        _applyLooping();
        _applyVolume();
        _applyPlayPause(value.isPlaying);
        break;
      case 'completed':
        value = value.copyWith(isPlaying: false, position: value.duration);
        if (_audioPlayerCallback?.onPlayComplete != null) {
          _audioPlayerCallback?.onPlayComplete();
        }
        _cancelUpdatePositionTimer();
        break;
      case 'bufferingUpdate':
        final List<dynamic> values = map['values'];
        value =
            value.copyWith(buffered: [DurationRange.toDurationRange(values)]);
        break;
      case 'bufferingStart':
        value = value.copyWith(
          isBuffering: true,
        );
        break;
      case 'bufferingEnd':
        value = value.copyWith(
          isBuffering: false,
        );
        break;
      case 'playStateChanged':
        final bool isPlaying = map['isPlaying'];

        if (isPlaying && !(_updatePositionTimer?.isActive ?? false)) {
          _startUpdatePositionTimer();
        } else if (!isPlaying) {
          _cancelUpdatePositionTimer();
        }
        value = value.copyWith(
            isPlaying: isPlaying,
            errorDescription: null,
            forceSetErrorDescription: true);
        if (_audioPlayerCallback?.onPlayStateChange != null) {
          _audioPlayerCallback?.onPlayStateChange(value);
        }
        break;
      case 'downloadState':
        final int state = map['state'];
        double progress = map['progress'];
        downloadNotifier.value = DownloadState(state, progress: progress);
        break;
    }
  }

  Map<dynamic, dynamic> _getDataSourceDescription() {
    Map<dynamic, dynamic> dataSourceDescription;
    switch (_dataSource._dataSourceType) {
      case DataSourceType.asset:
        dataSourceDescription = <String, dynamic>{
          'asset': _dataSource._sourcePath,
          'package': _dataSource._package
        };
        break;
      case DataSourceType.network:
        dataSourceDescription = <String, dynamic>{'uri': _dataSource._sourcePath};
        break;
      case DataSourceType.file:
        dataSourceDescription = <String, dynamic>{'uri': _dataSource._sourcePath};
    }
    dataSourceDescription.addAll(<String, dynamic>{
      if (_playConfig.clipRange != null)
        'clipRange': _playConfig.clipRange.toList(),
      if (_playConfig.loopingTimes != null)
        'loopingTimes': _playConfig.loopingTimes,
      if(_playConfig.autoCache != null)
        'autoCache': _playConfig.autoCache
    });
    return dataSourceDescription;
  }

  EventChannel _eventChannelFor(String playerId) {
    return EventChannel('cnting.com/audio_player/audioEvents$playerId');
  }

  @override
  Future<void> dispose() async {
    if (_creatingCompleter != null) {
      await _creatingCompleter.future;
      if (!_isDisposed) {
        _isDisposed = true;
        _cancelUpdatePositionTimer();
        await _eventSubscription?.cancel();
        await _channel.invokeMethod<void>(
          'dispose',
          <String, dynamic>{'playerId': _playerId},
        );
      }
      _lifeCycleObserver.dispose();
    }
    _isDisposed = true;
    downloadNotifier?.dispose();
    super.dispose();
  }

  Future<void> play({bool autoInitial = false}) async {
    if (autoInitial && value.initialized != true) {
      await initialize();
    }
    await _applyPlayPause(true);
  }

  Future<void> setLooping(bool looping) async {
    value = value.copyWith(isLooping: looping);
    await _applyLooping();
  }

  Future<void> pause() async {
    await _applyPlayPause(false);
  }

  Future<void> _applyLooping() async {
    if (!value.initialized || _isDisposed) {
      return;
    }
    _channel.invokeMethod<void>(
      'setLooping',
      <String, dynamic>{'playerId': _playerId, 'looping': value.isLooping},
    );
  }

  Future<void> _applyPlayPause(bool isPlay) async {
    if (!value.initialized || _isDisposed) {
      return;
    }
    if (isPlay) {
      await _channel.invokeMethod<void>(
        'play',
        <String, dynamic>{'playerId': _playerId},
      );
    } else {
      _cancelUpdatePositionTimer();
      await _channel.invokeMethod<void>(
        'pause',
        <String, dynamic>{'playerId': _playerId},
      );
    }
  }

  _startUpdatePositionTimer() {
    _updatePositionTimer = Timer.periodic(
      const Duration(milliseconds: 500),
          (Timer timer) async {
        if (_isDisposed) {
          return;
        }
        final Duration newPosition = await position;
        if (_isDisposed) {
          return;
        }
        value = value.copyWith(position: newPosition);
      },
    );
  }

  _cancelUpdatePositionTimer() {
    _updatePositionTimer?.cancel();
  }

  Future<void> _applyVolume() async {
    if (!value.initialized || _isDisposed) {
      return;
    }
    await _channel.invokeMethod<void>(
      'setVolume',
      <String, dynamic>{'playerId': _playerId, 'volume': value.volume},
    );
  }

  /// The position in the current audio.
  Future<Duration> get position async {
    if (_isDisposed) {
      return null;
    }
    return Duration(
      milliseconds: await _channel.invokeMethod<int>(
        'position',
        <String, dynamic>{'playerId': _playerId},
      ),
    );
  }

  Future<void> seekTo(Duration moment) async {
    if (_isDisposed) {
      return;
    }
    if (moment > value.duration) {
      moment = value.duration;
    } else if (moment < const Duration()) {
      moment = const Duration();
    }
    await _channel.invokeMethod<void>('seekTo', <String, dynamic>{
      'playerId': _playerId,
      'location': moment.inMilliseconds,
    });
    value = value.copyWith(position: moment);
  }

  /// Sets the audio volume of [this].
  /// [volume] indicates a value between 0.0 (silent) and 1.0 (full volume) on a
  /// linear scale.
  Future<void> setVolume(double volume) async {
    value = value.copyWith(volume: volume.clamp(0.0, 1.0));
    await _applyVolume();
  }

  ///设置倍速
  Future<void> setSpeed(double speed) async {
    if (!value.initialized || _isDisposed) {
      return null;
    }
    value = value.copyWith(speed: speed);
    await _channel.invokeMethod<void>(
      'setSpeed',
      <String, dynamic>{'playerId': _playerId, 'speed': speed},
    );
  }

  ///下载
  Future<void> download(String name) async {
    await _channel.invokeMethod<void>(
      'download',
      <String, dynamic>{
        'playerId': _playerId,
        'name': name
      },
    );
  }

  ///删除下载
  Future<void> removeDownload() async {
    await _channel.invokeMethod<void>(
      'removeDownload',
      <String, dynamic>{
        'playerId': _playerId,
      },
    );
  }
}

class _AudioAppLifeCycleObserver extends Object with WidgetsBindingObserver {
  _AudioAppLifeCycleObserver(this._controller);

  bool _wasPlayingBeforePause = false;
  final AudioPlayerController _controller;

  void initialize() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        if (!Platform.isIOS) {
          _wasPlayingBeforePause = _controller.value.isPlaying;
          _controller.pause();
        }
        break;
      case AppLifecycleState.resumed:
        if (!Platform.isIOS) {
          if (_wasPlayingBeforePause) {
            _controller.play();
          }
        }
        break;
      default:
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}


class AudioPlayerCallback {
  AudioPlayerCallback({this.onPlayComplete, this.onPlayStateChange});

  VoidCallback onPlayComplete;
  Function(AudioPlayerValue) onPlayStateChange;
}