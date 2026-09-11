enum PaymentInvoiceKind { payment, invoice, other }

enum InvoiceIssueStatus { unissued, partial, completed }

class PaymentInvoiceRow {
  const PaymentInvoiceRow({
    required this.id,
    required this.businessType,
    required this.code,
    required this.title,
    required this.status,
    required this.kind,
    this.templateKey = '',
    this.createdByName = '',
    this.createdAt,
    this.purpose = '',
    this.payeeAccount = '',
    this.payAccountType = '',
    this.counterparty = '',
    this.appliedAmount,
    this.issuedAmount = 0,
    this.issueStatus = InvoiceIssueStatus.unissued,
    this.paymentCompleted = false,
    this.formValues = const {},
    this.subStatus = '',
  });

  final int id;
  final String businessType;
  final String code;
  final String title;
  final String status;
  final PaymentInvoiceKind kind;
  final String templateKey;
  final String createdByName;
  final DateTime? createdAt;
  final String purpose;
  final String payeeAccount;
  final String payAccountType;
  final String counterparty;
  final num? appliedAmount;
  final num issuedAmount;
  final InvoiceIssueStatus issueStatus;
  final bool paymentCompleted;
  final Map<String, dynamic> formValues;
  final String subStatus;

  num get unissuedAmount {
    final applied = appliedAmount;
    if (applied == null) return 0;
    final left = applied - issuedAmount;
    return left < 0 ? 0 : left;
  }

  bool get invoiceOpen => issueStatus != InvoiceIssueStatus.completed;

  String get displayId => code.trim().isNotEmpty ? code.trim() : (id > 0 ? '#$id' : '—');

  PaymentInvoiceRow copyWith({
    String? purpose,
    String? payeeAccount,
    String? payAccountType,
    String? counterparty,
    num? appliedAmount,
    num? issuedAmount,
    InvoiceIssueStatus? issueStatus,
    bool? paymentCompleted,
    Map<String, dynamic>? formValues,
    String? subStatus,
    String? status,
  }) {
    return PaymentInvoiceRow(
      id: id,
      businessType: businessType,
      code: code,
      title: title,
      status: status ?? this.status,
      kind: kind,
      templateKey: templateKey,
      createdByName: createdByName,
      createdAt: createdAt,
      purpose: purpose ?? this.purpose,
      payeeAccount: payeeAccount ?? this.payeeAccount,
      payAccountType: payAccountType ?? this.payAccountType,
      counterparty: counterparty ?? this.counterparty,
      appliedAmount: appliedAmount ?? this.appliedAmount,
      issuedAmount: issuedAmount ?? this.issuedAmount,
      issueStatus: issueStatus ?? this.issueStatus,
      paymentCompleted: paymentCompleted ?? this.paymentCompleted,
      formValues: formValues ?? this.formValues,
      subStatus: subStatus ?? this.subStatus,
    );
  }
}

class PaymentInvoiceQuery {
  const PaymentInvoiceQuery({
    required this.kind,
    this.id = '',
    this.title = '',
    this.initiator = '',
    this.account = '',
    this.payAccountType = '',
    this.status = '',
    this.completed = '',
    this.issueStatus = '',
    this.counterparty = '',
    this.from,
    this.to,
  });

  final PaymentInvoiceKind kind;
  final String id;
  final String title;
  final String initiator;
  final String account;
  final String payAccountType;
  final String status;
  final String completed;
  final String issueStatus;
  final String counterparty;
  final DateTime? from;
  final DateTime? to;
}

class PaymentInvoiceProgress {
  const PaymentInvoiceProgress({
    required this.issuedAmount,
    required this.issueStatus,
  });

  final num issuedAmount;
  final InvoiceIssueStatus issueStatus;
}

const _paymentTemplateKeys = {
  'finance-admin-procurement',
  'finance-business-procurement',
  'finance-promotion-payment',
  'finance-contract-payment',
  'finance-prepayment',
  'admin-procurement',
  'business-procurement',
  'promotion-payment',
  'contract-payment',
  'prepayment',
  'advance-payment',
};

