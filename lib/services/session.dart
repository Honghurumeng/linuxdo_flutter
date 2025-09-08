import 'dart:io';
import 'dart:convert';
// typed_data is available via flutter foundation; no direct import needed
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'settings.dart';
import 'webview_backend.dart';
import 'cookie_refresher.dart';
import 'native_cookie.dart';

class Session {
  Session._();
  static final Session instance = Session._();

  String get _baseUrl => SettingsService.instance.value.baseUrl.trim();

  Future<void> init() async {
    await WebViewBackend.instance.ensureStarted();
  }

  // 统一 JSON 获取：优先使用 WebView，同源携带 Cookie；挑战时静默刷新并重试，最终回退原生 HTTP。
  Future<http.Response> fetchJsonUri(Uri uri) async {
    await init();
    // 1) WebView fetch
    final res1 = await _fetchViaWebView(uri);
    if (res1 != null && !_isChallenged(res1.statusCode, res1.headers)) {
      return res1;
    }

    // 2) 静默刷新并重试（WebView）
    try {
      await CookieRefresher.instance.silentRefresh(force: true);
    } catch (_) {}
    final res2 = await _fetchViaWebView(uri);
    if (res2 != null && !_isChallenged(res2.statusCode, res2.headers)) {
      return res2;
    }

    // 3) 回退原生 HTTP（带 UA/Cookie），并根据 Set-Cookie 合并
    http.Response res = await _nativeGet(uri);
    final challenged = _isChallenged(res.statusCode, res.headers);
    final merged = _mergeSetCookie(res);
    if (challenged) {
      // 再尝试一次（若 Cookie 变更或刷新成功）
      bool refreshed = false;
      if (!merged) {
        try {
          refreshed = await CookieRefresher.instance.silentRefresh(force: true);
        } catch (_) {}
      }
      if (merged || refreshed) {
        res = await _nativeGet(uri);
        _mergeSetCookie(res);
      }
    }
    return res;
  }

  // 统一二进制获取（图片等）：同策略
  Future<Map<String, dynamic>> fetchBytes(String url) async {
    await init();
    // 1) WebView fetch
    final res1 = await _fetchBytesViaWebView(url);
    if (res1 != null && !_isChallenged(res1['status'] as int, Map<String, String>.from(res1['headers'] as Map))) {
      return res1;
    }
    // 2) 刷新后重试
    try { await CookieRefresher.instance.silentRefresh(force: true); } catch (_) {}
    final res2 = await _fetchBytesViaWebView(url);
    if (res2 != null && !_isChallenged(res2['status'] as int, Map<String, String>.from(res2['headers'] as Map))) {
      return res2;
    }
    // 3) 原生兜底
    final uri = Uri.parse(url);
    final res = await _nativeGet(uri, image: true);
    _mergeSetCookie(res);
    if (res.statusCode == 200) {
      return {
        'bytes': res.bodyBytes,
        'contentType': res.headers['content-type'] ?? '',
      };
    }
    throw HttpException('HTTP ${res.statusCode}', uri: uri);
  }

