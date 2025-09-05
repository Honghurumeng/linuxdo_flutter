import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../api/linuxdo_api.dart';
import '../models/topic.dart';
import '../widgets/secure_image.dart';
import 'image_viewer_page.dart';
import 'topic_detail_page.dart';
import 'web_login_page.dart';

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
  Map<int, UserBrief> _userMap = const {};

  Future<void> _doSearch(String q) async {
    final query = q.trim();
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
        _userMap = {for (final u in res.users) u.id: u};
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

  @override
  void initState() {
    super.initState();
    // autofocus 稍后在第一帧完成后请求，避免 build 报错
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
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
    if (_results.isEmpty) {
      return const Center(child: Text('输入关键词进行搜索'));
    }
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
    );
  }
}

