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
      // 固定内置 Base URL，不再读取或允许设置
      baseUrl: 'https://linux.do',
      userAgent: prefs.getString(_kUserAgent),
      proxy: prefs.getString(_kProxy),
      cookies: prefs.getString(_kCookies),
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> update({String? userAgent, String? proxy, String? cookies}) async {
    // 规则：
    // - 传入 null => 不变；
    // - 传入空字符串 => 清空；
    // - 传入非空字符串 => 覆盖。
    final newUa = userAgent == null
        ? _value.userAgent
        : (userAgent.isEmpty ? null : userAgent);
    final newProxy = proxy == null
        ? _value.proxy
        : (proxy.isEmpty ? null : proxy);
    final newCookies = cookies == null
        ? _value.cookies
        : (cookies.isEmpty ? null : cookies);

    // 若没有任何实际变化，直接返回，避免不必要的存储与通知（可减少页面无意义刷新）
    final noChange = newUa == _value.userAgent && newProxy == _value.proxy && newCookies == _value.cookies;
    if (noChange) {
      return;
    }

    _value = AppSettings(
      baseUrl: _value.baseUrl,
      userAgent: newUa,
      proxy: newProxy,
      cookies: newCookies,
    );

    final prefs = await SharedPreferences.getInstance();

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