const _paymentBusinessTypes = {
  'FINANCE_ADMIN_PROCUREMENT',
  'FINANCE_BUSINESS_PROCUREMENT',
  'FINANCE_PROMOTION_PAYMENT',
  'FINANCE_CONTRACT_PAYMENT',
  'FINANCE_PREPAYMENT',
  'PREPAYMENT',
  'CONTRACT_PAYMENT',
};

const _invoiceTemplateKeys = {
  'invoice',
  'invoice-application',
  'invoice-request',
  'issue-invoice',
  'sales-invoice',
};

const _excludeTemplateKeys = {
  'electronic-reimbursement',
  'entertainment',
  'entertainment-expense',
  'entertainment-approval',
  'travel',
  'travel-expense',
  'contract-seal',
  'sales-proposal',
  'proposal-intake',
  'upload-invoice',
  'verify-invoice',
};

String normalizePaymentInvoiceToken(String raw) {
  return raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_]+'), '-');
}

PaymentInvoiceKind classifyPaymentInvoice({
  String businessType = '',
  String templateKey = '',
  String title = '',
  String documentKind = '',
  String proposalType = '',
}) {
  final template = normalizePaymentInvoiceToken(templateKey);
  final kind = normalizePaymentInvoiceToken(documentKind);
  final type = normalizePaymentInvoiceToken(proposalType);
  final bt = businessType.trim().toUpperCase();
  final blob = '$title $documentKind $proposalType';

  if (_excludeTemplateKeys.contains(template) ||
      blob.contains('电子报销') ||
      blob.contains('招待费') ||
      blob.contains('差旅')) {
    return PaymentInvoiceKind.other;
  }

  final looksInvoice =
      bt == 'INVOICE' ||
      _invoiceTemplateKeys.contains(template) ||
      template.startsWith('invoice') ||
      blob.contains('发票申请') ||
      blob.contains('开票申请');
  if (looksInvoice) return PaymentInvoiceKind.invoice;

  final looksPayment =
      _paymentBusinessTypes.contains(bt) ||
      _paymentTemplateKeys.contains(template) ||
      _paymentTemplateKeys.contains(kind) ||
      _paymentTemplateKeys.contains(type) ||
      blob.contains('行政采购') ||
      blob.contains('业务采购') ||
      blob.contains('推广费') ||
      blob.contains('合同付款') ||
      blob.contains('预付款');
  if (looksPayment) return PaymentInvoiceKind.payment;
  return PaymentInvoiceKind.other;
}

PaymentInvoiceRow paymentInvoiceRowFromListJson(Map<String, dynamic> json) {
  final id = _firstPositiveInt([
    json['businessId'],
    json['id'],
    json['submissionId'],
  ]);
  final businessType = (json['businessType'] ?? json['business_type'] ?? '')
      .toString()
      .trim();
  final templateKey = (json['templateKey'] ?? '').toString().trim();
  final title = (json['title'] ?? json['name'] ?? '审批单').toString().trim();
  final documentKind = (json['documentKind'] ?? '').toString();
  final proposalType = (json['proposalType'] ?? json['documentType'] ?? '')
      .toString();
  final kind = classifyPaymentInvoice(
    businessType: businessType,
    templateKey: templateKey,
    title: title,
    documentKind: documentKind,
    proposalType: proposalType,
  );
  final code = (json['code'] ?? '').toString().trim();
  final form = _asMap(json['formData'] ?? json['formValues'] ?? json['form']);
  final row = PaymentInvoiceRow(
    id: id,
    businessType: businessType.isEmpty ? 'UNKNOWN' : businessType,
    code: code.isNotEmpty ? code : (id > 0 ? '#$id' : ''),
    title: title.isEmpty ? '审批单' : title,
    status: (json['status'] ?? json['approvalStatus'] ?? '').toString(),
    kind: kind,
    templateKey: templateKey,
    createdByName: (json['createdByName'] ?? json['initiatorName'] ?? '')
        .toString()
        .trim(),
    createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
    subStatus: (json['subStatus'] ?? '').toString(),
    formValues: form,
  );
  return applyPaymentInvoiceForm(row, form, subStatus: row.subStatus);
}

