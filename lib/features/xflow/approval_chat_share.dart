import 'xflow_models.dart';

/// 会话内「审批」卡片 payload：`payload.approvalCard`。
class ApprovalChatShare {
  const ApprovalChatShare({
    required this.businessType,
    required this.businessId,
    required this.title,
    this.status = '',
    this.templateKey = '',
    this.code = '',
    this.submitterName = '',
    this.actionLabel = '',
    this.todoId = 0,
    this.kind = '',
  });

  final String businessType;
  final int businessId;
  final String title;
  final String status;
  final String templateKey;
  final String code;
  final String submitterName;
  final String actionLabel;
  final int todoId;
  final String kind;

  bool get isProposalIntake =>
      businessType.toUpperCase() == 'PROPOSAL_INTAKE';

  bool get isTaskTodo => kind.toUpperCase() == 'TASK' || todoId > 0;

  /// 协作提案 / 审批待办：正文说明要对方做什么，名片只承担入口。
  static String? assistantInstruction({
    required ApprovalChatShare share,
    required String bodyText,
    Map<String, dynamic>? payload,
  }) {
    if (share.isTaskTodo) {
      final fromPayload = '${payload?['instruction'] ?? ''}'.trim();
      final text = fromPayload.isNotEmpty ? fromPayload : bodyText.trim();
      if (text.isEmpty) return '你有一条审批待办';
      return text;
    }
    return proposalIntakeInstruction(
      share: share,
      bodyText: bodyText,
      payload: payload,
    );
  }

  /// 协作提案名片旁的待办说明：优先用 payload.instruction，否则用消息正文。
  static String? proposalIntakeInstruction({
    required ApprovalChatShare share,
    required String bodyText,
    Map<String, dynamic>? payload,
  }) {
    if (!share.isProposalIntake) return null;
    final fromPayload = '${payload?['instruction'] ?? ''}'.trim();
    final text = fromPayload.isNotEmpty ? fromPayload : bodyText.trim();
    if (text.isEmpty) return null;
    final title = share.title.trim();
    if (title.isNotEmpty && (text == title || text == '[审批] $title')) {
      return null;
    }
    return text;
  }

