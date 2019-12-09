package com.cnting.audio_player

import android.content.Context
import android.net.Uri
import android.util.Log
import com.google.android.exoplayer2.*
import com.google.android.exoplayer2.audio.AudioAttributes
import com.google.android.exoplayer2.source.BaseMediaSource
import com.google.android.exoplayer2.source.ClippingMediaSource
import com.google.android.exoplayer2.source.LoopingMediaSource
import com.google.android.exoplayer2.source.ProgressiveMediaSource
import com.google.android.exoplayer2.trackselection.AdaptiveTrackSelection
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector
import com.google.android.exoplayer2.upstream.DataSource
import com.google.android.exoplayer2.upstream.DefaultDataSourceFactory
import com.google.android.exoplayer2.upstream.DefaultHttpDataSource
import com.google.android.exoplayer2.upstream.DefaultHttpDataSourceFactory
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.Registrar
import java.util.*

class AudioPlayerPlugin(private val registrar: Registrar) : MethodCallHandler {

    private var audioPlayers = mutableMapOf<Long, AudioPlayer>()

    companion object {
        @JvmStatic
        fun registerWith(registrar: Registrar) {
            val plugin = AudioPlayerPlugin(registrar)
            val channel = MethodChannel(registrar.messenger(), "cnting.com/audio_player")
            channel.setMethodCallHandler(plugin)
            registrar.addViewDestroyListener {
                plugin.onDestory()
                false
            }
        }
    }

    private fun onDestory() {
        disposeAllPlayers()
    }

