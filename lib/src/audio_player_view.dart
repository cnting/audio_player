import 'package:audio_player/src/audio_player_contoller_view.dart';
import 'package:flutter/material.dart';

import 'audio_player.dart';

/// Created by cnting on 2019-12-05
///
class AudioPlayer extends StatefulWidget {
  AudioPlayer(this.controller, {this.playController});

  final AudioPlayerController controller;
  final Widget? playController;

  @override
  _AudioPlayerState createState() => _AudioPlayerState();
}

class _AudioPlayerState extends State<AudioPlayer> {
  _AudioPlayerState() {
    _listener = () {
      final String? newPlayerId = widget.controller.playerId;
      if (newPlayerId != _playerId) {
        setState(() {
          _playerId = newPlayerId;
        });
      }
    };
  }

  late VoidCallback _listener;
  String? _playerId;

  @override
  void initState() {
    super.initState();
    _playerId = widget.controller.playerId;
    widget.controller.addListener(_listener);
  }

  @override
  void didUpdateWidget(AudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.controller.removeListener(_listener);
    _playerId = widget.controller.playerId;
    widget.controller.addListener(_listener);
  }

  @override
  void deactivate() {
    super.deactivate();
    widget.controller.removeListener(_listener);
  }

  @override
  Widget build(BuildContext context) {
    return
//      _playerId == null
//        ? Container(
//            child: Text('playId为空'),
//            )
//        :
        AudioPlayerControllerProvider(
      controller: widget.controller,
      child: widget.playController ?? DefaultPlayControllerWidget(),
    );
  }
}

class AudioPlayerControllerProvider extends InheritedWidget {
  final AudioPlayerController controller;

  const AudioPlayerControllerProvider(
      {Key? key, required this.controller, required Widget child})
      : super(key: key, child: child);

  @override
  bool updateShouldNotify(AudioPlayerControllerProvider oldWidget) {
    return oldWidget.controller != controller;
  }

  static AudioPlayerController? of(BuildContext context) {
    AudioPlayerControllerProvider? provider =
        context.findAncestorWidgetOfExactType();
    return provider?.controller;
  }
}

class AudioProgressColors {
  AudioProgressColors({
    this.playedColor = const Color.fromRGBO(120, 120, 255, 0.7),
    this.bufferedColor = const Color.fromRGBO(50, 50, 200, 0.2),
    this.backgroundColor = const Color.fromRGBO(200, 200, 200, 0.5),
  });

  final Color playedColor;
  final Color bufferedColor;
  final Color backgroundColor;
}

class AudioScrubber extends StatefulWidget {
  AudioScrubber({
    required this.child,
    required this.controller,
  });

  final Widget child;
  final AudioPlayerController controller;

  @override
  _AudioScrubberState createState() => _AudioScrubberState();
}

class _AudioScrubberState extends State<AudioScrubber> {
  bool _controllerWasPlaying = false;

  AudioPlayerController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    void seekToRelativePosition(Offset globalPosition) {
      final RenderBox box = context.findRenderObject() as RenderBox;
      final Offset tapPos = box.globalToLocal(globalPosition);
      final double relative = tapPos.dx / box.size.width;
      final Duration position = controller.value.duration! * relative;
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
    AudioProgressColors? colors,
    this.allowScrubbing = true,
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

  late VoidCallback listener;

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
      final int duration = controller.value.duration!.inMilliseconds;
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
      return AudioScrubber(
        child: paddedProgressIndicator,
        controller: controller,
      );
    } else {
      return paddedProgressIndicator;
    }
  }
}
