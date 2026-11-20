package com.noddlecake.novel_to_epub

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        /** A link shared to Moonleaf that the app hasn't taken yet. */
        private var pendingShare: String? = null
        private var current: MainActivity? = null

        fun share(text: String) {
            pendingShare = text
            current?.deliverShare()
        }
    }

    private var background: MethodChannel? = null
    private var shares: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "moonleaf/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Used to recognize e-ink devices (Hisense, Boox, Kobo...).
                    "info" -> result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "brand" to Build.BRAND,
                            "model" to Build.MODEL,
                        )
                    )
                    else -> result.notImplemented()
                }
            }
        val shareChannel = MethodChannel(messenger, "moonleaf/share")
        shares = shareChannel
        shareChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                // The app asks for a link shared before it was ready.
                "take" -> {
                    result.success(pendingShare)
                    pendingShare = null
                }
                else -> result.notImplemented()
            }
        }
        current = this
        val channel = MethodChannel(messenger, "moonleaf/background")
        background = channel
        DownloadService.onCancel = { runOnUiThread { channel.invokeMethod("cancel", null) } }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Shows or updates the download notification.
                "update" -> {
                    askForNotifications()
                    try {
                        DownloadService.update(
                            this,
                            call.argument<String>("title") ?: "Downloading",
                            call.argument<String>("text") ?: "",
                            call.argument<Int>("done") ?: 0,
                            call.argument<Int>("total") ?: 0,
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        // Android can refuse while the app is in the background.
                        result.success(false)
                    }
                }
                "stop" -> {
                    DownloadService.stop(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        deliverShare()
    }

    /** Sends a shared link to the running app. */
    fun deliverShare() {
        val text = pendingShare ?: return
        val channel = shares ?: return
        pendingShare = null
        runOnUiThread { channel.invokeMethod("shared", text) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (current == this) current = null
        shares = null
        DownloadService.onCancel = null
        background = null
        // The download can't continue without the app; it resumes on launch.
        DownloadService.stop(this)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private var asked = false

    /** Android 13 and later ask before showing the progress notification. */
    private fun askForNotifications() {
        if (asked || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        asked = true
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7)
        }
    }
}
