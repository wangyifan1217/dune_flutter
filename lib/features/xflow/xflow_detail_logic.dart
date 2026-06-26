import 'xflow_models.dart';
import 'xflow_upload_field.dart';

const detailPreviewLimit = 6;

const colLabels = <String, String>{
  'cycle': '周期类型',
  'term': '账期',
  'weight': '权重(%)',
  'province': '省份',
  'note': '备注',
  'rate': '折扣率',
  'supplier': '供货商',
  'baseTier': '基准档',
  'currentRate': '当前费率',
  'marketing': '营销费率',
  'nonOil': '非油',
  'channel': '渠道',
  'universalRate': '通用费率',
  'marketingRate': '营销费率',
  'product': '产品',
  'cost': '成本',
  'salePrice': '售价',
  'customerPrice': '客户价',
  'rebate': '返佣',
  'tierType': '档位类型',
  'threshold': '阈值',
};

class DetailFieldItem {
  const DetailFieldItem({
    required this.key,
    required this.label,
    required this.value,
    required this.field,
    required this.rawValue,
    required this.expandable,
  });

  final String key;
  final String label;
  final String value;
  final XflowField field;
  final dynamic rawValue;
  final bool expandable;
}

class DetailSection {
  const DetailSection({required this.title, required this.items});

  final String title;
  final List<DetailFieldItem> items;
}

class RejectStepInfo {
  const RejectStepInfo({
    required this.comment,
    required this.who,
    required this.stepNo,
    required this.at,
  });

  final String comment;
  final String who;
  final int stepNo;
  final String at;
}

String detailStatusLabel(String? st) {
  switch ((st ?? '').toLowerCase()) {
    case 'draft':
      return '草稿';
    case 'pending_initiate':
      return '待确认发起';
    case 'pending':
      return '审批中';
    case 'approved':
      return '已通过';
    case 'rejected':
      return '已驳回';
    case 'voided':
      return '已作废';
    default:
      return st?.isNotEmpty == true ? st! : '—';
  }
}

DetailStatusTone detailStatusTone(String? st) {
  switch ((st ?? '').toLowerCase()) {
    case 'approved':
      return DetailStatusTone.ok;
    case 'rejected':
    case 'voided':
      return DetailStatusTone.bad;
    case 'pending':
    case 'pending_initiate':
      return DetailStatusTone.warn;
    default:
      return DetailStatusTone.muted;
  }
}

enum DetailStatusTone { ok, warn, bad, muted }

String formatUserDisplay(dynamic val) {
  if (val == null || val == '') return '';
  if (val is String) {
    if (val.startsWith('map[')) return '';
    return val;
  }
  if (val is Map) {
    final name = (val['displayName'] ?? val['name'] ?? '').toString();
    final dept = (val['dept'] ?? val['departmentName'] ?? '').toString();
    final title = (val['title'] ?? '').toString();
    final meta = [dept, title].where((e) => e.isNotEmpty).join(' · ');
    if (name.isNotEmpty && meta.isNotEmpty) return '$name（$meta）';
    if (name.isNotEmpty) return name;
    final uid = val['userId'] ?? val['id'];
    if (uid != null) return '用户#$uid';
  }
  return val.toString();
}

String labelForOptionValue(XflowField field, dynamic value) {
  if (value == null || value == '') return '';
  for (final o in field.options) {
    if (o.value == value.toString()) return o.label;
  }
  return value.toString();
}

