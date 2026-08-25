import 'package:flutter/material.dart';

import '../chat/chat_widgets.dart';

/// 薪人薪事审批名片（IM payload.type = xrxsApprovalCard）。
class XrxsChatCard {
  const XrxsChatCard({
    required this.sid,
    required this.title,
    this.subtitle = '审批待办',
    this.statusLabel = '待审批',
    this.eventType = '',
    this.roleHint = 'approver',
  });

  final String sid;
  final String title;
  final String subtitle;
  final String statusLabel;
  final String eventType;
  final String roleHint;

  bool get canOpenDetail => sid.trim().isNotEmpty;

  static XrxsChatCard? fromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final type = '${payload['type'] ?? ''}'.trim();
    final raw = payload['xrxsCard'];
    if (type != 'xrxsApprovalCard' && raw is! Map) return null;
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final title = '${map['title'] ?? ''}'.trim();
    if (title.isEmpty && type != 'xrxsApprovalCard') return null;
    final role = '${map['roleHint'] ?? 'approver'}'.trim();
    return XrxsChatCard(
      sid: '${map['sid'] ?? ''}'.trim(),
      title: title.isEmpty ? '薪人薪事审批' : title,
      subtitle: '${map['subtitle'] ?? '审批待办'}'.trim(),
      statusLabel: '${map['statusLabel'] ?? ''}'.trim(),
      eventType: '${map['eventType'] ?? ''}'.trim(),
      roleHint: role.isEmpty ? 'approver' : role,
    );
  }
}

/// 可复用的名片外观（对齐审批助手）。
class ChatXrxsCard extends StatelessWidget {
  const ChatXrxsCard({
    super.key,
    required this.card,
    required this.onTap,
  });

  final XrxsChatCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChatApprovalCard(
      title: card.title,
      subtitle: card.subtitle,
      statusLabel: card.statusLabel,
      brandLabel: '薪人薪事',
      onTap: onTap,
    );
  }
}
