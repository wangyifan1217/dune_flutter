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
  'offsetAmount',
};

/// 费用类型下拉，和报销明细汇总表的列一致。
const kReimbursementExpenseTypes = [
  '招待费',
  '差旅住宿',
  '差旅路费',
  '市内交通',
  '差旅打车',
  '团建',
  '入职体检',
  '办公费',
  '福利',
  '测试费',
  '公司车辆',
];

final _expenseTypeOptions = [
  for (final name in kReimbursementExpenseTypes)
    {'label': name, 'value': name},
];

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
      'entityField': 'applicantEntity',
    },
      'fill': {
        'advanceNo': 'advanceNo',
        'advanceReason': 'advanceReason',
        'remainingAdvanceAmount': 'remainingAdvanceAmount',
        'advanceEntity': 'advanceEntity',
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
          'advanceEntity': 'advanceEntity',
        },
      },
    },
  'advanceNo': {'readonly': true, 'placeholder': '选择借款申请单后自动带出'},
  'advanceReason': {'readonly': true, 'placeholder': '选择借款申请单后自动带出'},
  'remainingAdvanceAmount': {'readonly': true, 'placeholder': '选择借款申请单后自动带出'},
  'offsetAmount': {
    'readonly': true,
    'placeholder': '按同一主体自动冲减，不超过本次报销金额',
  },
};

const _settlementFields = <Map<String, dynamic>>[
  {
    'key': 'pendingOffsetAmount',
    'label': '待冲抵借支金额',
    'type': 'money',
    'readonly': true,
    'visibleWhen': 'hasAdvance=是',
    'placeholder': '同一主体的待冲借支',
  },
  {
    'key': 'paymentAmount',
    'label': '本次打款金额',
    'type': 'money',
    'readonly': true,
    'placeholder': '报销金额 − 待冲抵借支金额',
  },
];

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
  final mapped = [
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
        _withExpenseTypeSelect(_withInvoiceOcrUploads(field)),
  ];
  return _withSettlementFields(mapped);
}

List<XflowField> _withSettlementFields(List<XflowField> fields) {
  final keys = {for (final field in fields) field.key};
  if (!keys.contains('reimbursementAmount')) return fields;
  if (keys.contains('paymentAmount') && keys.contains('pendingOffsetAmount')) {
    return fields;
  }
  final extra = [
    for (final raw in _settlementFields)
      if (!keys.contains(raw['key'])) XflowField.fromJson(raw),
  ];
  if (extra.isEmpty) return fields;
  final out = <XflowField>[];
  var inserted = false;
  for (final field in fields) {
    out.add(field);
    if (!inserted &&
        (field.key == 'offsetAmount' || field.key == 'remainingAdvanceAmount')) {
      out.addAll(extra);
      inserted = true;
    }
  }
  if (!inserted) out.addAll(extra);
  return out;
}

/// 报销项目里的费用类型固定为单选下拉，不改其他列。
XflowField _withExpenseTypeSelect(XflowField field) {
  if (field.key != 'expenseItems') return field;
  final raw = Map<String, dynamic>.from(field.raw);
  final columns = raw['columns'];
  if (columns is! List) return field;
  final next = <dynamic>[];
  var changed = false;
  for (final col in columns) {
    if (col is! Map) {
      next.add(col);
      continue;
    }
    final map = Map<String, dynamic>.from(col);
    if ('${map['key'] ?? ''}' == 'expenseType') {
      map['type'] = 'select';
      map['options'] = _expenseTypeOptions;
      map['placeholder'] = '请选择费用类型';
      changed = true;
    }
    next.add(map);
  }
  if (!changed) return field;
  raw['columns'] = next;
  return XflowField.fromJson(raw);
}

/// 电子报销「关联发票」固定走识别。模板设计器里的开关写在列的 meta 上，
/// 旧模板或未重新进单时 App 拿不到这个标记，上传后就只显示文件名。
XflowField _withInvoiceOcrUploads(XflowField field) {
  final raw = Map<String, dynamic>.from(field.raw);
  var changed = _stampInvoiceOcr(raw);
  final columns = raw['columns'];
  if (columns is List) {
    final next = <dynamic>[];
    for (final col in columns) {
      if (col is! Map) {
        next.add(col);
        continue;
      }
      final map = Map<String, dynamic>.from(col);
      if (_stampInvoiceOcr(map)) changed = true;
      next.add(map);
    }
    raw['columns'] = next;
  }
  if (!changed) return field;
  return XflowField.fromJson(raw);
}

