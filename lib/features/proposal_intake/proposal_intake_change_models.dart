import 'dart:convert';

import 'proposal_intake_models.dart';

/// 列表 / 详情行上带的进行中变更摘要。
class ProposalIntakeChangeSummary {
  const ProposalIntakeChangeSummary({
    required this.id,
    required this.status,
    this.reason = '',
    this.applicantId = 0,
    this.affectedSections = const [],
    this.myAction = '',
    this.myActionLabel = '',
    this.version = 1,
  });

  final int id;
  final String status;
  final String reason;
  final int applicantId;
  final List<String> affectedSections;
  final String myAction;
  final String myActionLabel;
  final int version;

  static ProposalIntakeChangeSummary? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = _int(map['id']);
    if (id <= 0) return null;
    return ProposalIntakeChangeSummary(
      id: id,
      status: _text(map['status']),
      reason: _text(map['reason']),
      applicantId: _int(map['applicantId']),
      affectedSections: _strings(map['affectedSections']),
      myAction: _text(map['myAction']),
      myActionLabel: _text(map['myActionLabel']),
      version: _int(map['version'], fallback: 1),
    );
  }
}

class ProposalIntakeChangeValueDiff {
  const ProposalIntakeChangeValueDiff({
    required this.path,
    this.oldValue,
    this.newValue,
    this.oldExists = true,
    this.newExists = true,
  });

  final List<String> path;
  final Object? oldValue;
  final Object? newValue;
  final bool oldExists;
  final bool newExists;

  factory ProposalIntakeChangeValueDiff.fromJson(Map<String, dynamic> json) =>
      ProposalIntakeChangeValueDiff(
        path: _strings(json['path']),
        oldValue: json['oldValue'],
        newValue: json['newValue'],
        oldExists: json['oldExists'] != false,
        newExists: json['newExists'] != false,
      );
}

class ProposalIntakeChangeDiffItem {
  const ProposalIntakeChangeDiffItem({
    required this.key,
    this.sections = const [],
    this.changes = const [],
  });

  final String key;
  final List<String> sections;
  final List<ProposalIntakeChangeValueDiff> changes;

  factory ProposalIntakeChangeDiffItem.fromJson(Map<String, dynamic> json) =>
      ProposalIntakeChangeDiffItem(
        key: _text(json['key']),
        sections: _strings(json['sections']),
        changes: _maps(json['changes'])
            .map(ProposalIntakeChangeValueDiff.fromJson)
            .toList(),
      );
}

class ProposalIntakeChangeSection {
  const ProposalIntakeChangeSection({
    required this.section,
    this.label = '',
    this.status = '',
    this.reviewerId = 0,
    this.reviewerName = '',
    this.reviewerRole = '',
    this.actorId = 0,
    this.comment = '',
    this.at = '',
  });

  final String section;
  final String label;
  final String status;
  final int reviewerId;
  final String reviewerName;
  final String reviewerRole;
  final int actorId;
  final String comment;
  final String at;

  bool get approved => status == 'approved';
  bool get rejected => status == 'rejected';
  bool get pending => status == 'pending';

  factory ProposalIntakeChangeSection.fromJson(Map<String, dynamic> json) =>
      ProposalIntakeChangeSection(
        section: _text(json['section']),
        label: _text(json['label']),
        status: _text(json['status']),
        reviewerId: _int(json['reviewerId']),
        reviewerName: _text(json['reviewerName']),
        reviewerRole: _text(json['reviewerRole']),
        actorId: _int(json['actorId']),
        comment: _text(json['comment']),
        at: _text(json['at']),
      );
}

class ProposalIntakeChangeEvent {
  const ProposalIntakeChangeEvent({
    required this.event,
    this.actorId = 0,
    this.actorName = '',
    this.section = '',
    this.comment = '',
    this.detail = const {},
    this.createdAt = '',
  });

  final String event;
  final int actorId;
  final String actorName;
  final String section;
  final String comment;
  final Map<String, dynamic> detail;
  final String createdAt;

