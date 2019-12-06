import 'package:flutter/material.dart';

import 'audio_player.dart';
import 'audio_player_view.dart';
import 'utils.dart';

/// Created by cnting on 2019-12-05
///
class DefaultPlayControllerWidget extends StatefulWidget {
  final bool allowScrubbing;

  const DefaultPlayControllerWidget({this.allowScrubbing});

  @override
  _DefaultPlayControllerWidgetState createState() => _DefaultPlayControllerWidgetState();
}

class _DefaultPlayControllerWidgetState extends State<DefaultPlayControllerWidget> {
  final double _barHeight = 50;
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
      return Container();
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _buildPlayPause(),
          _buildPosition(),
          _buildProgressBar()
        ],
      ),
    );
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  ///播放暂停按钮
  Widget _buildPlayPause() {
    return GestureDetector(
      onTap: _playPause,
      child: Container(
        height: _barHeight,
        color: Colors.transparent,
        margin: EdgeInsets.only(right: 4.0),
        child: Icon(
          _controller.value.isPlaying
              ? Icons.pause_circle_filled
              : Icons.play_circle_filled,
          size: 40,
        ),
      ),
    );
  }

  void _playPause() {
    setState(() {
      if (_latestValue.isPlaying) {
        _controller.pause();
      } else {
        if (!_latestValue.initialized) {
          _controller.initialize().then((_) {
            _controller.play();
          });
        } else {
          _controller.play();
        }
      }
    });
  }

  ///时长
  Widget _buildPosition() {
    final position = _latestValue != null && _latestValue.position != null
        ? _latestValue.position
        : Duration.zero;
    final duration = _latestValue != null && _latestValue.duration != null
        ? _latestValue.duration
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
  Widget _buildProgressBar() {
    return Expanded(
      child: AudioProgressIndicator(
        _controller,
        padding: EdgeInsets.zero,
        colors:
            AudioProgressColors(playedColor: Theme.of(context).primaryColor),
        allowScrubbing: widget.allowScrubbing ?? true,
      ),
    );
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
