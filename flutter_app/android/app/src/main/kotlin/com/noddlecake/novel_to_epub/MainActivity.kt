package com.noddlecake.novel_to_epub

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var background: MethodChannel? = null

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

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
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
