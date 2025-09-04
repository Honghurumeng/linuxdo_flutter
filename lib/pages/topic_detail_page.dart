import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/linuxdo_api.dart';
import '../models/topic.dart';
import 'web_login_page.dart';

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
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '@${p.username}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
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