  /// 审批待办名片副标题：动作名（付款 / 盖章）+ 子状态。
  String get taskCardLine {
    final parts = <String>[
      if (actionLabel.trim().isNotEmpty) actionLabel.trim(),
      if (status.trim().isNotEmpty) status.trim(),
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    return '审批待办';
  }

  /// 协作提案名片副标题：谁提交的 + 需要填写/复核/最终确认。
  String get proposalCardLine {
    final parts = <String>[
      if (submitterName.trim().isNotEmpty) '${submitterName.trim()} 提交',
      if (actionLabel.trim().isNotEmpty) actionLabel.trim(),
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    return switch (status.trim().toLowerCase()) {
      'reviewing' => '协作提案 · 复核中',
      'pending_president' => '协作提案 · 待最终确认',
      'filling' || 'draft' => '协作提案 · 填写中',
      'done' => '协作提案 · 已完成',
      _ => '协作提案',
    };
  }

  String get bodyText {
    final t = title.trim().isEmpty ? '审批单' : title.trim();
    return '[审批] $t';
  }

  Map<String, dynamic> toMessagePayload() {
    return <String, dynamic>{
      'approvalCard': <String, dynamic>{
        'businessType': businessType,
        'businessId': businessId,
        'title': title,
        'status': status,
        'templateKey': templateKey,
        'code': code,
        if (submitterName.trim().isNotEmpty) 'submitterName': submitterName.trim(),
        if (actionLabel.trim().isNotEmpty) 'actionLabel': actionLabel.trim(),
        if (todoId > 0) 'todoId': todoId,
        if (kind.trim().isNotEmpty) 'kind': kind.trim(),
      },
    };
  }

  XflowProposalItem toListItem() {
    return XflowProposalItem(
      id: businessId,
      businessType: businessType,
      code: code.isNotEmpty
          ? code
          : (businessId > 0 ? '#$businessId' : ''),
      title: title.isEmpty ? '审批单' : title,
      status: status,
      createdByName: submitterName,
      createdAt: null,
      templateKey: templateKey.isEmpty ? null : templateKey,
      todoHint: todoId > 0
          ? XflowTodoHint(
              id: todoId,
              businessType: businessType,
              businessId: businessId,
              status: 'OPEN',
              kind: kind.trim().isEmpty ? 'TASK' : kind.trim(),
            )
          : null,
    );
  }

  factory ApprovalChatShare.fromProposalIntake({
    required int id,
    required String title,
    required String status,
    String code = '',
    String submitterName = '',
  }) {
    final t = title.trim();
    return ApprovalChatShare(
      businessType: 'PROPOSAL_INTAKE',
      businessId: id,
      title: t.isEmpty ? '未命名销售业务提案' : t,
      status: status,
      templateKey: 'proposal-intake',
      code: code,
      submitterName: submitterName.trim(),
    );
  }

  factory ApprovalChatShare.fromListItem(XflowProposalItem item) {
    final businessType = item.businessType.trim().isEmpty
        ? 'PROPOSAL'
        : item.businessType.trim();
    final rawTitle = item.title.trim();
    return ApprovalChatShare(
      businessType: businessType,
      businessId: item.id,
      title: _normalizeApprovalTitle(
        rawTitle.isEmpty ? _fallbackApprovalTitle(businessType) : rawTitle,
      ),
      status: item.status,
      templateKey: item.templateKey ??
          (businessType.toUpperCase() == 'PROPOSAL_INTAKE'
              ? 'proposal-intake'
              : ''),
      code: item.code,
      submitterName: item.createdByName.trim(),
    );
  }

  static ApprovalChatShare? fromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final raw = payload['approvalCard'];
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final businessId = (map['businessId'] as num?)?.toInt() ??
        int.tryParse((map['businessId'] ?? map['id'] ?? '').toString()) ??
        0;
    if (businessId <= 0) return null;
    final businessType = (map['businessType'] ?? 'PROPOSAL').toString().trim();
    if (businessType.isEmpty) return null;
    final title = (map['title'] ?? '').toString().trim();
    final todoId = (map['todoId'] as num?)?.toInt() ??
        int.tryParse((map['todoId'] ?? '').toString()) ??
        0;
    return ApprovalChatShare(
      businessType: businessType,
      businessId: businessId,
      title: _normalizeApprovalTitle(
        title.isEmpty ? '审批单 #$businessId' : title,
      ),
      status: (map['status'] ?? '').toString(),
      templateKey: (map['templateKey'] ?? '').toString(),
      code: (map['code'] ?? '').toString(),
      submitterName: (map['submitterName'] ?? map['createdByName'] ?? '')
          .toString()
          .trim(),
      actionLabel: (map['actionLabel'] ?? '').toString().trim(),
      todoId: todoId,
      kind: (map['kind'] ?? '').toString().trim(),
    );
  }
}

String _fallbackApprovalTitle(String businessType) {
  return switch (businessType.toUpperCase()) {
    'PROPOSAL_INTAKE' => '未命名销售业务提案',
    'PROPOSAL' => '销售提案',
    _ => '审批单',
  };
}

/// 兼容历史消息中后端重复加上的同一发起人前缀：
/// `陆青 - 陆青 - 广西卡品提案` → `陆青 - 广西卡品提案`。
String _normalizeApprovalTitle(String value) {
  final parts = value
      .split(' - ')
      .map((part) => part.trim())
      .toList(growable: false);
  if (parts.length >= 3 && parts[0].isNotEmpty && parts[0] == parts[1]) {
    return parts.skip(1).join(' - ');
  }
  return value.trim();
}
