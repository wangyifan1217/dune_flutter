import 'xflow_models.dart';
import 'xflow_template_runtime.dart';

/// 上传页内容预览板块配置（recognitionConfig.previewSections）。
class UploadPreviewSectionConfig {
  const UploadPreviewSectionConfig({
    required this.id,
    required this.title,
    this.orderCn = '',
    this.expanded = false,
    this.accent = false,
  });

  final String id;
  final String title;
  final String orderCn;
  final bool expanded;
  final bool accent;

  factory UploadPreviewSectionConfig.fromJson(Map<String, dynamic> json) {
    return UploadPreviewSectionConfig(
      id: (json['id'] ?? '').toString().trim(),
      title: (json['title'] ?? json['label'] ?? '').toString().trim(),
      orderCn: (json['orderCn'] ?? json['order_cn'] ?? '').toString().trim(),
      expanded: json['expanded'] == true || json['defaultExpanded'] == true,
      accent: json['accent'] == true || json['id'] == 'finance',
    );
  }
}

/// 与 proposal-archive-go sectionIDMap 对齐的默认预览板块。
const defaultUploadPreviewSections = <UploadPreviewSectionConfig>[
  UploadPreviewSectionConfig(id: 'business', title: '商务模式', orderCn: '一'),
  UploadPreviewSectionConfig(id: 'tech', title: '技术能力', orderCn: '二'),
  UploadPreviewSectionConfig(id: 'risk', title: '风控标准', orderCn: '三'),
  UploadPreviewSectionConfig(
    id: 'finance',
    title: '财务数据',
    orderCn: '四',
    accent: true,
  ),
  UploadPreviewSectionConfig(id: 'people', title: '责任人', orderCn: '五'),
];

/// 「已识别」摘要区字段配置（recognitionConfig.summaryFields）。
class UploadSummaryFieldConfig {
  const UploadSummaryFieldConfig({
    required this.label,
    required this.source,
    this.key = '',
    this.display = 'text',
  });

  final String key;
  final String label;
  final String source;
  final String display;

  factory UploadSummaryFieldConfig.fromJson(Map<String, dynamic> json) {
    return UploadSummaryFieldConfig(
      key: (json['key'] ?? '').toString().trim(),
      label: (json['label'] ?? '').toString().trim(),
      source: (json['source'] ?? json['field'] ?? '').toString().trim(),
      display: (json['display'] ?? 'text').toString().trim(),
    );
  }
}

const defaultUploadSummaryFields = <UploadSummaryFieldConfig>[
  UploadSummaryFieldConfig(
    key: 'proposalCode',
    label: '提案编号',
    source: 'proposalId',
    display: 'mono',
  ),
  UploadSummaryFieldConfig(
    key: 'proposalType',
    label: '提案类型',
    source: 'proposalType',
    display: 'chip',
  ),
  UploadSummaryFieldConfig(
    key: 'tag1',
    label: '产品属性',
    source: 'productTags',
    display: 'tags',
  ),
  UploadSummaryFieldConfig(
    key: 'launchChannel',
    label: '上线渠道',
    source: 'channelProvince',
    display: 'text',
  ),
  UploadSummaryFieldConfig(
    key: 'profitModel',
    label: '盈利模式',
    source: 'profitModel',
    display: 'text',
  ),
];

/// Excel 识别行标签 → 表单字段键的默认匹配规则（可被 recognitionConfig.extractRules 覆盖）。
const defaultUploadExtractRules = <String, List<String>>{
  'launchDate': ['上线日期', '计划上线日期'],
  'txType': ['交易类型'],
  'goodType': ['商品类型'],
  'techPlatform': ['技术平台', '技术标签', '技术能力'],
  'owner1Level': ['第一责任人等级', '任务等级'],
  'owner2Level': ['第二责任人等级'],
  'targetMonthlyScaleWan': ['销售规模', '承诺月规模', '月规模'],
  'targetMonthlyProfitWan': ['利润', '承诺月毛利', '月毛利'],
};

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
}

