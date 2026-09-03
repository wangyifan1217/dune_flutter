import 'dart:math' as math;

import 'proposal_intake_models.dart';

const kProposalCouponProcurementCostKey = 'couponProcurementCost';
const kProposalFinanceTaxRateKey = 'financeTaxRate';
const kProposalWriteOffAmountKey = 'writeOffAmount';

const kProposalOperatingCostManualKey = 'operatingCostItemManual';
const kProposalTaxCostManualKey = 'taxCostItemManual';
const kProposalBusinessCostManualKey = 'businessCostItemManual';

const kProposalRevenueFormulaTitle = '收入';
const kProposalRevenueFormula =
    '测算中的电子券销售收入 = 收入';

enum ProposalBusinessCostFormula { bn, u }

enum ProposalCostEstimateKind {
  revenue,
  operating,
  vat,
  stamp,
  incomeTax,
  businessBn,
  businessU,
}

class ProposalCostFormulaHelp {
  const ProposalCostFormulaHelp({
    required this.title,
    required this.formula,
    this.substitution = '',
  });

  final String title;
  final String formula;
  final String substitution;
}

double proposalRoundWan(double value) {
  if (value.isNaN || value.isInfinite) return 0;
  return (value * 100).round() / 100;
}

String proposalFormatWan(double value) {
  final rounded = proposalRoundWan(value);
  if (rounded == rounded.roundToDouble()) return rounded.toStringAsFixed(0);
  return rounded.toStringAsFixed(2);
}

double proposalFinanceAmount(Map<String, dynamic> form, String key) =>
    proposalCostAmountValue(form[key]);

double proposalParseTaxRate(Object? raw) {
  final text = '$raw'.trim().replaceAll('％', '%');
  if (text.isEmpty) return 0;
  final cleaned = text.endsWith('%')
      ? text.substring(0, text.length - 1).trim()
      : text;
  final n = double.tryParse(cleaned) ?? 0;
  if (n.abs() > 1) return n / 100;
  return n;
}

Set<String> proposalCostManualIdSet(Object? raw) {
  if (raw is List) {
    return {
      for (final item in raw)
        if ('$item'.trim().isNotEmpty) '$item'.trim(),
    };
  }
  if (raw is Map) {
    return {
      for (final entry in raw.entries)
        if (entry.value == true && '${entry.key}'.trim().isNotEmpty)
          '${entry.key}'.trim(),
    };
  }
  return {};
}

List<String> proposalCostSelectedNames(
  Map<String, dynamic> form,
  String namesKey,
) {
  final raw = form[namesKey];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if ('$item'.trim().isNotEmpty) '$item'.trim(),
  ];
}

ProposalBusinessCostFormula? proposalBusinessCostFormulaOf(String name) {
  final text = name.trim();
  if (text.isEmpty) return null;
  if (RegExp(r'侧U').hasMatch(text) ||
      (text.endsWith('U') && !text.contains('BN'))) {
    return ProposalBusinessCostFormula.u;
  }
  if (text.contains('BN') || RegExp(r'侧N').hasMatch(text)) {
    return ProposalBusinessCostFormula.bn;
  }
  return null;
}

ProposalCostEstimateKind? proposalCostEstimateKindOf(String name) {
  switch (name.trim()) {
    case '收入':
    case '收入（万元）':
    case '电子券销售收入':
      return ProposalCostEstimateKind.revenue;
    case '差旅成本':
    case '招待费':
      return ProposalCostEstimateKind.operating;
    case '增值税及附加（能源）':
    case '增值税及附加（运营商+公共出行）':
      return ProposalCostEstimateKind.vat;
    case '印花税':
      return ProposalCostEstimateKind.stamp;
    case '所得税':
      return ProposalCostEstimateKind.incomeTax;
    default:
      return switch (proposalBusinessCostFormulaOf(name)) {
        ProposalBusinessCostFormula.bn => ProposalCostEstimateKind.businessBn,
        ProposalBusinessCostFormula.u => ProposalCostEstimateKind.businessU,
        null => null,
      };
  }
}

bool proposalCostHasEstimateFormula(String name) =>
    proposalCostEstimateKindOf(name) != null;

bool proposalIsFinanceEstimateInputKey(String key) =>
    key == 'revenue' ||
    key == kProposalCouponProcurementCostKey ||
    key == kProposalFinanceTaxRateKey ||
    key == kProposalWriteOffAmountKey;

