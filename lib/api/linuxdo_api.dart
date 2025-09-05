import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/topic.dart';
import '../services/settings.dart';

class LinuxDoApi {
  LinuxDoApi({this.baseUrl});

  final String? baseUrl;

  String get _baseUrl => (baseUrl ?? SettingsService.instance.value.baseUrl).trim();

  Map<String, String> _headers({String? ua}) {
    final cookies = SettingsService.instance.value.cookies?.trim();
    final h = {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'User-Agent': ua ??
            (SettingsService.instance.value.userAgent?.trim().isNotEmpty == true
                ? SettingsService.instance.value.userAgent!.trim()
                :
            // 默认使用桌面 Chrome UA（按用户要求）
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36'),
        'Referer': _baseUrl.endsWith('/') ? _baseUrl : '$_baseUrl/',
        'Connection': 'keep-alive',
      };
    if (cookies != null && cookies.isNotEmpty) {
      h['Cookie'] = cookies;
    }
    return h;
  }

  Map<String, String> imageHeaders() => _headers();

  Uri _u(String path, [Map<String, dynamic>? q]) => Uri.parse(_baseUrl).replace(
        path: path,
        queryParameters: q?.map((k, v) => MapEntry(k, v.toString())),
      );

  String absolutizeUrl(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) {
      final scheme = Uri.parse(_baseUrl).scheme;
      return '$scheme:$url';
    }
    if (url.startsWith('/')) {
      final bu = _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
      return '$bu$url';
    }
    // relative path fallback
    return Uri.parse(_baseUrl).resolve(url).toString();
  }

  IOClient _buildClient() {
    final s = SettingsService.instance.value;
    final httpClient = HttpClient();
    String? proxy = s.proxy?.trim();
    if (proxy != null && proxy.isNotEmpty) {
      // 允许带协议或不带协议的写法
      proxy = proxy.replaceFirst(RegExp(r'^https?://'), '');
      httpClient.findProxy = (uri) => 'PROXY $proxy; DIRECT';
      // 打印代理信息
      // ignore: avoid_print
      debugPrint('[LinuxDoApi] Proxy enabled: $proxy');
    }
    return IOClient(httpClient);
  }

  Future<http.Response> _get(Uri uri) async {
    final client = _buildClient();
    try {
      final h1 = _headers();
      debugPrint('[LinuxDoApi] --> GET $uri');
      debugPrint('[LinuxDoApi] UA: ${h1['User-Agent']}');
      debugPrint('[LinuxDoApi] Referer: ${h1['Referer']}');
      if (h1.containsKey('Cookie') && (h1['Cookie']?.trim().isNotEmpty == true)) {
        final cookieNames = h1['Cookie']!
            .split(';')
            .map((e) => e.trim())
            .where((e) => e.contains('='))
            .map((e) => e.split('=').first)
            .toList();
        debugPrint('[LinuxDoApi] Cookie: ${cookieNames.join(', ')}');
      }
      final response = await client.get(uri, headers: h1);
      debugPrint('[LinuxDoApi] <-- ${response.statusCode} GET $uri');
      _mergeSetCookie(response);
      return response;
    } finally {
      client.close();
    }
  }

  // 从响应头中合并 Set-Cookie（若有）到本地 Cookies
  void _mergeSetCookie(http.Response res) {
    final setCookie = res.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) return;
    final existing = SettingsService.instance.value.cookies ?? '';
    final current = <String, String>{}
      ..addEntries(existing.split(';').map((e) => e.trim()).where((e) => e.contains('=')).map((kv) {
        final i = kv.indexOf('=');
        final name = kv.substring(0, i).trim();
        final value = kv.substring(i + 1).trim();
        return MapEntry(name, value);
      }));
    final reg = RegExp(r'(?:(?<=^)|(?<=, ))([^=; ,]+)=([^;]+)');
    for (final m in reg.allMatches(setCookie)) {
      final name = m.group(1);
      final value = m.group(2);
      if (name != null && value != null) {
        if (name.toLowerCase() == 'path' || name.toLowerCase() == 'expires' || name.toLowerCase() == 'httponly' || name.toLowerCase() == 'secure' || name.toLowerCase() == 'samesite' || name.toLowerCase() == 'domain') {
          continue;
        }
        current[name] = value;
      }
    }
    final merged = current.entries.map((e) => '${e.key}=${e.value}').join('; ');
    SettingsService.instance.update(cookies: merged);
    debugPrint('[LinuxDoApi] Set-Cookie merged -> ${current.keys.join(', ')}');
  }

  Future<LatestPage> fetchLatest({String? moreTopicsUrl, int? page}) async {
    Uri uri;
    if (moreTopicsUrl != null && moreTopicsUrl.isNotEmpty) {
      // 支持使用 JSON 返回的 more_topics_url 继续分页
      var u = Uri.parse(_baseUrl).resolve(moreTopicsUrl);
      // more_topics_url 通常不带 .json，这里补上以获取 JSON 响应
      if (!(u.path.endsWith('.json'))) {
        final segments = List<String>.from(u.pathSegments);
        if (segments.isNotEmpty) {
          segments[segments.length - 1] = '${segments.last}.json';
        }
        u = u.replace(pathSegments: segments);
      }
      uri = u;
    } else {
      // 首次加载 latest.json
      uri = _u('/latest.json', page != null ? {'page': page} : null);
    }
    debugPrint('[LinuxDoApi] fetchLatest url = $uri');
    final res = await _get(uri);
    if (res.statusCode != 200) {
      if (res.statusCode == 403) {
        throw ApiException(403, '需要登录');
      }
      throw ApiException(res.statusCode, '加载首页列表失败');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return LatestPage.fromJson(data);
  }

  Future<TopicDetail> fetchTopicDetail(int topicId) async {
    // Discourse 支持 /t/{id}.json 直接获取主题 + 帖子（包含 cooked HTML）
    final uri = _u('/t/$topicId.json');
    final res = await _get(uri);
    if (res.statusCode != 200) {
      if (res.statusCode == 403) {
        throw ApiException(403, '需要登录');
      }
      throw ApiException(res.statusCode, '加载帖子详情失败');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return TopicDetail.fromJson(data);
  }

  // 将帖子中的相对链接/图片地址转换为绝对地址，方便渲染
  String absolutizeHtml(String html) {
    final bu = _baseUrl;
    final prefix = bu.endsWith('/') ? bu.substring(0, bu.length - 1) : bu;
    var out = html;
    // src="/xxx" -> src="https://linux.do/xxx"
    out = out.replaceAllMapped(RegExp(r'src="/(?!/)'), (m) => 'src="$prefix/');
    // data-src 懒加载 -> src
    out = out.replaceAllMapped(RegExp(r'data-src="/(?!/)'), (m) => 'src="$prefix/');
    // srcset 相对地址补全
    out = out.replaceAllMapped(RegExp(r'srcset="/(?!/)'), (m) => 'srcset="$prefix/');
    // href="/xxx" -> href="https://linux.do/xxx"
    out = out.replaceAllMapped(RegExp(r'href="/(?!/)'), (m) => 'href="$prefix/');
    return out;
  }

  // 根据 avatar_template 生成头像地址
  String avatarUrlFromTemplate(String? template, {int size = 48}) {
    if (template == null || template.isEmpty) return '';
    var t = template.replaceAll('{size}', size.toString());
    if (t.startsWith('/')) {
      final bu = _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
      t = '$bu$t';
    }
    return t;
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}
