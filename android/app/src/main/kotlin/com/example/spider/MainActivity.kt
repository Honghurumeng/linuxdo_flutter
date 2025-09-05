package com.example.spider

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.webkit.CookieManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.content.ContentValues
import android.os.Environment
import android.media.MediaScannerConnection
import java.io.File
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    private val channelName = "app.webview.cookies"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookies" -> {
                    val url = call.argument<String>("url") ?: ""
                    if (url.isEmpty()) {
                        result.success("")
                        return@setMethodCallHandler
                    }
                    try {
                        val cookieManager = CookieManager.getInstance()
                        // Ensure accept cookie to read, though reading does not require it generally
                        cookieManager.setAcceptCookie(true)
                        val targetUrl = sanitizeUrl(url)
                        val header = cookieManager.getCookie(targetUrl) ?: ""
                        result.success(header)
                    } catch (e: Exception) {
                        result.success("")
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Media save channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.media").setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImage" -> {
                    try {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) { result.success(false); return@setMethodCallHandler }
                        val name = call.argument<String>("name") ?: ("linuxdo_" + System.currentTimeMillis().toString() + ".jpg")
                        val mime = call.argument<String>("mime") ?: "image/jpeg"
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val resolver = applicationContext.contentResolver
                            val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                            val values = ContentValues().apply {
                                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/LinuxDo")
                            }
                            val uri = resolver.insert(collection, values)
                            if (uri == null) { result.success(false); return@setMethodCallHandler }
                            resolver.openOutputStream(uri).use { os ->
                                if (os == null) { result.success(false); return@setMethodCallHandler }
                                os.write(bytes)
                            }
                            result.success(true)
                        } else {
                            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "LinuxDo")
                            if (!dir.exists()) dir.mkdirs()
                            val file = File(dir, name)
                            FileOutputStream(file).use { it.write(bytes) }
                            // 通知媒体库刷新
                            MediaScannerConnection.scanFile(applicationContext, arrayOf(file.absolutePath), arrayOf(mime), null)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun sanitizeUrl(url: String): String {
        return try {
            val u = Uri.parse(url)
            if (u.scheme.isNullOrEmpty()) {
                "https://$url"
            } else url
        } catch (_: Exception) {
            url
        }
    }
}
