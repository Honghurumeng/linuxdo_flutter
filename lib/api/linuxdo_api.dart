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
    final bu = Uri.parse(_baseUrl);
    final origin = '${bu.scheme}://${bu.host}${bu.hasPort ? ':${bu.port}' : ''}';
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
        'Origin': origin,
        // 模拟浏览器请求特征，降低 Cloudflare/BIC 误判
        'X-Requested-With': 'XMLHttpRequest',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-origin',
        'Sec-Fetch-Dest': 'empty',
        'Connection': 'keep-alive',
      };
    if (cookies != null && cookies.isNotEmpty) {
      h['Cookie'] = cookies;
    }
    return h;
  }

  // 已简化为直接使用默认 GET 加载图片，不再提供专门的图片头部
  Map<String, String> imageHeaders() {
    final s = SettingsService.instance.value;
    final ua = (s.userAgent?.trim().isNotEmpty == true)
        ? s.userAgent!.trim()
        : 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36';
    final ref = _baseUrl.endsWith('/') ? _baseUrl : '$_baseUrl/';
    final bu = Uri.parse(_baseUrl);
    final origin = '${bu.scheme}://${bu.host}${bu.hasPort ? ':${bu.port}' : ''}';
    final h = <String, String>{
      'User-Agent': ua,
      'Referer': ref,
      'Origin': origin,
      'Sec-Fetch-Mode': 'no-cors',
      'Sec-Fetch-Site': 'same-origin',
      'Sec-Fetch-Dest': 'image',
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Connection': 'keep-alive',
    };
    final cookies = s.cookies?.trim();
    if (cookies != null && cookies.isNotEmpty) {
      h['Cookie'] = cookies;
    }
    return h;
  }

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
      // 打印代理信息（仅 Debug）
      if (kDebugMode) {
        debugPrint('[LinuxDoApi] Proxy enabled: $proxy');
      }
    }
    return IOClient(httpClient);
  }

  Future<http.Response> _get(Uri uri) async {
    final client = _buildClient();
    try {
      final h1 = _headers();
      if (kDebugMode) {
        debugPrint('[LinuxDoApi] --> GET $uri');
        debugPrint('[LinuxDoApi] UA: ${h1['User-Agent']}');
        debugPrint('[LinuxDoApi] Referer: ${h1['Referer']}');
      }
      if (h1.containsKey('Cookie') && (h1['Cookie']?.trim().isNotEmpty == true)) {
        final cookieNames = h1['Cookie']!
            .split(';')
            .map((e) => e.trim())
            .where((e) => e.contains('='))
            .map((e) => e.split('=').first)
            .toList();
        if (kDebugMode) {
          debugPrint('[LinuxDoApi] Cookie: ${cookieNames.join(', ')}');
        }
      }
      http.Response response = await client.get(uri, headers: h1);
      if (kDebugMode) {
        debugPrint('[LinuxDoApi] <-- ${response.statusCode} GET $uri');
      }
      final merged = _mergeSetCookie(response);

      // 如果被 Cloudflare/服务端拦截（常见 403/503/520），且发现 Set-Cookie 发生了变更（例如下发新的 cf_clearance），
      // 则自动重试一次以提升稳定性，避免用户看到“需要登录”。
      final sc = response.statusCode;
      final server = (response.headers['server'] ?? '').toLowerCase();
      final cfRay = response.headers.containsKey('cf-ray');
      final maybeChallenged = (sc == 403 || sc == 503 || sc == 520) && (merged || server.contains('cloudflare') || cfRay);
      if (maybeChallenged) {
        if (kDebugMode) {
          debugPrint('[LinuxDoApi] Challenge suspected, retrying once with refreshed cookies...');
        }
        // 以最新 Cookie 再请求一次
        final h2 = _headers();
        response = await client.get(uri, headers: h2);
        if (kDebugMode) {
          debugPrint('[LinuxDoApi] <-- RETRY ${response.statusCode} GET $uri');
        }
        _mergeSetCookie(response);
      }
      return response;
    } finally {
      client.close();
    }
  }

  // 从响应头中合并 Set-Cookie（若有）到本地 Cookies
  bool _mergeSetCookie(http.Response res) {
    final setCookie = res.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) return false;
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
        // 忽略服务端要求删除的 cookie 值（常见 value 为 'deleted' 或空），避免短时间内误删 cf_clearance 等关键值
        final v = value.trim();
        if (v.isEmpty || v.toLowerCase() == 'deleted') continue;
        current[name] = value;
      }
    }
    final merged = current.entries.map((e) => '${e.key}=${e.value}').join('; ');
    final changed = merged.trim() != existing.trim();
    if (changed) {
      SettingsService.instance.update(cookies: merged);
      if (kDebugMode) {
        debugPrint('[LinuxDoApi] Set-Cookie merged -> ${current.keys.join(', ')}');
      }
    }
    return changed;
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
    if (kDebugMode) {
      debugPrint('[LinuxDoApi] fetchLatest url = $uri');
    }
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

  // 搜索帖子（按关键词），返回主题列表与相关用户
  Future<SearchResult> searchTopics(String query, {int? page}) async {
    // 按用户习惯：不额外添加 include_* 参数，完全由 query 决定行为
    final params = <String, dynamic>{
      'q': query,
    };
    if (page != null) params['page'] = page;
    final uri = _u('/search.json', params);
    final res = await _get(uri);
    if (res.statusCode != 200) {
      if (res.statusCode == 403) {
        throw ApiException(403, '需要登录');
      }
      throw ApiException(res.statusCode, '搜索失败');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return SearchResult.fromJson(data);
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

  // 将 optimized 的图片 URL 转为 original 原图 URL（若匹配）
  String toOriginalImageUrl(String url) {
    try {
      final u = Uri.parse(url);
      final ps = List<String>.from(u.pathSegments);
      if (ps.length >= 6 && ps[0] == 'uploads' && ps[1] == 'default') {
        const idxType = 2; // optimized/original
        if (ps[idxType] == 'optimized') {
          ps[idxType] = 'original';
          final last = ps.last;
          final newLast = last.replaceAll(RegExp(r'_(?:\d+_)?\d+x\d+(?=\.)'), '');
          ps[ps.length - 1] = newLast;
          final replaced = u.replace(pathSegments: ps);
          return replaced.toString();
        }
      }
    } catch (_) {}
    return url;
  }

  // 获取图片字节和类型信息
  Future<Map<String, dynamic>> fetchImageBytesWithType(String url) async {
    final client = _buildClient();
    try {
      final candidates = <String>{toOriginalImageUrl(url), url}.toList();
      http.Response? res;
      late Uri uri;
      for (final u in candidates) {
        uri = Uri.parse(u);
        res = await client.get(uri, headers: imageHeaders());
        if (kDebugMode) {
          debugPrint('[LinuxDoApi] IMG try ${res.statusCode} $uri');
          debugPrint('[LinuxDoApi] Content-Type: ${res.headers['content-type']}');
        }
        if (res.statusCode == 200) {
          final contentType = res.headers['content-type'] ?? '';
          return {
            'bytes': res.bodyBytes,
            'isSvg': contentType.toLowerCase().contains('svg') || contentType.toLowerCase().contains('image/svg+xml'),
          };
        }
      }
      // 仍未成功
      throw HttpException('HTTP ${res?.statusCode ?? -1}', uri: uri);
    } finally {
      client.close();
    }
  }

  // 兜底：以带头方式抓取图片字节，便于在 CF/鉴权场景下展示
  Future<Uint8List> fetchImageBytes(String url) async {
    final result = await fetchImageBytesWithType(url);
    return result['bytes'] as Uint8List;
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}
