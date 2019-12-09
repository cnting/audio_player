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