PaymentInvoiceRow applyPaymentInvoiceForm(
  PaymentInvoiceRow row,
  Map<String, dynamic> form, {
  String subStatus = '',
}) {
  final merged = <String, dynamic>{...row.formValues, ...form};
  final purpose = pickPaymentInvoiceText(merged, const [
    'expensePurpose',
    'purpose',
    'reason',
    'applyReason',
    'applicationReason',
    'expenseUse',
    'useOfFunds',
    '费用用途',
    '申请事由',
    '事由',
  ]);
  final account = pickPaymentInvoiceText(merged, const [
    'payeeAccount',
    'receiveAccount',
    'receivingAccount',
    'collectionAccount',
    'bankAccount',
    'accountNo',
    'accountNumber',
    'payAccount',
    'vendorAccount',
    '收款账户',
    '收款账号',
  ]);
  final payType = normalizePayAccountType(
    pickPaymentInvoiceText(merged, const [
      'payAccountType',
      'accountType',
      'paymentType',
      'payType',
      'payeeType',
      'accountKind',
      '付款类型',
      '账户类型',
    ]),
  );
  final counterparty = pickPaymentInvoiceText(merged, const [
    'promoter',
    'promoterName',
    'vendor',
    'vendorName',
    'customer',
    'customerName',
    'clientName',
    'counterparty',
    'payeeName',
    'companyName',
    '推广商',
    '客户',
    '收款方',
  ]);
  final applied = pickPaymentInvoiceMoney(merged, const [
    'appliedAmount',
    'applyAmount',
    'requestAmount',
    'paymentAmount',
    'totalAmount',
    'amount',
    'invoiceAmount',
    '申请金额',
  ]);
  final issued = pickPaymentInvoiceMoney(merged, const [
        'issuedAmount',
        'invoicedAmount',
        'alreadyIssued',
        'openedAmount',
        'billedAmount',
        '已开金额',
      ]) ??
      0;
  final explicitStatus = pickPaymentInvoiceText(merged, const [
    'issueStatus',
    'invoiceStatus',
    'billingStatus',
    'openStatus',
    '开票状态',
  ]);
  final issueStatus = parseInvoiceIssueStatus(
    explicit: explicitStatus,
    applied: applied,
    issued: issued,
  );
  return row.copyWith(
    purpose: purpose,
    payeeAccount: account,
    payAccountType: payType,
    counterparty: counterparty,
    appliedAmount: applied ?? row.appliedAmount,
    issuedAmount: issued,
    issueStatus: issueStatus,
    paymentCompleted: isPaymentCompleted(
      merged,
      status: row.status,
      subStatus: subStatus.isEmpty ? row.subStatus : subStatus,
    ),
    formValues: merged,
    subStatus: subStatus.isEmpty ? row.subStatus : subStatus,
  );
}

PaymentInvoiceRow applyInvoiceProgress(
  PaymentInvoiceRow row,
  PaymentInvoiceProgress progress,
) {
  final issued = progress.issuedAmount < 0 ? 0 : progress.issuedAmount;
  var status = progress.issueStatus;
  if (status != InvoiceIssueStatus.completed) {
    status = parseInvoiceIssueStatus(
      applied: row.appliedAmount,
      issued: issued,
    );
  }
  return row.copyWith(issuedAmount: issued, issueStatus: status);
}

String pickPaymentInvoiceText(Map<String, dynamic> form, List<String> keys) {
  final flat = flattenPaymentInvoiceForm(form);
  for (final key in keys) {
    final hit = _lookupFlat(flat, key);
    final text = stringifyPaymentInvoiceValue(hit);
    if (text.isNotEmpty) return text;
  }
  return '';
}

num? pickPaymentInvoiceMoney(Map<String, dynamic> form, List<String> keys) {
  final flat = flattenPaymentInvoiceForm(form);
  for (final key in keys) {
    final parsed = parsePaymentInvoiceMoney(_lookupFlat(flat, key));
    if (parsed != null) return parsed;
  }
  return null;
}

