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

String formatProposalDisplay(dynamic val) {
  if (val == null || val == '') return '';
  if (val is String) {
    final text = val.trim();
    if (text.isEmpty || text.startsWith('map[')) return '';
    return text;
  }
  if (val is Map) {
    final code = (val['code'] ?? val['proposalCode'] ?? '').toString().trim();
    final title = (val['title'] ?? val['name'] ?? '').toString().trim();
    if (code.isNotEmpty && title.isNotEmpty) return '$code · $title';
    if (code.isNotEmpty) return code;
    if (title.isNotEmpty) return title;
    final pid = val['proposalId'] ?? val['id'];
    if (pid != null) return '提案#$pid';
  }
  return val.toString();
}

/// 从关联提案字段取值解析可跳转的提案 ID；解析不到返回 0。
int parseLinkedProposalId(dynamic val) {
  if (val == null || val == '') return 0;
  if (val is num) return val.toInt() > 0 ? val.toInt() : 0;
  if (val is String) {
    final text = val.trim();
    if (text.isEmpty) return 0;
    return int.tryParse(text) ?? 0;
  }
  if (val is Map) {
    final pid = val['proposalId'] ?? val['id'];
    if (pid is num) return pid.toInt() > 0 ? pid.toInt() : 0;
    if (pid != null) return int.tryParse('$pid') ?? 0;
  }
  return 0;
}

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
    case 'proposal':
      return formatProposalDisplay(val);
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
      return field.isCardDynamicList ? '${val.length}组' : '${val.length}行';
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
      return field.isCardDynamicList ? '1组' : '1行';
    }
    if (val['fileName'] != null) return val['fileName'].toString();
    if (val['text'] != null) return val['text'].toString();
    if (field.type == 'proposal' ||
        val['proposalId'] != null ||
        val['code'] != null && val['title'] != null) {
      return formatProposalDisplay(val);
    }
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

String formatGroupCellDisplay(XflowField col, Map<String, dynamic> row) {
  if (col.type == 'upload') return '';
  final cfg = col.remoteSearch;
  if (cfg != null && cfg.fill.length > 1) {
    final joined = cfg.fillDisplayOf(row);
    if (joined.isNotEmpty) return joined;
  }
  return formatCellDisplay(row[col.key], col.raw, row);
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
  // 并发/并行：优先用后端汇总的 currentNodeLabel，勿依赖 currentStep == 某一步
  final nodeLabel = trail.currentNodeLabel;
  if (nodeLabel.isNotEmpty) return nodeLabel;

  if (trail.isParallel) {
    final curSteps = trail.currentSteps.toSet();
    final open = trail.steps.where((s) {
      if (s.decision.trim().isNotEmpty) return false;
      final flagged = s.isCurrent;
      if (flagged != null) return flagged;
      if (curSteps.isNotEmpty) return curSteps.contains(s.stepNo);
      return true;
    });
    final labels = <String>[];
    for (final step in open) {
      final stage = trailStepRole(step, stages);
      final who = () {
        if (step.assigneeId > 0 && assigneeNames.containsKey(step.assigneeId)) {
          return assigneeNames[step.assigneeId]!;
        }
        if (step.assigneeName.isNotEmpty) return step.assigneeName;
        if (step.assigneeId > 0) return '用户 ${step.assigneeId}';
        return '待分配';
      }();
      final text = stage.isEmpty ? who : '$stage·$who';
      if (!labels.contains(text)) labels.add(text);
    }
    return labels.join('、');
  }

  final stepNo = trail.currentStep;
  final step = trail.steps.where((s) => s.stepNo == stepNo).firstOrNull;
  if (step == null) return stepNo > 0 ? '第$stepNo步' : '';
  final stageName = trailStepRole(step, stages);
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
  return '提交 · $code';
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

String trailStepRole(
  XflowApprovalStep step,
  List<Map<String, dynamic>> stages,
) {
  return humanizeApproverRole(
    step.stageName.isNotEmpty
        ? step.stageName
        : stageLabel(
            step.stepNo,
            step.stepType,
            stages,
            sourceStageNo: step.sourceStageNo,
          ),
    fallbackType: step.stepType,
  );
}

String stageLabel(
  int stepNo,
  String stepType,
  List<Map<String, dynamic>> stages, {
  int sourceStageNo = 0,
}) {
  final wantNo = sourceStageNo > 0 ? sourceStageNo : 0;
  final stepNorm = _normApproverType(stepType);
  if (wantNo > 0) {
    for (final stage in stages) {
      final no = _stageNoOf(stage);
      if (no != wantNo) continue;
      final liveNorm = _normApproverType('${stage['approverType'] ?? ''}');
      if (liveNorm.isNotEmpty &&
          stepNorm.isNotEmpty &&
          liveNorm != stepNorm) {
        continue;
      }
      final name = (stage['stageName'] ?? stage['name'] ?? stage['label'] ?? '')
          .toString()
          .trim();
      if (name.isNotEmpty) {
        return humanizeApproverRole(name, fallbackType: stepType);
      }
    }
  }
  return stepTypeLabel(stepType);
}

/// 接口可能把审批类型枚举（CUSTOM / DIRECT_SUP）写进 stageName，不能当角色名展示。
String humanizeApproverRole(String raw, {String fallbackType = ''}) {
  final text = raw.trim();
  if (text.isEmpty) return stepTypeLabel(fallbackType);
  if (_isApproverTypeCode(text)) return stepTypeLabel(text);
  return text;
}

bool _isApproverTypeCode(String text) {
  return RegExp(r'^[A-Z][A-Z0-9_]+$').hasMatch(text.trim());
}

String stepTypeLabel(String stepType) {
  switch (stepType.toUpperCase().trim()) {
    case 'DIRECT_SUP':
      return '直接主管';
    case 'DIVISION':
      return '部门主管';
    case 'FINANCE':
      return '财务总监';
    case 'ROLE':
      return '角色审批';
    case 'FORM_FIELD':
      return '表单选人';
    case 'CUSTOM':
    case 'USER':
      return '指定审批人';
    case 'SYSTEM':
      return '系统自动';
    case 'CONDITION':
    case 'CONDITIONAL':
      return '条件审批';
    case 'FINAL':
      return '最终审批';
    default:
      final text = stepType.trim();
      if (text.isEmpty) return '审批节点';
      if (RegExp(r'^[A-Z][A-Z0-9_]+$').hasMatch(text)) return '审批节点';
      return text;
  }
}

String _normApproverType(String raw) {
  final v = raw.toUpperCase().trim();
  if (v == 'USER') return 'CUSTOM';
  return v;
}

int _stageNoOf(Map<String, dynamic> stage) {
  final v = stage['stageNo'] ?? stage['stage_no'];
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
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