  factory ProposalIntakeChangeEvent.fromJson(Map<String, dynamic> json) =>
      ProposalIntakeChangeEvent(
        event: _text(json['event']),
        actorId: _int(json['actorId']),
        actorName: _text(json['actorName']),
        section: _text(json['section']),
        comment: _text(json['comment']),
        detail: _map(json['detail']),
        createdAt: _text(json['createdAt']),
      );
}

class ProposalIntakeChange {
  const ProposalIntakeChange({
    required this.id,
    required this.proposalId,
    required this.applicantId,
    required this.status,
    required this.version,
    this.reason = '',
    this.applicantName = '',
    this.proposalCode = '',
    this.proposalTitle = '',
    this.baseVersion = 0,
    this.baseForm = const {},
    this.proposedForm = const {},
    this.review = const {},
    this.affectedSections = const [],
    this.diff = const [],
    this.financeItemKeys = const [],
    this.sections = const [],
    this.events = const [],
    this.myAction = '',
    this.myActionLabel = '',
    this.canEdit = false,
    this.canCancel = false,
    this.createdAt = '',
    this.submittedAt = '',
    this.decidedAt = '',
    this.notified = const [],
  });

  final int id;
  final int proposalId;
  final int applicantId;
  final String status;
  final int version;
  final String reason;
  final String applicantName;
  final String proposalCode;
  final String proposalTitle;
  final int baseVersion;
  final Map<String, dynamic> baseForm;
  final Map<String, dynamic> proposedForm;
  final Map<String, dynamic> review;
  final List<String> affectedSections;
  final List<ProposalIntakeChangeDiffItem> diff;
  final List<String> financeItemKeys;
  final List<ProposalIntakeChangeSection> sections;
  final List<ProposalIntakeChangeEvent> events;
  final String myAction;
  final String myActionLabel;
  final bool canEdit;
  final bool canCancel;
  final String createdAt;
  final String submittedAt;
  final String decidedAt;
  final List<String> notified;

  bool get active => proposalIntakeChangeIsActive(status);

  bool financeItemApproved(String key) {
    final items = review['financeItems'];
    if (items is! Map) return false;
    final entry = items[key];
    return entry is Map && entry['status'] == 'approved';
  }

  List<String> get pendingFinanceItems =>
      financeItemKeys.where((key) => !financeItemApproved(key)).toList();

  /// 历轮驳回意见（含当前这一轮）。
  List<Map<String, dynamic>> get rejectRounds {
    final out = <Map<String, dynamic>>[];
    final history = review['history'];
    if (history is List) {
      for (final item in history) {
        if (item is Map) out.add(Map<String, dynamic>.from(item));
      }
    }
    if (_text(review['rejectSection']).isNotEmpty ||
        review['presidentRejected'] == true) {
      out.add(review);
    }
    return out;
  }

  factory ProposalIntakeChange.fromJson(Map<String, dynamic> json) {
    final notified = <String>[];
    for (final item in _maps(json['notified'])) {
      final name = _text(item['name']);
      final role = _text(item['role']);
      final label = [role, name].where((e) => e.isNotEmpty).join(' ');
      if (label.isNotEmpty) notified.add(label);
    }
    return ProposalIntakeChange(
      id: _int(json['id']),
      proposalId: _int(json['proposalId']),
      applicantId: _int(json['applicantId']),
      status: _text(json['status']),
      version: _int(json['version'], fallback: 1),
      reason: _text(json['reason']),
      applicantName: _text(json['applicantName']),
      proposalCode: _text(json['proposalCode']),
      proposalTitle: _text(json['proposalTitle']),
      baseVersion: _int(json['baseVersion']),
      baseForm: _map(json['baseForm']),
      proposedForm: _map(json['proposedForm']),
      review: _map(json['review']),
      affectedSections: _strings(json['affectedSections']),
      diff: _maps(json['diff']).map(ProposalIntakeChangeDiffItem.fromJson).toList(),
      financeItemKeys: _strings(json['financeItemKeys']),
      sections: _maps(json['sections'])
          .map(ProposalIntakeChangeSection.fromJson)
          .toList(),
      events: _maps(json['events']).map(ProposalIntakeChangeEvent.fromJson).toList(),
      myAction: _text(json['myAction']),
      myActionLabel: _text(json['myActionLabel']),
      canEdit: json['canEdit'] == true,
      canCancel: json['canCancel'] == true,
      createdAt: _text(json['createdAt']),
      submittedAt: _text(json['submittedAt']),
      decidedAt: _text(json['decidedAt']),
      notified: notified,
    );
  }
}

