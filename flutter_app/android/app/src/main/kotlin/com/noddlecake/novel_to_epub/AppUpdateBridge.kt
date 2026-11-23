package com.noddlecake.novel_to_epub

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Reads the installed identity and opens Android's installer for a verified cache file. */
class AppUpdateBridge(private val activity: FlutterActivity, messenger: BinaryMessenger) {
    private val worker = Executors.newSingleThreadExecutor()
    private val channel = MethodChannel(messenger, "moonleaf/updates")
    private val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "installed" -> try {
                    val info = activity.packageManager.getPackageInfo(activity.packageName, flags)
                    result.success(mapOf("name" to info.versionName, "build" to version(info), "certificate" to certificates(info).single()))
                } catch (error: Exception) { result.error("identity", "Could not read the installed app identity.", null) }
                "install" -> {
                    val path = call.argument<String>("path")
                    val hash = call.argument<String>("sha256")
                    worker.execute {
                        try {
                            val file = File(requireNotNull(path)).canonicalFile
                            val folder = File(activity.cacheDir, "updates").canonicalFile
                            require(file.parentFile == folder && file.name.matches(Regex("moonleaf-[0-9]+\\.apk")))
                            require(file.isFile && hash?.matches(Regex("[a-f0-9]{64}")) == true)
                            val digest = MessageDigest.getInstance("SHA-256")
                            file.inputStream().use { input ->
                                val buffer = ByteArray(65536)
                                while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
                            }
                            require(hex(digest.digest()) == hash)
                            val installed = activity.packageManager.getPackageInfo(activity.packageName, flags)
                            val update = requireNotNull(activity.packageManager.getPackageArchiveInfo(file.path, flags))
                            require(update.packageName == activity.packageName && version(update) > version(installed))
                            require(certificates(update) == certificates(installed))
                            activity.runOnUiThread {
                                try {
                                    if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                                        activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                            Uri.parse("package:${activity.packageName}")))
                                        result.success("permission_required")
                                    } else {
                                        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
                                        activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri,
                                            "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                                        result.success("opened")
                                    }
                                } catch (error: Exception) { result.error("installer", "Android could not open the installer.", null) }
                            }
                        } catch (error: Exception) {
                            activity.runOnUiThread { result.error("verification", "The update failed verification.", null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    @Suppress("DEPRECATION")
    private fun version(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    @Suppress("DEPRECATION")
    private fun certificates(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return requireNotNull(signatures).map { hex(MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) }.toSet()
    }
    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }
    fun close() { channel.setMethodCallHandler(null); worker.shutdown() }
}
