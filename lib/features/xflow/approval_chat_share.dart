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
  });

  final String businessType;
  final int businessId;
  final String title;
  final String status;
  final String templateKey;
  final String code;

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
      createdByName: '',
      createdAt: null,
      templateKey: templateKey.isEmpty ? null : templateKey,
    );
  }

  factory ApprovalChatShare.fromListItem(XflowProposalItem item) {
    return ApprovalChatShare(
      businessType: item.businessType.trim().isEmpty
          ? 'PROPOSAL'
          : item.businessType.trim(),
      businessId: item.id,
      title: _normalizeApprovalTitle(item.title.trim().isEmpty
          ? (item.businessType.toUpperCase() == 'PROPOSAL' ? '销售提案' : '审批单')
          : item.title.trim()),
      status: item.status,
      templateKey: item.templateKey ?? '',
      code: item.code,
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
    return ApprovalChatShare(
      businessType: businessType,
      businessId: businessId,
      title: _normalizeApprovalTitle(
        title.isEmpty ? '审批单 #$businessId' : title,
      ),
      status: (map['status'] ?? '').toString(),
      templateKey: (map['templateKey'] ?? '').toString(),
      code: (map['code'] ?? '').toString(),
    );
  }
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
