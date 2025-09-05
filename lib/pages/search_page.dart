import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../api/linuxdo_api.dart';
import '../models/topic.dart';
import '../widgets/secure_image.dart';
import 'image_viewer_page.dart';
import 'topic_detail_page.dart';
import 'web_login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _api = LinuxDoApi();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _loading = false;
  String? _error;
  bool _authRequired = false;
  List<TopicSummary> _results = const [];
  List<SearchPost> _postResults = const [];
  Map<int, UserBrief> _userMap = const {};
  Map<int, TopicSummary> _topicMap = const {};
  static const _kHistoryKey = 'search_history';
  List<String> _history = const [];
  SearchScope _scope = SearchScope.all; // 按你说的方式：不改写范围

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '-';
    final d = dt.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final mo = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$y-$mo-$da $h:$mi';
  }

  String _formatRelative(DateTime? dt) {
    if (dt == null) return '-';
    final now = DateTime.now();
    final d = dt.toLocal();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟';
    if (diff.inHours < 24) return '${diff.inHours} 小时';
    if (diff.inDays < 30) return '${diff.inDays} 天';
    final months = (diff.inDays / 30).floor();
    if (months < 12) return '$months 个月';
    final years = (months / 12).floor();
    return '$years 年';
  }

  String _stripHtml(String s) {
    // 去掉 HTML 标签与多余空白，保留内容
    final noTags = s.replaceAll(RegExp(r'<[^>]*>'), '');
    final noEntities = noTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    return noEntities.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _history = prefs.getStringList(_kHistoryKey) ?? [];
    });
  }

  Future<void> _saveHistory(String query) async {
    final prefs = await SharedPreferences.getInstance();
    var list = List<String>.from(_history);
    list.removeWhere((e) => e == query);
    list.insert(0, query);
    if (list.length > 20) list = list.sublist(0, 20);
    await prefs.setStringList(_kHistoryKey, list);
    setState(() => _history = list);
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHistoryKey);
    setState(() => _history = []);
  }

  Future<void> _doSearch(String q) async {
    var query = q.trim();
    query = _applyScopeToQuery(query);
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _authRequired = false;
    });
    try {
      final res = await _api.searchTopics(query);
      setState(() {
        _results = res.topics;
        _postResults = res.posts;
        _userMap = {for (final u in res.users) u.id: u};
        _topicMap = {for (final t in res.topics) t.id: t};
      });
      await _saveHistory(query);
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

  String _applyScopeToQuery(String q) {
    var out = q;
    // 若未指定排序，则自动追加 order:latest
    final hasOrder = RegExp(r'(^|\s)order:', caseSensitive: false).hasMatch(out);
    if (!hasOrder) {
      out = out.isEmpty ? 'order:latest' : '$out order:latest';
    }
    // 仅当用户在菜单里选择范围时才追加 in:xxx；否则不添加
    final hasExplicitScope = RegExp(r'(^|\s)in:').hasMatch(out);
    if (!hasExplicitScope) {
      switch (_scope) {
        case SearchScope.all:
          break;
        case SearchScope.titles:
          out = '$out in:title';
          break;
        case SearchScope.posts:
          out = '$out in:posts';
          break;
      }
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    // autofocus 稍后在第一帧完成后请求，避免 build 报错
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: _doSearch,
            decoration: InputDecoration(
              hintText: '搜索帖子…',
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: (_controller.text.isNotEmpty)
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _controller.clear();
                          _results = const [];
                          _error = null;
                          _authRequired = false;
                        });
                        _focusNode.requestFocus();
                      },
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => _doSearch(_controller.text),
          ),
          PopupMenuButton<SearchScope>(
            tooltip: '匹配范围',
            icon: const Icon(Icons.tune),
            onSelected: (v) => setState(() => _scope = v),
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: SearchScope.posts,
                checked: _scope == SearchScope.posts,
                child: const Text('仅内容'),
              ),
              CheckedPopupMenuItem(
                value: SearchScope.titles,
                checked: _scope == SearchScope.titles,
                child: const Text('仅标题'),
              ),
              CheckedPopupMenuItem(
                value: SearchScope.all,
                checked: _scope == SearchScope.all,
                child: const Text('全部'),
              ),
            ],
          ),
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
            const Text('搜索需要登录'),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.account_circle_outlined),
              label: const Text('去登录'),
              onPressed: () async {
                final updated = await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WebLoginPage()),
                );
                if (updated == true) {
                  if (_controller.text.trim().isNotEmpty) _doSearch(_controller.text);
                }
              },
            ),
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
            FilledButton(onPressed: () => _doSearch(_controller.text), child: const Text('重试')),
          ],
        ),
      );
    }
    if (_results.isEmpty && _postResults.isEmpty) {
      if (_history.isEmpty) {
        return const Center(child: Text('输入关键词进行搜索'));
      }
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('搜索历史', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _clearHistory,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('清空'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _history.map((h) {
                return ActionChip(
                  label: Text(h, overflow: TextOverflow.ellipsis),
                  onPressed: () {
                    _controller.text = h;
                    _focusNode.unfocus();
                    _doSearch(h);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
      );
    }
    final items = _postResults.isNotEmpty ? _postResults : _results;
    // 若 API 未返回 posts，则退化为仅按主题展示（旧行为）
    final isPostMode = items is List<SearchPost> || _postResults.isNotEmpty;
    if (isPostMode) {
      return ListView.separated(
        itemCount: _postResults.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final p = _postResults[index];
          final t = _topicMap[p.topicId];
          final title = t?.title ?? '';
          final avatarUrl = _api.avatarUrlFromTemplate(p.avatarTemplate, size: 40);
          if (kDebugMode && avatarUrl.isNotEmpty) {
            debugPrint('[Avatar] Search post user=${p.username} url=$avatarUrl');
          }
          return ListTile(
            leading: SizedBox(
              width: 40,
              height: 40,
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
                          child: Text((p.username.isNotEmpty ? p.username.substring(0, 1) : '#')),
                        ),
                ),
              ),
            ),
            title: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: p.username, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const TextSpan(text: '  '),
                  TextSpan(text: title),
                ],
                style: Theme.of(context).textTheme.titleMedium,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Builder(builder: (context) {
              final floor = (p.postNumber != null && p.postNumber! > 1)
                  ? ' · ${p.postNumber} 楼'
                  : '';
              return Text(
                '${_formatRelative(p.createdAt)}$floor - ${_stripHtml(p.blurb)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              );
            }),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TopicDetailPage(
                    topicId: p.topicId,
                    title: title.isEmpty ? '详情' : title,
                    initialPostNumber: p.postNumber,
                    initialPostId: p.id,
                  ),
                ),
              );
            },
          );
        },
      );
    }
    // 主题模式（无 posts）
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final t = _results[index];
        final authorId = t.postersUserIds.isNotEmpty ? t.postersUserIds.first : null;
        final user = authorId != null ? _userMap[authorId] : null;
        final avatarUrl = _api.avatarUrlFromTemplate(user?.avatarTemplate, size: 40);
        if (kDebugMode && avatarUrl.isNotEmpty) {
          debugPrint('[Avatar] Search user=${user?.username ?? '-'} url=$avatarUrl');
        }
        return ListTile(
          leading: SizedBox(
            width: 40,
            height: 40,
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
          title: Text(t.title),
          subtitle: Text('#${t.id}  ·  楼层: ${t.postsCount ?? '-'}  ·  回复: ${t.replyCount ?? '-'}  ·  最后回复: ${_formatDateTime(t.lastPostedAt)}  ·  浏览: ${t.views ?? '-'}  ·  赞: ${t.likeCount ?? '-'}'),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TopicDetailPage(topicId: t.id, title: t.title),
              ),
            );
          },
        );
      },
    );
  }
}

enum SearchScope { all, titles, posts }
