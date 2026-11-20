package com.noddlecake.novel_to_epub

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps Moonleaf running while books download with the app in the
 * background, showing the download's progress in a notification. Android
 * doesn't stop an app with a foreground service to reclaim memory, so the
 * download carries on with the screen off or another app open.
 */
class DownloadService : Service() {
    companion object {
        const val CHANNEL = "downloads"
        const val ID = 4107
        const val ACTION_UPDATE = "moonleaf.download.UPDATE"
        const val ACTION_CANCEL = "moonleaf.download.CANCEL"

        /** Called when the notification's Cancel is tapped. */
        var onCancel: (() -> Unit)? = null

        fun update(context: Context, title: String, text: String, done: Int, total: Int) {
            val intent = Intent(context, DownloadService::class.java)
                .setAction(ACTION_UPDATE)
                .putExtra("title", title)
                .putExtra("text", text)
                .putExtra("done", done)
                .putExtra("total", total)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DownloadService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            onCancel?.invoke()
            return START_NOT_STICKY
        }
        val notification = build(
            intent?.getStringExtra("title") ?: "Downloading",
            intent?.getStringExtra("text") ?: "",
            intent?.getIntExtra("done", 0) ?: 0,
            intent?.getIntExtra("total", 0) ?: 0,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(ID, notification)
        }
        holdWakeLock()
        // Without the app's process the download can't continue, so don't
        // restart the service on its own.
        return START_NOT_STICKY
    }

    /** Android 15 limits data-sync services to six hours a day. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    /** Keeps the processor awake between chapters, renewed with each update. */
    private fun holdWakeLock() {
        val lock = wakeLock ?: (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Moonleaf:download")
            .also { it.setReferenceCounted(false); wakeLock = it }
        lock.acquire(10 * 60 * 1000L)
    }

    private fun build(title: String, text: String, done: Int, total: Int): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(CHANNEL) == null
        ) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW)
                    .apply { description = "Progress of books downloading in the background" }
            )
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val open = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java),
            flags,
        )
        val cancel = PendingIntent.getService(
            this, 1,
            Intent(this, DownloadService::class.java).setAction(ACTION_CANCEL),
            flags,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(total, done, total <= 0)
            .addAction(
                Notification.Action.Builder(null, "Cancel", cancel).build()
            )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }
}
