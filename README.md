# audio_player

A Flutter plugin for android for playing audio

#### Getting Started

First, add `audio_player` as a [dependency in your pubspec.yaml file](https://flutter.io/using-packages/).

```yaml
audio_player:
  git: git@github.com:cnting/audio_player.git
```

#### Android

Ensure the following permission is present in your Android Manifest file, located in `/android/app/src/main/AndroidManifest.xml`:

```java
<uses-permission android:name="android.permission.INTERNET"/>
```

#### iOS

TODO

#### Supported Formats

* On Android,the backing player is [ExoPlayer](https://google.github.io/ExoPlayer/), please refer [here](https://google.github.io/ExoPlayer/supported-formats.html) for list of supported formats.
* On iOS,the backing player is [AVAudioPlayer](https://developer.apple.com/documentation/avfoundation/avaudioplayer)

#### Supported Functions

* play network/assets/file audio
* set looping times
* play clip range audio
* custom play controller ui

#### Example

```dart
import 'package:flutter/material.dart';
import 'package:audio_player/audio.dart';

import 'custom_controller.dart';

void main() => runApp(MyApp());

String url = 'http://music.163.com/song/media/outer/url?id=29561063.mp3';

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
            _Item('play clip range', _Clip()),
            _Item('custom ui', _CustomController()),
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
            clipRange: DurationRange.fromList([0, 10 * 1000]),
            autoPlay: false,
            loopingTimes: 2
        ));
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
    audioPlayerController = AudioPlayerController.asset('assets/Utakata.mp3',
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

```



