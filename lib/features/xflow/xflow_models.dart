import 'dart:convert';

class XflowTemplateCard {
  const XflowTemplateCard({
    required this.templateKey,
    required this.title,
    required this.subtitle,
    required this.endpoint,
    required this.tagLabel,
    required this.category,
  });

  final String templateKey;
  final String title;
  final String subtitle;
  final String endpoint;
  final String tagLabel;
  final String category;

  factory XflowTemplateCard.fromJson(Map<String, dynamic> json) {
    return XflowTemplateCard(
      templateKey: (json['templateKey'] ?? '').toString(),
      title: (json['title'] ?? '销售提案').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      endpoint: (json['endpoint'] ?? '').toString(),
      tagLabel: (json['tagLabel'] ?? '新建').toString(),
      category: (json['category'] ?? 'biz').toString(),
    );
  }
}

class XflowFieldOption {
  const XflowFieldOption({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  factory XflowFieldOption.fromJson(Map<String, dynamic> json) {
    final label =
        (json['label'] ?? json['name'] ?? json['text'] ?? '').toString();
    final value = (json['value'] ?? json['id'] ?? label).toString();
    return XflowFieldOption(label: label, value: value);
  }
}

class XflowField {
  const XflowField({
    required this.key,
    required this.type,
    required this.label,
    required this.placeholder,
    required this.required,
    required this.readonly,
    required this.options,
    required this.children,
    required this.raw,
  });

  final String key;
  final String type;
  final String label;
  final String placeholder;
  final bool required;
  final bool readonly;
  final List<XflowFieldOption> options;
  final List<String> children;
  final Map<String, dynamic> raw;

  factory XflowField.fromJson(Map<String, dynamic> json) {
    final optionsRaw = json['options'];
    final options = <XflowFieldOption>[];
    if (optionsRaw is List) {
      for (final row in optionsRaw) {
        if (row is Map<String, dynamic>) {
          options.add(XflowFieldOption.fromJson(row));
        } else if (row is Map) {
          options.add(
            XflowFieldOption.fromJson(Map<String, dynamic>.from(row)),
          );
        } else if (row != null) {
          final text = row.toString();
          options.add(XflowFieldOption(label: text, value: text));
        }
      }
    }
    final childrenRaw = json['children'];
    final children = <String>[];
    if (childrenRaw is List) {
      for (final row in childrenRaw) {
        if (row != null) children.add(row.toString());
      }
    }
    return XflowField(
      key: (json['key'] ?? '').toString(),
      type: (json['type'] ?? 'text').toString(),
      label: (json['label'] ?? json['title'] ?? json['name'] ?? '').toString(),
      placeholder: (json['placeholder'] ?? '').toString(),
      required: json['required'] == true || json['isRequired'] == true,
      readonly: json['readonly'] == true || json['readOnly'] == true,
      options: options,
      children: children,
      raw: json,
    );
  }
}

class XflowTemplateDetail {
  const XflowTemplateDetail({
    required this.templateKey,
    required this.title,
    required this.fields,
    required this.stages,
    required this.layout,
    required this.raw,
  });

  final String templateKey;
  final String title;
  final List<XflowField> fields;
  final List<Map<String, dynamic>> stages;
  final Map<String, dynamic> layout;
  final Map<String, dynamic> raw;
}

class XflowTodoHint {
  const XflowTodoHint({
    required this.id,
    required this.businessType,
    required this.businessId,
    required this.status,
    this.sourceStepId,
    this.kind = 'APPROVAL',
  });

  final int id;
  final String businessType;
  final int businessId;
  final String status;
  final int? sourceStepId;
  final String kind;
}

class XflowProposalItem {
  const XflowProposalItem({
    required this.id,
    required this.businessType,
    required this.code,
    required this.title,
    required this.status,
    required this.createdByName,
    required this.createdAt,
    this.todoHint,
    this.tag1,
    this.txType,
    this.scaleWan,
    this.currentStep = 0,
    this.totalSteps = 0,
    this.canRefedit = false,
  });

  final int id;
  final String businessType;
  final String code;
  final String title;
  final String status;
  final String createdByName;
  final DateTime? createdAt;
  final XflowTodoHint? todoHint;
  final String? tag1;
  final String? txType;
  final String? scaleWan;
  final int currentStep;
  final int totalSteps;
  final bool canRefedit;

  bool get isPending =>
      status.toUpperCase() == 'OPEN' || status.toUpperCase() == 'PENDING';

  XflowProposalItem copyWith({
    String? code,
    String? title,
    String? status,
    String? createdByName,
    DateTime? createdAt,
    String? tag1,
    String? txType,
    String? scaleWan,
    int? currentStep,
    int? totalSteps,
    bool? canRefedit,
  }) {
    return XflowProposalItem(
      id: id,
      businessType: businessType,
      code: code ?? this.code,
      title: title ?? this.title,
      status: status ?? this.status,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      todoHint: todoHint,
      tag1: tag1 ?? this.tag1,
      txType: txType ?? this.txType,
      scaleWan: scaleWan ?? this.scaleWan,
      currentStep: currentStep ?? this.currentStep,
      totalSteps: totalSteps ?? this.totalSteps,
      canRefedit: canRefedit ?? this.canRefedit,
    );
  }
}

class XflowProduct {
  const XflowProduct({
    required this.name,
    required this.platformProductId,
    required this.ratio,
  });

  final String name;
  final String platformProductId;
  final String ratio;
}

class XflowSettlementSlot {
  const XflowSettlementSlot({
    required this.seq,
    required this.slotType,
    required this.name,
    required this.ratio,
    required this.tags,
  });

  final int seq;
  final String slotType;
  final String name;
  final String ratio;
  final List<String> tags;
}

class XflowProposalDetail {
  const XflowProposalDetail({
    required this.id,
    required this.code,
    required this.title,
    required this.status,
    required this.summary,
    required this.beaconId,
    required this.ownerName,
    required this.amountText,
    required this.formValues,
    required this.products,
    required this.slots,
    required this.createdById,
    required this.raw,
  });

  final int id;
  final String code;
  final String title;
  final String status;
  final String summary;
  final String beaconId;
  final String ownerName;
  final String amountText;
  final Map<String, dynamic> formValues;
  final List<XflowProduct> products;
  final List<XflowSettlementSlot> slots;
  final int createdById;
  final Map<String, dynamic> raw;

  bool get canReedit => status.toLowerCase() == 'rejected';
}

class XflowApprovalStep {
  const XflowApprovalStep({
    required this.stepNo,
    required this.stepName,
    required this.decision,
    required this.assigneeId,
    required this.assigneeName,
    required this.comment,
    required this.updatedAt,
    required this.raw,
  });

  final int stepNo;
  final String stepName;
  final String decision;
  final int assigneeId;
  final String assigneeName;
  final String comment;
  final DateTime? updatedAt;
  final Map<String, dynamic> raw;
}

class XflowApprovalTrail {
  const XflowApprovalTrail({
    required this.status,
    required this.initiatorId,
    required this.steps,
    required this.raw,
  });

  final String status;
  final int initiatorId;
  final List<XflowApprovalStep> steps;
  final Map<String, dynamic> raw;
}

class XflowDetailBundle {
  const XflowDetailBundle({
    required this.detail,
    required this.trail,
    required this.fields,
    required this.detailConfig,
    required this.stages,
    required this.myTodo,
    this.assigneeNames = const {},
    this.ccList = const [],
    this.canReedit = false,
    this.layout = const {},
    this.isDesignatedInitiator = false,
    this.isPusher = false,
    this.canDeleteDraft = false,
  });

  final XflowProposalDetail detail;
  final XflowApprovalTrail? trail;
  final List<XflowField> fields;
  final Map<String, dynamic> detailConfig;
  final List<Map<String, dynamic>> stages;
  final XflowTodoHint? myTodo;
  final Map<int, String> assigneeNames;
  final List<Map<String, dynamic>> ccList;
  final bool canReedit;
  final Map<String, dynamic> layout;

  /// 「待发起」提案中，当前用户是被推送的代发起人（owner_id == me）。
  final bool isDesignatedInitiator;

  /// 「待发起」提案中，当前用户是推送人（创建人，已推送给他人代发起）。
  final bool isPusher;

  /// 创建人本人的草稿(DRAFT)可删除。
  final bool canDeleteDraft;
}

extension XflowApprovalTrailExt on XflowApprovalTrail {
  int get currentStep {
    final v = raw['currentStep'];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 1;
  }

  String? get createdAtRaw => raw['createdAt']?.toString();
  String? get finishedAtRaw => raw['finishedAt']?.toString();
}

extension XflowApprovalStepExt on XflowApprovalStep {
  String get stepType => (raw['stepType'] ?? '').toString();
  String get decidedAtRaw => (raw['decidedAt'] ?? raw['updatedAt'] ?? '').toString();
}

Map<String, dynamic> parseLayout(dynamic rawLayout) {
  if (rawLayout is Map<String, dynamic>) return rawLayout;
  if (rawLayout is String && rawLayout.trim().isNotEmpty) {
    try {
      final json = jsonDecode(rawLayout);
      if (json is Map<String, dynamic>) return json;
    } catch (_) {}
  }
  return const <String, dynamic>{};
}
