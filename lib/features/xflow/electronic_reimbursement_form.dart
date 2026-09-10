import 'xflow_models.dart';

const kElectronicReimbursementTemplateKey = 'electronic-reimbursement';
const kApprovedMineDataSource = 'approved_my_submission';

const _approvedStatuses = {'APPROVED', 'LIVE', 'DONE', 'COMPLETED'};

const _overlayKeys = {
  'applicant',
  'applicantPosition',
  'applicantRank',
  'applicantDepartment',
  'entertainmentApprovalNo',
  'advanceApplicationNo',
  'advanceNo',
  'advanceReason',
  'remainingAdvanceAmount',
};

const _attachmentTemplateMeta = <String, String>{
  'templateUrl':
      '/api/v1/xflow/templates/electronic-reimbursement/expense-template',
  'templateName': '差旅报销费用模板202609.xlsx',
  'templateLabel': '下载报销费用模板',
};

const _fieldOverlays = <String, Map<String, dynamic>>{
  'applicant': {
    'readonly': true,
    'defaultFrom': 'current_user',
    'placeholder': '提交人（自动带出）',
  },
  'applicantPosition': {'readonly': true, 'placeholder': '根据提交人自动带出'},
  'applicantRank': {'readonly': true, 'placeholder': '根据提交人自动带出'},
  'applicantDepartment': {
    'key': 'applicantDepartment',
    'label': '部门',
    'type': 'text',
    'readonly': true,
    'placeholder': '根据提交人自动带出',
  },
  'entertainmentApprovalNo': {
    'type': 'proposal',
    'dataSource': kApprovedMineDataSource,
    'placeholder': '选择自己已通过的招待费提案',
    'meta': {
      'titleContains': '招待费',
      'templateKey':
          'entertainment,entertainment-expense,entertainment-approval,entertainment-request',
      'businessType':
          'ENTERTAINMENT,ENTERTAINMENT_EXPENSE,ENTERTAINMENT_APPROVAL',
    },
  },
  'advanceApplicationNo': {
    'type': 'proposal',
    'dataSource': kApprovedMineDataSource,
    'placeholder': '选择自己已通过的借款申请单',
    'meta': {
      'titleContains': '借款',
      'templateKey': 'loan-request,loan-application,advance-request',
      'businessType': 'LOAN_REQUEST,LOAN_APPLICATION,ADVANCE',
    },
    'fill': {
      'advanceNo': 'advanceNo',
      'advanceReason': 'advanceReason',
      'remainingAdvanceAmount': 'remainingAdvanceAmount',
    },
    'remoteSearch': {
      'path': '/xflow/submissions/mine',
      'labelFields': ['code', 'title'],
      'valueFields': ['code'],
      'allowManual': false,
      'fill': {
        'advanceNo': 'advanceNo',
        'advanceReason': 'advanceReason',
        'remainingAdvanceAmount': 'remainingAdvanceAmount',
      },
    },
  },
  'advanceNo': {'readonly': true, 'placeholder': '选择借款申请单后自动带出'},
  'advanceReason': {'readonly': true, 'placeholder': '选择借款申请单后自动带出'},
  'remainingAdvanceAmount': {'readonly': true, 'placeholder': '选择借款申请单后自动带出'},
};

XflowTemplateDetail applyElectronicReimbursementTemplate(
  XflowTemplateDetail template,
) {
  var layout = template.layout;
  if (template.templateKey == kElectronicReimbursementTemplateKey) {
    layout = Map<String, dynamic>.from(layout)..remove('progress');
  }
  return XflowTemplateDetail(
    templateKey: template.templateKey,
    title: template.title,
    fields: applyElectronicReimbursementFieldRules(
      template.templateKey,
      template.fields,
    ),
    stages: template.stages,
    layout: layout,
    raw: template.raw,
  );
}

List<XflowField> applyElectronicReimbursementFieldRules(
  String templateKey,
  List<XflowField> fields,
) {
  if (templateKey != kElectronicReimbursementTemplateKey) return fields;
  final hasDepartment = fields.any((field) => field.key == 'applicantDepartment');
  return [
    for (final field in fields)
      if (field.key == 'applicantRank' && !hasDepartment)
        XflowField.fromJson({
          ...field.raw,
          ...?_fieldOverlays['applicantDepartment'],
        })
      else if (field.key == 'supportingAttachments')
        _withAttachmentTemplateMeta(field)
      else if (_overlayKeys.contains(field.key))
        XflowField.fromJson({...field.raw, ...?_fieldOverlays[field.key]})
      else
        field,
  ];
}

XflowField _withAttachmentTemplateMeta(XflowField field) {
  final meta = <String, dynamic>{..._attachmentTemplateMeta};
  final existing = field.raw['meta'];
  if (existing is Map) {
    existing.forEach((key, value) {
      final text = '$value'.trim();
      if (text.isNotEmpty) meta['$key'] = text;
    });
  }
  return XflowField.fromJson({...field.raw, 'meta': meta});
}

bool isApprovedMineStatus(String status) =>
    _approvedStatuses.contains(status.trim().toUpperCase());

