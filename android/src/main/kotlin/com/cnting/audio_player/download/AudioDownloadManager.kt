package com.cnting.audio_player.download

import android.annotation.SuppressLint
import android.content.Context
import com.google.android.exoplayer2.database.DatabaseProvider
import com.google.android.exoplayer2.database.ExoDatabaseProvider
import com.google.android.exoplayer2.offline.DefaultDownloadIndex
import com.google.android.exoplayer2.offline.DefaultDownloaderFactory
import com.google.android.exoplayer2.offline.DownloadManager
import com.google.android.exoplayer2.offline.DownloaderConstructorHelper
import com.google.android.exoplayer2.upstream.*
import com.google.android.exoplayer2.upstream.cache.*
import com.google.android.exoplayer2.util.Util
import java.io.File

/**
 * Created by cnting on 2019-08-05
 *
 */
class AudioDownloadManager private constructor(private val context: Context) {

    private val DOWNLOAD_CONTENT_DIRECTORY = "audio_downloads"
    private val userAgent = Util.getUserAgent(context, "ExoPlayerDemo")

    companion object {
        @SuppressLint("StaticFieldLeak")
        @Volatile
        private var instance: AudioDownloadManager? = null

        fun getInstance(context: Context) = instance ?: synchronized(this) {
            instance ?: AudioDownloadManager(context).also { instance = it }
        }
    }


    val downloadManager: DownloadManager by lazy {
        val downloadIndex = DefaultDownloadIndex(databaseProvider)
        val downloaderConstructorHelper = DownloaderConstructorHelper(downloadCache, buildHttpDataSourceFactory)
        val downloadManager = DownloadManager(
                context, downloadIndex, DefaultDownloaderFactory(downloaderConstructorHelper)
        )
        downloadManager
    }

    val downloadTracker: AudioDownloadTracker by lazy {
        val downloadTracker = AudioDownloadTracker(downloadManager)
        downloadTracker
    }

    private val databaseProvider: DatabaseProvider by lazy {
        val p = ExoDatabaseProvider(context)
        p
    }

    private val downloadDirectory: File by lazy {
        var directionality = context.getExternalFilesDir(null)
        if (directionality == null) {
            directionality = context.filesDir
        }
        directionality!!
    }

    private val downloadCache: Cache by lazy {
        val downloadContentDirectory = File(downloadDirectory, DOWNLOAD_CONTENT_DIRECTORY)
        val downloadCache = SimpleCache(downloadContentDirectory, NoOpCacheEvictor(), databaseProvider)
        downloadCache
    }

    private val buildHttpDataSourceFactory: HttpDataSource.Factory by lazy {
        val factory = DefaultHttpDataSourceFactory(userAgent)
        factory
    }

    val localDataSourceFactory:DataSource.Factory by lazy {
        val upstreamFactory = DefaultDataSourceFactory(context, buildHttpDataSourceFactory)
        val factory = buildReadOnlyCacheDataSource(upstreamFactory, downloadCache)
        factory
    }

    private fun buildReadOnlyCacheDataSource(
            upstreamFactory: DataSource.Factory,
            cache: Cache
    ): CacheDataSourceFactory {
        return CacheDataSourceFactory(
                cache, upstreamFactory, FileDataSourceFactory(), null, CacheDataSource.FLAG_BLOCK_ON_CACHE or CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR, null
        )
    }


}