String formatFieldValue(XflowField field, dynamic val) {
  if (val == null || val == '') return '';
  switch (field.type) {
    case 'user':
      return formatUserDisplay(val);
    case 'upload':
      final files = normalizeUploadItems(val).where((it) => it['status'] != 'error').toList();
      return files.isEmpty ? '' : '${files.length} 个文件';
    case 'multiSelect':
      final ms = val is List ? val : [val];
      return ms
          .map((v) => labelForOptionValue(field, v))
          .where((e) => e.isNotEmpty)
          .join('、');
    case 'select':
    case 'pill':
    case 'level':
      return labelForOptionValue(field, val);
  }
  if (val is List) {
    if (val.isEmpty) return '';
    if (field.type == 'dynamicList' || field.type == 'matrix' || field.type == 'structuredTable') {
      return '${val.length}行';
    }
    if (val.isNotEmpty && val.first is Map) {
      return val
          .map((row) {
            if (row is! Map) return row.toString();
            if (row['fileName'] != null) return row['fileName'].toString();
            if (row['label'] != null) return row['label'].toString();
            if (row['name'] != null) return row['name'].toString();
            if (row['province'] != null) return row['province'].toString();
            return '';
          })
          .where((e) => e.isNotEmpty)
          .join('、');
    }
    return val.where((e) => '$e'.isNotEmpty).join('、');
  }
  if (val is Map) {
    if (field.type == 'dynamicList' || field.type == 'matrix' || field.type == 'structuredTable') {
      return '1行';
    }
    if (val['fileName'] != null) return val['fileName'].toString();
    if (val['text'] != null) return val['text'].toString();
    return formatUserDisplay(val);
  }
  if (val is bool) return val ? '是' : '否';
  return val.toString();
}

bool isExpandableField(XflowField field, dynamic val) {
  if (val == null) return false;
  if (field.type == 'dynamicList' || field.type == 'matrix' || field.type == 'structuredTable') {
    return normalizeDynamicListValue(val).isNotEmpty;
  }
  if (field.type == 'upload') {
    return normalizeUploadItems(val).where((it) => it['status'] != 'error').isNotEmpty;
  }
  return false;
}

List<Map<String, dynamic>> normalizeDynamicListValue(dynamic val) {
  if (val == null || val == '') return [];
  if (val is List) {
    return val
        .map((e) => e is Map<String, dynamic> ? e : (e is Map ? Map<String, dynamic>.from(e) : null))
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }
  if (val is Map) return [Map<String, dynamic>.from(val)];
  return [];
}

List<Map<String, dynamic>> inferColumns(List<Map<String, dynamic>> rows, XflowField field) {
  if (field.raw['columns'] is List && (field.raw['columns'] as List).isNotEmpty) {
    return (field.raw['columns'] as List)
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList(growable: false);
  }
  if (rows.isEmpty || rows.first.isEmpty) return [];
  final nestedKey = (field.raw['nestedKey'] ?? 'items').toString();
  return rows.first.keys
      .where((k) => k != nestedKey && rows.first[k] is! List && rows.first[k] is! Map)
      .map((k) => {'key': k, 'label': colLabels[k] ?? k})
      .toList(growable: false);
}

String formatCellDisplay(dynamic val, Map<String, dynamic> col, Map<String, dynamic> row) {
  if (val == null || val == '') {
    final aliases = {
      'note': ['description', 'desc', 'remark'],
      'rate': ['discount', 'ratio', 'value'],
      'province': ['prov', 'name'],
    };
    final key = col['key']?.toString() ?? '';
    for (final alt in aliases[key] ?? const []) {
      final v = row[alt];
      if (v != null && '$v'.trim().isNotEmpty) {
        val = v;
        break;
      }
    }
  }
  if (val == null || val == '') return '—';
  if (col['type']?.toString() == 'select' && col['options'] is List) {
    for (final o in col['options'] as List) {
      if (o is Map && '${o['value']}' == '$val') return (o['label'] ?? val).toString();
    }
  }
  if (val is Map) return formatUserDisplay(val);
  return val.toString();
}

String fmtList(dynamic arr) {
  if (arr is! List || arr.isEmpty) return '—';
  return arr
      .map((x) {
        if (x == null || x == '') return '';
        if (x is String) return x;
        if (x is Map) return (x['label'] ?? x['name'] ?? x['province'] ?? '').toString();
        return x.toString();
      })
      .where((e) => e.isNotEmpty)
      .join('、');
}

