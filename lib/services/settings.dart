import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final String baseUrl;
  final String? userAgent;
  final String? proxy; // 形如 127.0.0.1:7890 或 http://127.0.0.1:7890
  final String? cookies; // 形如 k1=v1; k2=v2

  const AppSettings({
    this.baseUrl = 'https://linux.do',
    this.userAgent,
    this.proxy,
    this.cookies,
  });

  AppSettings copyWith({String? baseUrl, String? userAgent, String? proxy, String? cookies}) {
    return AppSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      userAgent: userAgent ?? this.userAgent,
      proxy: proxy ?? this.proxy,
      cookies: cookies ?? this.cookies,
    );
  }
}

class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _kBaseUrl = 'baseUrl';
  static const _kUserAgent = 'userAgent';
  static const _kProxy = 'proxy';
  static const _kCookies = 'cookies';

  AppSettings _value = const AppSettings();
  AppSettings get value => _value;

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _value = AppSettings(
      baseUrl: prefs.getString(_kBaseUrl) ?? 'https://linux.do',
      userAgent: prefs.getString(_kUserAgent),
      proxy: prefs.getString(_kProxy),
      cookies: prefs.getString(_kCookies),
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> update({String? baseUrl, String? userAgent, String? proxy, String? cookies}) async {
    // 按传入值“覆盖或清空”，而不是 copyWith 忽略 null
    final newBaseUrl = baseUrl ?? _value.baseUrl;
    final newUa = (userAgent != null && userAgent.isEmpty) ? null : userAgent; // 允许显式清空
    final newProxy = (proxy != null && proxy.isEmpty) ? null : proxy;
    final newCookies = (cookies != null && cookies.isEmpty) ? null : cookies;

    _value = AppSettings(
      baseUrl: newBaseUrl,
      userAgent: newUa,
      proxy: newProxy,
      cookies: newCookies,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, newBaseUrl);

    if (newUa == null || newUa.isEmpty) {
      await prefs.remove(_kUserAgent);
    } else {
      await prefs.setString(_kUserAgent, newUa);
    }

    if (newProxy == null || newProxy.isEmpty) {
      await prefs.remove(_kProxy);
    } else {
      await prefs.setString(_kProxy, newProxy);
    }

    if (newCookies == null || newCookies.isEmpty) {
      await prefs.remove(_kCookies);
    } else {
      await prefs.setString(_kCookies, newCookies);
    }

    notifyListeners();
  }
}
