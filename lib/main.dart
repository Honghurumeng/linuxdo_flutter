import 'package:flutter/material.dart';
import 'dart:io';

import 'pages/home_page.dart';
import 'services/settings.dart';
import 'services/http_overrides.dart';
import 'services/app_navigator.dart';
import 'services/webview_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = GlobalHttpOverrides();
  await SettingsService.instance.load();
  // 若启用 WebView 后端，尽早启动以保持 Cookies 与挑战状态
  if (SettingsService.instance.value.useWebViewBackend) {
    // ignore: unawaited_futures
    WebViewBackend.instance.ensureStarted();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinuxDo Reader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      navigatorKey: AppNavigator.navigatorKey,
      home: const HomePage(),
    );
  }
}