    private fun disposeAllPlayers() {
        audioPlayers.values.forEach { it.dispose() }
        audioPlayers.clear()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "init" -> disposeAllPlayers()
            "create" -> {
                val id = System.currentTimeMillis()
                val eventChannel = EventChannel(registrar.messenger(), "cnting.com/audio_player/audioEvents$id")
                val player: AudioPlayer
                var clipRange: List<Long>? = null
                if (call.argument<Any?>("clipRange") != null) {
                    clipRange = call.argument<List<Long>>("clipRange")
                }
                val loopingTimes = call.argument<Int>("loopingTimes") ?: 0
                if (call.argument<Any?>("asset") != null) {
                    val assetLookupKey = if (call.argument<Any?>("package") != null) {
                        registrar.lookupKeyForAsset(call.argument("asset"), call.argument("package"))
                    } else {
                        registrar.lookupKeyForAsset(call.argument("asset"))
                    }
                    player = AudioPlayer(
                            registrar.context(),
                            id,
                            eventChannel,
                            "asset:///$assetLookupKey", result, clipRange, loopingTimes
                    )
                    audioPlayers[id] = player
                } else {
                    player = AudioPlayer(
                            registrar.context(), id, eventChannel, call.argument<String>("uri")!!, result, clipRange, loopingTimes)
                    audioPlayers[id] = player
                }
            }
            else -> {
                val playerId = call.argument<Long>("playerId") ?: 0
                val audioPlayer = audioPlayers[playerId]
                if (audioPlayer == null) {
                    result.error("Unknown playerId",
                            "No audio player associated with player id $playerId",
                            null)
                    return
                }
                onMethodCall(call, result, playerId, audioPlayer)
            }
        }
    }

    private fun onMethodCall(call: MethodCall, result: Result, playerId: Long, player: AudioPlayer) {
        when (call.method) {
            "setLooping" -> {
                player.setLooping(call.argument<Boolean>("looping")!!)
                result.success(null)
            }
            "setVolume" -> {
                player.setVolume(call.argument<Double>("volume")!!)
                result.success(null)
            }
            "play" -> {
                player.play()
                result.success(null)
            }
            "pause" -> {
                player.pause()
                result.success(null)
            }
            "seekTo" -> {
                val location: Int = (call.argument<Any>("location") as Number?)?.toInt() ?: 0
                player.seekTo(location)
                result.success(null)
            }
            "position" -> {
                result.success(player.getPosition())
                player.sendBufferingUpdate()
            }
            "dispose" -> {
                player.dispose()
                audioPlayers.remove(playerId)
                result.success(null)
            }
            "setSpeed" -> {
                val speed: Double = (call.argument<Any>("speed") as Number?)?.toDouble() ?: 0.0
                player.setSpeed(speed)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

}

class AudioPlayer(c: Context, private val playerId: Long, private val eventChannel: EventChannel,
                  dataSource: String, private val result: Result, private val clipRange: List<Long>?,
                  private val loopingTimes: Int = 0) {

    private lateinit var exoPlayer: SimpleExoPlayer
    private lateinit var dataSourceFactory: DataSource.Factory
    private val eventSink = QueuingEventSink()
    private var dataSourceUri: Uri = Uri.parse(dataSource)
    private var context: Context = c.applicationContext
    private var isInitialized = false

    init {
        setupAudioPlayer()
    }

    private fun setupAudioPlayer() {
        // TODO: LoadControl可以自定义缓冲策略
        val renderersFactory = AudioOnlyRenderersFactory(context)
        exoPlayer = ExoPlayerFactory.newSimpleInstance(context, renderersFactory, DefaultTrackSelector(AdaptiveTrackSelection.Factory()))
        exoPlayer.setAudioAttributes(AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.CONTENT_TYPE_MUSIC)
                .build(), true)
        dataSourceFactory = if (isFileOrAsset(dataSourceUri)) {
            DefaultDataSourceFactory(context, "ExoPlayer")
        } else {
            DefaultHttpDataSourceFactory("ExoPlayer", null, DefaultHttpDataSource.DEFAULT_CONNECT_TIMEOUT_MILLIS,
                    DefaultHttpDataSource.DEFAULT_READ_TIMEOUT_MILLIS, true)
        }
        val mediaSourceFactory =
                ProgressiveMediaSource.Factory(dataSourceFactory)
        var mediaSource: BaseMediaSource = mediaSourceFactory.createMediaSource(dataSourceUri)

        //set clip range
        if (clipRange != null) {
            mediaSource = ClippingMediaSource(mediaSource, clipRange[0] * 1000, clipRange[1] * 1000)  //传入微秒
        }

        //set looping times
        if (loopingTimes > 0) {
            mediaSource = LoopingMediaSource(mediaSource, loopingTimes)
        } else if (loopingTimes < 0) {
            exoPlayer.repeatMode = Player.REPEAT_MODE_ALL
        }

        exoPlayer.prepare(mediaSource)

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(p0: Any?, sink: EventChannel.EventSink?) {
                eventSink.setDelegate(sink)
            }

            override fun onCancel(p0: Any?) {
                eventSink.setDelegate(null)
            }
        })
        addExoPlayerListener()

        val event: MutableMap<String, Any> = HashMap()
        event["playerId"] = playerId
        result.success(event)
    }

    private fun addExoPlayerListener() {
        exoPlayer.addListener(object : Player.EventListener {
            override fun onPlayerStateChanged(playWhenReady: Boolean, playbackState: Int) {
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        sendBufferingStart()
                        sendBufferingUpdate()
                    }
                    Player.STATE_READY -> {
                        sendBufferingEnd()
                        sendPlayStateChange(playWhenReady)
                        if (!isInitialized) {
                            isInitialized = true
                            sendInitialized()
                        }
                    }
                    Player.STATE_ENDED -> {
                        val event: MutableMap<String, Any> = HashMap()
                        event["event"] = "completed"
                        eventSink.success(event)
                    }
                }
            }

            override fun onPlayerError(error: ExoPlaybackException?) {
                eventSink?.error("AudioError", "Audio player had error $error", error?.message)
            }

        })
    }

    private fun isFileOrAsset(uri: Uri?): Boolean {
        if (uri == null || uri.scheme == null) {
            return false
        }
        return uri.scheme == "file" || uri.scheme == "asset"
    }

    private fun sendBufferingStart() {
        val event: MutableMap<String, Any> = HashMap()
        event["event"] = "bufferingStart"
        eventSink.success(event)
    }

    private fun sendBufferingEnd() {
        val event: MutableMap<String, Any> = HashMap()
        event["event"] = "bufferingEnd"
        eventSink.success(event)
    }

    fun sendBufferingUpdate() {
        val event: MutableMap<String, Any> = HashMap()
        event["event"] = "bufferingUpdate"
        // iOS supports a list of buffered ranges, so here is a list with a single range.
        event["values"] = listOf<Number>(0, exoPlayer.bufferedPosition)
        eventSink.success(event)
    }

    private fun sendPlayStateChange(playWhenReady: Boolean) {
        val event: MutableMap<String, Any> = HashMap()
        event["event"] = "playStateChanged"
        event["isPlaying"] = playWhenReady
        eventSink.success(event)
    }

    fun play() {
        if (exoPlayer.playbackState == Player.STATE_IDLE) {
            exoPlayer.retry()
        } else if (exoPlayer.playbackState == Player.STATE_ENDED) {
            seekTo(0)
        }
        exoPlayer.playWhenReady = true
    }

    fun pause() {
        exoPlayer.playWhenReady = false
    }

    fun setLooping(value: Boolean) {
        exoPlayer.repeatMode = if (value) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
    }

    fun setVolume(value: Double) {
        val bracketedValue = value.coerceAtMost(1.0).coerceAtLeast(0.0).toFloat()
        exoPlayer.volume = bracketedValue
    }

    fun seekTo(location: Int) {
        exoPlayer.seekTo(location.toLong())
    }

    fun getPosition(): Long {
        return exoPlayer.currentPosition
    }

    private fun sendInitialized() {
        if (isInitialized) {
            val event: MutableMap<String, Any> = HashMap()
            event["event"] = "initialized"
            event["duration"] = exoPlayer.duration
            eventSink.success(event)
        }
    }

    fun dispose() {
        if (isInitialized) {
            exoPlayer.stop()
        }
        eventChannel.setStreamHandler(null)
        exoPlayer?.release()
    }

    fun setSpeed(speed: Double) {
        if (!isInitialized) {
            return
        }
        val playbackParameters = PlaybackParameters(speed.toFloat())
        exoPlayer.playbackParameters = playbackParameters
    }
}
