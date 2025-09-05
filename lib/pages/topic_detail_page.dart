import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
// import 'package:flutter/foundation.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/linuxdo_api.dart';
import '../models/topic.dart';
import 'web_login_page.dart';
import '../widgets/secure_image.dart';
import 'image_viewer_page.dart';

class TopicDetailPage extends StatefulWidget {
  const TopicDetailPage({super.key, required this.topicId, required this.title});

  final int topicId;
  final String title;

  @override
  State<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends State<TopicDetailPage> {
  final _api = LinuxDoApi();
  late Future<TopicDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchTopicDetail(widget.topicId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _future = _api.fetchTopicDetail(widget.topicId)),
          ),
        ],
      ),
      body: FutureBuilder<TopicDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final err = snap.error;
            if (err is ApiException && err.statusCode == 403) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('请先登录'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text('去登录'),
                      onPressed: () async {
                        final updated = await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const WebLoginPage()),
                        );
                        if (updated == true) {
                          setState(() => _future = _api.fetchTopicDetail(widget.topicId));
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('刷新'),
                      onPressed: () => setState(() => _future = _api.fetchTopicDetail(widget.topicId)),
                    ),
                  ],
                ),
              );
            }
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('加载失败: $err'),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => setState(() => _future = _api.fetchTopicDetail(widget.topicId)),
                    child: const Text('重试'),
                  )
                ],
              ),
            );
          }
          final detail = snap.data!;
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: detail.posts.length,
            separatorBuilder: (_, __) => const Divider(height: 24),
            itemBuilder: (context, index) {
              final p = detail.posts[index];
              final cooked = _api.absolutizeHtml(p.cookedHtml);
              final avatarUrl = _api.avatarUrlFromTemplate(p.avatarTemplate, size: 40);
              if (kDebugMode && avatarUrl.isNotEmpty) {
                debugPrint('[Avatar] Detail user=@${p.username} url=$avatarUrl');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: GestureDetector(
                          onTap: () async {
                            if (avatarUrl.isNotEmpty) {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ImageViewerPage(url: avatarUrl),
                                ),
                              );
                            }
                          },
                          child: ClipOval(
                            child: (avatarUrl.isNotEmpty)
                                ? SecureImage(
                                    url: avatarUrl,
                                    width: 32,
                                    height: 32,
                                    fit: BoxFit.cover,
                                    error: Container(
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.person_outline, size: 16),
                                    ),
                                  )
                                : CircleAvatar(
                                    radius: 16,
                                    child: Text(p.username.isNotEmpty ? p.username.substring(0, 1) : '?'),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('@${p.username}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Text(
                        p.createdAt?.toLocal().toString() ?? '',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  HtmlWidget(
                    cooked,
                    onTapUrl: (url) async {
                      final uri = Uri.tryParse(url);
                      if (uri != null) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                        return true;
                      }
                      return false;
                    },
                    // 覆盖 <img> 渲染，携带 Cookie/UA 以避免 403，并支持点击外部打开
                    customWidgetBuilder: (element) {
                      try {
                        if (element.localName == 'img') {
                          final attrs = element.attributes;
                          String raw = attrs['src'] ?? attrs['data-src'] ?? '';
                          if (raw.isEmpty && attrs['srcset'] != null) {
                            final ss = attrs['srcset']!;
                            // 取 srcset 里的第一个 URL
                            final first = ss.split(',').first.trim();
                            final sp = first.split(' ');
                            if (sp.isNotEmpty) raw = sp.first.trim();
                          }
                          if (raw.isEmpty) return null;
                          final url = _api.absolutizeUrl(raw);
                          if (kDebugMode) {
                            debugPrint('[Image] Detail url=$url');
                          }
                          // emoji 图片：按文字字号渲染，内联显示
                          final cls = attrs['class'] ?? '';
                          final isEmoji = cls.contains('emoji') ||
                              url.contains('/images/emoji/') ||
                              url.contains('/emoji/twemoji/') ||
                              url.contains('/twemoji/');
                          if (isEmoji) {
                            final fontSize = DefaultTextStyle.of(context).style.fontSize ??
                                Theme.of(context).textTheme.bodyMedium?.fontSize ??
                                14.0;
                            return SizedBox(
                              width: fontSize,
                              height: fontSize,
                              child: SecureImage(
                                url: url,
                                width: fontSize,
                                height: fontSize,
                                fit: BoxFit.contain,
                              ),
                            );
                          }
                          // 普通图片：保留点击放大与错误提示
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: GestureDetector(
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ImageViewerPage(url: url),
                                  ),
                                );
                              },
                              child: SecureImage(
                                url: url,
                                fit: BoxFit.contain,
                                error: Container(
                                  color: Colors.grey.shade100,
                                  padding: const EdgeInsets.all(8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.image_not_supported_outlined, size: 16),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          '图片受保护，点击外部打开',
                                          style: Theme.of(context).textTheme.bodySmall,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                      } catch (_) {}
                      return null;
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
