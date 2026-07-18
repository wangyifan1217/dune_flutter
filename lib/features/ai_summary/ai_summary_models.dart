class AiSummaryTemplate {
  const AiSummaryTemplate({
    required this.id,
    required this.title,
    required this.subtitle,
  });

  final String id;
  final String title;
  final String subtitle;

  factory AiSummaryTemplate.fromJson(Map<String, dynamic> json) {
    return AiSummaryTemplate(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
    );
  }
}

class AiSummaryInitiator {
  const AiSummaryInitiator({
    required this.userId,
    required this.displayName,
  });

  final int userId;
  final String displayName;

  factory AiSummaryInitiator.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const AiSummaryInitiator(userId: 0, displayName: '');
    }
    return AiSummaryInitiator(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      displayName: (json['displayName'] ?? '').toString(),
    );
  }
}

class AiSummaryItem {
  const AiSummaryItem({
    required this.id,
    required this.theme,
    required this.template,
    required this.conversationIds,
    required this.memberUserIds,
    required this.memberCount,
    required this.from,
    required this.to,
    required this.status,
    this.summaryPreview,
    this.resultMarkdown,
    this.errorMessage,
    this.model,
    this.messageCount = 0,
    this.skippedCount = 0,
    this.truncated = false,
    this.chunked = false,
    this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.initiator = const AiSummaryInitiator(userId: 0, displayName: ''),
  });

  final int id;
  final String theme;
  final String template;
  final List<int> conversationIds;
  final List<int> memberUserIds;
  final int memberCount;
  final DateTime? from;
  final DateTime? to;
  final String status;
  final String? summaryPreview;
  final String? resultMarkdown;
  final String? errorMessage;
  final String? model;
  final int messageCount;
  final int skippedCount;
  final bool truncated;
  final bool chunked;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final AiSummaryInitiator initiator;

  bool get isPending => status == 'PENDING';
  bool get isRunning => status == 'RUNNING';
  bool get isGenerating => isPending || isRunning;
  bool get isSuccess => status == 'SUCCESS';
  bool get isFailed => status == 'FAILED';

  String get statusLabel {
    switch (status) {
      case 'PENDING':
        return '排队中…';
      case 'RUNNING':
        return '生成中…';
      case 'SUCCESS':
        return '已完成';
      case 'FAILED':
        return '生成失败';
      default:
        return status;
    }
  }

  /// 列表角标文案。
  String get statusBadgeLabel {
    if (isPending) return '排队中';
    if (isRunning) return '生成中';
    if (isFailed) return '失败';
    return '';
  }

  String get inboxPreview {
    if (isGenerating) return '「$theme」正在生成…';
    if (isFailed) return '「$theme」生成失败';
    final preview = (summaryPreview ?? '').trim();
    if (preview.isNotEmpty) return preview;
    return '「$theme」总结已更新';
  }

  DateTime? get sortTime => finishedAt ?? createdAt;

  static const Object _unset = Object();

  AiSummaryItem copyWith({
    String? status,
    Object? summaryPreview = _unset,
    Object? resultMarkdown = _unset,
    Object? errorMessage = _unset,
    Object? finishedAt = _unset,
    List<int>? conversationIds,
  }) {
    return AiSummaryItem(
      id: id,
      theme: theme,
      template: template,
      conversationIds: conversationIds ?? this.conversationIds,
      memberUserIds: memberUserIds,
      memberCount: memberCount,
      from: from,
      to: to,
      status: status ?? this.status,
      summaryPreview: identical(summaryPreview, _unset)
          ? this.summaryPreview
          : summaryPreview as String?,
      resultMarkdown: identical(resultMarkdown, _unset)
          ? this.resultMarkdown
          : resultMarkdown as String?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      model: model,
      messageCount: messageCount,
      skippedCount: skippedCount,
      truncated: truncated,
      chunked: chunked,
      createdAt: createdAt,
      startedAt: startedAt,
      finishedAt: identical(finishedAt, _unset)
          ? this.finishedAt
          : finishedAt as DateTime?,
      initiator: initiator,
    );
  }

  /// 进入重新生成 / 排队时的乐观态。
  AiSummaryItem asGenerating({List<int>? conversationIds}) {
    return copyWith(
      status: 'PENDING',
      summaryPreview: '正在重新生成…',
      resultMarkdown: null,
      errorMessage: null,
      finishedAt: null,
      conversationIds: conversationIds,
    );
  }

  factory AiSummaryItem.fromJson(Map<String, dynamic> json) {
    List<int> ints(dynamic raw) {
      if (raw is! List) return const <int>[];
      return raw
          .map((e) => (e as num?)?.toInt())
          .whereType<int>()
          .toList(growable: false);
    }

    DateTime? parseTime(dynamic raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    return AiSummaryItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      theme: (json['theme'] ?? '').toString(),
      template: (json['template'] ?? 'custom').toString(),
      conversationIds: ints(json['conversationIds']),
      memberUserIds: ints(json['memberUserIds']),
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      from: parseTime(json['from']),
      to: parseTime(json['to']),
      status: (json['status'] ?? '').toString().toUpperCase(),
      summaryPreview: json['summaryPreview']?.toString(),
      resultMarkdown: json['resultMarkdown']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
      model: json['model']?.toString(),
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
      skippedCount: (json['skippedCount'] as num?)?.toInt() ?? 0,
      truncated: json['truncated'] == true,
      chunked: json['chunked'] == true,
      createdAt: parseTime(json['createdAt']),
      startedAt: parseTime(json['startedAt']),
      finishedAt: parseTime(json['finishedAt']),
      initiator: AiSummaryInitiator.fromJson(
        json['initiator'] is Map<String, dynamic>
            ? json['initiator'] as Map<String, dynamic>
            : null,
      ),
    );
  }
}

class AiSummaryListPage {
  const AiSummaryListPage({
    required this.items,
    required this.page,
    required this.size,
    required this.total,
    required this.hasMore,
  });

  final List<AiSummaryItem> items;
  final int page;
  final int size;
  final int total;
  final bool hasMore;

  factory AiSummaryListPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(AiSummaryItem.fromJson)
            .toList(growable: false)
        : const <AiSummaryItem>[];
    return AiSummaryListPage(
      items: items,
      page: (json['page'] as num?)?.toInt() ?? 1,
      size: (json['size'] as num?)?.toInt() ?? 20,
      total: (json['total'] as num?)?.toInt() ?? items.length,
      hasMore: json['hasMore'] == true,
    );
  }
}

class AiSummaryRealtimeUpdate {
  const AiSummaryRealtimeUpdate({
    required this.id,
    required this.theme,
    required this.status,
    this.preview,
    this.body,
  });

  final int id;
  final String theme;
  final String status;
  final String? preview;
  final String? body;

  factory AiSummaryRealtimeUpdate.fromPayload(Map<String, dynamic> payload) {
    final data = payload['data'];
    final map = data is Map<String, dynamic> ? data : payload;
    return AiSummaryRealtimeUpdate(
      id: (map['id'] as num?)?.toInt() ?? 0,
      theme: (map['theme'] ?? '').toString(),
      status: (map['status'] ?? '').toString().toUpperCase(),
      preview: map['preview']?.toString(),
      body: map['body']?.toString(),
    );
  }
}
