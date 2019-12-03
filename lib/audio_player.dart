import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final MethodChannel _channel = const MethodChannel('audio_player')
  ..invokeMethod<void>('init');

class DurationRange {
  DurationRange(this.start, this.end);

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

enum DataSourceType { asset, network, file }

class AudioPlayerController extends ValueNotifier<AudioPlayerValue> {
  AudioPlayerController.asset(this.dataSource, {this.package})
      : dataSourceType = DataSourceType.asset,
        super(AudioPlayerValue(duration: null));

  AudioPlayerController.network(this.dataSource)
      : dataSourceType = DataSourceType.network,
        package = null,
        super(AudioPlayerValue(duration: null));

  AudioPlayerController.file(File file)
      : dataSource = 'file://${file.path}',
        dataSourceType = DataSourceType.file,
        package = null,
        super(AudioPlayerValue(duration: null));

  int _textureId;
  final String dataSource;

  final DataSourceType dataSourceType;

  final String package;
  Timer _timer;
  bool _isDisposed = false;
  Completer<void> _creatingCompleter;
  StreamSubscription<dynamic> _eventSubscription;
  _AudioAppLifeCycleObserver _lifeCycleObserver;

  @visibleForTesting
  int get textureId => _textureId;

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
    final Map<String, dynamic> response =
        await _channel.invokeMapMethod<String, dynamic>(
      'create',
      dataSourceDescription,
    );
    _textureId = response['textureId'];
    _creatingCompleter.complete(null);
    final Completer<void> initializingCompleter = Completer<void>();

    DurationRange toDurationRange(dynamic value) {
      final List<dynamic> pair = value;
      return DurationRange(
        Duration(milliseconds: pair[0]),
        Duration(milliseconds: pair[1]),
      );
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
          initializingCompleter.complete(null);
          _applyLooping();
          _applyVolume();
          _applyPlayPause(value.isPlaying);
          break;
        case 'completed':
          value = value.copyWith(isPlaying: false, position: value.duration);
          _cancelTimer();
          break;
        case 'bufferingUpdate':
          final List<dynamic> values = map['values'];
          value = value.copyWith(
              buffered: values.map<DurationRange>(toDurationRange).toList());
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

          if (isPlaying && !(_timer?.isActive ?? false)) {
            _startTimer();
          } else if (!isPlaying) {
            _cancelTimer();
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

      _cancelTimer();
    }

    _eventSubscription = _eventChannelFor(_textureId)
        .receiveBroadcastStream()
        .listen(eventListener, onError: errorListener);
    return initializingCompleter.future;
  }

  EventChannel _eventChannelFor(int textureId) {
    return EventChannel('audioPlayer/audioEvents$textureId');
  }

