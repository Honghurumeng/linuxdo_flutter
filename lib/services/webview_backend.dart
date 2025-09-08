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
  String? _uaApplied; // UA used by current headless instance

  bool get isStarted => _started && _controller != null;

  Future<void> ensureStarted() async {
    final uaSetting = SettingsService.instance.value.userAgent?.trim();
    // Restart headless WV if UA changed (Cloudflare binds cf_clearance to UA)
    if (isStarted && _uaApplied != (uaSetting?.isNotEmpty == true ? uaSetting : null)) {
      await dispose();
    }
    if (isStarted || _starting) {
      // Even if already started, try to apply latest cookies
      await _applyCookiesFromSettings();
      return;
    }
    _starting = true;
    try {
      final base = SettingsService.instance.value.baseUrl;
      final ua = uaSetting;
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
      _uaApplied = ua;
      await _applyCookiesFromSettings();
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
    _uaApplied = null;
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

  Future<void> syncCookiesFromSettings() async {
    await _applyCookiesFromSettings();
  }

  Future<void> _applyCookiesFromSettings() async {
    try {
      final cookies = SettingsService.instance.value.cookies?.trim();
      if (cookies == null || cookies.isEmpty) return;
      final base = SettingsService.instance.value.baseUrl;
      final uri = WebUri(base);
      final parsed = Uri.parse(base);
      final parts = cookies.split(';');
      for (final p in parts) {
        final kv = p.trim();
        final i = kv.indexOf('=');
        if (i <= 0) continue;
        final name = kv.substring(0, i).trim();
        final value = kv.substring(i + 1).trim();
        if (name.isEmpty || value.isEmpty) continue;
        await CookieManager.instance().setCookie(
          url: uri,
          name: name,
          value: value,
          domain: parsed.host,
          path: '/',
          isSecure: parsed.scheme == 'https',
          // heuristics: many auth cookies are HttpOnly
          isHttpOnly: true,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebViewBackend] apply cookies failed: $e');
      }
    }
  }
}
