import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/topic.dart';
import '../services/settings.dart';

class LinuxDoApi {
  LinuxDoApi({this.baseUrl});

  final String? baseUrl;

  String get _baseUrl => (baseUrl ?? SettingsService.instance.value.baseUrl).trim();

  Map<String, String> _headers({String? ua}) => {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'User-Agent': ua ??
            (SettingsService.instance.value.userAgent?.trim().isNotEmpty == true
                ? SettingsService.instance.value.userAgent!.trim()
                :
            // 模拟常见 Android 移动端浏览器 UA，规避部分反爬拦截
            'Mozilla/5.0 (Linux; Android 14; Pixel 7 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36'),
        'Referer': _baseUrl.endsWith('/') ? _baseUrl : '$_baseUrl/',
        'Connection': 'keep-alive',
      };

  Uri _u(String path, [Map<String, dynamic>? q]) => Uri.parse(_baseUrl).replace(
        path: path,
        queryParameters: q?.map((k, v) => MapEntry(k, v.toString())),
      );

  IOClient _buildClient() {
    final s = SettingsService.instance.value;
    final httpClient = HttpClient();
    String? proxy = s.proxy?.trim();
    if (proxy != null && proxy.isNotEmpty) {
      // 允许带协议或不带协议的写法
      proxy = proxy.replaceFirst(RegExp(r'^https?://'), '');
      httpClient.findProxy = (uri) => 'PROXY $proxy; DIRECT';
    }
    return IOClient(httpClient);
  }

  Future<http.Response> _get(Uri uri) async {
    final client = _buildClient();
    // 首次使用 Android Chrome UA，请求失败（403/429/503）时再用 iOS Safari UA 重试一次
    try {
      final primary = await client.get(uri, headers: _headers());
      if (primary.statusCode == 403 || primary.statusCode == 429 || primary.statusCode == 503) {
        await Future.delayed(const Duration(milliseconds: 200));
        final iosUa =
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
        final fallback = await client.get(uri, headers: _headers(ua: iosUa));
        return fallback;
      }
      return primary;
    } finally {
      client.close();
    }
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
    final res = await _get(uri);
    if (res.statusCode != 200) {
      throw Exception('加载首页列表失败: ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return LatestPage.fromJson(data);
  }

  Future<TopicDetail> fetchTopicDetail(int topicId) async {
    // Discourse 支持 /t/{id}.json 直接获取主题 + 帖子（包含 cooked HTML）
    final uri = _u('/t/$topicId.json');
    final res = await _get(uri);
    if (res.statusCode != 200) {
      throw Exception('加载帖子详情失败: ${res.statusCode}');
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
    // href="/xxx" -> href="https://linux.do/xxx"
    out = out.replaceAllMapped(RegExp(r'href="/(?!/)'), (m) => 'href="$prefix/');
    return out;
  }
}