  Future<http.Response?> _fetchViaWebView(Uri uri) async {
    try {
      final map = await WebViewBackend.instance.fetchJson(uri.toString());
      final status = (map['status'] is int)
          ? map['status'] as int
          : int.tryParse('${map['status']}') ?? 0;
      final headers = (map['headers'] is Map)
          ? Map<String, String>.from(
              (map['headers'] as Map).map((k, v) => MapEntry('$k', '$v')),
            )
          : <String, String>{};
      final body = (map['body'] ?? '').toString();
      if (kDebugMode) {
        debugPrint('[Session] (WV) <-- $status GET $uri');
      }
      if (status < 100 || status > 599) {
        // 某些情况下 WebView fetch 失败会给出 0，这里视为失败
        return null;
      }
      // 尝试从原生存储同步 Cookie，供原生兜底使用
      try {
        final header = await NativeCookie.getCookieHeader(_baseUrl);
        if (header.trim().isNotEmpty) {
          await SettingsService.instance.update(cookies: header.trim());
        }
      } catch (_) {}
      return http.Response(body, status, headers: headers);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Session] WebView fetch failed: $e');
      }
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchBytesViaWebView(String url) async {
    try {
      final map = await WebViewBackend.instance.fetchBytes(url);
      final status = (map['status'] is int)
          ? map['status'] as int
          : int.tryParse('${map['status']}') ?? 0;
      final headers = (map['headers'] is Map)
          ? Map<String, String>.from(
              (map['headers'] as Map).map((k, v) => MapEntry('$k', '$v')),
            )
          : <String, String>{};
      final b64 = (map['bodyBase64'] ?? '').toString();
      if (kDebugMode) {
        debugPrint('[Session] (WV) IMG <-- $status GET $url');
      }
      if (status < 100 || status > 599) return null;
      // 同步 Cookie（从原生）
      try {
        final header = await NativeCookie.getCookieHeader(_baseUrl);
        if (header.trim().isNotEmpty) {
          await SettingsService.instance.update(cookies: header.trim());
        }
      } catch (_) {}
      final bytes = (b64.isEmpty) ? Uint8List(0) : base64Decode(b64);
      return {
        'status': status,
        'headers': headers,
        'bytes': bytes,
        'contentType': headers['content-type'] ?? '',
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Session] WebView fetchBytes failed: $e');
      }
      return null;
    }
  }

  bool _isChallenged(int statusCode, Map<String, String> headers) {
    if (statusCode == 403 || statusCode == 503 || statusCode == 520) return true;
    final server = (headers['server'] ?? '').toLowerCase();
    final cfRay = headers.keys.any((k) => k.toLowerCase() == 'cf-ray');
    if (server.contains('cloudflare') || cfRay) return statusCode >= 400;
    return false;
  }

  IOClient _buildClient() {
    final s = SettingsService.instance.value;
    final httpClient = HttpClient();
    String? proxy = s.proxy?.trim();
    if (proxy != null && proxy.isNotEmpty) {
      proxy = proxy.replaceFirst(RegExp(r'^https?://'), '');
      httpClient.findProxy = (uri) => 'PROXY $proxy; DIRECT';
      if (kDebugMode) {
        debugPrint('[Session] Proxy enabled: $proxy');
      }
    }
    return IOClient(httpClient);
  }

  Map<String, String> _headers() {
    final s = SettingsService.instance.value;
    final bu = Uri.parse(_baseUrl);
    final origin = '${bu.scheme}://${bu.host}${bu.hasPort ? ':${bu.port}' : ''}';
    final cookies = s.cookies?.trim();
    final ua = (s.userAgent?.trim().isNotEmpty == true)
        ? s.userAgent!.trim()
        : 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36';
    final h = <String, String>{
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'User-Agent': ua,
      'Referer': _baseUrl.endsWith('/') ? _baseUrl : '$_baseUrl/',
      'Origin': origin,
      'X-Requested-With': 'XMLHttpRequest',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'same-origin',
      'Sec-Fetch-Dest': 'empty',
      'Connection': 'keep-alive',
    };
    if (cookies != null && cookies.isNotEmpty) {
      h['Cookie'] = cookies;
    }
    return h;
  }

  Future<http.Response> _nativeGet(Uri uri, {bool image = false}) async {
    final client = _buildClient();
    try {
      final h = image ? _imageHeaders() : _headers();
      if (kDebugMode) {
        debugPrint('[Session] (HTTP) --> GET $uri');
      }
      final res = await client.get(uri, headers: h);
      if (kDebugMode) {
        debugPrint('[Session] (HTTP) <-- ${res.statusCode} GET $uri');
      }
      return res;
    } finally {
      client.close();
    }
  }

  Map<String, String> _imageHeaders() {
    final s = SettingsService.instance.value;
    final bu = Uri.parse(_baseUrl);
    final origin = '${bu.scheme}://${bu.host}${bu.hasPort ? ':${bu.port}' : ''}';
    final ua = (s.userAgent?.trim().isNotEmpty == true)
        ? s.userAgent!.trim()
        : 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36';
    final h = <String, String>{
      'User-Agent': ua,
      'Referer': _baseUrl.endsWith('/') ? _baseUrl : '$_baseUrl/',
      'Origin': origin,
      'Sec-Fetch-Mode': 'no-cors',
      'Sec-Fetch-Site': 'same-origin',
      'Sec-Fetch-Dest': 'image',
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Connection': 'keep-alive',
    };
    final cookies = s.cookies?.trim();
    if (cookies != null && cookies.isNotEmpty) {
      h['Cookie'] = cookies;
    }
    return h;
  }

  // 从响应头中合并 Set-Cookie 到 SettingsService（仅原生兜底路径适用）
  bool _mergeSetCookie(http.Response res) {
    final setCookie = res.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) return false;
    final existing = SettingsService.instance.value.cookies ?? '';
    final current = <String, String>{}
      ..addEntries(existing
          .split(';')
          .map((e) => e.trim())
          .where((e) => e.contains('='))
          .map((kv) {
            final i = kv.indexOf('=');
            final name = kv.substring(0, i).trim();
            final value = kv.substring(i + 1).trim();
            return MapEntry(name, value);
          }));
    final reg = RegExp(r'(?:(?<=^)|(?<=, ))([^=; ,]+)=([^;]+)');
    for (final m in reg.allMatches(setCookie)) {
      final name = m.group(1);
      final value = m.group(2);
      if (name != null && value != null) {
        final n = name.toLowerCase();
        if (n == 'path' || n == 'expires' || n == 'httponly' || n == 'secure' || n == 'samesite' || n == 'domain') {
          continue;
        }
        final v = value.trim();
        if (v.isEmpty || v.toLowerCase() == 'deleted') continue;
        current[name] = value;
      }
    }
    final merged = current.entries.map((e) => '${e.key}=${e.value}').join('; ');
    final changed = merged.trim() != existing.trim();
    if (changed) {
      SettingsService.instance.update(cookies: merged);
      if (kDebugMode) {
        debugPrint('[Session] Set-Cookie merged -> ${current.keys.join(', ')}');
      }
    }
    return changed;
  }
}
