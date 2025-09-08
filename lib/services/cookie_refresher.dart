import 'dart:async';
import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// import 'app_navigator.dart';
import 'settings.dart';
import 'native_cookie.dart';

class CookieRefresher {
  CookieRefresher._();
  static final CookieRefresher instance = CookieRefresher._();

  bool _refreshing = false;
  DateTime? _lastRefreshAt;

  // 最短刷新间隔，避免频繁触发
  Duration minInterval = const Duration(seconds: 15);
  Duration timeout = const Duration(seconds: 15);

  bool get isCoolingDown {
    if (_lastRefreshAt == null) return false;
    return DateTime.now().difference(_lastRefreshAt!) < minInterval;
  }

  Future<bool> silentRefresh({bool force = false}) async {
    if (_refreshing || (isCoolingDown && !force)) {
      if (kDebugMode) {
        debugPrint('[CookieRefresher] Skip: refreshing=$_refreshing cooldown=$isCoolingDown force=$force');
      }
      return false;
    }
    _refreshing = true;
    _lastRefreshAt = DateTime.now();
    try {
      final baseUrl = SettingsService.instance.value.baseUrl;
      final latest = Uri.parse(baseUrl).resolve('/latest');
      final target = latest.replace(queryParameters: {
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final ua = SettingsService.instance.value.userAgent?.trim();
      final settings = InAppWebViewSettings(
        javaScriptEnabled: true,
        thirdPartyCookiesEnabled: true,
        transparentBackground: true,
        userAgent: (ua != null && ua.isNotEmpty) ? ua : null,
      );
      final ready = Completer<void>();
      final headless = HeadlessInAppWebView(
        initialSettings: settings,
        initialUrlRequest: URLRequest(url: WebUri(target.toString())),
        onLoadStop: (_, __) {
          if (!ready.isCompleted) ready.complete();
        },
        onReceivedError: (_, __, ___) {
          if (!ready.isCompleted) ready.complete();
        },
      );
      await headless.run();
      await ready.future.timeout(timeout, onTimeout: (){});

      // 等待 Cloudflare 下发 cf_clearance（最多 timeout 时间，轮询）
      final t0 = DateTime.now();
      String header = '';
      while (DateTime.now().difference(t0) < timeout) {
        try {
          final list = await CookieManager.instance().getCookies(url: WebUri(baseUrl));
          if (list.isNotEmpty) {
            header = list.map((e) => '${e.name}=${e.value}').join('; ');
            final hasClearance = list.any((c) => c.name.toLowerCase() == 'cf_clearance');
            if (hasClearance) break;
          }
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 400));
      }

      // 若 InAppWebView 拿不到，退回原生获取（可包含 HttpOnly）
      if (header.trim().isEmpty) {
        header = (await NativeCookie.getCookieHeader(baseUrl)).trim();
      }
      if (kDebugMode) {
        final names = header.isEmpty
            ? []
            : header
                .split(';')
                .map((e) => e.trim())
                .where((e) => e.contains('='))
                .map((e) => e.substring(0, e.indexOf('=')))
                .toList();
        debugPrint('[CookieRefresher] got cookies: ${names.join(', ')}');
      }

      if (header.isEmpty) {
        await headless.dispose();
        return false;
      }

      final changed = await _mergeAndSave(header);
      await headless.dispose();
      return changed;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CookieRefresher] failed: $e');
      }
      return false;
    } finally {
      _refreshing = false;
    }
  }

  Future<bool> _mergeAndSave(String newHeader) async {
    String normalize(String s) => s.trim();
    Map<String, String> parse(String s) {
      final m = <String, String>{};
      for (final p in s.split(';')) {
        final kv = p.trim();
        final i = kv.indexOf('=');
        if (i > 0) {
          final k = kv.substring(0, i).trim();
          final v = kv.substring(i + 1).trim();
          if (k.isNotEmpty && v.isNotEmpty && v.toLowerCase() != 'deleted') {
            m[k] = v;
          }
        }
      }
      return m;
    }

    final existing = SettingsService.instance.value.cookies ?? '';
    final cur = parse(existing);
    final add = parse(newHeader);
    cur.addAll(add);
    final merged = cur.entries.map((e) => '${e.key}=${e.value}').join('; ');
    if (normalize(merged) != normalize(existing)) {
      await SettingsService.instance.update(cookies: merged);
      return true;
    }
    return false;
  }
}