List<String> splitMetaList(dynamic value) {
  if (value == null) return const [];
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return const [];
  return text
      .split(RegExp('[,，;；|]'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
}

bool matchesApprovedMineFilter(
  Map<String, dynamic> item,
  Map<String, dynamic>? meta,
) {
  if (meta == null || meta.isEmpty) return true;
  final tokens = <String>[
    ...splitMetaList(meta['match']),
    ...splitMetaList(meta['titleContains']),
    ...splitMetaList(meta['templateKey']),
    ...splitMetaList(meta['businessType']),
  ];
  if (tokens.isEmpty) return true;
  final hay =
      [
            item['title'],
            item['name'],
            item['code'],
            item['templateKey'],
            item['businessType'],
            item['documentKind'],
            item['proposalType'],
          ]
          .map((value) => '$value'.trim().toLowerCase())
          .where((value) => value.isNotEmpty && value != 'null')
          .join(' ');
  return tokens.any((token) => hay.contains(token.toLowerCase()));
}

bool matchesApprovedMineQuery(Map<String, dynamic> item, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return [
    item['code'],
    item['title'],
    item['name'],
    item['templateKey'],
  ].map((value) => '$value'.toLowerCase()).any((value) => value.contains(q));
}

const _fillAliases = <String, List<String>>{
  'advanceNo': ['advanceNo', 'loanNo', 'loanCode', 'code'],
  'advanceReason': [
    'advanceReason',
    'loanReason',
    'reason',
    'purpose',
    'borrowReason',
  ],
  'remainingAdvanceAmount': [
    'remainingAdvanceAmount',
    'remainingAmount',
    'remainAmount',
    'balance',
    'unpaidAmount',
  ],
};

Map<String, dynamic> flattenApprovedDocSource(
  Map<String, dynamic> item, [
  Map<String, dynamic>? formData,
]) {
  return {
    ...?formData,
    ...item,
    'code': item['code'] ?? formData?['code'],
    'title': item['title'] ?? item['name'] ?? formData?['title'],
  };
}

Map<String, dynamic> fillFromApprovedDoc(
  Map<String, String> fill,
  Map<String, dynamic> source,
) {
  if (fill.isEmpty) return const {};
  final patch = <String, dynamic>{};
  fill.forEach((formKey, respKey) {
    final aliases = _fillAliases[formKey] ?? [respKey, formKey];
    for (final key in aliases) {
      final value = source[key];
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      patch[formKey] = value is String ? value.trim() : value;
      break;
    }
  });
  return patch;
}

String orgPositionText(Map<String, dynamic>? user) {
  if (user == null) return '';
  return '${user['positionName'] ?? user['title'] ?? user['jobTitle'] ?? ''}'
      .trim();
}

String orgRankText(Map<String, dynamic>? user) {
  if (user == null) return '';
  return '${user['rankName'] ?? user['rankTitle'] ?? user['jobLevel'] ?? ''}'
      .trim();
}

String orgDepartmentText(Map<String, dynamic>? user) {
  if (user == null) return '';
  return '${user['departmentName'] ?? user['department'] ?? user['deptName'] ?? user['dept'] ?? ''}'
      .trim();
}

void applySubmitterDefaults({
  required List<XflowField> fields,
  required Map<String, dynamic> values,
  required int userId,
  required String displayName,
  Map<String, dynamic>? profile,
}) {
  if (userId <= 0) return;
  for (final field in fields) {
    final defaultFrom = '${field.raw['defaultFrom'] ?? ''}';
    final dataSource = '${field.raw['dataSource'] ?? ''}';
    final isUser = field.type == 'user' || field.type == 'userSelect';
    if (!isUser) continue;
    if (defaultFrom != 'current_user' && dataSource != 'current_user') continue;
    if (!field.readonly && _isFilled(values[field.key])) continue;
    values[field.key] = {'userId': userId, 'name': displayName};
  }
  final position = orgPositionText(profile);
  final rank = orgRankText(profile);
  final department = orgDepartmentText(profile);
  if (_hasKey(fields, 'applicantPosition') &&
      (_locked(fields, 'applicantPosition') ||
          !_isFilled(values['applicantPosition'])) &&
      position.isNotEmpty) {
    values['applicantPosition'] = position;
  }
  if (_hasKey(fields, 'applicantRank') &&
      (_locked(fields, 'applicantRank') ||
          !_isFilled(values['applicantRank'])) &&
      rank.isNotEmpty) {
    values['applicantRank'] = rank;
  }
  if (_hasKey(fields, 'applicantDepartment') &&
      (_locked(fields, 'applicantDepartment') ||
          !_isFilled(values['applicantDepartment'])) &&
      department.isNotEmpty) {
    values['applicantDepartment'] = department;
  }
}

bool _hasKey(List<XflowField> fields, String key) =>
    fields.any((field) => field.key == key);

bool _locked(List<XflowField> fields, String key) =>
    fields.any((field) => field.key == key && field.readonly);

bool _isFilled(dynamic value) {
  if (value == null) return false;
  if (value is Map) {
    return value['userId'] != null ||
        value['proposalId'] != null ||
        value['id'] != null ||
        '${value['name'] ?? ''}'.trim().isNotEmpty;
  }
  if (value is List) return value.isNotEmpty;
  return '$value'.trim().isNotEmpty;
}