bool _stampInvoiceOcr(Map<String, dynamic> field) {
  final key = '${field['key'] ?? ''}';
  final type = '${field['type'] ?? ''}'.trim().toLowerCase();
  final label = '${field['label'] ?? ''}';
  final invoiceUpload =
      type == 'upload' &&
      (key == 'invoiceAttachments' || label.contains('关联发票'));
  if (!invoiceUpload) return false;
  final meta = field['meta'] is Map
      ? Map<String, dynamic>.from(field['meta'] as Map)
      : <String, dynamic>{};
  if (meta['invoiceOcr'] == true ||
      '${meta['invoiceOcr']}'.toLowerCase() == 'true') {
    field['meta'] = meta;
    return false;
  }
  meta['invoiceOcr'] = true;
  field['meta'] = meta;
  return true;
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
  'advanceEntity': [
    'advanceEntity',
    'applicantEntity',
    'paySubject',
    'payEntity',
    'borrowSubject',
    'companyEntity',
    'entity',
    'loanEntity',
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

/// 借支单上的打款/借款主体。哪个主体打款，就只冲这个主体的借支。
String advanceEntityText(Map<String, dynamic> source) {
  for (final key in _fillAliases['advanceEntity'] ?? const <String>[]) {
    final value = source[key];
    if (value == null) continue;
    final text = value is String ? value.trim() : '$value'.trim();
    if (text.isEmpty || text == 'null') continue;
    if (value is Map) {
      final named = '${value['name'] ?? value['label'] ?? value['title'] ?? ''}'
          .trim();
      if (named.isNotEmpty) return named;
    }
    return text;
  }
  return '';
}

double _settlementMoney(dynamic value) {
  if (value is num) return value.toDouble();
  final text = '$value'.replaceAll(',', '').replaceAll('¥', '').trim();
  return double.tryParse(text) ?? 0;
}

String _settlementText(dynamic value) {
  if (value is Map) {
    return '${value['name'] ?? value['label'] ?? value['title'] ?? value['value'] ?? ''}'
        .trim();
  }
  return '$value'.trim();
}

/// 本次打款金额 = 本次报销金额 − 同一主体的待冲抵借支。主体不一致时不冲减。
void applyElectronicReimbursementSettlement(Map<String, dynamic> values) {
  final amount = _settlementMoney(values['reimbursementAmount']);
  final entity = _settlementText(values['applicantEntity']);
  final advanceEntity = _settlementText(values['advanceEntity']);
  final hasAdvance = _settlementText(values['hasAdvance']) == '是';
  final mismatch = hasAdvance &&
      entity.isNotEmpty &&
      advanceEntity.isNotEmpty &&
      entity != advanceEntity;
  if (mismatch) {
    values['advanceApplicationNo'] = null;
    values['advanceNo'] = '';
    values['advanceReason'] = '';
    values['remainingAdvanceAmount'] = '';
    values['advanceEntity'] = '';
  }
  final pending = hasAdvance && !mismatch
      ? _settlementMoney(values['remainingAdvanceAmount'])
      : 0.0;
  final offset = pending <= 0
      ? 0.0
      : (pending < amount ? pending : amount);
  if (!hasAdvance || mismatch) {
    values['pendingOffsetAmount'] = '';
    values['offsetAmount'] = '';
  } else {
    values['pendingOffsetAmount'] = offset.toStringAsFixed(2);
    values['offsetAmount'] = offset.toStringAsFixed(2);
  }
  if ('${values['reimbursementAmount'] ?? ''}'.trim().isEmpty) {
    values['paymentAmount'] = '';
    return;
  }
  final pay = amount - offset;
  values['paymentAmount'] = (pay < 0 ? 0 : pay).toStringAsFixed(2);
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
