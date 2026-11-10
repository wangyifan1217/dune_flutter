/// 资金提案（融资立项申请）的数据结构。
///
/// 下拉选项、测算结果、校验都来自后端 `/funding-proposals/*`，前端只展示，不做计算。
library;

String _s(Object? v) => v == null ? '' : '$v'.trim();

int _i(Object? v) => v is num ? v.toInt() : int.tryParse(_s(v)) ?? 0;

int? _iOrNull(Object? v) => v is num ? v.toInt() : int.tryParse(_s(v));

Map<String, dynamic> _m(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<dynamic> _l(Object? v) => v is List ? v : const [];

DateTime? _t(Object? v) {
  final text = _s(v);
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}

const kFundingStatusDraft = 'draft';
const kFundingStatusReviewing = 'reviewing';
const kFundingStatusRejected = 'rejected';
const kFundingStatusApproved = 'approved';

/// 审批节点顺序与后端 fundingNodeOrder 一致，只用来排版，不决定流程。
const kFundingNodeOrder = ['funding', 'finance', 'risk', 'gm'];

String fundingStatusLabel(String status) => switch (status) {
  kFundingStatusDraft => '草稿',
  kFundingStatusReviewing => '审批中',
  kFundingStatusRejected => '已驳回',
  kFundingStatusApproved => '已通过',
  _ => status,
};

class FundingAccess {
  const FundingAccess({
    this.view = false,
    this.fill = false,
    this.viewAll = false,
  });

  final bool view;
  final bool fill;
  final bool viewAll;

  factory FundingAccess.fromJson(Map<String, dynamic> json) => FundingAccess(
    view: json['view'] == true,
    fill: json['fill'] == true,
    viewAll: json['viewAll'] == true,
  );
}

class FundingOption {
  const FundingOption({required this.value, required this.label});

  final String value;
  final String label;

  factory FundingOption.fromJson(Object? raw) {
    final m = _m(raw);
    final value = _s(m['value']);
    final label = _s(m['label']);
    return FundingOption(value: value, label: label.isEmpty ? value : label);
  }
}

class FundingMaterialOption {
  const FundingMaterialOption({
    required this.key,
    required this.label,
    required this.required,
  });

  final String key;
  final String label;
  final bool required;

  factory FundingMaterialOption.fromJson(Object? raw) {
    final m = _m(raw);
    return FundingMaterialOption(
      key: _s(m['key']),
      label: _s(m['label']),
      required: m['required'] == true,
    );
  }
}

class FundingNodeOption {
  const FundingNodeOption({
    required this.key,
    required this.label,
    this.defaultUserId = 0,
    this.defaultUserName = '',
  });

  final String key;
  final String label;
  final int defaultUserId;
  final String defaultUserName;

  factory FundingNodeOption.fromJson(Object? raw) {
    final m = _m(raw);
    return FundingNodeOption(
      key: _s(m['key']),
      label: _s(m['label']),
      defaultUserId: _i(m['defaultUserId']),
      defaultUserName: _s(m['defaultUserName']),
    );
  }
}

class FundingOptions {
  const FundingOptions({
    this.funderTypes = const [],
    this.repayMethods = const [],
    this.collectionAccounts = const [],
    this.materials = const [],
    this.approvalNodes = const [],
    this.dayBasis = 360,
    this.bufferDays = 10,
  });

  final List<FundingOption> funderTypes;
  final List<FundingOption> repayMethods;
  final List<FundingOption> collectionAccounts;
  final List<FundingMaterialOption> materials;
  final List<FundingNodeOption> approvalNodes;
  final int dayBasis;
  final int bufferDays;

  factory FundingOptions.fromJson(Map<String, dynamic> json) {
    final config = _m(json['config']);
    return FundingOptions(
      funderTypes: [for (final o in _l(json['funderTypes'])) FundingOption.fromJson(o)],
      repayMethods: [for (final o in _l(json['repayMethods'])) FundingOption.fromJson(o)],
      collectionAccounts: [
        for (final o in _l(json['collectionAccounts'])) FundingOption.fromJson(o),
      ],
      materials: [
        for (final o in _l(json['materials'])) FundingMaterialOption.fromJson(o),
      ],
      approvalNodes: [
        for (final o in _l(json['approvalNodes'])) FundingNodeOption.fromJson(o),
      ],
      dayBasis: _iOrNull(config['dayBasis']) ?? 360,
      bufferDays: _iOrNull(config['bufferDays']) ?? 10,
    );
  }

  String labelOf(List<FundingOption> list, String value) {
    for (final o in list) {
      if (o.value == value) return o.label;
    }
    return value;
  }

  String nodeLabel(String key) {
    for (final n in approvalNodes) {
      if (n.key == key) return n.label;
    }
    return key;
  }
}

/// 后端测算返回的一个值：raw 是原值，text 是格式化好的展示文本。
class FundingValue {
  const FundingValue({this.raw, this.text = '', this.formula = ''});

  final Object? raw;
  final String text;
  final String formula;

  factory FundingValue.fromJson(Object? raw) {
    final m = _m(raw);
    return FundingValue(
      raw: m['raw'],
      text: _s(m['text']),
      formula: _s(m['formula']),
    );
  }

  bool get isEmpty => text.isEmpty;
}

class FundingFunderResult {
  const FundingFunderResult({
    required this.rowId,
    this.interestDays = 0,
    this.interest = const FundingValue(),
    this.serviceFee = const FundingValue(),
    this.maturityDate = '',
  });

  final String rowId;
  final int interestDays;
  final FundingValue interest;
  final FundingValue serviceFee;
  final String maturityDate;

  factory FundingFunderResult.fromJson(Object? raw) {
    final m = _m(raw);
    return FundingFunderResult(
      rowId: _s(m['rowId']),
      interestDays: _i(m['interestDays']),
      interest: FundingValue.fromJson(m['interest']),
      serviceFee: FundingValue.fromJson(m['serviceFee']),
      maturityDate: _s(m['maturityDate']),
    );
  }
}

class FundingCheck {
  const FundingCheck({
    required this.id,
    required this.level,
    required this.pass,
    required this.message,
  });

  final String id;
  final String level;
  final bool pass;
  final String message;

  bool get blocking => level == 'block';

  factory FundingCheck.fromJson(Object? raw) {
    final m = _m(raw);
    return FundingCheck(
      id: _s(m['id']),
      level: _s(m['level']),
      pass: m['pass'] == true,
      message: _s(m['message']),
    );
  }
}

class FundingSlice {
  const FundingSlice({
    required this.key,
    required this.label,
    required this.amount,
    required this.percent,
    required this.weight,
  });

  final String key;
  final String label;
  final String amount;
  final String percent;

  /// 占毛利的万分比，后端算好，只用来画分段条。
  final int weight;

  factory FundingSlice.fromJson(Object? raw) {
    final m = _m(raw);
    return FundingSlice(
      key: _s(m['key']),
      label: _s(m['label']),
      amount: _s(m['amount']),
      percent: _s(m['percent']),
      weight: _i(m['weight']),
    );
  }
}

class FundingTimeline {
  const FundingTimeline({
    this.turnoverDays,
    this.maturityDays,
    this.breakEvenDays,
    this.bufferDays,
    this.requiredBuffer = 0,
  });

  final int? turnoverDays;
  final int? maturityDays;
  final int? breakEvenDays;
  final int? bufferDays;
  final int requiredBuffer;

  factory FundingTimeline.fromJson(Object? raw) {
    final m = _m(raw);
    return FundingTimeline(
      turnoverDays: _iOrNull(m['turnoverDays']),
      maturityDays: _iOrNull(m['maturityDays']),
      breakEvenDays: _iOrNull(m['breakEvenDays']),
      bufferDays: _iOrNull(m['bufferDays']),
      requiredBuffer: _i(m['requiredBuffer']),
    );
  }
}

class FundingEstimate {
  const FundingEstimate({
    this.fields = const {},
    this.funders = const [],
    this.composition = const [],
    this.timeline = const FundingTimeline(),
    this.checks = const [],
    this.missing = const [],
    this.blocking = 0,
    this.calculatedAt,
  });

  final Map<String, FundingValue> fields;
  final List<FundingFunderResult> funders;
  final List<FundingSlice> composition;
  final FundingTimeline timeline;
  final List<FundingCheck> checks;
  final List<String> missing;
  final int blocking;
  final DateTime? calculatedAt;

  static const empty = FundingEstimate();

  factory FundingEstimate.fromJson(Object? raw) {
    final m = _m(raw);
    final fields = <String, FundingValue>{};
    _m(m['fields']).forEach((k, v) => fields[k] = FundingValue.fromJson(v));
    return FundingEstimate(
      fields: fields,
      funders: [for (final f in _l(m['funders'])) FundingFunderResult.fromJson(f)],
      composition: [
        for (final s in _l(m['composition'])) FundingSlice.fromJson(s),
      ],
      timeline: FundingTimeline.fromJson(m['timeline']),
      checks: [for (final c in _l(m['checks'])) FundingCheck.fromJson(c)],
      missing: [for (final x in _l(m['missing'])) _s(x)],
      blocking: _i(m['blocking']),
      calculatedAt: _t(m['calculatedAt']),
    );
  }

  String text(String key, {String fallback = '—'}) {
    final v = fields[key];
    if (v == null || v.text.isEmpty) return fallback;
    return v.text;
  }

  FundingFunderResult? funder(String rowId) {
    for (final f in funders) {
      if (f.rowId == rowId) return f;
    }
    return null;
  }
}

class FundingEvent {
  const FundingEvent({
    required this.id,
    required this.round,
    required this.node,
    required this.nodeLabel,
    required this.action,
    required this.actorId,
    required this.actorName,
    required this.comment,
    this.createdAt,
  });

  final int id;
  final int round;
  final String node;
  final String nodeLabel;
  final String action;
  final int actorId;
  final String actorName;
  final String comment;
  final DateTime? createdAt;

  String get actionLabel => switch (action) {
    'submit' => '提交',
    'approve' => '同意',
    'reject' => '驳回',
    'withdraw' => '撤回',
    _ => action,
  };

  factory FundingEvent.fromJson(Object? raw) {
    final m = _m(raw);
    return FundingEvent(
      id: _i(m['id']),
      round: _i(m['round']),
      node: _s(m['node']),
      nodeLabel: _s(m['nodeLabel']),
      action: _s(m['action']),
      actorId: _i(m['actorId']),
      actorName: _s(m['actorName']),
      comment: _s(m['comment']),
      createdAt: _t(m['createdAt']),
    );
  }
}

class FundingPermissions {
  const FundingPermissions({
    this.canEdit = false,
    this.canSubmit = false,
    this.canWithdraw = false,
    this.canDecide = false,
    this.canDelete = false,
    this.canEditMaterials = false,
  });

  final bool canEdit;
  final bool canSubmit;
  final bool canWithdraw;
  final bool canDecide;
  final bool canDelete;
  final bool canEditMaterials;

  factory FundingPermissions.fromJson(Object? raw) {
    final m = _m(raw);
    return FundingPermissions(
      canEdit: m['canEdit'] == true,
      canSubmit: m['canSubmit'] == true,
      canWithdraw: m['canWithdraw'] == true,
      canDecide: m['canDecide'] == true,
      canDelete: m['canDelete'] == true,
      canEditMaterials: m['canEditMaterials'] == true,
    );
  }
}

class FundingProposal {
  const FundingProposal({
    required this.id,
    required this.code,
    required this.title,
    required this.status,
    required this.currentNode,
    required this.currentNodeLabel,
    required this.currentApproverName,
    required this.round,
    required this.form,
    required this.estimate,
    required this.createdBy,
    required this.createdByName,
    required this.version,
    required this.events,
    required this.permissions,
    this.submittedAt,
    this.finishedAt,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String code;
  final String title;
  final String status;
  final String currentNode;
  final String currentNodeLabel;
  final String currentApproverName;
  final int round;
  final Map<String, dynamic> form;
  final FundingEstimate estimate;
  final int createdBy;
  final String createdByName;
  final int version;
  final List<FundingEvent> events;
  final FundingPermissions permissions;
  final DateTime? submittedAt;
  final DateTime? finishedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory FundingProposal.fromJson(Map<String, dynamic> json) {
    final approver = _m(json['currentApprover']);
    return FundingProposal(
      id: _i(json['id']),
      code: _s(json['code']),
      title: _s(json['title']),
      status: _s(json['status']),
      currentNode: _s(json['currentNode']),
      currentNodeLabel: _s(json['currentNodeLabel']),
      currentApproverName: _s(approver['name']),
      round: _i(json['round']),
      form: _m(json['form']),
      estimate: FundingEstimate.fromJson(json['estimate']),
      createdBy: _i(json['createdBy']),
      createdByName: _s(json['createdByName']),
      version: _i(json['version']),
      events: [for (final e in _l(json['events'])) FundingEvent.fromJson(e)],
      permissions: FundingPermissions.fromJson(json['permissions']),
      submittedAt: _t(json['submittedAt']),
      finishedAt: _t(json['finishedAt']),
      createdAt: _t(json['createdAt']),
      updatedAt: _t(json['updatedAt']),
    );
  }
}

class FundingListResult {
  const FundingListResult({
    this.items = const [],
    this.total = 0,
    this.todoCount = 0,
  });

  final List<FundingProposal> items;
  final int total;
  final int todoCount;

  factory FundingListResult.fromJson(Map<String, dynamic> json) =>
      FundingListResult(
        items: [
          for (final item in _l(json['items']))
            FundingProposal.fromJson(_m(item)),
        ],
        total: _i(json['total']),
        todoCount: _i(json['todoCount']),
      );
}
