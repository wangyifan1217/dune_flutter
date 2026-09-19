enum GlobalSearchCategory {
  all,
  contacts,
  groups,
  messages,
  approvals,
  tasks,
  documents,
  meetings,
  apps,
}

enum GlobalSearchGroupStatus { idle, loading, ready, timeout, error }

enum GlobalSearchHitKind {
  contact,
  conversation,
  message,
  approval,
  proposalIntake,
  task,
  kbDoc,
  driveItem,
  meeting,
  app,
}

class GlobalSearchHit {
  const GlobalSearchHit({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.status = '',
    this.time,
    this.raw,
    this.matchCount = 1,
  });

  final GlobalSearchHitKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String status;
  final DateTime? time;
  final Object? raw;
  final int matchCount;
}

/// 同一会话下的多条聊天命中，先聚合再展开定位。
class MessageThreadGroup {
  const MessageThreadGroup({
    required this.conversationId,
    required this.title,
    required this.hits,
    this.totalCount,
  });

  final int conversationId;
  final String title;
  final List<GlobalMessageHit> hits;
  final int? totalCount;

  int get count {
    final n = hits.length;
    final total = totalCount ?? 0;
    return total > n ? total : n;
  }

  GlobalMessageHit get latest => hits.first;
}

class GlobalSearchGroupState {
  const GlobalSearchGroupState({
    required this.category,
    this.status = GlobalSearchGroupStatus.idle,
    this.items = const <GlobalSearchHit>[],
    this.total = 0,
    this.error = '',
  });

  final GlobalSearchCategory category;
  final GlobalSearchGroupStatus status;
  final List<GlobalSearchHit> items;
  final int total;
  final String error;

  bool get hasItems => items.isNotEmpty;
  bool get isPending =>
      status == GlobalSearchGroupStatus.loading ||
      status == GlobalSearchGroupStatus.idle;

  GlobalSearchGroupState copyWith({
    GlobalSearchGroupStatus? status,
    List<GlobalSearchHit>? items,
    int? total,
    String? error,
  }) {
    return GlobalSearchGroupState(
      category: category,
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      error: error ?? this.error,
    );
  }
}

class GlobalSearchSnapshot {
  const GlobalSearchSnapshot({
    required this.seq,
    required this.query,
    required this.tab,
    required this.groups,
    this.slowHint = false,
    this.queryHint = '',
  });

  final int seq;
  final String query;
  final GlobalSearchCategory tab;
  final Map<GlobalSearchCategory, GlobalSearchGroupState> groups;
  final bool slowHint;
  final String queryHint;

  GlobalSearchGroupState group(GlobalSearchCategory category) {
    return groups[category] ?? GlobalSearchGroupState(category: category);
  }

  GlobalSearchSnapshot replaceGroup(GlobalSearchGroupState group) {
    final next = Map<GlobalSearchCategory, GlobalSearchGroupState>.from(groups);
    next[group.category] = group;
    return GlobalSearchSnapshot(
      seq: seq,
      query: query,
      tab: tab,
      groups: next,
      slowHint: slowHint,
      queryHint: queryHint,
    );
  }
}

class GlobalSearchAppTarget {
  const GlobalSearchAppTarget({
    required this.title,
    this.subtitle = '',
    this.screenId = '',
    this.templateKey = '',
  });

  final String title;
  final String subtitle;
  final String screenId;
  final String templateKey;
}

class GlobalMessageHit {
  const GlobalMessageHit({
    required this.conversationId,
    required this.conversationTitle,
    required this.messageId,
    required this.senderName,
    this.senderUserId = 0,
    this.senderAvatarPreset,
    this.senderAvatarObjectKey,
    this.senderAvatarUrl,
    required this.bodyText,
    required this.kind,
    this.createdAt,
    this.payload,
    this.matchCount = 1,
  });

  final int conversationId;
  final String conversationTitle;
  final int messageId;
  final String senderName;
  final int senderUserId;
  final String? senderAvatarPreset;
  final String? senderAvatarObjectKey;
  final String? senderAvatarUrl;
  final String bodyText;
  final String kind;
  final DateTime? createdAt;
  final Map<String, dynamic>? payload;
  final int matchCount;
}

extension GlobalSearchCategoryX on GlobalSearchCategory {
  String get label => switch (this) {
    GlobalSearchCategory.all => '全部',
    GlobalSearchCategory.contacts => '联系人',
    GlobalSearchCategory.groups => '群聊',
    GlobalSearchCategory.messages => '聊天记录',
    GlobalSearchCategory.approvals => '审批',
    GlobalSearchCategory.tasks => '任务',
    GlobalSearchCategory.documents => '文档',
    GlobalSearchCategory.meetings => '会议',
    GlobalSearchCategory.apps => '应用',
  };

  bool get isWave2 =>
      this == GlobalSearchCategory.messages ||
      this == GlobalSearchCategory.approvals ||
      this == GlobalSearchCategory.tasks ||
      this == GlobalSearchCategory.documents ||
      this == GlobalSearchCategory.meetings;
}