List<DetailSection> buildFieldSections(
  List<XflowField> fields,
  Map<String, dynamic> formValues,
  XflowProposalDetail detail,
) {
  final fv = Map<String, dynamic>.from(formValues);
  if ((fv['provinces'] == null || (fv['provinces'] is List && (fv['provinces'] as List).isEmpty)) &&
      detail.raw['coverage'] is List) {
    fv['provinces'] = detail.raw['coverage'];
  }
  const priorityKeys = [
    'title', 'tag1', 'provinces', 'txType', 'goodType', 'proposalType',
    'techPlatform', 'launchDate', 'launchChannel',
  ];
  final sections = <DetailSection>[];
  var currentTitle = '基本信息';
  var currentItems = <DetailFieldItem>[];

  void flush() {
    if (currentItems.isEmpty) return;
    currentItems.sort((a, b) {
      final ai = priorityKeys.indexOf(a.key);
      final bi = priorityKeys.indexOf(b.key);
      if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
      if (ai >= 0) return -1;
      if (bi >= 0) return 1;
      return 0;
    });
    sections.add(DetailSection(title: currentTitle, items: List.from(currentItems)));
    currentItems = [];
  }

  for (final field in fields) {
    if (field.key.isEmpty) continue;
    if (field.type == 'section') {
      flush();
      currentTitle = field.label.isEmpty ? '板块' : field.label;
      continue;
    }
    if (field.type == 'action' || field.type == 'row' || field.key == 'proposalCode') continue;
    var val = fv[field.key];
    if (field.type == 'dynamicList' || field.type == 'matrix' || field.type == 'structuredTable') {
      val = normalizeDynamicListValue(val);
    }
    var text = formatFieldValue(field, val);
    if (text.isEmpty) continue;
    var fieldDef = field;
    var expandable = isExpandableField(field, val);
    if (!expandable &&
        val is List &&
        val.isNotEmpty &&
        val.first is Map &&
        val.first['fileName'] == null &&
        val.first['url'] == null &&
        val.first['objectKey'] == null) {
      fieldDef = XflowField(
        key: field.key,
        type: field.type.isEmpty ? 'dynamicList' : field.type,
        label: field.label,
        placeholder: field.placeholder,
        required: field.required,
        readonly: field.readonly,
        options: field.options,
        children: field.children,
        raw: field.raw,
      );
      expandable = true;
      if (!text.contains('行')) text = '${val.length}行';
    }
    currentItems.add(
      DetailFieldItem(
        key: field.key,
        label: field.label.isEmpty ? field.key : field.label,
        value: text,
        field: fieldDef,
        rawValue: val,
        expandable: expandable,
      ),
    );
  }
  flush();
  return sections;
}

List<DetailSection> buildSectionsByDetailConfig(
  List<XflowField> fields,
  Map<String, dynamic> formValues,
  Map<String, dynamic> cfg,
  XflowProposalDetail detail,
) {
  final tabs = cfg['tabs'];
  final allSections = buildFieldSections(fields, formValues, detail);
  if (tabs is! List || tabs.isEmpty) return allSections;
  const tabGroups = {
    'biz': ['业务元数据'],
    'finance': ['财务模块', '商务模式'],
    'solution': ['方案叙事'],
    'tech': ['技术能力', '风控标准'],
  };
  return tabs.map<DetailSection>((tab) {
    final key = (tab is Map ? tab['key'] : tab)?.toString() ?? '';
    final tabLabel = (tab is Map ? tab['label'] : null)?.toString() ?? key;
    final titles = tabGroups[key] ?? [tabLabel.split(' · ').first];
    final items = <DetailFieldItem>[];
    for (final sec in allSections) {
      if (titles.contains(sec.title)) items.addAll(sec.items);
    }
    if (items.isEmpty && key == 'biz' && allSections.isNotEmpty) {
      items.addAll(allSections.first.items);
    }
    return DetailSection(title: tabLabel, items: items);
  }).where((s) => s.items.isNotEmpty).toList(growable: false);
}

