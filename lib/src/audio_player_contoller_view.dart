import 'package:flutter/material.dart';

import 'audio_player.dart';
import 'audio_player_view.dart';
import 'utils.dart';

/// Created by cnting on 2019-12-05
///

class PlayControllerWidget extends StatefulWidget {
  final Builder errorBuilder;
  final Widget Function(BuildContext context, AudioPlayerController controller,
      AudioPlayerValue latestValue) builder;

  const PlayControllerWidget({this.builder, this.errorBuilder});

  @override
  _PlayControllerWidgetState createState() => _PlayControllerWidgetState();
}

class _PlayControllerWidgetState extends State<PlayControllerWidget> {
  AudioPlayerValue _latestValue;
  AudioPlayerController _controller;

  @override
  void didChangeDependencies() {
    final oldController = _controller;
    _controller = AudioPlayerControllerProvider.of(context);
    if (oldController != _controller) {
      _dispose();
      _initialize();
    }
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    if (_latestValue.hasError) {
      return widget.errorBuilder ?? Container();
    }
    return widget.builder(context, _controller, _latestValue);
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  void _dispose() {
    _controller.removeListener(_updateState);
  }

  void _initialize() {
    _controller.addListener(_updateState);
    _updateState();
  }

  void _updateState() {
    setState(() {
      _latestValue = _controller.value;
    });
  }
}

class DefaultPlayControllerWidget extends StatefulWidget {
  final bool allowScrubbing;

  const DefaultPlayControllerWidget({this.allowScrubbing});

  @override
  _DefaultPlayControllerWidgetState createState() =>
      _DefaultPlayControllerWidgetState();
}

class _DefaultPlayControllerWidgetState
    extends State<DefaultPlayControllerWidget> {
  final double _barHeight = 50;

  @override
  Widget build(BuildContext context) {
    return PlayControllerWidget(
      builder: (context, AudioPlayerController controller,
          AudioPlayerValue latestValue) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _buildPlayPause(controller, latestValue),
              _buildPosition(controller, latestValue),
              _buildProgressBar(controller, latestValue)
            ],
          ),
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
        height: _barHeight,
        color: Colors.transparent,
        margin: EdgeInsets.only(right: 4.0),
        child: Icon(
          controller.value.isPlaying
              ? Icons.pause_circle_filled
              : Icons.play_circle_filled,
          size: 40,
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

  ///时长
  Widget _buildPosition(
      AudioPlayerController controller, AudioPlayerValue latestValue) {
    final position = latestValue != null && latestValue.position != null
        ? latestValue.position
        : Duration.zero;
    final duration = latestValue != null && latestValue.duration != null
        ? latestValue.duration
        : Duration.zero;

    return Padding(
      padding: const EdgeInsets.only(right: 10.0),
      child: Text(
        '${formatDuration(position)} / ${formatDuration(duration)}',
        style: TextStyle(
          fontSize: 14.0,
        ),
      ),
    );
  }

  ///进度条
  Widget _buildProgressBar(
      AudioPlayerController controller, AudioPlayerValue latestValue) {
    return Expanded(
      child: AudioProgressIndicator(
        controller,
        padding: EdgeInsets.zero,
        colors:
            AudioProgressColors(playedColor: Theme.of(context).primaryColor),
        allowScrubbing: widget.allowScrubbing ?? true,
      ),
    );
  }
}
