package com.cnting.audio_player

import android.content.Context
import android.net.Uri
import com.cnting.audio_player.download.AudioDownloadManager
import com.cnting.audio_player.download.AudioDownloadService
import com.cnting.audio_player.download.AudioDownloadTracker
import com.cnting.audio_player.download.GpDownloadState
import com.google.android.exoplayer2.*
import com.google.android.exoplayer2.audio.AudioAttributes
import com.google.android.exoplayer2.offline.Download
import com.google.android.exoplayer2.offline.DownloadRequest
import com.google.android.exoplayer2.offline.DownloadService
import com.google.android.exoplayer2.source.ClippingMediaSource
import com.google.android.exoplayer2.source.LoopingMediaSource
import com.google.android.exoplayer2.source.MediaSource
import com.google.android.exoplayer2.source.ProgressiveMediaSource
import com.google.android.exoplayer2.trackselection.AdaptiveTrackSelection
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.Registrar
import io.flutter.view.FlutterMain
import java.util.*

class AudioPlayerPlugin() : FlutterPlugin, MethodCallHandler {

    private var audioPlayers = mutableMapOf<String, AudioPlayer>()

    private var flutterState: FlutterState? = null
    private var channel: MethodChannel? = null

    companion object {
        const val channelName = "cnting.com/audio_player"

        @JvmStatic
        fun registerWith(registrar: Registrar) {
            val instance = AudioPlayerPlugin(registrar)
            registrar.addViewDestroyListener {
                instance.onDestory()
                false
            }
        }
    }

    private val audioDownloadManager: AudioDownloadManager by lazy {
        val manager = AudioDownloadManager.getInstance(flutterState!!.applicationContext)
        manager
    }

