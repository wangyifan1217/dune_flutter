import 'dart:convert';

class XflowTemplateCard {
  const XflowTemplateCard({
    required this.templateKey,
    required this.title,
    required this.subtitle,
    required this.endpoint,
    required this.tagLabel,
    required this.category,
    this.enabled = true,
  });

  final String templateKey;
  final String title;
  final String subtitle;
  final String endpoint;
  final String tagLabel;
  final String category;
  final bool enabled;

  factory XflowTemplateCard.fromJson(Map<String, dynamic> json) {
    final enabledRaw = json['enabled'];
    final enabled = enabledRaw is bool
        ? enabledRaw
        : enabledRaw?.toString().toLowerCase() != 'false';
    return XflowTemplateCard(
      templateKey: (json['templateKey'] ?? '').toString(),
      title: (json['title'] ?? '销售提案').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      endpoint: (json['endpoint'] ?? '').toString(),
      tagLabel: (json['tagLabel'] ?? '新建').toString(),
      category: (json['category'] ?? 'biz').toString(),
      enabled: enabled,
    );
  }
}

class XflowFieldOption {
  const XflowFieldOption({required this.label, required this.value});

  final String label;
  final String value;

  factory XflowFieldOption.fromJson(Map<String, dynamic> json) {
    final label = (json['label'] ?? json['name'] ?? json['text'] ?? '')
        .toString();
    final value = (json['value'] ?? json['id'] ?? label).toString();
    return XflowFieldOption(label: label, value: value);
  }
}

/// 模板字段通用远程搜索配置（`field.remoteSearch`）。
/// path / fill / label 均由后台配置，客户端不做业务分支。
class XflowRemoteSearchConfig {
  const XflowRemoteSearchConfig({
    required this.path,
    this.queryParam = 'q',
    this.minChars = 1,
    this.debounceMs = 250,
    this.labelFields = const <String>[],
    this.labelSeparator = ' · ',
    this.valueFields = const <String>[],
    this.fill = const <String, String>{},
    this.allowManual = true,
  });

  final String path;
  final String queryParam;
  final int minChars;
  final int debounceMs;
  final List<String> labelFields;
  final String labelSeparator;
  final List<String> valueFields;
  final Map<String, String> fill;
  final bool allowManual;

