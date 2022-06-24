import 'package:audio_player/audio.dart';
import 'package:flutter/material.dart';

import 'custom_controller.dart';

void main() => runApp(MyApp());

String url = 'http://music.163.com/song/media/outer/url?id=20110049.mp3';

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
            _Item('simple', [_Simple()]),
            _Item('play clip range has end time', [_Clip(true)]),
            _Item('play clip range no end time', [_Clip(false)]),
            _Item('custom ui', [_CustomController()]),
            _Item('listen download', [_DownloadItem()]),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Item(this.title, this.children);

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
        ...children,
        Divider(
          color: Colors.grey[600],
        ),
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
  late AudioPlayerController audioPlayerController;

  @override
  void initState() {
    super.initState();
    audioPlayerController = AudioPlayerController(DataSource.network(url), playConfig: PlayConfig(autoPlay: false));
    audioPlayerController.addListener(() {
      print('===>listener:${audioPlayerController.value}');
    });
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

class _DownloadStateWidget extends StatefulWidget {
  final AudioPlayerController audioPlayerController;

  const _DownloadStateWidget(this.audioPlayerController);

  @override
  _DownloadStateWidgetState createState() => _DownloadStateWidgetState();
}

class _DownloadStateWidgetState extends State<_DownloadStateWidget> {
  int downloadState = DownloadState.UNDOWNLOAD;
  double downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    widget.audioPlayerController.downloadNotifier.addListener(() {
      setState(() {
        downloadState = widget.audioPlayerController.downloadNotifier.value.state ?? 0;
        downloadProgress = widget.audioPlayerController.downloadNotifier.value.progress ?? 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    var text;
    if (downloadState == DownloadState.UNDOWNLOAD) {
      text = Text('点击下载');
    } else if (downloadState == DownloadState.COMPLETED) {
      text = Text('下载完成，点击删除');
    } else if (downloadState == DownloadState.ERROR) {
      text = Text('下载失败，点击重下');
    } else {
      text = Text('下载进度:$downloadProgress');
    }
    return ElevatedButton(
      child: text,
      onPressed: () {
        if (downloadState == DownloadState.UNDOWNLOAD || downloadState == DownloadState.ERROR) {
          widget.audioPlayerController.download('正在下载音频...');
        } else if (downloadState == DownloadState.COMPLETED) {
          widget.audioPlayerController.removeDownload();
        }
      },
    );
  }
}

///播放片段
class _Clip extends StatefulWidget {
  final bool hasEndTime;

  const _Clip(this.hasEndTime);

  @override
  _ClipState createState() => _ClipState();
}

class _ClipState extends State<_Clip> {
  late AudioPlayerController audioPlayerController;

  @override
  void initState() {
    super.initState();
    audioPlayerController = AudioPlayerController(DataSource.network(url),
        playConfig: PlayConfig(
            clipRange: DurationRange.fromList([5 * 1000, if (widget.hasEndTime) 10 * 1000]),
            autoPlay: false,
            loopingTimes: 2));
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
  late AudioPlayerController audioPlayerController;

  @override
  void initState() {
    super.initState();
    audioPlayerController =
        AudioPlayerController(DataSource.asset('assets/Utakata.mp3'), playConfig: PlayConfig(autoPlay: false));
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

///listen download state
class _DownloadItem extends StatefulWidget {
  @override
  _DownloadItemState createState() => _DownloadItemState();
}

class _DownloadItemState extends State<_DownloadItem> {
  late AudioPlayerController audioPlayerController;

  @override
  void initState() {
    super.initState();
    audioPlayerController = AudioPlayerController(DataSource.network(url),
        playConfig: PlayConfig(autoPlay: false, autoCache: true)); //set auto cache
  }

  @override
  void dispose() {
    audioPlayerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        AudioPlayer(
          audioPlayerController,
        ),
        _DownloadStateWidget(audioPlayerController)
      ],
    );
  }
}
