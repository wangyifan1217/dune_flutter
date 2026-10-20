import 'xflow_models.dart';

/// 从已提交表单里抽出列表上能辨认单据的几行：双方主体、事项、金额。
///
/// 模板字段有中文标签时按标签认；没有标签时按常见字段名认。
/// 附件、账号、联系人这类看不出「这是哪一笔」的内容不放进来。
List<ApprovalListHighlight> buildApprovalListHighlights({
  required Map<String, dynamic> form,
  List<XflowField> fields = const [],
  String title = '',
}) {
  final buckets = _HighlightBuckets(title: title);
  final seen = <String>{};
  for (final field in fields) {
    if (field.key.isEmpty) continue;
    _takeField(field, form[field.key], buckets, seen);
  }
  for (final entry in form.entries) {
    if (seen.contains(entry.key)) continue;
    if (_looksLikeFile(entry.value)) continue;
    final value = entry.value;
    if (value is Map && !_isEntityMap(value)) {
      seen.add(entry.key);
      for (final child in value.entries) {
        _takeLoose(child.key.toString(), child.value, buckets, seen);
      }
      continue;
    }
    _takeLoose(entry.key, value, buckets, seen);
  }
  return buckets.toLines();
}

/// 同一业务单的摘要跨列表进出复用，避免返回列表后重新逐条拉表单。
class ApprovalListDigestStore {
  ApprovalListDigestStore._();

  static final Map<String, List<ApprovalListHighlight>> _lines = {};
  static final Map<String, List<XflowField>> _fields = {};

  static String keyOf(XflowProposalItem item) =>
      '${item.businessType}:${item.id}';

  static bool has(XflowProposalItem item) => _lines.containsKey(keyOf(item));

  static List<ApprovalListHighlight>? peek(XflowProposalItem item) =>
      _lines[keyOf(item)];

  static void put(XflowProposalItem item, List<ApprovalListHighlight> lines) {
    _lines[keyOf(item)] = List<ApprovalListHighlight>.unmodifiable(lines);
  }

  static bool hasFields(String templateKey) =>
      _fields.containsKey(templateKey.trim());

  static List<XflowField> fieldsOf(String? templateKey) =>
      _fields[templateKey?.trim() ?? ''] ?? const [];

  static void putFields(String templateKey, List<XflowField> fields) {
    final key = templateKey.trim();
    if (key.isEmpty) return;
    _fields[key] = List<XflowField>.unmodifiable(fields);
  }
}

const _skipTypes = {
  'section',
  'action',
  'computed',
  'row',
  'upload',
  'file',
  'image',
  'attachment',
  'divider',
  'hint',
  'description',
};

const _matterKeys = {
  'expensepurpose',
  'purpose',
  'reason',
  'applyreason',
  'applicationreason',
  'matter',
  'subject',
  'expenseuse',
  'useoffunds',
  'applyitem',
  'paymentcontent',
};

const _amountKeys = {
  'amount',
  'paymentamount',
  'applyamount',
  'appliedamount',
  'requestamount',
  'totalamount',
  'payamount',
  'invoiceamount',
};

void _takeField(
  XflowField field,
  dynamic value,
  _HighlightBuckets buckets,
  Set<String> seen,
) {
  seen.add(field.key);
  final type = field.type.trim().toLowerCase();
  if (_skipTypes.contains(type)) return;
  if (type == 'dynamiclist' || type == 'table') {
    _takeTable(field, value, buckets);
    return;
  }
  if (_looksLikeFile(value)) return;
  final label = field.label.trim().isEmpty ? field.key : field.label.trim();
  _classify(label, field.key, value, buckets);
}

void _takeLoose(
  String key,
  dynamic value,
  _HighlightBuckets buckets,
  Set<String> seen,
) {
  if (key.isEmpty || seen.contains(key) || _looksLikeFile(value)) return;
  seen.add(key);
  if (value is List && value.isNotEmpty && value.first is Map) {
    for (final row in value.take(3)) {
      if (row is! Map) continue;
      for (final child in row.entries) {
        _classify(child.key.toString(), child.key.toString(), child.value, buckets);
      }
    }
    return;
  }
  _classify(key, key, value, buckets);
}

void _takeTable(
  XflowField field,
  dynamic value,
  _HighlightBuckets buckets,
) {
  if (value is! List) return;
  final columns = field.columnsAsFields;
  for (final row in value.take(3)) {
    if (row is! Map) continue;
    if (columns.isEmpty) {
      for (final child in row.entries) {
        _classify(child.key.toString(), child.key.toString(), child.value, buckets);
      }
      continue;
    }
    for (final column in columns) {
      _classify(
        column.label.trim().isEmpty ? column.key : column.label.trim(),
        column.key,
        row[column.key],
        buckets,
      );
    }
  }
}

void _classify(
  String label,
  String key,
  dynamic value,
  _HighlightBuckets buckets,
) {
  if (_skipPartyNoise(label) || _skipPartyNoise(key)) return;
  final text = approvalListDisplayText(value);
  if (text.isEmpty) return;
  if (_isAmountLabel(label) || _isAmountKey(key)) {
    buckets.addAmount(text);
    return;
  }
  if (!_isUsefulText(text)) return;
  if (_isPartyLabel(label) || _isPartyKey(key)) {
    buckets.addParty(_shortPartyLabel(label), text);
    return;
  }
  if (_isMatterLabel(label) || _isMatterKey(key)) {
    buckets.addMatter(_shortMatterLabel(label), text);
  }
}

class _HighlightBuckets {
  _HighlightBuckets({required this.title});

