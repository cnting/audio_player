### 1. create

##### flutter ====> 原生

* asset类型：
  * asset：文件名称
  * package：包名，要拿别的应用的文件时才用
  * clipRange：播放片段，传入开始和结束的**毫秒**时间
  * loopingTimes：设置播放次数。小于0表示一直播放
* file：
  * uri：文件地址
  * clipRange
  * loopingTimes
* network：同file

##### 原生 ====> flutter

* playerId的生成保证唯一即可，可以是毫秒时间戳、uuid等。不要使用Texture，关于Texture可以看[这里](https://juejin.im/post/5b7b9051e51d45388b6aeceb)
* 设置EventChannel：`cnting.com/audio_player/audioEvents$playId`
* 创建完成需要返回`playerId`