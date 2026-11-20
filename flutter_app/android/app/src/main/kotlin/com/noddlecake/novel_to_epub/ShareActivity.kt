package com.noddlecake.novel_to_epub

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Receives a link shared from a browser ("Share → Moonleaf"), hands it to
 * the app and closes. The app opens in its own window, so sharing never
 * starts a second copy of Moonleaf inside the browser's window.
 */
class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.action == Intent.ACTION_SEND) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                ?: intent.getStringExtra(Intent.EXTRA_SUBJECT)
            if (!text.isNullOrBlank()) MainActivity.share(text)
        }
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(it)
        }
        finish()
    }
}
