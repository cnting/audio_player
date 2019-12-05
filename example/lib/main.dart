import 'package:flutter/material.dart';
import 'package:audio_player/audio.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AudioPlayerController audioPlayerController;

  @override
  void initState() {
    super.initState();
    audioPlayerController = AudioPlayerController.network('http://audio04.dmhmusic.com/71_53_T10038816745_128_4_1_0_sdk-cpm/cn/0208/M00/E4/A0/ChR461172N6AXz4YAD_5Qa6UpzU759.mp3?xcode=8fe9e6abd2f1b33f5812077614fde6c013bb4bf');
  }

  @override
  void dispose() {
    audioPlayerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: AudioPlayer(audioPlayerController),
        ),
      ),
    );
  }
}