class ProposalIntakeChangeList {
  const ProposalIntakeChangeList({
    this.items = const [],
    this.canStart = false,
    this.startBlockedReason = '',
  });

  final List<ProposalIntakeChange> items;
  final bool canStart;
  final String startBlockedReason;

  ProposalIntakeChange? get active {
    for (final item in items) {
      if (item.active) return item;
    }
    return null;
  }

  factory ProposalIntakeChangeList.fromJson(Map<String, dynamic> json) =>
      ProposalIntakeChangeList(
        items: _maps(json['items']).map(ProposalIntakeChange.fromJson).toList(),
        canStart: json['canStart'] == true,
        startBlockedReason: _text(json['startBlockedReason']),
      );
}

bool proposalIntakeChangeIsActive(String status) => switch (status) {
  'draft' ||
  'reviewing' ||
  'returned' ||
  'awaiting_submit' ||
  'pending_president' => true,
  _ => false,
};

String proposalIntakeChangeStatusLabel(String status) => switch (status) {
  'draft' => '草稿',
  'reviewing' => '复核中',
  'returned' => '已驳回待修改',
  'awaiting_submit' => '待通知最终人',
  'pending_president' => '待最终确认',
  'approved' => '已生效',
  'cancelled' => '已撤销',
  _ => status,
};

String proposalIntakeChangeSectionLabel(String section) => switch (section) {
  'market' => '市场部',
  'technology' => '科技部',
  'finance' => '财务部',
  'financeItems' => '财务逐条',
  'purchaseContract' => '采购合同',
  'salesContract' => '销售合同',
  _ => section,
};

String proposalIntakeChangeEventLabel(ProposalIntakeChangeEvent event) {
  final section = event.section.isEmpty
      ? ''
      : proposalIntakeChangeSectionLabel(event.section);
  return switch (event.event) {
    'created' => '发起变更',
    'saved' => '保存草稿',
    'submitted' => '提交复核',
    'finance_items_approved' => '财务逐条复核通过',
    'section_approved' => '$section复核通过',
    'section_rejected' => '$section驳回',
    'notified_final' => '通知最终人',
    'president_approved' => '最终人确认通过，变更生效',
    'president_rejected' => '最终人驳回',
    'cancelled' => '撤销变更',
    _ => event.event,
  };
}

/// 当前用户在变更里能做的复核动作对应的板块。
String proposalIntakeChangeReviewSection(String action) => switch (action) {
  'change_review_market' => 'market',
  'change_review_tech' => 'technology',
  'change_review_finance' => 'financeItems',
  'change_review_finance_module' => 'finance',
  _ => '',
};