  final String title;
  final List<({String label, String value})> parties = [];
  String? matterLabel;
  String? matterValue;
  String? amount;

  void addParty(String label, String value) {
    if (parties.length >= 3) return;
    if (parties.any((row) => row.value == value)) return;
    if (value == title.trim()) return;
    parties.add((label: label, value: value));
  }

  void addMatter(String label, String value) {
    if (matterValue != null) return;
    if (value == title.trim()) return;
    matterLabel = label;
    matterValue = value;
  }

  void addAmount(String value) {
    amount ??= _money(value);
  }

  List<ApprovalListHighlight> toLines() {
    final lines = <ApprovalListHighlight>[];
    if (parties.isNotEmpty) {
      final label = parties.length >= 2 ? '双方主体' : parties.first.label;
      lines.add(
        ApprovalListHighlight(
          label: label,
          value: parties.map((row) => row.value).join(' · '),
        ),
      );
    }
    final matter = matterValue;
    if (matter != null && matter.isNotEmpty) {
      lines.add(
        ApprovalListHighlight(label: matterLabel ?? '事项', value: matter),
      );
    }
    final money = amount;
    if (money != null && money.isNotEmpty) {
      lines.add(ApprovalListHighlight(label: '金额', value: money));
    }
    return lines;
  }
}

String approvalListDisplayText(dynamic value) {
  if (value == null) return '';
  if (value is num) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
  if (value is String) {
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.startsWith('{') || text.startsWith('[')) return '';
    if (text.length > 80) return '${text.substring(0, 80)}…';
    return text;
  }
  if (value is Map) {
    for (final key in const [
      'label',
      'name',
      'displayName',
      'companyName',
      'ourEntityName',
      'payeeName',
      'payer',
      'payee',
      'title',
    ]) {
      final text = approvalListDisplayText(value[key]);
      if (text.isNotEmpty) return text;
    }
    return '';
  }
  if (value is List) {
    final parts = value
        .map(approvalListDisplayText)
        .where((text) => text.isNotEmpty)
        .take(3)
        .toList(growable: false);
    return parts.join('、');
  }
  return '';
}

bool _isEntityMap(Map value) {
  const keys = [
    'label',
    'name',
    'displayName',
    'companyName',
    'ourEntityName',
    'payeeName',
  ];
  return value.length <= 8 && keys.any(value.containsKey);
}

bool _looksLikeFile(dynamic value) {
  if (value is Map) {
    return value.containsKey('objectKey') ||
        value.containsKey('fileName') ||
        value.containsKey('object_key');
  }
  if (value is List && value.isNotEmpty) return _looksLikeFile(value.first);
  return false;
}

bool _isUsefulText(String text) {
  if (text.isEmpty) return false;
  if (RegExp(r'^\d+$').hasMatch(text)) return false;
  return true;
}

bool _skipPartyNoise(String label) {
  return RegExp(r'联系人|电话|手机|邮箱|账号|账户|开户|银行|大写').hasMatch(label);
}

bool _isPartyLabel(String label) {
  return RegExp(
    r'主体|甲方|乙方|我方|对方|付款方|收款方|收款单位|付款单位|供应商|推广商|客户',
  ).hasMatch(label);
}

bool _isMatterLabel(String label) {
  return RegExp(r'事项|事由|用途|付款内容').hasMatch(label);
}

bool _isAmountLabel(String label) => label.contains('金额');

String _normKey(String key) =>
    key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

bool _isPartyKey(String key) {
  final norm = _normKey(key);
  return _ourPartyKeys.contains(norm) || _theirPartyKeys.contains(norm);
}

bool _isMatterKey(String key) {
  final norm = _normKey(key);
  if (_matterKeys.contains(norm)) return true;
  return key.contains('事由') || key.contains('事项') || key.contains('用途');
}

bool _isAmountKey(String key) => _amountKeys.contains(_normKey(key));

const _ourPartyKeys = {
  'ourparty',
  'ourentity',
  'ourentityname',
  'payingentity',
  'paysubject',
  'payer',
  'payername',
  'partya',
  'salesourparty',
  'purchaseourparty',
};

const _theirPartyKeys = {
  'counterparty',
  'counterpartyname',
  'payee',
  'payeename',
  'partyb',
  'vendor',
  'vendorname',
  'customer',
  'customername',
  'clientname',
  'promoter',
  'promotername',
  'supplier',
  'suppliername',
};

String _shortPartyLabel(String label) {
  final key = _normKey(label);
  if (_ourPartyKeys.contains(key) ||
      label.contains('我方') ||
      label.contains('付款') ||
      label.contains('甲方')) {
    return '我方主体';
  }
  if (_theirPartyKeys.contains(key) ||
      label.contains('对方') ||
      label.contains('收款') ||
      label.contains('乙方') ||
      label.contains('客户') ||
      label.contains('供应商') ||
      label.contains('推广')) {
    return '对方主体';
  }
  return '主体';
}

String _shortMatterLabel(String label) {
  if (label.contains('事由')) return '事由';
  if (label.contains('用途')) return '用途';
  return '事项';
}

String? _money(String raw) {
  final cleaned = raw.replaceAll(',', '').replaceAll('￥', '').replaceAll('¥', '').trim();
  final number = num.tryParse(cleaned);
  if (number == null) {
    if (raw.contains('¥') || raw.contains('￥') || raw.contains('元')) return raw;
    return null;
  }
  if (number == 0) return null;
  final digits = number == number.roundToDouble()
      ? _group(number.toInt())
      : number.toString();
  return '¥$digits';
}

String _group(int number) {
  final negative = number < 0;
  final text = number.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}