RejectStepInfo? lastRejectStep(XflowApprovalTrail? trail, Map<int, String> assigneeNames) {
  if (trail == null) return null;
  final rejected = trail.steps.where((s) => s.decision.toUpperCase() == 'REJECTED').toList();
  if (rejected.isEmpty) return null;
  final step = rejected.last;
  return RejectStepInfo(
    comment: step.comment.isEmpty ? '无说明' : step.comment,
    who: assigneeNames[step.assigneeId] ?? step.assigneeName.ifEmpty('审批人'),
    stepNo: step.stepNo,
    at: step.decidedAtRaw,
  );
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

String currentApproverLabel(
  XflowApprovalTrail? trail,
  Map<int, String> assigneeNames,
  List<Map<String, dynamic>> stages,
) {
  if (trail == null) return '';
  final stepNo = trail.currentStep;
  final step = trail.steps.where((s) => s.stepNo == stepNo).firstOrNull;
  if (step == null) return stepNo > 0 ? '第$stepNo步' : '';
  final stageName = stageLabel(stepNo, step.stepType, stages);
  if (step.assigneeId > 0 && assigneeNames.containsKey(step.assigneeId)) {
    return '$stageName · ${assigneeNames[step.assigneeId]}';
  }
  if (step.assigneeName.isNotEmpty) {
    return '$stageName · ${step.assigneeName}';
  }
  if (step.decision.isNotEmpty) return '第$stepNo步 · ${step.decision}';
  return stageName.isNotEmpty ? stageName : '第$stepNo步';
}

/// 流程追踪首节点「提交人」：代发起场景仍展示推送人，审批链归属不变。
String trailSubmitterLabel(XflowProposalDetail detail, XflowApprovalTrail? trail, Map<int, String> assigneeNames) {
  final raw = detail.raw;
  final draftedBy = raw['draftedBy'];
  if (draftedBy is Map) {
    final pusherName = (draftedBy['name'] ?? '').toString();
    if (pusherName.isNotEmpty) return pusherName;
  }

  if (trail != null && trail.initiatorId > 0) {
    final fromTrail = assigneeNames[trail.initiatorId];
    if (fromTrail != null && fromTrail.isNotEmpty) return fromTrail;
  }

  final createdBy = (raw['createdBy'] ?? raw['createdByName'] ?? '').toString();
  if (createdBy.isNotEmpty) return createdBy;
  return detail.ownerName.ifEmpty('发起人');
}

String trailSubmitterComment(XflowProposalDetail detail) {
  final code = detail.code.isEmpty ? '—' : detail.code;
  return '提交提案 · $code';
}

String? trailProxyInitiatorNote(XflowProposalDetail detail) {
  final raw = detail.raw;
  if (raw['draftedBy'] == null) return null;
  final name = _designatedInitiatorName(raw);
  if (name.isEmpty) return null;
  return '由 $name 代为确认发起';
}

String _designatedInitiatorName(Map<String, dynamic> raw) {
  final designated = raw['designatedInitiator'];
  if (designated is Map) return (designated['name'] ?? '').toString();
  return '';
}

String stageLabel(int stepNo, String stepType, List<Map<String, dynamic>> stages) {
  if (stepNo > 0 && stepNo <= stages.length) {
    final name = (stages[stepNo - 1]['stageName'] ?? '').toString();
    if (name.isNotEmpty) return name;
  }
  switch (stepType) {
    case 'DIRECT_SUP':
      return '部门主管';
    case 'FINANCE':
      return '财务总监';
    case 'ROLE':
      return '技术审批';
    default:
      return stepType.isEmpty ? '审批节点' : stepType;
  }
}

String fmtDetailTime(dynamic v) {
  if (v == null || '$v'.isEmpty) return '';
  var s = v.toString().trim();
  // 兼容 PostgreSQL 风格 `...+00` 时区，避免 parse 失败直接展示原始串。
  if (RegExp(r'\+00:?00?$').hasMatch(s)) {
    s = s.replaceFirst(RegExp(r'\+00:?00?$'), 'Z');
  }
  final d = DateTime.tryParse(s)?.toLocal();
  if (d == null) return v.toString();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}:${p(d.second)}';
}

String owner2Line(Map<String, dynamic> fv, Map<String, dynamic> raw) {
  final name = formatUserDisplay(fv['owner2']).ifEmpty(formatUserDisplay(raw['owner2']));
  final level = (fv['owner2Level'] ?? raw['owner2Level'] ?? '').toString();
  if (name.isEmpty) return level.isEmpty ? '' : '${level.toUpperCase()}级';
  return level.isEmpty ? name : '$name · ${level.toUpperCase()}级';
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
