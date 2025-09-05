import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/settings.dart';
import '../services/native_cookie.dart';

class WebLoginPage extends StatefulWidget {
  const WebLoginPage({
    super.key, 
    this.initialUrl,
    this.showAppBarTitle = '站内登录',
    this.showUrlBar = true,
    this.showSaveButton = true,
  });
  
  final String? initialUrl;
  final String showAppBarTitle;
  final bool showUrlBar;
  final bool showSaveButton;

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  late final WebViewController _controller;
  String _currentUrl = '';
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    final baseUrl = SettingsService.instance.value.baseUrl;
    final targetUrl = widget.initialUrl ?? Uri.parse(baseUrl).resolve('/login').toString();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) => setState(() {
          _currentUrl = url;
        }),
        onProgress: (p) => setState(() => _progress = p / 100.0),
        onPageFinished: (url) => setState(() {
          _currentUrl = url;
          _progress = 0;
        }),
      ))
      ..loadRequest(Uri.parse(targetUrl));
  }

  Future<void> _saveCookies() async {
    try {
      // 1) 读取 WebView 原生 Cookie（可获取 HttpOnly，如 cf_clearance）
      final baseUrl = SettingsService.instance.value.baseUrl;
      final urlForCookie = _currentUrl.isNotEmpty ? _currentUrl : baseUrl;
      final nativeMap = <String, String>{};
      try {
        final c1 = await NativeCookie.getCookies(urlForCookie);
        nativeMap.addAll(c1);
      } catch (_) {}
      try {
        final c2 = await NativeCookie.getCookies(baseUrl);
        nativeMap.addAll(c2);
      } catch (_) {}

      // 2) 同时读取 document.cookie（补充非 HttpOnly）
      String jsCookieStr = '';
      try {
        final result = await _controller.runJavaScriptReturningResult('document.cookie');
        if (result is String) {
          jsCookieStr = result;
        } else {
          jsCookieStr = result.toString();
        }
        jsCookieStr = jsCookieStr.trim();
        if (jsCookieStr.startsWith('"') && jsCookieStr.endsWith('"')) {
          jsCookieStr = jsonDecode(jsCookieStr) as String;
        }
      } catch (_) {
        // 忽略 JS 读取失败
      }
      if (jsCookieStr.isNotEmpty) {
        final parts = jsCookieStr.split(';');
        for (final p in parts) {
          final kv = p.trim();
          final i = kv.indexOf('=');
          if (i > 0) {
            final k = kv.substring(0, i).trim();
            final v = kv.substring(i + 1).trim();
            if (k.isNotEmpty && v.isNotEmpty && !nativeMap.containsKey(k)) {
              nativeMap[k] = v;
            }
          }
        }
      }

      // 3) 获取 WebView 的 UA
      String ua = '';
      try {
        final uaResult = await _controller.runJavaScriptReturningResult('navigator.userAgent');
        ua = (uaResult is String ? uaResult : uaResult.toString()).trim();
        if (ua.startsWith('"') && ua.endsWith('"')) {
          ua = jsonDecode(ua) as String;
        }
      } catch (_) {}

      // 4) 序列化为请求头可用的格式：k1=v1; k2=v2
      final raw = nativeMap.entries.map((e) => '${e.key}=${e.value}').join('; ');

      // 5) 保存（Cloudflare 会将 cf_clearance 与 UA 绑定）
      await SettingsService.instance.update(cookies: raw, userAgent: ua.isEmpty ? null : ua);
      if (!mounted) return;
      final hasClearance = nativeMap.keys.any((k) => k.toLowerCase() == 'cf_clearance');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hasClearance ? 'Cookies 和 UA 已保存' : '已保存，但未检测到 cf_clearance，请确认已通过 Cloudflare 验证')), 
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取 Cookies 失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.showAppBarTitle),
        actions: [
          IconButton(
            tooltip: '刷新网页',
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _progress > 0
              ? LinearProgressIndicator(value: _progress)
              : const SizedBox.shrink(),
        ),
      ),
      body: Column(
        children: [
          if (widget.showUrlBar)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                _currentUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
          SafeArea(
            top: false,
            child: Row(
              children: [
                IconButton(
                  tooltip: '后退',
                  onPressed: () async {
                    if (await _controller.canGoBack()) {
                      _controller.goBack();
                    }
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
                IconButton(
                  tooltip: '前进',
                  onPressed: () async {
                    if (await _controller.canGoForward()) {
                      _controller.goForward();
                    }
                  },
                  icon: const Icon(Icons.arrow_forward),
                ),
                const Spacer(),
                if (widget.showSaveButton)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton.icon(
                      onPressed: _saveCookies,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('保存Cookies并返回'),
                    ),
                  ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
