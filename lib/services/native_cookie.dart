import 'dart:async';
import 'package:flutter/services.dart';

class NativeCookie {
  static const MethodChannel _channel = MethodChannel('app.webview.cookies');

  static Map<String, String> _parseCookieHeader(String header) {
    final out = <String, String>{};
    if (header.isEmpty) return out;
    for (final part in header.split(';')) {
      final kv = part.trim();
      final i = kv.indexOf('=');
      if (i > 0) {
        final k = kv.substring(0, i).trim();
        final v = kv.substring(i + 1).trim();
        if (k.isNotEmpty) out[k] = v;
      }
    }
    return out;
  }

  static Future<String> getCookieHeader(String url) async {
    try {
      final res = await _channel.invokeMethod<String>('getCookies', {'url': url});
      return (res ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  static Future<Map<String, String>> getCookies(String url) async {
    final header = await getCookieHeader(url);
    return _parseCookieHeader(header);
  }
}