Map<String, dynamic> flattenPaymentInvoiceForm(Map<String, dynamic> form) {
  final out = <String, dynamic>{};
  void walk(String prefix, dynamic value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map.containsKey('value') &&
          (map.containsKey('label') || map.length <= 4)) {
        final leaf = prefix.isEmpty ? 'value' : prefix;
        out.putIfAbsent(leaf, () => map['value']);
        final label = stringifyPaymentInvoiceValue(map['label']);
        if (label.isNotEmpty) out.putIfAbsent('${leaf}Label', () => label);
      }
      for (final entry in map.entries) {
        final next = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
        walk(next, entry.value);
        if (prefix.isNotEmpty) walk(entry.key.toString(), entry.value);
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        walk(prefix, item);
      }
      return;
    }
    if (prefix.isNotEmpty) out.putIfAbsent(prefix, () => value);
  }

  walk('', form);
  return out;
}

String normalizePayAccountType(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  final lower = text.toLowerCase();
  if (text.contains('对公') ||
      lower.contains('corporate') ||
      lower.contains('public') ||
      lower.contains('company')) {
    return '对公';
  }
  if (text.contains('对私') ||
      lower.contains('private') ||
      lower.contains('personal')) {
    return '对私';
  }
  return text;
}

InvoiceIssueStatus parseInvoiceIssueStatus({
  String? explicit,
  num? applied,
  num issued = 0,
}) {
  final text = (explicit ?? '').trim().toLowerCase();
  if (text.isNotEmpty) {
    if (RegExp(r'complete|done|finish|closed|settled|已完结|已开完|已开具完毕|^完结$').hasMatch(text)) {
      return InvoiceIssueStatus.completed;
    }
    if (RegExp(r'partial|部分').hasMatch(text)) {
      return InvoiceIssueStatus.partial;
    }
    if (RegExp(r'unissued|none|^open$|未开$|未开票').hasMatch(text)) {
      return InvoiceIssueStatus.unissued;
    }
  }
  final appliedVal = applied ?? 0;
  if (issued <= 0) return InvoiceIssueStatus.unissued;
  if (appliedVal > 0 && issued + 0.005 >= appliedVal) {
    return InvoiceIssueStatus.completed;
  }
  return InvoiceIssueStatus.partial;
}

bool isPaymentCompleted(
  Map<String, dynamic> form, {
  String status = '',
  String subStatus = '',
}) {
  final blob = '${pickPaymentInvoiceText(form, const [
        'completed',
        'settled',
        'finished',
        'payStatus',
        'paymentStatus',
        'closeStatus',
        '是否完结',
        '付款状态',
      ])} $subStatus'
      .toLowerCase();
  if (RegExp(r'true|yes|1|complete|done|settled|已完结|已支付|已付清').hasMatch(blob)) {
    return true;
  }
  final flag = form['completed'] == true || form['settled'] == true;
  if (flag) return true;
  return false;
}

bool matchesPaymentInvoiceQuery(PaymentInvoiceRow row, PaymentInvoiceQuery query) {
  if (row.kind != query.kind) return false;
  if (query.id.trim().isNotEmpty &&
      !_contains(row.displayId, query.id) &&
      !_contains('${row.id}', query.id)) {
    return false;
  }
  if (!_contains(row.title, query.title)) return false;
  if (!_contains(row.createdByName, query.initiator)) return false;
  if (!_contains(row.payeeAccount, query.account)) return false;
  if (!_contains(row.counterparty, query.counterparty)) return false;
  if (query.payAccountType.trim().isNotEmpty &&
      row.payAccountType != query.payAccountType.trim()) {
    return false;
  }
  if (query.status.trim().isNotEmpty &&
      row.status.toUpperCase() != query.status.trim().toUpperCase()) {
    return false;
  }
  if (query.kind == PaymentInvoiceKind.payment && query.completed.trim().isNotEmpty) {
    final wantDone = query.completed.trim() == 'yes';
    if (row.paymentCompleted != wantDone) return false;
  }
  if (query.kind == PaymentInvoiceKind.invoice && query.issueStatus.trim().isNotEmpty) {
    final want = query.issueStatus.trim().toLowerCase();
    if (want == 'open' && !row.invoiceOpen) return false;
    if (want == 'unissued' && row.issueStatus != InvoiceIssueStatus.unissued) {
      return false;
    }
    if (want == 'partial' && row.issueStatus != InvoiceIssueStatus.partial) {
      return false;
    }
    if (want == 'completed' && row.issueStatus != InvoiceIssueStatus.completed) {
      return false;
    }
  }
  if (query.from != null && row.createdAt != null) {
    final created = DateTime(row.createdAt!.year, row.createdAt!.month, row.createdAt!.day);
    final from = DateTime(query.from!.year, query.from!.month, query.from!.day);
    if (created.isBefore(from)) return false;
  }
  if (query.to != null && row.createdAt != null) {
    final created = DateTime(row.createdAt!.year, row.createdAt!.month, row.createdAt!.day);
    final to = DateTime(query.to!.year, query.to!.month, query.to!.day);
    if (created.isAfter(to)) return false;
  }
  return true;
}