String proposalCostFormulaText(ProposalCostEstimateKind kind) => switch (kind) {
  ProposalCostEstimateKind.revenue => kProposalRevenueFormula,
  ProposalCostEstimateKind.operating =>
    '(电子券销售收入 − 电子券采购成本 − 项目成本) × 2%',
  ProposalCostEstimateKind.vat =>
    '(电子券销售收入 × 税率 − 电子券采购成本 × 税率 − 项目成本 × 税率) × 1.12',
  ProposalCostEstimateKind.stamp => '核销金额 × 0.0006',
  ProposalCostEstimateKind.incomeTax =>
    '(电子券销售收入 − 电子券采购成本 − 项目成本 − 业务成本 − 经营成本) × 25%',
  ProposalCostEstimateKind.businessBn =>
    '(电子券销售收入 − 电子券采购成本 − 项目成本 − 经营成本) × 10%',
  ProposalCostEstimateKind.businessU =>
    '(电子券销售收入 − 电子券采购成本 − 项目成本 − 经营成本) × 45%',
};

ProposalCostFormulaHelp? proposalCostFormulaHelpOf({
  required String name,
  Map<String, dynamic> form = const {},
  List<ProposalCostItemOption> businessCatalog = const [],
}) {
  final kind = proposalCostEstimateKindOf(name);
  if (kind == null) return null;
  return ProposalCostFormulaHelp(
    title: name.trim(),
    formula: proposalCostFormulaText(kind),
    substitution: proposalCostFormulaSubstitution(
      kind: kind,
      form: form,
      businessCatalog: businessCatalog,
    ),
  );
}

String proposalCostFormulaSubstitution({
  required ProposalCostEstimateKind kind,
  required Map<String, dynamic> form,
  List<ProposalCostItemOption> businessCatalog = const [],
}) {
  final revenue = proposalFinanceAmount(form, 'revenue');
  final procurement = proposalFinanceAmount(
    form,
    kProposalCouponProcurementCostKey,
  );
  final project = proposalFinanceAmount(form, 'projectCost');
  final taxRate = proposalParseTaxRate(form[kProposalFinanceTaxRateKey]);
  final writeOff = proposalFinanceAmount(form, kProposalWriteOffAmountKey);
  final operating = _bucketTotal(
    form,
    namesKey: 'operatingCostItems',
    amountsKey: 'operatingCostItemAmounts',
    totalKey: 'operatingCost',
  );
  final business = _bucketTotal(
    form,
    namesKey: 'businessCostItems',
    amountsKey: 'businessCostItemAmounts',
    totalKey: 'businessCost',
    catalog: businessCatalog,
  );
  final r = proposalFormatWan;
  final base = math.max(0.0, revenue - procurement - project);
  final vatBase = revenue - procurement - project;
  final bizBase = math.max(0.0, base - operating);
  final incomeBase = math.max(
    0.0,
    revenue - procurement - project - business - operating,
  );

  return switch (kind) {
    ProposalCostEstimateKind.revenue => '电子券销售收入 = ${r(revenue)} 万元',
    ProposalCostEstimateKind.operating =>
      '(${r(revenue)} − ${r(procurement)} − ${r(project)}) × 2% = ${r(base * 0.02)} 万元',
    ProposalCostEstimateKind.vat =>
      '(${r(revenue)} − ${r(procurement)} − ${r(project)}) × ${r(taxRate * 100)}% × 1.12 = ${r(vatBase * taxRate * 1.12)} 万元',
    ProposalCostEstimateKind.stamp =>
      '${r(writeOff)} × 0.0006 = ${r(writeOff * 0.0006)} 万元',
    ProposalCostEstimateKind.incomeTax =>
      '(${r(revenue)} − ${r(procurement)} − ${r(project)} − ${r(business)} − ${r(operating)}) × 25% = ${r(incomeBase * 0.25)} 万元',
    ProposalCostEstimateKind.businessBn =>
      '(${r(revenue)} − ${r(procurement)} − ${r(project)} − ${r(operating)}) × 10% = ${r(bizBase * 0.10)} 万元',
    ProposalCostEstimateKind.businessU =>
      '(${r(revenue)} − ${r(procurement)} − ${r(project)} − ${r(operating)}) × 45% = ${r(bizBase * 0.45)} 万元',
  };
}

double? proposalEstimateAmountForName({
  required String name,
  required Map<String, dynamic> form,
  List<ProposalCostItemOption> businessCatalog = const [],
}) {
  final kind = proposalCostEstimateKindOf(name);
  if (kind == null || kind == ProposalCostEstimateKind.revenue) return null;
  final revenue = proposalFinanceAmount(form, 'revenue');
  final procurement = proposalFinanceAmount(
    form,
    kProposalCouponProcurementCostKey,
  );
  final project = proposalFinanceAmount(form, 'projectCost');
  final taxRate = proposalParseTaxRate(form[kProposalFinanceTaxRateKey]);
  final writeOff = proposalFinanceAmount(form, kProposalWriteOffAmountKey);
  final operating = _bucketTotal(
    form,
    namesKey: 'operatingCostItems',
    amountsKey: 'operatingCostItemAmounts',
    totalKey: 'operatingCost',
  );
  final business = _bucketTotal(
    form,
    namesKey: 'businessCostItems',
    amountsKey: 'businessCostItemAmounts',
    totalKey: 'businessCost',
    catalog: businessCatalog,
  );
  final base = math.max(0.0, revenue - procurement - project);
  return switch (kind) {
    ProposalCostEstimateKind.revenue => null,
    ProposalCostEstimateKind.operating => base * 0.02,
    ProposalCostEstimateKind.vat =>
      (revenue - procurement - project) * taxRate * 1.12,
    ProposalCostEstimateKind.stamp => writeOff * 0.0006,
    ProposalCostEstimateKind.incomeTax =>
      math.max(0.0, revenue - procurement - project - business - operating) *
      0.25,
    ProposalCostEstimateKind.businessBn =>
      math.max(0.0, base - operating) * 0.10,
    ProposalCostEstimateKind.businessU =>
      math.max(0.0, base - operating) * 0.45,
  };
}

