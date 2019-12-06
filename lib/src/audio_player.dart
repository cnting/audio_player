import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final MethodChannel _channel = const MethodChannel('cnting.com/audio_player')
  ..invokeMethod<void>('init');

class DurationRange {
  DurationRange(this.start, this.end);

  factory DurationRange.fromValue(dynamic value) {
    List<dynamic> pair = value;
    return DurationRange(
        Duration(milliseconds: pair[0]), Duration(milliseconds: pair[1]));
  }

  factory DurationRange.fromList(List<int> value) {
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
  AudioPlayerValue(
      {@required this.duration,
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

  AudioPlayerValue copyWith(
      {Duration duration,
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
        'isBuffering: $isBuffering'
        'volume: $volume, '
        'errorDescription: $errorDescription)';
  }
}

class PlayConfig {
  final bool autoInitialize;
  final bool autoPlay;
  final Duration startAt;
  final DurationRange clipRange; //play clip media

  const PlayConfig(
      {this.autoPlay = true,
      this.autoInitialize = true,
      this.startAt,
      this.clipRange})
      : assert(startAt == null || clipRange == null,
            'Cannot provide both startAt and clipRange');
}

enum DataSourceType { asset, network, file }

class AudioPlayerController extends ValueNotifier<AudioPlayerValue> {
  int _playerId;
  final String dataSource;
  final DataSourceType dataSourceType;
  final String package;
  final PlayConfig playConfig;
  Timer _updatePositionTimer;
  bool _isDisposed = false;
  Completer<void> _creatingCompleter;
  StreamSubscription<dynamic> _eventSubscription;
  _AudioAppLifeCycleObserver _lifeCycleObserver;

  int get playerId => _playerId;

  AudioPlayerController._(this.dataSource, this.dataSourceType,
      {this.package, this.playConfig = const PlayConfig()})
      : super(AudioPlayerValue(duration: null)) {
    _tryInitialize();
  }

  AudioPlayerController.asset(String dataSource,
      {String package, PlayConfig playConfig = const PlayConfig()})
      : this._(dataSource, DataSourceType.asset,
            package: package, playConfig: playConfig);

  AudioPlayerController.network(String dataSource,
      {PlayConfig playConfig = const PlayConfig()})
      : this._(dataSource, DataSourceType.network,
            package: null, playConfig: playConfig);

  AudioPlayerController.file(File file,
      {PlayConfig playConfig = const PlayConfig()})
      : this._('file://${file.path}', DataSourceType.file,
            package: null, playConfig: playConfig);

  Future _tryInitialize() async {
    if ((playConfig.autoInitialize || playConfig.autoPlay) &&
        !value.initialized) {
      await initialize();
    }
    if (value.initialized && playConfig.startAt != null) {
      await seekTo(playConfig.startAt);
    }
    if (playConfig.autoPlay) {
      await play();
    }
  }

  Future<void> initialize() async {
    _lifeCycleObserver = _AudioAppLifeCycleObserver(this);
    _lifeCycleObserver.initialize();
    _creatingCompleter = Completer<void>();
    Map<dynamic, dynamic> dataSourceDescription;
    switch (dataSourceType) {
      case DataSourceType.asset:
        dataSourceDescription = <String, dynamic>{
          'asset': dataSource,
          'package': package
        };
        break;
      case DataSourceType.network:
        dataSourceDescription = <String, dynamic>{'uri': dataSource};
        break;
      case DataSourceType.file:
        dataSourceDescription = <String, dynamic>{'uri': dataSource};
    }
    if (playConfig.clipRange != null) {
      dataSourceDescription.addAll(
          <String, dynamic>{'clipRange': playConfig.clipRange.toList()});
    }
    final Map<String, dynamic> response =
        await _channel.invokeMapMethod<String, dynamic>(
      'create',
      dataSourceDescription,
    );
    _playerId = response['playerId'];
    _creatingCompleter.complete(null);
    final Completer<void> initializingCompleter = Completer<void>();

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
          initializingCompleter.complete(null);
          _applyLooping();
          _applyVolume();
          _applyPlayPause(value.isPlaying);
          break;
        case 'completed':
          value = value.copyWith(isPlaying: false, position: value.duration);
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
          break;
      }
    }

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
    return initializingCompleter.future;
  }

  EventChannel _eventChannelFor(int playerId) {
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
    super.dispose();
  }

  Future<void> play() async {
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
        _wasPlayingBeforePause = _controller.value.isPlaying;
        _controller.pause();
        break;
      case AppLifecycleState.resumed:
        if (_wasPlayingBeforePause) {
          _controller.play();
        }
        break;
      default:
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