String formatPaymentInvoiceMoney(num? value) {
  if (value == null) return '—';
  final negative = value < 0;
  final abs = value.abs();
  final fixed = abs.toStringAsFixed(2);
  final parts = fixed.split('.');
  final grouped = _groupThousands(parts[0]);
  return '${negative ? '-' : ''}$grouped.${parts[1]}';
}

String invoiceIssueStatusLabel(InvoiceIssueStatus status) {
  return switch (status) {
    InvoiceIssueStatus.unissued => '未开',
    InvoiceIssueStatus.partial => '部分开',
    InvoiceIssueStatus.completed => '已完结',
  };
}

String paymentInvoiceStatusLabel(String status) {
  switch (status.trim().toUpperCase()) {
    case 'DRAFT':
      return '草稿';
    case 'PENDING_INITIATE':
      return '待发起';
    case 'PENDING':
    case 'OPEN':
      return '审批中';
    case 'APPROVED':
      return '已通过';
    case 'REJECTED':
      return '已退回';
    case 'VOIDED':
      return '已作废';
    case 'SUPERSEDED':
      return '已替代';
    case 'WITHDRAWN':
      return '已撤回';
    default:
      return status.trim().isEmpty ? '—' : status.trim();
  }
}

String stringifyPaymentInvoiceValue(dynamic value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  if (value is num || value is bool) return value.toString();
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    final preferred = map['label'] ?? map['name'] ?? map['value'] ?? map['text'];
    final text = stringifyPaymentInvoiceValue(preferred);
    if (text.isNotEmpty) return text;
  }
  if (value is List) {
    return value
        .map(stringifyPaymentInvoiceValue)
        .where((item) => item.isNotEmpty)
        .join(' / ');
  }
  return value.toString().trim();
}

num? parsePaymentInvoiceMoney(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw;
  var text = stringifyPaymentInvoiceValue(raw);
  if (text.isEmpty) return null;
  text = text
      .replaceAll('¥', '')
      .replaceAll('￥', '')
      .replaceAll('元', '')
      .replaceAll(',', '')
      .replaceAll('，', '')
      .replaceAll(' ', '');
  return num.tryParse(text);
}

dynamic _lookupFlat(Map<String, dynamic> flat, String key) {
  final want = key.trim().toLowerCase();
  for (final entry in flat.entries) {
    final current = entry.key.toLowerCase();
    if (current == want || current.endsWith('.$want')) return entry.value;
  }
  return null;
}

bool _contains(String source, String query) {
  final q = query.trim();
  if (q.isEmpty) return true;
  return source.toLowerCase().contains(q.toLowerCase());
}

String _groupThousands(String digits) {
  if (digits.length <= 3) return digits;
  final buf = StringBuffer();
  final lead = digits.length % 3;
  if (lead > 0) buf.write(digits.substring(0, lead));
  for (var i = lead; i < digits.length; i += 3) {
    if (buf.isNotEmpty) buf.write(',');
    buf.write(digits.substring(i, i + 3));
  }
  return buf.toString();
}

Map<String, dynamic> _asMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const {};
}

int _firstPositiveInt(List<dynamic> values) {
  for (final value in values) {
    final parsed = _asInt(value);
    if (parsed > 0) return parsed;
  }
  return 0;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value'.trim()) ?? 0;
}
