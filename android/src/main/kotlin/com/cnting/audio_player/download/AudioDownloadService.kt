package com.cnting.audio_player.download

import android.app.Notification
import android.content.Context
import com.cnting.audio_player.R
import com.google.android.exoplayer2.offline.Download
import com.google.android.exoplayer2.offline.DownloadManager
import com.google.android.exoplayer2.offline.DownloadService
import com.google.android.exoplayer2.scheduler.PlatformScheduler
import com.google.android.exoplayer2.scheduler.Scheduler
import com.google.android.exoplayer2.ui.DownloadNotificationHelper
import com.google.android.exoplayer2.util.NotificationUtil
import com.google.android.exoplayer2.util.Util
import java.lang.Exception

/**
 * Created by cnting on 2019-08-05
 * 下载
 */
class AudioDownloadService : DownloadService(
        1,
        DEFAULT_FOREGROUND_NOTIFICATION_UPDATE_INTERVAL,
        "download_channel",
        R.string.download_channel_name,
        R.string.download_channel_name_description
) {

    private val JOB_ID = 1

    override fun getDownloadManager(): DownloadManager {
        val notificationHelper = AudioDownloadManager.getInstance(applicationContext).downloadNotificationHelper
        val downloadManager = AudioDownloadManager.getInstance(applicationContext).downloadManager
        downloadManager.addListener(TerminalStateNotificationHelper(this,notificationHelper))
        return downloadManager
    }

    override fun getScheduler(): Scheduler? {
        return if (Util.SDK_INT >= 21) PlatformScheduler(this, JOB_ID) else null
    }

    override fun getForegroundNotification(downloads: MutableList<Download>): Notification {
        val notificationHelper = AudioDownloadManager.getInstance(applicationContext).downloadNotificationHelper
        return notificationHelper.buildProgressNotification(this,android.R.drawable.stat_sys_download, null, null, downloads)
    }
}

class TerminalStateNotificationHelper(
    private val context: Context,
    private val notificationHelper: DownloadNotificationHelper
) : DownloadManager.Listener {
    private val FOREGROUND_NOTIFICATION_ID = 1
    private var nextNotificationId = FOREGROUND_NOTIFICATION_ID + 1

    override fun onDownloadChanged(
        downloadManager: DownloadManager,
        download: Download,
        finalException: Exception?
    ) {
        val notification: Notification = when (download.state) {
            Download.STATE_COMPLETED -> notificationHelper.buildDownloadCompletedNotification(
                context,
                android.R.drawable.stat_sys_download_done,
                /* contentIntent= */ null,
                Util.fromUtf8Bytes(download.request.data)
            )/* contentIntent= */
            Download.STATE_FAILED -> notificationHelper.buildDownloadFailedNotification(
                context,
                android.R.drawable.stat_notify_error, null,
                Util.fromUtf8Bytes(download.request.data)
            )
            else -> return
        }
        NotificationUtil.setNotification(context, nextNotificationId++, notification)
    }
}
 