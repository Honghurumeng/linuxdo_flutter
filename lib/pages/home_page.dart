import 'package:flutter/material.dart';

import '../api/linuxdo_api.dart';
import '../models/topic.dart';
import '../services/settings.dart';
import 'topic_detail_page.dart';
import 'settings_page.dart';
import 'web_login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _api = LinuxDoApi();
  final _scrollController = ScrollController();
  var _loading = true;
  String? _error;
  List<TopicSummary> _topics = const [];
  String? _moreTopicsUrl; // 服务端给出的下一页链接
  bool _loadingMore = false;
  bool _noMore = false;
  bool _authRequired = false;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_maybeLoadMore);
    SettingsService.instance.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    // 设置变化后，重载列表
    _load();
  }

  void _maybeLoadMore() {
    if (_noMore || _loadingMore || _loading) return;
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _noMore = false;
      _moreTopicsUrl = null;
      _authRequired = false;
    });
    try {
      final page = await _api.fetchLatest();
      setState(() {
        _topics = page.topics;
        _moreTopicsUrl = page.moreTopicsUrl;
        _noMore = _moreTopicsUrl == null;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        setState(() => _authRequired = true);
      } else {
        setState(() => _error = e.toString());
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      if (_moreTopicsUrl == null) {
        setState(() => _noMore = true);
        return;
      }
      final page = await _api.fetchLatest(moreTopicsUrl: _moreTopicsUrl);
      if (page.topics.isEmpty) {
        setState(() => _noMore = true);
      } else {
        setState(() {
          _topics = [..._topics, ...page.topics];
          _moreTopicsUrl = page.moreTopicsUrl;
          _noMore = _moreTopicsUrl == null;
        });
      }
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        setState(() => _authRequired = true);
      }
    } catch (_) {
      // 忽略翻页错误，用户可下拉刷新
    } finally {
      setState(() => _loadingMore = false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    SettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LinuxDo 主页帖子'),
        actions: [
          IconButton(
            tooltip: '刷新列表',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          IconButton(
            tooltip: '站内登录（获取Cookies）',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () async {
              final updated = await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WebLoginPage()),
              );
              if (updated == true) {
                _load();
              }
            },
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              final updated = await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
              if (updated == true) {
                _load();
              }
            },
          )
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_authRequired) {
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
                if (updated == true) _load();
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
              onPressed: _load,
            )
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _scrollController,
        itemCount: _topics.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == _topics.length) {
            if (_noMore) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('没有更多了')),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _loadingMore
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('上拉加载更多…'),
              ),
            );
          }
          final t = _topics[index];
          return ListTile(
            title: Text(t.title),
            subtitle: Text('#${t.id}  ·  回复: ${t.replyCount ?? t.postsCount ?? '-'}  ·  浏览: ${t.views ?? '-'}  ·  赞: ${t.likeCount ?? '-'}'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TopicDetailPage(topicId: t.id, title: t.title),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