  static XflowRemoteSearchConfig? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final path = (map['path'] ?? '').toString().trim();
    if (path.isEmpty) return null;
    return XflowRemoteSearchConfig(
      path: path,
      queryParam: _nonEmpty(map['queryParam'], 'q'),
      minChars: _positiveInt(map['minChars'], 1),
      debounceMs: _positiveInt(map['debounceMs'], 250),
      labelFields: _stringList(map['labelFields']),
      labelSeparator: _nonEmpty(map['labelSeparator'], ' · '),
      valueFields: _stringList(map['valueFields']),
      fill: _stringMap(map['fill']),
      allowManual: map['allowManual'] != false,
    );
  }

  String labelOf(Map<String, dynamic> row) {
    final parts = <String>[];
    for (final key in labelFields) {
      final text = '${row[key] ?? ''}'.trim();
      if (text.isNotEmpty) parts.add(text);
    }
    return parts.join(labelSeparator);
  }

  String? valueOf(Map<String, dynamic> row) {
    for (final key in valueFields) {
      final text = '${row[key] ?? ''}'.trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  /// 选中回填：表单 key → 非空字符串。
  Map<String, String> fillPatches(Map<String, dynamic> row) {
    final out = <String, String>{};
    fill.forEach((formKey, respKey) {
      final text = '${row[respKey] ?? ''}'.trim();
      if (text.isNotEmpty) out[formKey] = text;
    });
    return out;
  }

  /// 分组内展示：把 fill 映射到的多个非空值拼成一行（去重）。
  String fillDisplayOf(Map<String, dynamic>? values) {
    if (values == null || fill.isEmpty) return '';
    final parts = <String>[];
    final seen = <String>{};
    for (final formKey in fill.keys) {
      final text = '${values[formKey] ?? ''}'.trim();
      if (text.isNotEmpty && seen.add(text)) parts.add(text);
    }
    return parts.join(labelSeparator);
  }

  static String _nonEmpty(dynamic v, String fallback) {
    final text = (v ?? '').toString();
    return text.isEmpty ? fallback : text;
  }

  static int _positiveInt(dynamic v, int fallback) {
    if (v is num && v.toInt() > 0) return v.toInt();
    final parsed = int.tryParse('$v');
    if (parsed != null && parsed > 0) return parsed;
    return fallback;
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, String> _stringMap(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final key = k?.toString().trim() ?? '';
      final val = v?.toString().trim() ?? '';
      if (key.isNotEmpty && val.isNotEmpty) out[key] = val;
    });
    return out;
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

  /// 通用远程搜索配置；path 缺失时返回 null（不当作 remoteSearch 渲染）。
  XflowRemoteSearchConfig? get remoteSearch =>
      XflowRemoteSearchConfig.tryParse(raw['remoteSearch']);

  /// 仅 `dynamicList` + `itemLayout=card` 走可新增分组；其它保持旧行编辑。
  bool get isCardDynamicList =>
      type == 'dynamicList' &&
      (raw['itemLayout'] ?? '').toString().trim() == 'card';

  /// 组标题前缀，展示为 `{itemTitle}{index+1}`。
  String get itemTitle {
    final title = (raw['itemTitle'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;
    return label.isNotEmpty ? label : '一组';
  }

  String get addText {
    final text = (raw['addText'] ?? '').toString().trim();
    return text.isEmpty ? '新增一组' : text;
  }

  int get minItems {
    final rawMin = raw['minItems'];
    if (rawMin is num && rawMin.toInt() >= 0) return rawMin.toInt();
    final parsed = int.tryParse('$rawMin');
    if (parsed != null && parsed >= 0) return parsed;
    return required ? 1 : 0;
  }

  List<XflowField> get columnsAsFields {
    final cols = raw['columns'];
    if (cols is! List || cols.isEmpty) return const [];
    return cols
        .whereType<Map>()
        .map((c) => XflowField.fromJson(Map<String, dynamic>.from(c)))
        .where((c) => c.key.isNotEmpty)
        .toList(growable: false);
  }

  List<String> get moneyColumnKeys => columnsAsFields
      .where((c) => c.type == 'money')
      .map((c) => c.key)
      .toList(growable: false);

  /// 卡片分组的组内必填缺口，文案含「付款1…」。非卡片 dynamicList 返回空。
  List<String> missingRequiredGroupLabels(dynamic rawValue) {
    if (!isCardDynamicList) return const [];
    final groups = _asGroupList(rawValue);
    final cols = columnsAsFields;
    final min = minItems;
    final out = <String>[];
    if (groups.length < min) {
      out.add('$itemTitle$min');
      return out;
    }
    for (var i = 0; i < groups.length; i++) {
      final prefix = '$itemTitle${i + 1}';
      for (final col in cols) {
        if (!col.required) continue;
        if (!_groupCellHasValue(col, groups[i])) {
          out.add('$prefix${col.label.isEmpty ? col.key : col.label}');
        }
      }
    }
    return out;
  }
}

List<Map<String, dynamic>> _asGroupList(dynamic raw) {
  if (raw is List) {
    return raw
        .map(
          (e) => e is Map<String, dynamic>
              ? e
              : (e is Map ? Map<String, dynamic>.from(e) : null),
        )
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }
  if (raw is Map) return [Map<String, dynamic>.from(raw)];
  return const [];
}

bool _groupCellHasValue(XflowField col, Map<String, dynamic> group) {
  final val = group[col.key];
  if (col.type == 'upload') {
    if (val is! List) return false;
    return val.any((e) => e is Map && e['status'] != 'error');
  }
  if (val == null) return false;
  if (val is String) return val.trim().isNotEmpty;
  if (val is List) return val.isNotEmpty;
  if (val is Map) return val.isNotEmpty;
  if (val is num) return true;
  return val.toString().trim().isNotEmpty;
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
    this.proposalType,
    this.documentKind,
    this.templateKey,
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
  final String? proposalType;
  final String? documentKind;
  final String? templateKey;
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
    String? proposalType,
    String? documentKind,
    String? templateKey,
    String? scaleWan,
    int? currentStep,
    int? totalSteps,
    bool? canRefedit,
    XflowTodoHint? todoHint,
  }) {
    return XflowProposalItem(
      id: id,
      businessType: businessType,
      code: code ?? this.code,
      title: title ?? this.title,
      status: status ?? this.status,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      tag1: tag1 ?? this.tag1,
      txType: txType ?? this.txType,
      proposalType: proposalType ?? this.proposalType,
      documentKind: documentKind ?? this.documentKind,
      templateKey: templateKey ?? this.templateKey,
      scaleWan: scaleWan ?? this.scaleWan,
      currentStep: currentStep ?? this.currentStep,
      totalSteps: totalSteps ?? this.totalSteps,
      canRefedit: canRefedit ?? this.canRefedit,
      todoHint: todoHint ?? this.todoHint,
    );
  }
}

class XflowSubmissionDetail {
  const XflowSubmissionDetail({
    required this.id,
    required this.templateKey,
    required this.businessType,
    required this.businessId,
    required this.title,
    required this.status,
    required this.formData,
    required this.createdById,
    required this.createdAt,
    this.createdByName = '',
    this.proposalType = '',
    this.documentKind = '',
  });

  final int id;
  final String templateKey;
  final String businessType;
  final int businessId;
  final String title;
  final String status;
  final Map<String, dynamic> formData;
  final int createdById;
  final String createdByName;
  final DateTime? createdAt;
  /// 服务端中文类型标签（模板标题），列表种类/类型展示用。
  final String proposalType;
  final String documentKind;

  factory XflowSubmissionDetail.fromJson(Map<String, dynamic> json) {
    final form = json['formData'];
    return XflowSubmissionDetail(
      id: _xflowInt(json['id']),
      templateKey: (json['templateKey'] ?? '').toString(),
      businessType: (json['businessType'] ?? '').toString(),
      businessId: _xflowInt(json['businessId']),
      title: (json['title'] ?? '动态审批').toString(),
      status: (json['status'] ?? '').toString(),
      formData: form is Map ? Map<String, dynamic>.from(form) : const {},
      createdById: _xflowInt(json['createdById']),
      createdByName: (json['createdByName'] ?? json['initiatorName'] ?? '')
          .toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      proposalType: (json['proposalType'] ?? json['documentType'] ?? '')
          .toString()
          .trim(),
      documentKind: (json['documentKind'] ?? '').toString().trim(),
    );
  }
}

int _xflowInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is String) {
    final s = value.trim();
    if (s.isEmpty) return 0;
    return int.tryParse(s) ?? 0;
  }
  if (value is num) {
    return int.tryParse(value.toString().split('.').first) ?? value.toInt();
  }
  return int.tryParse('$value') ?? 0;
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
    this.canWithdraw = false,
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

  /// 创建人的待审批提案，在尚未产生任何审批意见前可撤回。
  final bool canWithdraw;
}

