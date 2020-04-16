package com.cnting.audio_player

import android.content.Context
import android.net.Uri
import android.util.Log
import com.cnting.audio_player.download.AudioDownloadManager
import com.cnting.audio_player.download.AudioDownloadService
import com.cnting.audio_player.download.AudioDownloadTracker
import com.cnting.audio_player.download.GpDownloadState
import com.google.android.exoplayer2.*
import com.google.android.exoplayer2.audio.AudioAttributes
import com.google.android.exoplayer2.offline.Download
import com.google.android.exoplayer2.offline.DownloadRequest
import com.google.android.exoplayer2.offline.DownloadService
import com.google.android.exoplayer2.offline.StreamKey
import com.google.android.exoplayer2.source.ClippingMediaSource
import com.google.android.exoplayer2.source.LoopingMediaSource
import com.google.android.exoplayer2.source.MediaSource
import com.google.android.exoplayer2.source.ProgressiveMediaSource
import com.google.android.exoplayer2.trackselection.AdaptiveTrackSelection
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.Registrar
import java.util.*

class AudioPlayerPlugin(private val registrar: Registrar) : MethodCallHandler {

    private var audioPlayers = mutableMapOf<String, AudioPlayer>()
    private val audioDownloadManager: AudioDownloadManager = AudioDownloadManager.getInstance(registrar.activeContext().applicationContext)

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
                val id = System.currentTimeMillis().toString()
                val eventChannel = EventChannel(registrar.messenger(), "cnting.com/audio_player/audioEvents$id")
                val player: AudioPlayer
                var clipRange: List<Long>? = null
                if (call.argument<Any?>("clipRange") != null) {
                    clipRange = call.argument<List<Long>>("clipRange")
                }
                val loopingTimes = call.argument<Int>("loopingTimes") ?: 0
                val dataSource: String = getDataSource(call)
                player = AudioPlayer(
                        registrar.context(),
                        id,
                        eventChannel = eventChannel,
                        dataSource = dataSource,
                        result = result,
                        clipRange = clipRange?.toMutableList(),
                        loopingTimes = loopingTimes,
                        audioDownloadManager = audioDownloadManager
                )
                audioPlayers[id] = player
                val autoCache = call.argument<Boolean>("autoCache")?:false
                player.initDownloadState(autoCache)
            }
            "reset" -> {
                val playerId: String = call.argument<String>("playerId") ?: "0"
                checkPlayerId(playerId, result) { player ->
                    var clipRange: List<Long>? = null
                    if (call.argument<Any?>("clipRange") != null) {
                        clipRange = call.argument<List<Long>>("clipRange")
                    }
                    val loopingTimes = call.argument<Int>("loopingTimes") ?: 0
                    val dataSource: String = getDataSource(call)
                    player.reset(dataSource, clipRange, loopingTimes)
                    // TODO: 这里需要看下
                    val autoCache = call.argument<Boolean>("autoCache") ?: false
                    player.initDownloadState(autoCache)
                }
                result.success(null)
            }
            else -> {
                val playerId: String = call.argument<String>("playerId") ?: "0"
                checkPlayerId(playerId, result) {
                    onMethodCall(call, result, playerId, it)
                }
            }
        }
    }

    private fun getDataSource(call: MethodCall): String {
        return if (call.argument<Any?>("asset") != null) {
            val assetLookupKey = if (call.argument<Any?>("package") != null) {
                registrar.lookupKeyForAsset(call.argument("asset"), call.argument("package"))
            } else {
                registrar.lookupKeyForAsset(call.argument("asset"))
            }
            "asset:///$assetLookupKey"
        } else {
            call.argument<String>("uri")!!
        }
    }

    private fun checkPlayerId(playerId: String, result: Result, next: (AudioPlayer) -> Unit) {
        val audioPlayer = audioPlayers[playerId]
        if (audioPlayer == null) {
            result.error("Unknown playerId",
                    "No audio player associated with player id $playerId",
                    null)
            return
        }
        next(audioPlayer)
    }

    private fun onMethodCall(call: MethodCall, result: Result, playerId: String, player: AudioPlayer) {
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
            "download" -> {
                val name = call.argument<String>("name") ?: ""
                player.doDownload(name)
                result.success(null)
            }
            "removeDownload" -> {
                player.removeDownload()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

}

class AudioPlayer(c: Context, private val playerId: String, private val eventChannel: EventChannel,
                  dataSource: String, private val result: Result, val clipRange: MutableList<Long>?,
                  private var loopingTimes: Int = 0, private val audioDownloadManager: AudioDownloadManager) {

    private lateinit var exoPlayer: SimpleExoPlayer
    private val eventSink = QueuingEventSink()
    private var dataSourceUri: Uri = Uri.parse(dataSource)
    private var context: Context = c.applicationContext
    private var isInitialized = false
    private var refreshProgressTimer: Timer? = null

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

        resetMediaSource()

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

    fun reset(dataSource: String, clipRange: List<Long>? = null,
              loopingTimes: Int = 0) {
        exoPlayer.stop(true)
        this.dataSourceUri = Uri.parse(dataSource)
        this.clipRange?.clear()
        if (clipRange != null) {
            this.clipRange?.addAll(clipRange)
        }
        this.loopingTimes = loopingTimes
        this.isInitialized = false

        resetMediaSource()
    }

    private fun resetMediaSource() {
        var mediaSource = buildMediaSource()

        //set clip range
        if (clipRange != null) {
            mediaSource = ClippingMediaSource(mediaSource, clipRange[0] * 1000, if (clipRange[1] < 0) C.TIME_END_OF_SOURCE else clipRange[1] * 1000)  //传入微秒
        }

        //set looping times
        if (loopingTimes > 0) {
            mediaSource = LoopingMediaSource(mediaSource, loopingTimes)
        } else if (loopingTimes < 0) {
            exoPlayer.repeatMode = Player.REPEAT_MODE_ALL
        }

        exoPlayer.prepare(mediaSource)
    }

    private fun buildMediaSource(): MediaSource {
        return ProgressiveMediaSource.Factory(audioDownloadManager.localDataSourceFactory)
                .createMediaSource(dataSourceUri)
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
                error?.printStackTrace()
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
        exoPlayer.release()
        refreshProgressTimer?.cancel()
    }

    fun setSpeed(speed: Double) {
        if (!isInitialized) {
            return
        }
        val playbackParameters = PlaybackParameters(speed.toFloat())
        exoPlayer.playbackParameters = playbackParameters
    }

    fun doDownload(downloadNotificationName: String) {
        if (isFileOrAsset(dataSourceUri)) {
            return
        }
        val downloadRequest = DownloadRequest(playerId.toString(), DownloadRequest.TYPE_PROGRESSIVE, dataSourceUri, mutableListOf<StreamKey>(), null, downloadNotificationName.toByteArray())
        DownloadService.sendAddDownload(context, AudioDownloadService::class.java, downloadRequest, false)
        startRefreshProgressTask()
    }

    fun removeDownload() {
        val download = audioDownloadManager.downloadTracker.getDownload(dataSourceUri)
        if (download != null) {
            DownloadService.sendRemoveDownload(context, AudioDownloadService::class.java, download.request.id, false)
            audioDownloadManager.downloadTracker.addListener(object : AudioDownloadTracker.Listener {
                override fun onDownloadsChanged() {
                    if (audioDownloadManager.downloadTracker.getDownloadState(dataSourceUri) == Download.STATE_QUEUED) {
                        sendDownloadState()
                        audioDownloadManager.downloadTracker.removeListener(this)
                    }
                }
            })
        }
    }

    fun initDownloadState(autoCache: Boolean) {
        val download = sendDownloadState()
        if (autoCache && download?.state != Download.STATE_DOWNLOADING && download?.state != Download.STATE_COMPLETED) {
            doDownload("")
        }
        if (download != null) { //如果在STATE_DOWNLOADING状态，直到下载完成onDownloadsChanged才会回调，所以不能用startRefreshProgressTask()方法
            startRefreshProgressTimer(null)
        }
    }

    private fun sendDownloadState(): Download? {
        val download: Download? = audioDownloadManager.downloadTracker.getDownload(dataSourceUri)
        val event: MutableMap<String, Any> = HashMap()
        event["event"] = "downloadState"
        when (download?.state ?: Download.STATE_QUEUED) {
            Download.STATE_COMPLETED -> {
                event["state"] = GpDownloadState.COMPLETED
            }
            Download.STATE_DOWNLOADING -> {
                event["state"] = GpDownloadState.DOWNLOADING
                event["progress"] = download!!.percentDownloaded
            }
            Download.STATE_FAILED -> {
                event["state"] = GpDownloadState.ERROR
            }
            else -> {
                event["state"] = GpDownloadState.UNDOWNLOAD
            }
        }
        eventSink.success(event)
        return download
    }

    private fun startRefreshProgressTask() {
        var isRunTask = false
        audioDownloadManager.downloadTracker.addListener(object : AudioDownloadTracker.Listener {
            override fun onDownloadsChanged() {
                if (!isRunTask) {
                    startRefreshProgressTimer(this);
                    isRunTask = false
                }
            }
        })
    }

    private fun startRefreshProgressTimer(listener: AudioDownloadTracker.Listener?) {
        refreshProgressTimer?.cancel()
        refreshProgressTimer = Timer()
        val timerTask: TimerTask = object : TimerTask() {
            override fun run() {
                val download: Download? = audioDownloadManager.downloadTracker.getDownload(dataSourceUri)
                sendDownloadState()
                if (download != null && download.isTerminalState) {
                    cancelRefreshProgressTimer()
                    if (listener != null) {
                        audioDownloadManager.downloadTracker.removeListener(listener)
                    }
                }
            }
        }
        refreshProgressTimer?.schedule(timerTask, 1000, 1000)
    }

    private fun cancelRefreshProgressTimer() {
        if (refreshProgressTimer != null) {
            refreshProgressTimer!!.cancel()
            refreshProgressTimer = null
        }
    }
}