Map<String, dynamic> proposalMarkCostAmountManual(
  Map<String, dynamic> form, {
  required String amountsKey,
  required String id,
}) {
  final manualKey = _manualKeyForAmounts(amountsKey);
  if (manualKey == null || id.trim().isEmpty) return form;
  final ids = proposalCostManualIdSet(form[manualKey])..add(id.trim());
  return Map<String, dynamic>.from(form)..[manualKey] = ids.toList();
}

Map<String, dynamic> proposalApplyEstimatedFinanceCosts(
  Map<String, dynamic> form, {
  List<ProposalCostItemOption> businessCatalog = const [],
}) {
  var next = Map<String, dynamic>.from(form);
  next = _writeEstimatedBucket(
    next,
    namesKey: 'operatingCostItems',
    amountsKey: 'operatingCostItemAmounts',
    totalKey: 'operatingCost',
    manualKey: kProposalOperatingCostManualKey,
    catalog: const [],
    businessCatalog: businessCatalog,
  );
  next = _writeEstimatedBucket(
    next,
    namesKey: 'businessCostItems',
    amountsKey: 'businessCostItemAmounts',
    totalKey: 'businessCost',
    manualKey: kProposalBusinessCostManualKey,
    catalog: businessCatalog,
    businessCatalog: businessCatalog,
  );
  next = _writeEstimatedBucket(
    next,
    namesKey: 'taxCostItems',
    amountsKey: 'taxCostItemAmounts',
    totalKey: 'taxCost',
    manualKey: kProposalTaxCostManualKey,
    catalog: const [],
    businessCatalog: businessCatalog,
  );
  return next;
}

String? _manualKeyForAmounts(String amountsKey) => switch (amountsKey) {
  'operatingCostItemAmounts' => kProposalOperatingCostManualKey,
  'taxCostItemAmounts' => kProposalTaxCostManualKey,
  'businessCostItemAmounts' => kProposalBusinessCostManualKey,
  _ => null,
};

double _bucketTotal(
  Map<String, dynamic> form, {
  required String namesKey,
  required String amountsKey,
  required String totalKey,
  List<ProposalCostItemOption> catalog = const [],
}) {
  final names = proposalCostSelectedNames(form, namesKey);
  if (names.isEmpty) return proposalFinanceAmount(form, totalKey);
  final amounts = proposalCostAmountMap(form[amountsKey]);
  var sum = 0.0;
  for (final name in names) {
    final id = proposalCostAmountId(name, catalog);
    sum += amounts[id] ?? amounts[name] ?? 0;
  }
  return sum;
}

Map<String, dynamic> _writeEstimatedBucket(
  Map<String, dynamic> form, {
  required String namesKey,
  required String amountsKey,
  required String totalKey,
  required String manualKey,
  required List<ProposalCostItemOption> catalog,
  required List<ProposalCostItemOption> businessCatalog,
}) {
  final names = proposalCostSelectedNames(form, namesKey);
  final keep = <String>{
    for (final name in names) ...proposalProjectCostNamesOf(name),
    for (final name in names) proposalCostAmountId(name, catalog),
  };
  final amounts = proposalCostAmountMap(form[amountsKey])
    ..removeWhere((id, _) => !keep.contains(id));
  final manual = proposalCostManualIdSet(form[manualKey]);
  final keepManual = <String>{};
  for (final name in names) {
    final id = proposalCostAmountId(name, catalog);
    final estimated = proposalEstimateAmountForName(
      name: name,
      form: form,
      businessCatalog: businessCatalog,
    );
    if (estimated == null) continue;
    if (manual.contains(id) || manual.contains(name)) {
      keepManual.add(id);
      continue;
    }
    amounts[id] = proposalRoundWan(estimated);
  }
  final next = Map<String, dynamic>.from(form)
    ..[amountsKey] = {
      for (final entry in amounts.entries) entry.key: entry.value,
    }
    ..[totalKey] = proposalCostAmountTotal(amounts)
    ..[manualKey] = keepManual.toList();
  return next;
}
