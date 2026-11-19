package com.noddlecake.novel_to_epub

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "moonleaf/device")
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
    }
}
