import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final String baseUrl;
  final String? userAgent;
  final String? proxy; // 形如 127.0.0.1:7890 或 http://127.0.0.1:7890

  const AppSettings({
    this.baseUrl = 'https://linux.do',
    this.userAgent,
    this.proxy,
  });

  AppSettings copyWith({String? baseUrl, String? userAgent, String? proxy}) {
    return AppSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      userAgent: userAgent ?? this.userAgent,
      proxy: proxy ?? this.proxy,
    );
  }
}

class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _kBaseUrl = 'baseUrl';
  static const _kUserAgent = 'userAgent';
  static const _kProxy = 'proxy';

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
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> update({String? baseUrl, String? userAgent, String? proxy}) async {
    final next = _value.copyWith(
      baseUrl: baseUrl,
      userAgent: userAgent,
      proxy: proxy,
    );
    _value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, next.baseUrl);
    if (next.userAgent == null || next.userAgent!.isEmpty) {
      await prefs.remove(_kUserAgent);
    } else {
      await prefs.setString(_kUserAgent, next.userAgent!);
    }
    if (next.proxy == null || next.proxy!.isEmpty) {
      await prefs.remove(_kProxy);
    } else {
      await prefs.setString(_kProxy, next.proxy!);
    }
    notifyListeners();
  }
}