/// 从 detail-config / layout detailConfig 解析 Excel 行标签匹配规则。
Map<String, List<String>> extractRulesFromDetailConfig(
  Map<String, dynamic>? detailConfig,
) {
  final cfg = detailConfig ?? const <String, dynamic>{};
  final recognition = cfg['recognitionConfig'];
  if (recognition is! Map) {
    return Map<String, List<String>>.from(defaultUploadExtractRules);
  }
  final raw = recognition['extractRules'] ?? recognition['sectionMatchers'];
  if (raw is! Map) {
    return Map<String, List<String>>.from(defaultUploadExtractRules);
  }
  final out = <String, List<String>>{};
  for (final entry in raw.entries) {
    final key = entry.key.toString().trim();
    if (key.isEmpty) continue;
    final labels = _stringList(entry.value);
    if (labels.isNotEmpty) out[key] = labels;
  }
  if (out.isEmpty) {
    return Map<String, List<String>>.from(defaultUploadExtractRules);
  }
  return out;
}

Map<String, dynamic>? _recognitionConfig(Map<String, dynamic>? detailConfig) {
  final cfg = detailConfig ?? const <String, dynamic>{};
  final recognition = cfg['recognitionConfig'];
  if (recognition is Map<String, dynamic>) return recognition;
  if (recognition is Map) return Map<String, dynamic>.from(recognition);
  return null;
}

bool _looksLikePreviewSectionList(Object? raw) {
  if (raw is! List || raw.isEmpty) return false;
  for (final item in raw) {
    if (item is! Map) return false;
    final id = (item['id'] ?? '').toString().trim();
    final title = (item['title'] ?? item['label'] ?? '').toString().trim();
    if (id.isEmpty || title.isEmpty) return false;
  }
  return true;
}

List<UploadPreviewSectionConfig> _parsePreviewSectionList(Object? raw) {
  if (raw is! List || raw.isEmpty) return const [];
  final out = <UploadPreviewSectionConfig>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final cfg = UploadPreviewSectionConfig.fromJson(
      item is Map<String, dynamic>
          ? item
          : Map<String, dynamic>.from(item),
    );
    if (cfg.id.isNotEmpty && cfg.title.isNotEmpty) out.add(cfg);
  }
  return out;
}

/// 内容预览板块配置；未配置时回退默认五板块。
List<UploadPreviewSectionConfig> previewSectionsFromDetailConfig(
  Map<String, dynamic>? detailConfig,
) {
  final recognition = _recognitionConfig(detailConfig);
  final fromPreview = _parsePreviewSectionList(recognition?['previewSections']);
  if (fromPreview.isNotEmpty) return fromPreview;

  // 兼容：误把 previewSections 存进 extractRules 数组时仍能生效。
  final extractRules = recognition?['extractRules'];
  if (_looksLikePreviewSectionList(extractRules)) {
    final fromExtract = _parsePreviewSectionList(extractRules);
    if (fromExtract.isNotEmpty) return fromExtract;
  }

  return List<UploadPreviewSectionConfig>.from(defaultUploadPreviewSections);
}

List<UploadSummaryFieldConfig> _parseSummaryFieldList(Object? raw) {
  if (raw is! List || raw.isEmpty) return const [];
  final out = <UploadSummaryFieldConfig>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final cfg = UploadSummaryFieldConfig.fromJson(
      item is Map<String, dynamic>
          ? item
          : Map<String, dynamic>.from(item),
    );
    if (cfg.label.isNotEmpty && cfg.source.isNotEmpty) out.add(cfg);
  }
  return out;
}

/// 「已识别」摘要区展示字段。
List<UploadSummaryFieldConfig> summaryFieldsFromDetailConfig(
  Map<String, dynamic>? detailConfig,
) {
  final recognition = _recognitionConfig(detailConfig);
  final fromConfig = _parseSummaryFieldList(recognition?['summaryFields']);
  if (fromConfig.isNotEmpty) return fromConfig;
  return List<UploadSummaryFieldConfig>.from(defaultUploadSummaryFields);
}

Map<String, dynamic> uploadSummaryData({
  required String proposalId,
  required String proposalType,
  required List<String> productTags,
  required String channel,
  required String province,
  required String profitModel,
  String fileName = '',
}) {
  final channelText = channel.trim();
  final provinceText = province.trim();
  final channelProvince = [
    if (channelText.isNotEmpty) channelText,
    if (provinceText.isNotEmpty) provinceText,
  ].join(' · ');
  return {
    'proposalId': proposalId,
    'proposalCode': proposalId,
    'proposalType': proposalType,
    'productTags': productTags,
    'tag1': productTags,
    'channel': channel,
    'province': province,
    'channelProvince': channelProvince,
    'profitModel': profitModel,
    'fileName': fileName,
  };
}

