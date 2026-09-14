import 'xflow_models.dart';
import 'xflow_upload_field.dart';

const kTaskTodoUploadFieldKeys = {
  'paymentVoucher',
  'returnedInvoice',
  'receiptVoucher',
};

const kTaskTodoCompletionLabels = <String, String>{
  'actualPayAmount': '实付金额',
  'repayAmount': '还款金额',
  'paymentVoucher': '支付凭证',
  'returnedInvoice': '回传发票',
  'receiptVoucher': '回款凭证',
  'verifyResult': '核验结果',
  'fileDestination': '文件去向',
  'expressTrackingNo': '快递单号',
  'expressSentAt': '寄出时间',
  'signedAt': '签收时间',
  'invoiceFiles': '发票文件',
  'paymentVoucherFiles': '支付凭证',
};

bool taskTodoValueLooksLikeUpload(Object? value) {
  if (value is! List || value.isEmpty) return false;
  var hits = 0;
  for (final item in value) {
    if (item is! Map) continue;
    final map = item.map((key, val) => MapEntry('$key', val));
    if ('${map['objectKey'] ?? ''}'.trim().isNotEmpty ||
        '${map['url'] ?? ''}'.trim().isNotEmpty ||
        '${map['fileName'] ?? map['name'] ?? ''}'.trim().isNotEmpty) {
      hits++;
    }
  }
  return hits > 0 && hits == value.length;
}

bool taskTodoFieldIsUpload(
  String key, {
  Object? value,
  List<XflowTodoFieldDef> defs = const [],
}) {
  for (final def in defs) {
    if (def.key == key && def.isUpload) return true;
  }
  if (taskTodoValueLooksLikeUpload(value)) return true;
  if (!kTaskTodoUploadFieldKeys.contains(key)) return false;
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty;
  if (value is List) return true;
  return false;
}

String taskTodoFieldLabel(
  String key, {
  List<XflowTodoFieldDef> defs = const [],
}) {
  for (final def in defs) {
    if (def.key == key && def.label.trim().isNotEmpty) return def.label.trim();
  }
  return kTaskTodoCompletionLabels[key] ?? key;
}

List<(String, String)> taskTodoCompletionTexts(
  Map<String, dynamic> form, {
  List<XflowTodoFieldDef> defs = const [],
}) {
  final out = <(String, String)>[];
  for (final entry in kTaskTodoCompletionLabels.entries) {
    if (taskTodoFieldIsUpload(entry.key, value: form[entry.key], defs: defs)) {
      continue;
    }
    final raw = form[entry.key];
    if (raw is List || raw is Map) continue;
    final text = '${raw ?? ''}'.trim();
    if (text.isEmpty) continue;
    out.add((entry.value, text));
  }
  return out;
}

List<Map<String, dynamic>> _usableUploadItems(Object? raw) {
  return normalizeUploadItems(raw).where((item) {
    final key = '${item['objectKey'] ?? item['url'] ?? item['fileName'] ?? ''}'
        .trim();
    return key.isNotEmpty && item['status'] != 'error';
  }).toList(growable: false);
}

List<(String, List<Map<String, dynamic>>)> taskTodoCompletionFileGroups(
  Map<String, dynamic> form, {
  List<XflowTodoFieldDef> defs = const [],
}) {
  const order = [
    'paymentVoucher',
    'returnedInvoice',
    'receiptVoucher',
    'invoiceFiles',
    'paymentVoucherFiles',
    'files',
  ];
  final seen = <String>{};
  final out = <(String, List<Map<String, dynamic>>)>[];
  void add(String key, String label) {
    if (seen.contains(key)) return;
    final files = _usableUploadItems(form[key]);
    if (files.isEmpty) return;
    seen.add(key);
    out.add((label, files));
  }

  for (final def in defs) {
    if (!def.isUpload) continue;
    add(def.key, taskTodoFieldLabel(def.key, defs: defs));
  }
  for (final key in order) {
    if (!taskTodoFieldIsUpload(key, value: form[key], defs: defs) &&
        key != 'invoiceFiles' &&
        key != 'files' &&
        key != 'paymentVoucherFiles') {
      continue;
    }
    add(key, taskTodoFieldLabel(key, defs: defs));
  }
  for (final entry in form.entries) {
    if (taskTodoValueLooksLikeUpload(entry.value)) {
      add(entry.key, taskTodoFieldLabel(entry.key, defs: defs));
    }
  }
  return out;
}

List<Map<String, dynamic>> taskTodoCompletionFiles(Map<String, dynamic> form) {
  return [
    for (final group in taskTodoCompletionFileGroups(form)) ...group.$2,
  ];
}