extension XflowApprovalTrailExt on XflowApprovalTrail {
  int get currentStep {
    final v = raw['currentStep'];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 1;
  }

  /// 并行时后端置 0，勿再依赖其等于某一步。
  bool get isParallel =>
      (raw['stageExecutionMode'] ?? '').toString().toUpperCase() == 'PARALLEL';

  String get currentNodeLabel =>
      (raw['currentNodeLabel'] ?? '').toString().trim();

  List<int> get currentSteps {
    final v = raw['currentSteps'];
    if (v is! List) return const [];
    return v
        .map((e) => e is num ? e.toInt() : int.tryParse('$e') ?? 0)
        .where((n) => n > 0)
        .toList(growable: false);
  }

  String? get createdAtRaw => raw['createdAt']?.toString();
  String? get finishedAtRaw => raw['finishedAt']?.toString();
}

extension XflowApprovalStepExt on XflowApprovalStep {
  String get stepType => (raw['stepType'] ?? '').toString();
  String get stageName => (raw['stageName'] ?? '').toString().trim();
  bool? get isCurrent {
    final v = raw['isCurrent'];
    if (v is bool) return v;
    if (v == null) return null;
    final s = '$v'.toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return null;
  }

  String get decidedAtRaw =>
      (raw['decidedAt'] ?? raw['updatedAt'] ?? '').toString();
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

class ApprovalCommentAttachment {
  const ApprovalCommentAttachment({
    required this.name,
    required this.objectKey,
    this.size = 0,
    this.mimeType = '',
  });

  final String name;
  final String objectKey;
  final int size;
  final String mimeType;

  bool get isImage {
    if (mimeType.toLowerCase().startsWith('image/')) return true;
    return RegExp(
      r'\.(jpg|jpeg|png|heic|heif|gif|webp|bmp)$',
    ).hasMatch(name.trim().toLowerCase());
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'objectKey': objectKey,
        if (size > 0) 'size': size,
        if (mimeType.isNotEmpty) 'mimeType': mimeType,
      };

  /// 供 resolveFileUrl / openXflowAttachment 使用的通用 item 形态。
  Map<String, dynamic> toFileItem() => <String, dynamic>{
        'fileName': name,
        'objectKey': objectKey,
        if (mimeType.isNotEmpty) 'mimeType': mimeType,
      };

  factory ApprovalCommentAttachment.fromJson(Map<String, dynamic> json) {
    return ApprovalCommentAttachment(
      name: (json['name'] ?? json['fileName'] ?? '附件').toString(),
      objectKey: (json['objectKey'] ?? '').toString(),
      size: _xflowInt(json['size']),
      mimeType: (json['mimeType'] ?? '').toString(),
    );
  }
}

class ApprovalCommentItem {
  const ApprovalCommentItem({
    required this.id,
    required this.authorUserId,
    required this.authorName,
    required this.bodyText,
    this.mentionUserIds = const [],
    this.attachments = const [],
    this.parentId,
    this.authorAvatarPreset = '',
    this.authorAvatarObjectKey = '',
    this.createdAt,
  });

  final int id;
  final int authorUserId;
  final String authorName;
  final String bodyText;
  final List<int> mentionUserIds;
  final List<ApprovalCommentAttachment> attachments;
  final int? parentId;
  final String authorAvatarPreset;
  final String authorAvatarObjectKey;
  final DateTime? createdAt;
}

class ApprovalStakeholderPerson {
  const ApprovalStakeholderPerson({
    required this.id,
    required this.displayName,
    this.role = '',
  });

  final int id;
  final String displayName;
  final String role;
}
