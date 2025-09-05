import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

import '../api/linuxdo_api.dart';
import '../models/topic.dart';
import '../services/settings.dart';
import 'topic_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'image_viewer_page.dart';
import 'settings_page.dart';
import 'web_login_page.dart';
import '../widgets/secure_image.dart';

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
  Map<int, UserBrief> _userMap = const {};
  // 记录上一版首页数据的快照，用于对比刷新前后的变化
  Map<int, _TopicSnapshot> _prevSnapshot = const <int, _TopicSnapshot>{};
  // 记录用户点击某个帖子时的快照，作为“旧数据”的锚点，避免后续所有帖子都显示更新
  final Map<int, _TopicSnapshot> _clickSnapshot = {};
  // 记录最近一次“刷新(_load)”出现的新帖 ID（不包含翻页追加的）
  Set<int> _newFromRefreshIds = <int>{};
  static const _kPrevSnapshotKey = 'homePrevSnapshot';
  static const _kClickSnapshotKey = 'homeClickSnapshot';

  _TopicSnapshot _snapshotOf(TopicSummary t) => _TopicSnapshot(
        replies: t.replyCount ?? t.postsCount ?? 0,
        lastPostedAt: t.lastPostedAt,
      );

  bool _isUpdated(TopicSummary t) {
    final now = _snapshotOf(t);
    final base = _clickSnapshot[t.id] ?? _prevSnapshot[t.id];
    // 若不存在基准，仅当其属于最近一次“刷新”新增的帖子且历史快照非空时标红；
    // 这样通过“上拉加载更多”新增的帖子不会被标红；
    // 首次启动（无历史快照）也不标红，避免全屏红点。
    if (base == null) return _prevSnapshot.isNotEmpty && _newFromRefreshIds.contains(t.id);
    final repliesIncreased = now.replies > base.replies;
    final lastMoved = (now.lastPostedAt != null && base.lastPostedAt != null)
        ? now.lastPostedAt!.isAfter(base.lastPostedAt!)
        : false;
    return repliesIncreased || lastMoved;
  }

  Future<void> _restoreSnapshots() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prevStr = prefs.getString(_kPrevSnapshotKey) ?? '';
      final clickStr = prefs.getString(_kClickSnapshotKey) ?? '';
      if (prevStr.isNotEmpty) {
        _prevSnapshot = _decodeSnapshotMap(prevStr);
      }
      if (clickStr.isNotEmpty) {
        _clickSnapshot
          ..clear()
          ..addAll(_decodeSnapshotMap(clickStr));
      }
    } catch (_) {}
  }

  Future<void> _savePrevSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrevSnapshotKey, _encodeSnapshotMap(_prevSnapshot));
    } catch (_) {}
  }

  Future<void> _saveClickSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kClickSnapshotKey, _encodeSnapshotMap(_clickSnapshot));
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _restoreSnapshots().whenComplete(_load);
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
        // 在覆盖 _topics 之前先保存一份旧数据的快照，供更新标记对比
        if (_topics.isNotEmpty) {
          _prevSnapshot = {for (final t in _topics) t.id: _snapshotOf(t)};
          // 计算本次刷新产生的新帖集合（不包含翻页追加）
          _newFromRefreshIds = {
            for (final t in page.topics)
              if (!_prevSnapshot.containsKey(t.id)) t.id,
          };
          // 持久化上一版快照
          _savePrevSnapshot();
        } else {
          // 首次加载：没有历史快照，不标红；也清空刷新新增集合
          _newFromRefreshIds = <int>{};
        }
        _topics = page.topics;
        _moreTopicsUrl = page.moreTopicsUrl;
        _noMore = _moreTopicsUrl == null;
        _userMap = {for (final u in page.users) u.id: u};
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
          _userMap.addAll({for (final u in page.users) u.id: u});
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
          final authorId = t.postersUserIds.isNotEmpty ? t.postersUserIds.first : null;
          final user = authorId != null ? _userMap[authorId] : null;
          final avatarUrl = _api.avatarUrlFromTemplate(user?.avatarTemplate, size: 48);
          if (kDebugMode && avatarUrl.isNotEmpty) {
            debugPrint('[Avatar] Home user=${user?.username ?? '-'} url=$avatarUrl');
          }
          return ListTile(
            leading: SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () async {
                        if (avatarUrl.isNotEmpty) {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ImageViewerPage(url: avatarUrl)),
                          );
                        }
                      },
                      child: ClipOval(
                        child: (avatarUrl.isNotEmpty)
                            ? SecureImage(
                                url: avatarUrl,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                error: Container(
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.person_outline),
                                ),
                              )
                            : CircleAvatar(
                                child: Text((t.title.isNotEmpty ? t.title.substring(0, 1) : '#')),
                              ),
                      ),
                    ),
                  ),
                  if (_isUpdated(t))
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            title: Text(t.title),
            subtitle: Text('#${t.id}  ·  回复: ${t.replyCount ?? t.postsCount ?? '-'}  ·  浏览: ${t.views ?? '-'}  ·  赞: ${t.likeCount ?? '-'}'),
            onTap: () {
              // 点击时将当前数据作为“旧数据”锚点记录下来，避免后续自动刷新导致整页红点
              setState(() {
                _clickSnapshot[t.id] = _snapshotOf(t);
              });
              _saveClickSnapshot();
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

class _TopicSnapshot {
  final int replies;
  final DateTime? lastPostedAt;
  const _TopicSnapshot({required this.replies, required this.lastPostedAt});

  Map<String, dynamic> toJson() => {
        'r': replies,
        't': lastPostedAt?.toIso8601String(),
      };

  static _TopicSnapshot fromJson(Map<String, dynamic> json) {
    DateTime? ts;
    final t = json['t'];
    if (t is String && t.isNotEmpty) {
      ts = DateTime.tryParse(t);
    }
    return _TopicSnapshot(
      replies: (json['r'] is int) ? json['r'] as int : int.tryParse('${json['r']}') ?? 0,
      lastPostedAt: ts,
    );
  }
}

String _encodeSnapshotMap(Map<int, _TopicSnapshot> m) {
  final map = <String, dynamic>{
    for (final e in m.entries) e.key.toString(): e.value.toJson(),
  };
  return const JsonEncoder().convert(map);
}

Map<int, _TopicSnapshot> _decodeSnapshotMap(String s) {
  try {
    final raw = const JsonDecoder().convert(s);
    if (raw is Map) {
      final out = <int, _TopicSnapshot>{};
      raw.forEach((k, v) {
        final id = int.tryParse('$k');
        if (id != null && v is Map) {
          out[id] = _TopicSnapshot.fromJson(v.cast<String, dynamic>());
        }
      });
      return out;
    }
  } catch (_) {}
  return <int, _TopicSnapshot>{};
}
