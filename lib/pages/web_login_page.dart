import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/settings.dart';

class WebLoginPage extends StatefulWidget {
  const WebLoginPage({super.key});

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
    final loginUrl = Uri.parse(baseUrl).resolve('/login');
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
      ..loadRequest(loginUrl);
  }

  Future<void> _saveCookies() async {
    try {
      // 读取 document.cookie 字符串
      final result = await _controller.runJavaScriptReturningResult('document.cookie');
      String raw;
      if (result is String) {
        raw = result;
      } else {
        // iOS 可能返回 JSON 字符串包了引号
        raw = result.toString();
      }
      // 去掉可能的多余引号
      raw = raw.trim();
      if (raw.startsWith('"') && raw.endsWith('"')) {
        raw = jsonDecode(raw) as String; // 解码一次
      }
      await SettingsService.instance.update(cookies: raw);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cookies 已保存')),
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
        title: const Text('站内登录'),
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
