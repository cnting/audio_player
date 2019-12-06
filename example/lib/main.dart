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
    audioPlayerController = AudioPlayerController.network(
        'https://webfs.yun.kugou.com/201912060956/7b29de9dd3f89d4139a2957eab384c9b/G132/M08/11/01/ZJQEAFsYxiWAbsJdAEexGAxvqAc720.mp3');
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