    private constructor(registrar: Registrar) : this() {
        this.flutterState = FlutterState(
            registrar.context(),
            registrar.messenger(),
            registrar::lookupKeyForAsset,
            registrar::lookupKeyForAsset
        )
        this.channel = MethodChannel(registrar.messenger(), channelName)
        channel?.setMethodCallHandler(this)
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.flutterState = FlutterState(
            binding.applicationContext,
            binding.binaryMessenger,
            { assets: String? -> FlutterMain.getLookupKeyForAsset(assets!!) },
            { asset: String?, packageName: String? ->
                FlutterMain.getLookupKeyForAsset(
                    asset!!,
                    packageName!!
                )
            }
        )
        this.channel = MethodChannel(binding.flutterEngine.dartExecutor, channelName)
        this.channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        onDestory()
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
                val eventChannel = EventChannel(
                    flutterState!!.binaryMessenger,
                    "cnting.com/audio_player/audioEvents$id"
                )
                val player: AudioPlayer
                var clipRange: List<Long>? = null
                if (call.argument<Any?>("clipRange") != null) {
                    clipRange = call.argument<List<Long>>("clipRange")
                }
                val loopingTimes = call.argument<Int>("loopingTimes") ?: 0
                val dataSource: String = getDataSource(call)
                player = AudioPlayer(
                    flutterState!!.applicationContext,
                    id,
                    eventChannel = eventChannel,
                    dataSource = dataSource,
                    result = result,
                    clipRange = clipRange?.toMutableList(),
                    loopingTimes = loopingTimes,
                    audioDownloadManager = audioDownloadManager
                )
                audioPlayers[id] = player
//                val autoCache = call.argument<Boolean>("autoCache") ?: false
//                player.initDownloadState(autoCache)
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
                flutterState!!.keyForAssetAndPackageName(
                    call.argument("asset"),
                    call.argument("package")
                )
            } else {
                flutterState!!.keyForAsset(call.argument("asset"))
            }
            "asset:///$assetLookupKey"
        } else {
            call.argument<String>("uri")!!
        }
    }

    private fun checkPlayerId(playerId: String, result: Result, next: (AudioPlayer) -> Unit) {
        val audioPlayer = audioPlayers[playerId]
        if (audioPlayer == null) {
            result.error(
                "Unknown playerId",
                "No audio player associated with player id $playerId",
                null
            )
            return
        }
        next(audioPlayer)
    }

    private fun onMethodCall(
        call: MethodCall,
        result: Result,
        playerId: String,
        player: AudioPlayer
    ) {
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

class AudioPlayer(
    c: Context, private val playerId: String, private val eventChannel: EventChannel,
    dataSource: String, private val result: Result, val clipRange: MutableList<Long>?,
    private var loopingTimes: Int = 0, private val audioDownloadManager: AudioDownloadManager
) {

    private lateinit var exoPlayer: ExoPlayer
    private val eventSink = QueuingEventSink()
    private var dataSourceUri: Uri = Uri.parse(dataSource)
    private var context: Context = c.applicationContext
    private var isInitialized = false
    private var refreshProgressTimer: Timer? = null

    init {
        setupAudioPlayer()
    }

    private fun setupAudioPlayer() {
        val renderersFactory = AudioOnlyRenderersFactory(context)
        exoPlayer = ExoPlayer.Builder(context, renderersFactory)
            .setTrackSelector(DefaultTrackSelector(context, AdaptiveTrackSelection.Factory()))
            .build()
        exoPlayer.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                .build(), true
        )

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

    fun reset(
        dataSource: String, clipRange: List<Long>? = null,
        loopingTimes: Int = 0
    ) {
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
            mediaSource = ClippingMediaSource(
                mediaSource,
                clipRange[0] * 1000,
                if (clipRange[1] < 0) C.TIME_END_OF_SOURCE else clipRange[1] * 1000
            )  //传入微秒
        }

        //set looping times
        if (loopingTimes > 0) {
            exoPlayer.setMediaSources(List(loopingTimes) { mediaSource })
        } else if (loopingTimes < 0) {
            exoPlayer.repeatMode = Player.REPEAT_MODE_ALL
            exoPlayer.setMediaSource(mediaSource)
        }else{
            exoPlayer.setMediaSource(mediaSource)
        }

        exoPlayer.prepare()
    }

    private fun buildMediaSource(): MediaSource {
        return ProgressiveMediaSource.Factory(audioDownloadManager.localDataSourceFactory)
            .createMediaSource(MediaItem.fromUri(dataSourceUri))
    }

    private fun addExoPlayerListener() {
        var lastPlaybackState: Int = Player.STATE_IDLE
        exoPlayer.addListener(object : Player.Listener {
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
                        if (lastPlaybackState != playbackState) {
                            val event: MutableMap<String, Any> = HashMap()
                            event["event"] = "completed"
                            eventSink.success(event)
                        }
                    }
                }
                lastPlaybackState = playbackState
            }

            override fun onPlayerError(error: PlaybackException) {
                error.printStackTrace()
                eventSink.error("AudioError", "Audio player had error $error", error?.message)
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
        val downloadRequest = DownloadRequest.Builder(playerId, dataSourceUri)
            .build()
        DownloadService.sendAddDownload(
            context,
            AudioDownloadService::class.java,
            downloadRequest,
            true
        )
        startRefreshProgressTask()
    }

    fun removeDownload() {
        val download = audioDownloadManager.downloadTracker.getDownload(dataSourceUri)
        if (download != null) {
            DownloadService.sendRemoveDownload(
                context,
                AudioDownloadService::class.java,
                download.request.id,
                false
            )
            audioDownloadManager.downloadTracker.addListener(object :
                AudioDownloadTracker.Listener {
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
                val download: Download? =
                    audioDownloadManager.downloadTracker.getDownload(dataSourceUri)
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


private class FlutterState constructor(
    val applicationContext: Context,
    val binaryMessenger: BinaryMessenger,
    val keyForAsset: (asset: String?) -> String?,
    val keyForAssetAndPackageName: (asset: String?, packageName: String?) -> String?
) {
//        fun startListening(methodCallHandler: io.flutter.plugins.videoplayer.VideoPlayerPlugin?, messenger: BinaryMessenger?) {
//            VideoPlayerApi.setup(messenger, methodCallHandler)
//        }
//
//        fun stopListening(messenger: BinaryMessenger?) {
//            VideoPlayerApi.setup(messenger, null)
//        }

}
