import 'package:flutter/material.dart';
import 'package:audio_player/audio.dart';

import 'custom_controller.dart';

void main() => runApp(MyApp());

String url =
    'https://webfs.yun.kugou.com/201912060956/7b29de9dd3f89d4139a2957eab384c9b/G132/M08/11/01/ZJQEAFsYxiWAbsJdAEexGAxvqAc720.mp3';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Audio player'),
        ),
        body: Column(
          children: <Widget>[
            _Item('simple', _Simple()),
            _Item('播放[0:00-1:00]片段', _Clip()),
            _Item('自定义视觉', _CustomController()),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final String title;
  final Widget child;

  const _Item(this.title, this.child);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(left: 8, top: 8),
          child: Text(
            title,
            style: TextStyle(color: Colors.grey),
          ),
        ),
        child,
        Divider(
          color: Colors.grey[600],
        ),
        Container()
      ],
    );
  }
}

///最简单用法
class _Simple extends StatefulWidget {
  @override
  _SimpleState createState() => _SimpleState();
}

class _SimpleState extends State<_Simple> {
  AudioPlayerController audioPlayerController;

  @override
  void initState() {
    super.initState();
    audioPlayerController = AudioPlayerController.network(url);
  }

  @override
  void dispose() {
    audioPlayerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AudioPlayer(
      audioPlayerController,
    );
  }
}

///播放片段
class _Clip extends StatefulWidget {
  @override
  _ClipState createState() => _ClipState();
}

class _ClipState extends State<_Clip> {
  AudioPlayerController audioPlayerController;

  @override
  void initState() {
    super.initState();
    audioPlayerController = AudioPlayerController.network(url,
        playConfig: PlayConfig(
            clipRange: DurationRange.fromList([0, 1 * 60 * 1000]),
            autoPlay: false));
  }

  @override
  void dispose() {
    audioPlayerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AudioPlayer(
      audioPlayerController,
      playController: DefaultPlayControllerWidget(
        allowScrubbing: false,
      ),
    );
  }
}

///自定义ui
class _CustomController extends StatefulWidget {
  @override
  _CustomControllerState createState() => _CustomControllerState();
}

class _CustomControllerState extends State<_CustomController> {
  AudioPlayerController audioPlayerController;

  @override
  void initState() {
    super.initState();
    audioPlayerController = AudioPlayerController.network(url,
        playConfig: PlayConfig(autoPlay: false));
  }

  @override
  void dispose() {
    audioPlayerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AudioPlayer(
        audioPlayerController,
        playController: CustomPlayController(),
      ),
    );
  }
}
