package com.example.spider

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.webkit.CookieManager
import android.net.Uri

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
