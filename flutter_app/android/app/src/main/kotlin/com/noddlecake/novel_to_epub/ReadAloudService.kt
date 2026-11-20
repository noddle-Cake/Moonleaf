package com.noddlecake.novel_to_epub

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps Moonleaf reading aloud with the screen off or another app open,
 * with Pause/Play, Next and Stop in the notification. The voice itself runs
 * in the app (the phone's text-to-speech or the downloaded voice); this
 * service only keeps the app's process alive and awake while it reads.
 */
class ReadAloudService : Service() {
    companion object {
        const val CHANNEL = "read_aloud"
        const val ID = 4108
        const val ACTION_UPDATE = "moonleaf.readaloud.UPDATE"
        const val ACTION_BUTTON = "moonleaf.readaloud.BUTTON"

        /** Called with "play", "pause", "next" or "stop" from the notification. */
        var onButton: ((String) -> Unit)? = null

        fun update(context: Context, title: String, text: String, playing: Boolean) {
            val intent = Intent(context, ReadAloudService::class.java)
                .setAction(ACTION_UPDATE)
                .putExtra("title", title)
                .putExtra("text", text)
                .putExtra("playing", playing)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ReadAloudService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_BUTTON) {
            intent.getStringExtra("button")?.let { onButton?.invoke(it) }
            return START_NOT_STICKY
        }
        val playing = intent?.getBooleanExtra("playing", true) ?: true
        val notification = build(
            intent?.getStringExtra("title") ?: "Reading aloud",
            intent?.getStringExtra("text") ?: "",
            playing,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(ID, notification)
        }
        if (playing) holdWakeLock() else releaseWakeLock()
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        onButton?.invoke("stop")
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    /** Keeps the processor awake between sentences; renewed with each update. */
    private fun holdWakeLock() {
        val lock = wakeLock ?: (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Moonleaf:readaloud")
            .also { it.setReferenceCounted(false); wakeLock = it }
        lock.acquire(30 * 60 * 1000L)
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
    }

    private fun button(name: String, code: Int): PendingIntent = PendingIntent.getService(
        this, code,
        Intent(this, ReadAloudService::class.java)
            .setAction(ACTION_BUTTON)
            .putExtra("button", name),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun action(icon: Int, label: String, intent: PendingIntent): Notification.Action =
        Notification.Action.Builder(Icon.createWithResource(this, icon), label, intent).build()

    private fun build(title: String, text: String, playing: Boolean): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(CHANNEL) == null
        ) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Read Aloud", NotificationManager.IMPORTANCE_LOW)
                    .apply { description = "Controls for the book being read aloud" }
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(
                if (playing) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause
            )
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(playing)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(
                if (playing) action(android.R.drawable.ic_media_pause, "Pause", button("pause", 1))
                else action(android.R.drawable.ic_media_play, "Play", button("play", 2))
            )
            .addAction(action(android.R.drawable.ic_media_next, "Next", button("next", 3)))
            .addAction(
                action(android.R.drawable.ic_menu_close_clear_cancel, "Stop", button("stop", 4))
            )
            .setStyle(Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }
}
