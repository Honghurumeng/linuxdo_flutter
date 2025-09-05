import 'dart:io';

import 'settings.dart';

class GlobalHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    final proxy = SettingsService.instance.value.proxy?.trim();
    if (proxy != null && proxy.isNotEmpty) {
      final p = proxy.replaceFirst(RegExp(r'^https?://'), '');
      client.findProxy = (uri) => 'PROXY $p; DIRECT';
    }
    return client;
  }
}