const _kProposalChangeExtraLabels = <String, String>{
  'projectBackground': '项目背景',
  'sector': '业务板块',
  'sectorRef': '业务板块',
  'product': '产品（标签一）',
  'productRef': '产品（标签一）',
  'projectName': '项目名称（标签一二级）',
  'projectRef': '项目名称（标签一二级）',
  'supplyTagL1': '标签二一级',
  'supplyTagL1Ref': '标签二一级',
  'channelTagL1': '标签三一级',
  'channelTagL1Ref': '标签三一级',
  'technologyCapabilities': '能力',
  'technologyRecords': '科技记录',
  'onlineProductFiles': '上线产品文件',
  'syncSource': '业务平台',
  'skuDetails': '产品明细',
  'childProducts': '子产品',
  'channelSkus': '渠道产品',
  'skuSettlements': '产品结算',
  'sharedSettlements': '共享结算',
  'productFinance': '产品财务',
  'productFormulas': '产品公式',
  'financeModules': '财务模块',
  'launchRows': '上线省份',
  'launchModules': '上线模块',
  'costItems': '项目成本',
  'costItemAmounts': '项目成本金额',
  'costItemCodes': '项目成本项',
  'operatingCost': '经营成本',
  'operatingCostItems': '经营成本项',
  'operatingCostItemAmounts': '经营成本金额',
  'taxCost': '税费成本',
  'taxCostItems': '税费成本项',
  'taxCostItemAmounts': '税费成本金额',
  'businessCost': '业务成本',
  'businessCostItems': '业务成本项',
  'projectCost': '项目成本合计',
  'revenueFormula': '收入公式',
  'promotionTiers': '促销阶梯',
  'turnoverCash': '周转资金',
  'rollback': '回滚',
  'benefitProduct': '权益产品',
  'proposalSubtitle': '提案副标题',
  'outputForms': '能力输出/输入形式',
  'rdAmount': '研发费用金额',
  'purchaseNo': '采购合同编号',
  'purchaseMode': '采购合同状态',
  'purchaseFiles': '采购合同文件',
  'salesNo': '销售合同编号',
  'salesMode': '销售合同状态',
  'salesName': '销售合同名称',
  'salesSignDate': '销售合同签署时间',
  'salesOurParty': '销售合同我方签约主体',
  'salesCounterparty': '销售合同对方签约主体',
  'salesValidPeriod': '销售合同有效期',
  'salesCoreTerms': '销售合同核心条款',
  'salesInvoiceType': '销售发票类型',
  'salesInvoiceFlow': '销售开票流程',
  'salesFiles': '销售合同文件',
};

String proposalIntakeChangeFieldLabel(String key) {
  final extra = _kProposalChangeExtraLabels[key];
  if (extra != null) return extra;
  final tech = kProposalTechnologyReviewLabels[key];
  if (tech != null) return tech;
  for (final field in kProposalSalesFinanceFillFields) {
    if (field.$1 == key) return field.$2;
  }
  return key;
}

/// 差异里的取值转成一行可读文本；复杂结构压成 JSON，过长截断。
String proposalIntakeChangeValueText(Object? value, {bool exists = true}) {
  if (!exists || value == null) return '（空）';
  if (value is String) return value.trim().isEmpty ? '（空）' : value.trim();
  if (value is num || value is bool) {
    if (value is bool) return value ? '是' : '否';
    return '$value';
  }
  if (value is Map) {
    for (final key in const ['name', 'label', 'title', 'text']) {
      final text = _text(value[key]);
      if (text.isNotEmpty) return text;
    }
    if (value.isEmpty) return '（空）';
  }
  if (value is List) {
    if (value.isEmpty) return '（空）';
    if (value.every((e) => e is String || e is num)) {
      return value.map((e) => '$e').join('、');
    }
    if (value.every((e) => e is Map)) {
      final names = value
          .map((e) => proposalIntakeChangeValueText(e))
          .toList();
      if (names.every((e) => !e.startsWith('{'))) return names.join('、');
    }
  }
  final raw = jsonEncode(value);
  return raw.length > 160 ? '${raw.substring(0, 160)}…' : raw;
}

String proposalIntakeChangePathLabel(List<String> path) {
  if (path.isEmpty) return '';
  final head = proposalIntakeChangeFieldLabel(path.first);
  if (path.length == 1) return head;
  return '$head · ${path.skip(1).join(' · ')}';
}

int _int(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}'.trim()) ?? fallback;
}

String _text(Object? value) => '${value ?? ''}'.trim();

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _maps(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return value.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
}

/// 在现有提案表单里改变更草稿：保存和提交走变更申请，不改生效版本。
class ProposalIntakeChangeEdit {
  const ProposalIntakeChangeEdit({
    required this.change,
    required this.onSave,
    required this.onSubmit,
    this.onCancel,
  });

  final ProposalIntakeChange change;
  final Future<ProposalIntakeChange> Function(Map<String, dynamic> form) onSave;
  final Future<void> Function() onSubmit;
  final Future<void> Function()? onCancel;
}
