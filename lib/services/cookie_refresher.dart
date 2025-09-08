import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_navigator.dart';
import 'settings.dart';
import 'native_cookie.dart';

class CookieRefresher {
  CookieRefresher._();
  static final CookieRefresher instance = CookieRefresher._();

  bool _refreshing = false;
  DateTime? _lastRefreshAt;

  // 最短刷新间隔，避免频繁触发
  Duration minInterval = const Duration(seconds: 45);
  Duration timeout = const Duration(seconds: 15);

  bool get isCoolingDown {
    if (_lastRefreshAt == null) return false;
    return DateTime.now().difference(_lastRefreshAt!) < minInterval;
  }

  Future<bool> silentRefresh() async {
    if (_refreshing || isCoolingDown) {
      if (kDebugMode) {
        debugPrint('[CookieRefresher] Skip: refreshing=$_refreshing cooldown=$isCoolingDown');
      }
      return false;
    }
    final nav = AppNavigator.navigatorKey.currentState;
    final overlay = nav?.overlay;
    if (overlay == null) {
      if (kDebugMode) {
        debugPrint('[CookieRefresher] No overlay available');
      }
      return false;
    }

    _refreshing = true;
    _lastRefreshAt = DateTime.now();
    try {
      final baseUrl = SettingsService.instance.value.baseUrl;
      final target = Uri.parse(baseUrl).replace(queryParameters: {
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      });

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate());

      final done = Completer<void>();
      Timer? timer;

      // 使用 JS 轮询 document.readyState 作为兜底完成信号
      void setupReadinessProbe() {
        timer?.cancel();
        timer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
          try {
            final rs = await controller.runJavaScriptReturningResult('document.readyState');
            final s = (rs is String ? rs : rs.toString()).replaceAll('"', '');
            if (s.toLowerCase() == 'complete') {
              if (!done.isCompleted) done.complete();
            }
          } catch (_) {}
        });
      }

      final entry = OverlayEntry(builder: (_) {
        // 保证 WebView 实际创建并运行：给一个 1x1 的可见尺寸，但完全透明不遮挡
        return Positioned(
          left: -1000, // 放到屏幕之外，降低渲染影响
          top: -1000,
          child: SizedBox(
            width: 1,
            height: 1,
            child: WebViewWidget(controller: controller),
          ),
        );
      });

      overlay.insert(entry);
      setupReadinessProbe();
      // 启动加载
      await controller.loadRequest(target);

      // 超时控制
      final to = Timer(timeout, () {
        if (!done.isCompleted) done.complete();
      });

      await done.future;
      to.cancel();
      timer?.cancel();

      // 拉取原生 Cookie（可包含 HttpOnly）
      final header = (await NativeCookie.getCookieHeader(baseUrl)).trim();
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
        entry.remove();
        return false;
      }

      final changed = await _mergeAndSave(header);
      entry.remove();
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

