import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
// material.dart is not needed here
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'settings.dart';

class WebViewBackend {
  WebViewBackend._();
  static final WebViewBackend instance = WebViewBackend._();

  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;
  bool _starting = false;
  bool _started = false;

  bool get isStarted => _started && _controller != null;

  Future<void> ensureStarted() async {
    if (isStarted || _starting) return;
    _starting = true;
    try {
      final base = SettingsService.instance.value.baseUrl;
      final ua = SettingsService.instance.value.userAgent?.trim();
      final settings = InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
        incognito: false,
        useShouldOverrideUrlLoading: false,
        thirdPartyCookiesEnabled: true,
        allowsInlineMediaPlayback: true,
        mediaPlaybackRequiresUserGesture: false,
        useOnLoadResource: false,
        userAgent: (ua != null && ua.isNotEmpty) ? ua : null,
      );

      final c = Completer<void>();
      _headless = HeadlessInAppWebView(
        initialSettings: settings,
        initialUrlRequest: URLRequest(url: WebUri(base)),
        onWebViewCreated: (ctrl) {
          _controller = ctrl;
        },
        onLoadStop: (_, __) async {
          if (!c.isCompleted) c.complete();
        },
        onReceivedError: (_, __, ___) {
          if (!c.isCompleted) c.complete();
        },
      );
      await _headless!.run();

      // 最长等待 10s 视为 ready
      await c.future.timeout(const Duration(seconds: 10));
      _started = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebViewBackend] start failed: $e');
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> dispose() async {
    try {
      await _headless?.dispose();
    } catch (_) {}
    _headless = null;
    _controller = null;
    _started = false;
  }

  Future<Map<String, dynamic>> fetchJson(String url) async {
    await ensureStarted();
    final ctrl = _controller;
    if (ctrl == null) throw StateError('WebView backend not ready');
    final u = jsonEncode(url);
    final js = '''
      (async () => {
        try {
          const u = new URL($u, window.location.origin).toString();
          const res = await fetch(u, { credentials: 'include' });
          const text = await res.text();
          const headers = {};
          res.headers.forEach((v,k)=> headers[k]=v);
          return JSON.stringify({ status: res.status, body: text, headers });
        } catch (e) {
          return JSON.stringify({ status: 0, body: '', headers: {}, error: String(e) });
        }
      })();
    ''';
    final raw = await ctrl.evaluateJavascript(source: js);
    final s = raw is String ? raw : raw?.toString() ?? '{}';
    final map = jsonDecode(s) as Map<String, dynamic>;
    return map;
  }

  // 同源获取二进制资源（图片等）。返回：{ status, headers, bodyBase64 }
  Future<Map<String, dynamic>> fetchBytes(String url) async {
    await ensureStarted();
    final ctrl = _controller;
    if (ctrl == null) throw StateError('WebView backend not ready');
    final u = jsonEncode(url);
    final js = '''
      (async () => {
        try {
          const u = new URL($u, window.location.origin).toString();
          const res = await fetch(u, { credentials: 'include' });
          const headers = {};
          res.headers.forEach((v,k)=> headers[k]=v);
          const arrayBuf = await res.arrayBuffer();
          // Convert ArrayBuffer to base64 in chunks to avoid stack issues
          let binary = '';
          const bytes = new Uint8Array(arrayBuf);
          const chunk = 0x8000;
          for (let i = 0; i < bytes.length; i += chunk) {
            const sub = bytes.subarray(i, i + chunk);
            binary += String.fromCharCode.apply(null, sub);
          }
          const base64 = btoa(binary);
          return JSON.stringify({ status: res.status, headers, bodyBase64: base64 });
        } catch (e) {
          return JSON.stringify({ status: 0, headers: {}, bodyBase64: '', error: String(e) });
        }
      })();
    ''';
    final raw = await ctrl.evaluateJavascript(source: js);
    final s = raw is String ? raw : raw?.toString() ?? '{}';
    final map = jsonDecode(s) as Map<String, dynamic>;
    return map;
  }
}
