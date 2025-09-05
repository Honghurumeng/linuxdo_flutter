import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
// import 'package:flutter/foundation.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/linuxdo_api.dart';
import '../models/topic.dart';
import 'web_login_page.dart';
import '../widgets/secure_image.dart';
import 'image_viewer_page.dart';

class TopicDetailPage extends StatefulWidget {
  const TopicDetailPage({
    super.key,
    required this.topicId,
    required this.title,
    this.initialPostNumber,
    this.initialPostId,
  });

  final int topicId;
  final String title;
  // 进入详情页时，若提供了楼层号，则尝试自动滚动到该楼层
  final int? initialPostNumber;
  // 若提供帖子 ID，优先按 ID 精准定位
  final int? initialPostId;

  @override
  State<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends State<TopicDetailPage> {
  final _api = LinuxDoApi();
  late Future<TopicDetail> _future;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {}; // 列表 index -> key（含标题头部）
  bool _didAutoScroll = false;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchTopicDetail(widget.topicId);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('详情'),
        actions: [
          IconButton(
            tooltip: '跳到顶部',
            icon: const Icon(Icons.vertical_align_top),
            onPressed: () {
              // 滚动到顶部
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            },
          ),
          IconButton(
            tooltip: '在浏览器中查看',
            icon: const Icon(Icons.open_in_browser),
            onPressed: () async {
              final uri = Uri.parse('https://linux.do/t/${widget.topicId}');
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
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
          // 数据到达后尝试滚动到指定楼层（若提供）
          WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoScroll(detail));
          return ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: detail.posts.length + 1, // +1 for title header
            separatorBuilder: (context, index) {
              // 在标题卡片(index=0)和第一个帖子之间不显示分割线
              if (index == 0) {
                return const SizedBox(height: 8);
              }
              return const Divider(height: 24);
            },
            itemBuilder: (context, index) {
              if (index == 0) {
                // 显示完整标题
                return Container(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).shadowColor.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (detail.posts.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        RichText(
                          text: TextSpan(
                            children: [
                              const TextSpan(
                                text: '作者: ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              if (detail.posts[0].name != null && detail.posts[0].name!.isNotEmpty)
                                TextSpan(
                                  text: detail.posts[0].name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              if (detail.posts[0].name != null && detail.posts[0].name!.isNotEmpty)
                                const TextSpan(text: ' '),
                              TextSpan(
                                text: '@${detail.posts[0].username}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w300,
                                  color: Colors.grey,
                                ),
                              ),
                              TextSpan(
                                text: ' · ${detail.posts[0].createdAt?.toLocal().toString().split('.')[0] ?? ''}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }
              final p = detail.posts[index - 1]; // 调整索引
              final cooked = _api.absolutizeHtml(p.cookedHtml);
              final avatarUrl = _api.avatarUrlFromTemplate(p.avatarTemplate, size: 40);
              if (kDebugMode && avatarUrl.isNotEmpty) {
                debugPrint('[Avatar] Detail user=@${p.username} url=$avatarUrl');
              }
              final createdStr = p.createdAt?.toLocal().toString().split('.')[0] ?? '';
              final key = _itemKeys.putIfAbsent(index, () => GlobalKey());
              return Container(
                key: key,
                child: Column(
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
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            RichText(
                              text: TextSpan(
                                children: [
                                  if (p.name != null && p.name!.isNotEmpty)
                                    TextSpan(
                                      text: p.name,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                  if (p.name != null && p.name!.isNotEmpty)
                                    const TextSpan(text: ' '),
                                  TextSpan(
                                    text: '@${p.username}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w300,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              softWrap: true,
                            ),
                            if (detail.posts.isNotEmpty && p.username == detail.posts[0].username)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  '楼主',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            Text(
                              createdStr,
                              style: Theme.of(context).textTheme.bodySmall,
                              softWrap: true,
                            ),
                          ],
                        ),
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
                    customStylesBuilder: (element) {
                       if (element.classes.contains('quote') || element.classes.contains('quote-modified')) {
                         return {
                           'background-color': '#f5f5f5',
                           'border-left': '3px solid #ddd',
                           'padding': '12px',
                           'margin': '8px 0',
                           'border-radius': '4px',
                           'font-size': '14px',
                           'color': '#666',
                         };
                       }
                       // 行内代码样式（不做语法高亮，仅底色和等宽字体）
                       if (element.localName == 'code' && element.parent?.localName != 'pre') {
                         return {
                           'background-color': '#f6f8fa',
                           'border-radius': '4px',
                           'padding': '2px 4px',
                           'font-family': 'monospace',
                           'font-size': '90%'
                         };
                       }
                       // 代码块外围 <pre> 简单留白（实际渲染在 customWidgetBuilder 中处理）
                       if (element.localName == 'pre') {
                         return {
                           'margin': '8px 0',
                         };
                       }
                       if (element.localName == 'blockquote') {
                         return {
                           'margin': '0',
                           'padding': '0',
                         };
                       }
                       if (element.classes.contains('title')) {
                         return {
                           'display': 'flex',
                           'align-items': 'center',
                           'margin-bottom': '8px',
                           'color': '#333',
                         };
                       }
                       if (element.localName == 'img' && element.attributes['class']?.contains('avatar') == true) {
                         return {
                           'width': '20px',
                           'height': '20px',
                           'border-radius': '50%',
                           'margin-right': '8px',
                         };
                       }
                       if (element.classes.contains('quote-title__text-content')) {
                         return {
                           'flex': '1',
                         };
                       }
                       return null;
                     },
                    // 自定义代码块与图片渲染（代码块不做高亮，等宽字体，限定最大高度并支持滚动 + 复制）
                    customWidgetBuilder: (element) {
                      // 处理代码块 <pre><code>...</code></pre>
                      try {
                        if (element.localName == 'pre') {
                          // 取内部文本，保持转义还原
                          final text = element.text;
                          if (text.trim().isEmpty) return null;
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xfff6f8fa),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xffe1e4e8)),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Stack(
                                children: [
                                  // 限定最大高度，内部可垂直/水平滚动
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxHeight: 320),
                                    child: Scrollbar(
                                      thumbVisibility: true,
                                      child: SingleChildScrollView(
                                        padding: const EdgeInsets.fromLTRB(12, 12, 42, 12),
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: SelectableText(
                                            text,
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 13,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // 复制按钮（右上角）
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: IconButton(
                                      icon: const Icon(Icons.copy, size: 18),
                                      tooltip: '复制',
                                      onPressed: () async {
                                        await Clipboard.setData(ClipboardData(text: text));
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).clearSnackBars();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('已复制到剪贴板')),
                                          );
                                        }
                                      },
                                      padding: const EdgeInsets.all(8),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        // 行内 <code> 交给样式处理，默认返回 null 走内置渲染
                      } catch (_) {}
                      // 覆盖 <img> 渲染，携带 Cookie/UA 以避免 403，并支持点击外部打开
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
                          // 头像图片（引用标题中的用户头像）：缩小显示
                          final cls = attrs['class'] ?? '';
                          if (cls.contains('avatar')) {
                            return SizedBox(
                              width: 20,
                              height: 20,
                              child: ClipOval(
                                child: SecureImage(
                                  url: url,
                                  width: 20,
                                  height: 20,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            );
                          }
                          // emoji 图片：按文字字号渲染，内联显示
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
              ),
              );
            },
          );
        },
      ),
    );
  }

  void _maybeAutoScroll(TopicDetail detail) {
    if (_didAutoScroll) return;
    // 1) 优先使用 postId 精准定位
    int? listIndex;
    if (widget.initialPostId != null) {
      final idx = detail.posts.indexWhere((e) => e.id == widget.initialPostId);
      if (idx >= 0) listIndex = idx + 1; // +1 for header
    }
    // 2) 其次使用 postNumber
    if (listIndex == null) {
      final target = widget.initialPostNumber;
      if (target == null || target <= 1) {
        _didAutoScroll = true; // 1 楼或未提供则无需滚动
        return;
      }
      final maxPostIndex = detail.posts.length - 1;
      if (maxPostIndex < 0) {
        _didAutoScroll = true;
        return;
      }
      final postIdx = (target - 1).clamp(0, maxPostIndex); // 0-based in posts
      listIndex = postIdx + 1; // +1 for header
    }

    // 先粗略跳转到一个大致位置，促使目标 item 构建出来
    final approxOffset = ((listIndex - 1) * 220.0).toDouble();
    if (_scrollController.hasClients) {
      try {
        _scrollController.jumpTo(
          approxOffset.clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          ),
        );
      } catch (_) {}
    }

    // 再尝试精确对齐到目标项
    Future<void> tryEnsureVisible([int retry = 0]) async {
      final key = _itemKeys[listIndex!];
      final ctx = key?.currentContext;
      if (ctx != null && mounted) {
        try {
          await Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 300),
            alignment: 0.05,
          );
          _didAutoScroll = true;
          return;
        } catch (_) {}
      }
      if (retry < 6 && mounted) {
        await Future.delayed(const Duration(milliseconds: 120));
        tryEnsureVisible(retry + 1);
      } else {
        _didAutoScroll = true;
      }
    }

    tryEnsureVisible(0);
  }
}