bool summaryFieldHasDisplayValue(dynamic value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is Iterable) {
    return value
        .map((e) => e.toString().trim())
        .any((e) => e.isNotEmpty);
  }
  return true;
}

dynamic summaryFieldValue(
  Map<String, dynamic> data,
  UploadSummaryFieldConfig field,
) {
  final source = field.source.trim();
  if (source.isEmpty) return null;
  return data[source];
}

/// 审批阶段（来自 detail-config / 模板 stages，不再从 Excel 生成审批人）。
List<Map<String, dynamic>> approvalStagesFromDetailConfig(
  Map<String, dynamic>? detailConfig,
) {
  final raw = detailConfig?['stages'];
  if (raw is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final row in raw) {
    if (row is Map<String, dynamic>) {
      out.add(row);
    } else if (row is Map) {
      out.add(Map<String, dynamic>.from(row));
    }
  }
  return out;
}

String uploadStageMetaLabel(Map<String, dynamic> stage) {
  final approverType = (stage['approverType'] ?? '').toString();
  final mode = (stage['mode'] ?? 'SINGLE').toString();
  String meta;
  if (approverType == 'SYSTEM') {
    meta = '系统自动';
  } else if (approverType == 'ROLE') {
    final role = (stage['roleCode'] ?? '').toString();
    meta = role == 'TECH' ? '按技术标签' : '角色 · $role';
  } else if (approverType == 'DIRECT_SUP') {
    meta = '部门主管';
  } else if (approverType == 'DIVISION') {
    meta = '事业部负责人';
  } else if (approverType == 'USER') {
    meta = '指定人员';
  } else {
    final ids = stage['approverIds'];
    meta = ids is List && ids.isNotEmpty ? '${ids.length} 人' : '指定审批人';
  }
  return '$mode · $meta';
}

/// 上传型模板中除 Excel 上传字段外的可填字段（如备注）。
List<XflowField> supplementalFormFields(List<XflowField> fields) {
  final upload = findPrimaryUploadField(fields);
  final uploadKey = upload?.key.trim() ?? '';
  return fields.where((field) {
    if (!isRenderableField(field)) return false;
    if (field.type == 'upload' || field.raw['actionKind'] == 'excel-import') {
      return false;
    }
    if (uploadKey.isNotEmpty && field.key == uploadKey) return false;
    return true;
  }).toList(growable: false);
}

bool supplementalFieldHasValue(dynamic value, {XflowField? field}) {
  if (value == null) return false;
  if (field != null &&
      (field.type == 'user' ||
          field.type == 'userSelect' ||
          field.raw['dataSource']?.toString() == 'org_user')) {
    if (value is Map) {
      final uid = value['userId'] ?? value['id'];
      final name = (value['name'] ?? value['displayName'] ?? '').toString().trim();
      if (uid != null && '$uid'.trim().isNotEmpty && uid != 0) return true;
      return name.isNotEmpty;
    }
    return value.toString().trim().isNotEmpty;
  }
  if (value is String) return value.trim().isNotEmpty;
  if (value is Iterable) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return true;
}

String? firstMissingRequiredSupplementalField(
  List<XflowField> fields,
  Map<String, dynamic> values,
) {
  for (final field in fields) {
    if (!field.required) continue;
    if (!supplementalFieldHasValue(values[field.key], field: field)) {
      final label = field.label.trim();
      return label.isNotEmpty ? label : field.key;
    }
  }
  return null;
}

/// 模板/业务线名称，如「销售提案」。
String proposalKindLabel({String? templateKey, String? businessType}) {
  final key = (templateKey ?? '').trim();
  switch (key) {
    case 'sales-proposal':
      return '销售提案';
    case 'purchase-proposal':
    case 'procurement-proposal':
      return '采购提案';
    case 'project-proposal':
      return '项目提案';
    default:
      if ((businessType ?? '').toUpperCase() == 'CONTRACT_SEAL') {
        return '合同用印';
      }
      if (key.isNotEmpty) {
        return key
            .split('-')
            .where((part) => part.isNotEmpty)
            .map((part) => part[0].toUpperCase() + part.substring(1))
            .join(' ')
            .replaceAll(RegExp(r'Proposal', caseSensitive: false), '提案');
      }
      return '销售提案';
  }
}

/// Excel 识别出的提案类型（与 summaryFields.proposalType 一致）。
String excelProposalTypeLabel(String? proposalType) {
  final text = (proposalType ?? '').trim();
  return text.isEmpty ? '—' : text;
}
