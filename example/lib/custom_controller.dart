import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audio_player/audio.dart';

/// Created by cnting on 2019-12-05
///
class CustomPlayController extends StatefulWidget {
  @override
  _CustomPlayControllerState createState() => _CustomPlayControllerState();
}

class _CustomPlayControllerState extends State<CustomPlayController> {
  @override
  Widget build(BuildContext context) {
    return PlayControllerWidget(
       (context, AudioPlayerController controller,
          AudioPlayerValue latestValue) {
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            _buildProgressBar(controller, latestValue),
            _buildPlayPause(controller, latestValue)
          ],
        );
      },
      errorBuilder: Builder(
        builder: (context) {
          return Container();
        },
      ),
    );
  }

  ///播放暂停按钮
  Widget _buildPlayPause(
      AudioPlayerController controller, AudioPlayerValue latestValue) {
    return GestureDetector(
      onTap: () => _playPause(controller, latestValue),
      child: Container(
        height: 50,
        child: Icon(
          controller.value.isPlaying
              ? Icons.pause_circle_filled
              : Icons.play_circle_filled,
          size: 50,
        ),
      ),
    );
  }

  void _playPause(
      AudioPlayerController controller, AudioPlayerValue latestValue) {
    setState(() {
      if (latestValue.isPlaying) {
        controller.pause();
      } else {
        if (!latestValue.initialized) {
          controller.initialize().then((_) {
            controller.play();
          });
        } else {
          controller.play();
        }
      }
    });
  }

  ///进度条
  Widget _buildProgressBar(
      AudioPlayerController controller, AudioPlayerValue latestValue) {
    return Container(
      width: 70,
      height: 70,
      child: _ProgressIndicator(controller),
    );
  }
}

class _ProgressIndicator extends StatefulWidget {
  _ProgressIndicator(
    this.controller, {
    AudioProgressColors? colors,
  }) : colors = colors ?? AudioProgressColors();

  final AudioPlayerController controller;
  final AudioProgressColors colors;

  @override
  _ProgressIndicatorState createState() => _ProgressIndicatorState();
}

class _ProgressIndicatorState extends State<_ProgressIndicator> {
  _ProgressIndicatorState() {
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
      final int duration = controller.value.duration?.inMilliseconds??0;
      final int position = controller.value.position.inMilliseconds;

      int maxBuffering = 0;
      for (DurationRange range in controller.value.buffered) {
        final int end = range.end.inMilliseconds;
        if (end > maxBuffering) {
          maxBuffering = end;
        }
      }

      progressIndicator = CustomPaint(
        painter: _ProgressBarPainter(
            duration: duration,
            position: position,
            maxBuffering: maxBuffering,
            colors: widget.colors),
      );
    } else {
      progressIndicator = Container();
    }
    return progressIndicator;
  }
}

class _ProgressBarPainter extends CustomPainter {
  final int duration;
  final int position;
  final int maxBuffering;
  final AudioProgressColors colors;
  final double borderWidth;

  const _ProgressBarPainter(
      {required this.duration,
      required this.position,
      required this.maxBuffering,
      required this.colors,
      this.borderWidth = 5});

  @override
  void paint(Canvas canvas, Size size) {
    Offset center = size.center(Offset.zero);
    double radius = center.dx - borderWidth;

    Paint paint = Paint();
    paint.isAntiAlias = true;
    paint.color = colors.backgroundColor;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = borderWidth;
    canvas.drawCircle(size.center(Offset.zero), radius, paint);

    Rect rect = Rect.fromCircle(center: center, radius: radius);
    paint.color = colors.bufferedColor;
    canvas.drawArc(rect, -pi / 2, (maxBuffering / duration) * pi, false, paint);

    paint.color = colors.playedColor;
    canvas.drawArc(rect, -pi / 2, (position / duration) * pi, false, paint);
  }

  @override
  bool shouldRepaint(_ProgressBarPainter oldDelegate) {
    return oldDelegate.duration != duration ||
        oldDelegate.position != position ||
        oldDelegate.maxBuffering != maxBuffering;
  }
}
