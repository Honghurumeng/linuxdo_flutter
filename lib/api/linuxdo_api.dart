import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
// io_client no longer used here


import '../models/topic.dart';
import '../services/settings.dart';
import '../services/session.dart';
// typed_data is available via flutter foundation; no direct import needed

class LinuxDoApi {
  LinuxDoApi({this.baseUrl});

  final String? baseUrl;

  String get _baseUrl => (baseUrl ?? SettingsService.instance.value.baseUrl).trim();

  // 请求头构造逻辑已集中在 Session，仅保留图片头部在本类（imageHeaders）

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

  // 网络客户端统一由 Session 管理

  Future<http.Response> _get(Uri uri) {
    return Session.instance.fetchJsonUri(uri);
  }

  // Set-Cookie 的合并与挑战处理由 Session 统一负责

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
    final candidates = <String>{toOriginalImageUrl(url), url}.toList();
    for (final u in candidates) {
      try {
        final r = await Session.instance.fetchBytes(u);
        final bytes = r['bytes'] as Uint8List;
        final ct = (r['contentType'] ?? '').toString().toLowerCase();
        final isSvg = ct.contains('svg') || ct.contains('image/svg+xml');
        if (kDebugMode) {
          debugPrint('[LinuxDoApi] IMG ok ${bytes.length}B $u');
          debugPrint('[LinuxDoApi] Content-Type: ${r['contentType']}');
        }
        return {
          'bytes': bytes,
          'isSvg': isSvg,
        };
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[LinuxDoApi] IMG fail for $u: $e');
        }
        // try next candidate
      }
    }
    // 仍未成功
    final uri = Uri.parse(candidates.last);
    throw HttpException('Failed to fetch image', uri: uri);
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