  @override
  Future<void> dispose() async {
    if (_creatingCompleter != null) {
      await _creatingCompleter.future;
      if (!_isDisposed) {
        _isDisposed = true;
        _cancelTimer();
        await _eventSubscription?.cancel();
        await _channel.invokeMethod<void>(
          'dispose',
          <String, dynamic>{'textureId': _textureId},
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
      <String, dynamic>{'textureId': _textureId, 'looping': value.isLooping},
    );
  }

  Future<void> _applyPlayPause(bool isPlay) async {
    if (!value.initialized || _isDisposed) {
      return;
    }
    if (isPlay) {
      await _channel.invokeMethod<void>(
        'play',
        <String, dynamic>{'textureId': _textureId},
      );
    } else {
      _cancelTimer();
      await _channel.invokeMethod<void>(
        'pause',
        <String, dynamic>{'textureId': _textureId},
      );
    }
  }

  _startTimer() {
    _timer = Timer.periodic(
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

  _cancelTimer() {
    _timer?.cancel();
  }

  Future<void> _applyVolume() async {
    if (!value.initialized || _isDisposed) {
      return;
    }
    await _channel.invokeMethod<void>(
      'setVolume',
      <String, dynamic>{'textureId': _textureId, 'volume': value.volume},
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
        <String, dynamic>{'textureId': _textureId},
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
      'textureId': _textureId,
      'location': moment.inMilliseconds,
    });
    value = value.copyWith(position: moment);
  }

  /// Sets the audio volume of [this].
  ///
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
      <String, dynamic>{'textureId': _textureId, 'speed': speed},
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

class AudioPlayer extends StatefulWidget {
  AudioPlayer(this.controller);

  final AudioPlayerController controller;

  @override
  _AudioPlayerState createState() => _AudioPlayerState();
}

class _AudioPlayerState extends State<AudioPlayer> {
  _AudioPlayerState() {
    _listener = () {
      final int newTextureId = widget.controller.textureId;
      if (newTextureId != _textureId) {
        setState(() {
          _textureId = newTextureId;
        });
      }
    };
  }

  VoidCallback _listener;
  int _textureId;

  @override
  void initState() {
    super.initState();
    _textureId = widget.controller.textureId;
    // Need to listen for initialization events since the actual texture ID
    // becomes available after asynchronous initialization finishes.
    widget.controller.addListener(_listener);
  }

  @override
  void didUpdateWidget(AudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.controller.removeListener(_listener);
    _textureId = widget.controller.textureId;
    widget.controller.addListener(_listener);
  }

  @override
  void deactivate() {
    super.deactivate();
    widget.controller.removeListener(_listener);
  }

  @override
  Widget build(BuildContext context) {
    return _textureId == null ? Container() : Texture(textureId: _textureId);
  }
}

class AudioProgressColors {
  AudioProgressColors({
    this.playedColor = const Color.fromRGBO(255, 0, 0, 0.7),
    this.bufferedColor = const Color.fromRGBO(50, 50, 200, 0.2),
    this.backgroundColor = const Color.fromRGBO(200, 200, 200, 0.5),
  });

  final Color playedColor;
  final Color bufferedColor;
  final Color backgroundColor;
}

class _AudioScrubber extends StatefulWidget {
  _AudioScrubber({
    @required this.child,
    @required this.controller,
  });

  final Widget child;
  final AudioPlayerController controller;

  @override
  _AudioScrubberState createState() => _AudioScrubberState();
}

class _AudioScrubberState extends State<_AudioScrubber> {
  bool _controllerWasPlaying = false;

  AudioPlayerController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    void seekToRelativePosition(Offset globalPosition) {
      final RenderBox box = context.findRenderObject();
      final Offset tapPos = box.globalToLocal(globalPosition);
      final double relative = tapPos.dx / box.size.width;
      final Duration position = controller.value.duration * relative;
      controller.seekTo(position);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      child: widget.child,
      onHorizontalDragStart: (DragStartDetails details) {
        if (!controller.value.initialized) {
          return;
        }
        _controllerWasPlaying = controller.value.isPlaying;
        if (_controllerWasPlaying) {
          controller.pause();
        }
      },
      onHorizontalDragUpdate: (DragUpdateDetails details) {
        if (!controller.value.initialized) {
          return;
        }
        seekToRelativePosition(details.globalPosition);
      },
      onHorizontalDragEnd: (DragEndDetails details) {
        if (_controllerWasPlaying) {
          controller.play();
        }
      },
      onTapDown: (TapDownDetails details) {
        if (!controller.value.initialized) {
          return;
        }
        seekToRelativePosition(details.globalPosition);
      },
    );
  }
}

class AudioProgressIndicator extends StatefulWidget {
  AudioProgressIndicator(
    this.controller, {
    AudioProgressColors colors,
    this.allowScrubbing,
    this.padding = const EdgeInsets.only(top: 5.0),
  }) : colors = colors ?? AudioProgressColors();

  final AudioPlayerController controller;
  final AudioProgressColors colors;
  final bool allowScrubbing;
  final EdgeInsets padding;

  @override
  _AudioProgressIndicatorState createState() => _AudioProgressIndicatorState();
}

class _AudioProgressIndicatorState extends State<AudioProgressIndicator> {
  _AudioProgressIndicatorState() {
    listener = () {
      if (!mounted) {
        return;
      }
      setState(() {});
    };
  }

  VoidCallback listener;

  AudioPlayerController get controller => widget.controller;

  AudioProgressColors get colors => widget.colors;

  @override
  void initState() {
    super.initState();
    controller.addListener(listener);
  }

  @override
  void deactivate() {
    controller.removeListener(listener);
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    Widget progressIndicator;
    if (controller.value.initialized) {
      final int duration = controller.value.duration.inMilliseconds;
      final int position = controller.value.position.inMilliseconds;

      int maxBuffering = 0;
      for (DurationRange range in controller.value.buffered) {
        final int end = range.end.inMilliseconds;
        if (end > maxBuffering) {
          maxBuffering = end;
        }
      }

      progressIndicator = Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          LinearProgressIndicator(
            value: maxBuffering / duration,
            valueColor: AlwaysStoppedAnimation<Color>(colors.bufferedColor),
            backgroundColor: colors.backgroundColor,
          ),
          LinearProgressIndicator(
            value: position / duration,
            valueColor: AlwaysStoppedAnimation<Color>(colors.playedColor),
            backgroundColor: Colors.transparent,
          ),
        ],
      );
    } else {
      progressIndicator = LinearProgressIndicator(
        value: null,
        valueColor: AlwaysStoppedAnimation<Color>(colors.playedColor),
        backgroundColor: colors.backgroundColor,
      );
    }
    final Widget paddedProgressIndicator = Padding(
      padding: widget.padding,
      child: progressIndicator,
    );
    if (widget.allowScrubbing) {
      return _AudioScrubber(
        child: paddedProgressIndicator,
        controller: controller,
      );
    } else {
      return paddedProgressIndicator;
    }
  }
}
