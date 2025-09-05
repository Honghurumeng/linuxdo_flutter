class TopicSummary {
  final int id;
  final String title; // 原始标题
  final String? fancyTitle; // 渲染后标题（HTML）
  final String? slug;
  final int? postsCount; // 总楼层数
  final int? replyCount; // 回复数（不含主楼）
  final int? views;
  final int? likeCount;
  final DateTime? lastPostedAt;
  final List<int> postersUserIds;

  TopicSummary({
    required this.id,
    required this.title,
    this.fancyTitle,
    this.slug,
    this.postsCount,
    this.replyCount,
    this.views,
    this.likeCount,
    this.lastPostedAt,
    this.postersUserIds = const [],
  });

  factory TopicSummary.fromJson(Map<String, dynamic> json) {
    final posters = (json['posters'] as List?) ?? const [];
    return TopicSummary(
      id: json['id'] as int,
      title: (json['title'] ?? '').toString(),
      fancyTitle: json['fancy_title']?.toString(),
      slug: json['slug']?.toString(),
      postsCount: (json['posts_count'] is int) ? json['posts_count'] as int : null,
      replyCount: (json['reply_count'] is int) ? json['reply_count'] as int : null,
      views: (json['views'] is int) ? json['views'] as int : null,
      likeCount: (json['like_count'] is int) ? json['like_count'] as int : null,
      lastPostedAt: json['last_posted_at'] != null
          ? DateTime.tryParse(json['last_posted_at'].toString())
          : null,
      postersUserIds: posters
          .whereType<Map<String, dynamic>>()
          .map((e) => e['user_id'])
          .whereType<int>()
          .toList(),
    );
  }
}

class PostItem {
  final int id;
  final String username;
  final String? name;
  final DateTime? createdAt;
  final String cookedHtml; // discourse 已经渲染好的 HTML
  final String? avatarTemplate;

  PostItem({
    required this.id,
    required this.username,
    this.name,
    required this.cookedHtml,
    this.createdAt,
    this.avatarTemplate,
  });

  factory PostItem.fromJson(Map<String, dynamic> json) => PostItem(
        id: json['id'] as int,
        username: (json['username'] ?? '').toString(),
        name: json['name']?.toString(),
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'].toString())
            : null,
        cookedHtml: (json['cooked'] ?? '').toString(),
        avatarTemplate: json['avatar_template']?.toString(),
      );
}

class TopicDetail {
  final int id;
  final String title;
  final List<PostItem> posts;

  TopicDetail({
    required this.id,
    required this.title,
    required this.posts,
  });

  factory TopicDetail.fromJson(Map<String, dynamic> json) {
    final posts = (json['post_stream']?['posts'] as List?) ?? const [];
    return TopicDetail(
      id: json['id'] as int,
      title: (json['title'] ?? '').toString(),
      posts: posts
          .whereType<Map<String, dynamic>>()
          .map(PostItem.fromJson)
          .toList(),
    );
  }
}

class LatestPage {
  final List<TopicSummary> topics;
  final String? moreTopicsUrl; // 例如 /latest?no_definitions=true&page=1
  final List<UserBrief> users;

  LatestPage({required this.topics, required this.moreTopicsUrl, required this.users});

  factory LatestPage.fromJson(Map<String, dynamic> json) {
    final list = (json['topic_list'] as Map?) ?? const {};
    final topics = (list['topics'] as List?) ?? const [];
    final users = (json['users'] as List?) ?? const [];
    return LatestPage(
      topics: topics
          .whereType<Map<String, dynamic>>()
          .map(TopicSummary.fromJson)
          .toList(),
      moreTopicsUrl: list['more_topics_url']?.toString(),
      users: users
          .whereType<Map<String, dynamic>>()
          .map(UserBrief.fromJson)
          .toList(),
    );
  }
}

class UserBrief {
  final int id;
  final String username;
  final String? avatarTemplate;

  UserBrief({required this.id, required this.username, this.avatarTemplate});

  factory UserBrief.fromJson(Map<String, dynamic> json) => UserBrief(
        id: json['id'] as int,
        username: (json['username'] ?? '').toString(),
        avatarTemplate: json['avatar_template']?.toString(),
      );
}

class SearchResult {
  final List<TopicSummary> topics;
  final List<UserBrief> users;
  final List<SearchPost> posts; // 命中的帖子列表（含楼层/时间/摘要）

  SearchResult({required this.topics, required this.users, required this.posts});

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    final topics = (json['topics'] as List?) ?? const [];
    final users = (json['users'] as List?) ?? const [];
    final posts = (json['posts'] as List?) ?? const [];
    return SearchResult(
      topics: topics
          .whereType<Map<String, dynamic>>()
          .map(TopicSummary.fromJson)
          .toList(),
      users: users
          .whereType<Map<String, dynamic>>()
          .map(UserBrief.fromJson)
          .toList(),
      posts: posts
          .whereType<Map<String, dynamic>>()
          .map(SearchPost.fromJson)
          .toList(),
    );
  }
}

class SearchPost {
  final int id; // 帖子 ID
  final int topicId; // 主题 ID
  final int? postNumber; // 楼层号
  final String username; // 作者用户名
  final String? name; // 昵称
  final String blurb; // 命中片段（HTML）
  final DateTime? createdAt; // 发帖时间
  final String? avatarTemplate;

  SearchPost({
    required this.id,
    required this.topicId,
    required this.username,
    required this.blurb,
    this.postNumber,
    this.name,
    this.createdAt,
    this.avatarTemplate,
  });

  factory SearchPost.fromJson(Map<String, dynamic> json) => SearchPost(
        id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}') ?? 0,
        topicId: json['topic_id'] is int ? json['topic_id'] as int : int.tryParse('${json['topic_id']}') ?? 0,
        username: (json['username'] ?? '').toString(),
        name: json['name']?.toString(),
        blurb: (json['blurb'] ?? '').toString(),
        postNumber: json['post_number'] is int ? json['post_number'] as int : int.tryParse('${json['post_number']}'),
        createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
        avatarTemplate: json['avatar_template']?.toString(),
      );
}
