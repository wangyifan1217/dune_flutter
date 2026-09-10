import 'dart:math' as math;

import 'proposal_intake_models.dart';

const kProposalCouponProcurementCostKey = 'couponProcurementCost';
const kProposalSalesScaleKey = 'salesScale';
const kProposalTurnoverCashKey = 'turnoverCash';
const kProposalTurnoverTimesKey = 'turnoverTimes';

const kProposalOperatingCostManualKey = 'operatingCostItemManual';
const kProposalTaxCostManualKey = 'taxCostItemManual';
const kProposalBusinessCostManualKey = 'businessCostItemManual';
const kProposalProjectCostManualKey = 'costItemManual';
const kProposalProcurementManualKey = 'couponProcurementCostManual';

const kProposalVatEnergyName = '增值税及附加（能源）';
const kProposalVatOperatorName = '增值税及附加（运营商+公共出行）';
const kProposalStampTaxName = '印花税';

const kProposalRevenueFormulaTitle = '收入';
const kProposalRevenueFormula = '各产品：年化规模 × 结算比例 加总';
const kProposalSalesScaleFormula = '各产品年化规模加总';
const kProposalProcurementFormula = '各供给规则：关联产品年化规模 × 该条比例，加总';
const kProposalProfitFormula = '收入 − 采购 − 项目';
const kProposalMarginFormula = '利润 ÷ 收入';
const kProposalTurnoverCashFormula = '销售规模 ÷ 月周转次数';
const kProposalProjectCostFormula = '各产品年化规模 × 结算比例，加总';

const kProposalVatSurcharge = 1.12;

class ProposalProductScaleRollup {
  const ProposalProductScaleRollup({
    required this.salesScale,
    required this.revenue,
  });

  final double salesScale;
  final double revenue;
}

class ProposalVatEstimate {
  const ProposalVatEstimate({
    required this.outputTax,
    required this.inputTax,
    required this.outputRate,
    required this.inputRate,
    required this.projectRate,
  });

  final double outputTax;
  final double inputTax;
  final double outputRate;
  final double inputRate;
  final double projectRate;

  double get payable => (outputTax - inputTax) * kProposalVatSurcharge;
}

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
    key == kProposalSalesScaleKey ||
    key == kProposalTurnoverTimesKey;

double proposalParseSettleRatio(Object? raw) {
  final text = '$raw'.trim();
  if (text.isEmpty) return 1;
  return proposalParseTaxRate(text);
}

ProposalProductScaleRollup? proposalProductScaleRollup(
  Map<String, dynamic> form,
) {
  var any = false;
  var scale = 0.0;
  var revenue = 0.0;
  for (final terms in proposalIntakeProductSalesSettleTerms(form)) {
    if (terms.scale.trim().isEmpty) continue;
    any = true;
    final amount = proposalAnnualizedScale(terms);
    scale += amount;
    revenue += amount * proposalParseSettleRatio(terms.displayRatio);
  }
  if (!any) return null;
  return ProposalProductScaleRollup(
    salesScale: proposalRoundWan(scale),
    revenue: proposalRoundWan(revenue),
  );
}

double proposalEffectiveSalesScale(Map<String, dynamic> form) {
  return proposalProductScaleRollup(form)?.salesScale ??
      proposalFinanceAmount(form, kProposalSalesScaleKey);
}

double proposalEffectiveRevenue(Map<String, dynamic> form) {
  return proposalProductScaleRollup(form)?.revenue ??
      proposalFinanceAmount(form, 'revenue');
}

double proposalEstimatedProfitAmount(
  Map<String, dynamic> form, {
  double? revenue,
}) {
  final r = revenue ?? proposalEffectiveRevenue(form);
  return proposalRoundWan(
    r -
        proposalFinanceAmount(form, kProposalCouponProcurementCostKey) -
        proposalFinanceAmount(form, 'projectCost'),
  );
}

double proposalEstimatedMarginAmount(
  Map<String, dynamic> form, {
  double? revenue,
  double? profit,
}) {
  final r = revenue ?? proposalEffectiveRevenue(form);
  if (r == 0) return 0;
  final p = profit ?? proposalEstimatedProfitAmount(form, revenue: r);
  return proposalRoundWan(p / r * 100);
}

Map<String, dynamic> proposalApplyProductScaleRollup(
  Map<String, dynamic> form,
) {
  final rollup = proposalProductScaleRollup(form);
  if (rollup == null) return form;
  final next = Map<String, dynamic>.from(form)
    ..[kProposalSalesScaleKey] = rollup.salesScale
    ..['revenue'] = rollup.revenue;
  return next;
}

Map<String, dynamic> proposalWriteDerivedProfit(Map<String, dynamic> form) {
  if (!proposalIntakeHasProductSalesScale(form) &&
      proposalProductScaleRollup(form) == null) {
    return form;
  }
  final revenue = proposalEffectiveRevenue(form);
  final next = Map<String, dynamic>.from(form);
  final profit = proposalEstimatedProfitAmount(next, revenue: revenue);
  next['profit'] = profit;
  next['margin'] = proposalEstimatedMarginAmount(
    next,
    revenue: revenue,
    profit: profit,
  );
  return next;
}

/// 周转资金 = 销售规模 ÷ 月周转次数。次数为空或 0 时不写。
double? proposalTurnoverCashAmount(Map<String, dynamic> form) {
  final times = proposalFinanceAmount(form, kProposalTurnoverTimesKey);
  if (times <= 0) return null;
  return proposalRoundWan(proposalEffectiveSalesScale(form) / times);
}

Map<String, dynamic> proposalApplyTurnoverCash(Map<String, dynamic> form) {
  final next = Map<String, dynamic>.from(form);
  final cash = proposalTurnoverCashAmount(form);
  if (cash == null) {
    next[kProposalTurnoverCashKey] = null;
  } else {
    next[kProposalTurnoverCashKey] = cash;
  }
  return next;
}

double _firstPositiveTaxRate(Iterable<String> rawRates) {
  for (final raw in rawRates) {
    final rate = proposalParseTaxRate(raw);
    if (rate > 0) return rate;
  }
  return 0;
}

/// 测算用税率取结算条款里第一项非空税率。
double proposalEstimateTaxRate(Map<String, dynamic> form) {
  final sales = proposalSalesOutputTaxRate(form);
  if (sales > 0) return sales;
  for (final key in const [
    'costItemSettleTerms',
    'businessCostItemSettleTerms',
    'operatingCostItemSettleTerms',
    'taxCostItemSettleTerms',
  ]) {
    final rate = _firstPositiveTaxRate(
      proposalCostSettleTermsMap(
        form[key],
      ).values.map((terms) => terms.taxRate),
    );
    if (rate > 0) return rate;
  }
  return 0;
}

double proposalSalesOutputTaxRate(Map<String, dynamic> form) {
  return _firstPositiveTaxRate(
    proposalIntakeProductSalesSettleTerms(form).map((terms) => terms.taxRate),
  );
}

double proposalPurchaseInputTaxRate(Map<String, dynamic> form) {
  return _firstPositiveTaxRate([
    for (final product in proposalIntakeSupplyProducts(form))
      for (final settle in proposalIntakeSupplySettlements(product))
        settle.terms.taxRate,
  ]);
}

double proposalProjectCostTaxRate(Map<String, dynamic> form) {
  final payable = _firstPositiveTaxRate([
    for (final hit in proposalPayableProjectCostHits(form)) hit.terms.taxRate,
  ]);
  if (payable > 0) return payable;
  final raw = form['costItemSettleTerms'];
  if (raw is! Map) return 0;
  return _firstPositiveTaxRate([
    for (final name in proposalCostSelectedNames(form, 'costItems'))
      for (final terms in proposalCostSettleTermsList(
        raw,
        name: name,
        id: proposalCostAmountId(name, const []),
      ))
        terms.taxRate,
    ...proposalCostSettleTermsMap(raw).values.map((terms) => terms.taxRate),
  ]);
}

/// 销项按各销售结算「规模 × 比例 × 该行税率」加总；无规模时用收入 × 销项税率。
/// 进项 = 采购成本 × 供给税率 + 项目成本 × 项目成本税率；缺进项税率时与销项相同。
ProposalVatEstimate proposalVatEstimate(Map<String, dynamic> form) {
  final outputRate = proposalSalesOutputTaxRate(form);
  var inputRate = proposalPurchaseInputTaxRate(form);
  if (inputRate <= 0) inputRate = outputRate;
  var projectRate = proposalProjectCostTaxRate(form);
  if (projectRate <= 0) projectRate = inputRate;

  var outputTax = 0.0;
  var anyScale = false;
  for (final terms in proposalIntakeProductSalesSettleTerms(form)) {
    if (terms.scale.trim().isEmpty) continue;
    anyScale = true;
    final amount =
        proposalAnnualizedScale(terms) *
        proposalParseSettleRatio(terms.displayRatio);
    var rate = proposalParseTaxRate(terms.taxRate);
    if (rate <= 0) rate = outputRate;
    outputTax += amount * rate;
  }
  if (!anyScale) {
    outputTax = proposalEffectiveRevenue(form) * outputRate;
  }

  final inputTax =
      proposalFinanceAmount(form, kProposalCouponProcurementCostKey) *
          inputRate +
      proposalFinanceAmount(form, 'projectCost') * projectRate;
  return ProposalVatEstimate(
    outputTax: outputTax,
    inputTax: inputTax,
    outputRate: outputRate,
    inputRate: inputRate,
    projectRate: projectRate,
  );
}

String proposalCostFormulaText(ProposalCostEstimateKind kind) => switch (kind) {
  ProposalCostEstimateKind.revenue => kProposalRevenueFormula,
  ProposalCostEstimateKind.operating => '(收入 − 采购 − 项目) × 2%',
  ProposalCostEstimateKind.vat => '(销项 − 进项) × 1.12',
  ProposalCostEstimateKind.stamp => '销售规模 × 0.0006',
  ProposalCostEstimateKind.incomeTax =>
    '(收入 − 采购 − 项目 − 业务 − 经营) × 25%（25% 未经财务确认）',
  ProposalCostEstimateKind.businessBn => '(收入 − 采购 − 项目 − 经营) × 10%',
  ProposalCostEstimateKind.businessU => '(收入 − 采购 − 项目 − 经营) × 45%',
};

ProposalCostFormulaHelp? proposalCostFormulaHelpOf({
  required String name,
  Map<String, dynamic> form = const {},
  List<ProposalCostItemOption> businessCatalog = const [],
  List<ProposalCostItemOption> costCatalog = const [],
}) {
  final estimated = proposalEstimateProjectCostAmount(
    form,
    name,
    catalog: costCatalog,
  );
  if (estimated != null) {
    return ProposalCostFormulaHelp(
      title: proposalProjectCostDisplayName(name),
      formula: kProposalProjectCostFormula,
      substitution: proposalProjectCostFormulaSubstitution(
        form,
        name,
        catalog: costCatalog,
      ),
    );
  }
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
  final revenue = proposalEffectiveRevenue(form);
  final procurement = proposalFinanceAmount(
    form,
    kProposalCouponProcurementCostKey,
  );
  final project = proposalFinanceAmount(form, 'projectCost');
  final salesScale = proposalEffectiveSalesScale(form);
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
  final vat = proposalVatEstimate(form);
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
      '销项 ${r(vat.outputTax)} − 进项 ${r(vat.inputTax)}，× 1.12 = ${r(vat.payable)} 万元',
    ProposalCostEstimateKind.stamp =>
      '${r(salesScale)} × 0.0006 = ${r(salesScale * 0.0006)} 万元',
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
  final revenue = proposalEffectiveRevenue(form);
  final procurement = proposalFinanceAmount(
    form,
    kProposalCouponProcurementCostKey,
  );
  final project = proposalFinanceAmount(form, 'projectCost');
  final salesScale = proposalEffectiveSalesScale(form);
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
    ProposalCostEstimateKind.vat => proposalVatEstimate(form).payable,
    ProposalCostEstimateKind.stamp => salesScale * 0.0006,
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

/// 增值税税种按业务板块判定：运营商 / 公共出行走「运营商+公共出行」，其余走「能源」。
String proposalDefaultVatItemName(Map<String, dynamic> form) {
  final sector = [
    '${form['sector'] ?? ''}',
    proposalIntakeFormRef(form, 'sectorRef')?.name ?? '',
  ].join(' ');
  if (sector.contains('运营商') || sector.contains('出行')) {
    return kProposalVatOperatorName;
  }
  return kProposalVatEnergyName;
}

/// 所有带比例的供给结算条款。
List<ProposalFinanceSettleTerms> proposalPurchaseSettleTerms(
  Map<String, dynamic> form,
) {
  return [
    for (final product in proposalIntakeSupplyProducts(form))
      for (final settle in proposalIntakeSupplySettlements(product))
        if (settle.terms.displayRatio.trim().isNotEmpty &&
            proposalParseSettleRatio(settle.terms.displayRatio) > 0)
          settle.terms,
  ];
}

/// 兼容旧口径：第一条非空供给比例。仅在没有任何一条勾选渠道产品时使用。
double proposalPurchaseSettleRatio(Map<String, dynamic> form) {
  final rows = proposalPurchaseSettleTerms(form);
  if (rows.isEmpty) return 0;
  return proposalParseSettleRatio(rows.first.displayRatio);
}

/// 采购成本 = 各供给结算「关联渠道产品年化规模 × 该条比例」加总。
/// 未被任何供给结算勾到的产品按第一条比例兜底，避免漏算成本把利润算高。
/// 一条都没勾时退回旧口径：全部年化规模 × 第一条比例。
double? proposalEstimatedProcurementCost(Map<String, dynamic> form) {
  final rows = proposalPurchaseSettleTerms(form);
  if (rows.isEmpty) return null;
  final scoped = [
    for (final terms in rows)
      if (terms.skuIds.isNotEmpty) terms,
  ];
  final fallbackRatio = proposalParseSettleRatio(rows.first.displayRatio);
  if (scoped.isEmpty) {
    final scale = proposalEffectiveSalesScale(form);
    if (scale <= 0) return null;
    return proposalRoundWan(scale * fallbackRatio);
  }
  var sum = 0.0;
  final covered = <String>{};
  for (final terms in scoped) {
    sum +=
        proposalAssociatedSalesScale(form, terms.skuIds) *
        proposalParseSettleRatio(terms.displayRatio);
    covered.addAll(terms.skuIds);
  }
  for (final sku in proposalIntakeSkuDetails(form)) {
    if (covered.contains(sku.id)) continue;
    sum += proposalIntakeSkuScaleTotal(sku) * fallbackRatio;
  }
  if (sum <= 0) return null;
  return proposalRoundWan(sum);
}

bool proposalIntakeHasDerivedProcurement(Map<String, dynamic> form) =>
    proposalEstimatedProcurementCost(form) != null;

double proposalAssociatedSalesScale(
  Map<String, dynamic> form,
  List<String> skuIds,
) {
  if (skuIds.isEmpty) return proposalEffectiveSalesScale(form);
  final want = skuIds.toSet();
  var sum = 0.0;
  for (final sku in proposalIntakeSkuDetails(form)) {
    if (!want.contains(sku.id)) continue;
    sum += proposalIntakeSkuScaleTotal(sku);
  }
  return sum;
}

class ProposalPayableCostHit {
  const ProposalPayableCostHit({
    required this.costName,
    required this.terms,
    required this.skuIds,
  });

  final String costName;
  final ProposalFinanceSettleTerms terms;
  final List<String> skuIds;
}

String proposalSettleBillPath(ProposalFinanceSettleTerms terms) {
  final path = (terms.billTypeRef?.displayPath ?? '').trim();
  if (path.isNotEmpty) return path;
  return terms.billType.trim();
}

String proposalSettleBillTypeL3(ProposalFinanceSettleTerms terms) {
  final path = proposalSettleBillPath(terms);
  if (path.contains('/')) return path.split('/').last.trim();
  final name = (terms.billTypeRef?.name ?? '').trim();
  if (name.isNotEmpty) return name;
  return path;
}

String? proposalPayableBillCostName(ProposalFinanceSettleTerms terms) {
  final path = proposalSettleBillPath(terms);
  if (path.contains('应收')) return null;
  if (path.contains('/') && !path.contains('应付')) return null;
  final display = proposalProjectCostDisplayName(proposalSettleBillTypeL3(terms));
  if (display.isEmpty || !kProposalProjectCostItems.contains(display)) {
    return null;
  }
  return display;
}

double _projectCostSettleRatio(ProposalFinanceSettleTerms terms) {
  if (terms.displayRatio.trim().isEmpty) return 0;
  return proposalParseSettleRatio(terms.displayRatio);
}

String _projectCostRatioLabel(ProposalFinanceSettleTerms terms) {
  final text = terms.displayRatio.trim();
  if (text.isNotEmpty) return text;
  return proposalFormatWan(_projectCostSettleRatio(terms));
}

double proposalPayableCostLineAmount(
  Map<String, dynamic> form,
  ProposalFinanceSettleTerms terms,
  List<String> skuIds,
) {
  final ratio = _projectCostSettleRatio(terms);
  if (ratio <= 0) return 0;
  final scale = proposalAssociatedSalesScale(form, skuIds);
  if (scale <= 0) return 0;
  return scale * ratio;
}

List<String> _expandPayableHitSkuIds(
  ProposalPayableCostHit hit,
  List<List<String>> salesGroups,
  Set<String> owned,
) {
  if (hit.skuIds.isEmpty) return hit.skuIds;
  final next = [...hit.skuIds];
  final seen = hit.skuIds.toSet();
  for (final group in salesGroups) {
    if (!group.any(seen.contains)) continue;
    for (final id in group) {
      if (seen.contains(id)) continue;
      if (owned.contains('$id|${hit.costName}')) continue;
      seen.add(id);
      next.add(id);
    }
  }
  return next;
}

List<ProposalPayableCostHit> proposalPayableProjectCostHits(
  Map<String, dynamic> form,
) {
  final hits = <ProposalPayableCostHit>[];
  final covered = <String>{};

  void addHit(ProposalFinanceSettleTerms terms, List<String> skuIds) {
    final costName = proposalPayableBillCostName(terms);
    if (costName == null) return;
    final ids = [
      for (final id in skuIds)
        if (id.trim().isNotEmpty) id.trim(),
    ];
    if (ids.isEmpty) {
      hits.add(
        ProposalPayableCostHit(costName: costName, terms: terms, skuIds: const []),
      );
      return;
    }
    final unused = [
      for (final id in ids)
        if (!covered.contains('$id|$costName')) id,
    ];
    if (unused.isEmpty) return;
    for (final id in unused) {
      covered.add('$id|$costName');
    }
    hits.add(
      ProposalPayableCostHit(costName: costName, terms: terms, skuIds: unused),
    );
  }

  for (final group in proposalIntakeSharedSettlements(form)) {
    if (group.isBlank) continue;
    addHit(group.terms, group.skuIds);
  }
  for (final sku in proposalIntakeSkuDetails(form)) {
    for (final settle in proposalIntakeSkuSettlements(sku)) {
      addHit(settle.terms, [sku.id]);
    }
  }

  final owned = <String>{
    for (final hit in hits)
      for (final id in hit.skuIds) '$id|${hit.costName}',
  };
  final salesGroups = [
    for (final group in proposalIntakeSharedSettlements(form))
      if (proposalPayableBillCostName(group.terms) == null)
        [
          for (final id in group.skuIds)
            if (id.trim().isNotEmpty) id.trim(),
        ],
  ];
  return [
    for (final hit in hits)
      ProposalPayableCostHit(
        costName: hit.costName,
        terms: hit.terms,
        skuIds: _expandPayableHitSkuIds(hit, salesGroups, owned),
      ),
  ];
}

String proposalProjectCostFormulaSubstitution(
  Map<String, dynamic> form,
  String name, {
  List<ProposalCostItemOption> catalog = const [],
}) {
  final estimated = proposalEstimateProjectCostAmount(
    form,
    name,
    catalog: catalog,
  );
  if (estimated == null) return '';
  final aliases = proposalProjectCostNamesOf(
    proposalProjectCostDisplayName(name),
  );
  final skus = {for (final sku in proposalIntakeSkuDetails(form)) sku.id: sku};
  final grouped = <String, List<double>>{};
  for (final hit in proposalPayableProjectCostHits(form)) {
    if (!aliases.contains(hit.costName)) continue;
    final ratio = _projectCostSettleRatio(hit.terms);
    if (ratio <= 0) continue;
    final label = _projectCostRatioLabel(hit.terms);
    if (hit.skuIds.isEmpty) {
      final scale = proposalEffectiveSalesScale(form);
      if (scale > 0) (grouped[label] ??= []).add(scale);
      continue;
    }
    for (final id in hit.skuIds) {
      final sku = skus[id];
      if (sku == null) continue;
      final scale = proposalIntakeSkuScaleTotal(sku);
      if (scale > 0) (grouped[label] ??= []).add(scale);
    }
  }
  if (grouped.isEmpty) {
    return '${kProposalProjectCostFormula} = ${proposalFormatWan(estimated)} 万元';
  }
  final parts = [
    for (final entry in grouped.entries)
      if (entry.value.length == 1)
        '${proposalFormatWan(entry.value.first)} × ${entry.key}'
      else
        '(${[for (final scale in entry.value) proposalFormatWan(scale)].join(' + ')}) × ${entry.key}',
  ];
  return '${parts.join(' + ')} = ${proposalFormatWan(estimated)} 万元';
}

List<String> proposalMatchedProjectCostNames(Map<String, dynamic> form) {
  final seen = <String>{};
  final names = <String>[];
  for (final hit in proposalPayableProjectCostHits(form)) {
    if (seen.add(hit.costName)) names.add(hit.costName);
  }
  return [
    for (final name in kProposalProjectCostItems)
      if (seen.contains(name)) name,
    ...names.where((name) => !kProposalProjectCostItems.contains(name)),
  ];
}

Map<String, dynamic> proposalEnsureProjectCostItems(
  Map<String, dynamic> form, {
  List<ProposalCostItemOption> catalog = const [],
}) {
  final matched = proposalMatchedProjectCostNames(form);
  if (matched.isEmpty) return form;
  final current = [
    for (final name in proposalCostSelectedNames(form, 'costItems'))
      proposalProjectCostDisplayName(name),
  ];
  final want = {...matched, ...current};
  final next = [
    for (final name in kProposalProjectCostItems)
      if (want.contains(name)) name,
    for (final name in current)
      if (!kProposalProjectCostItems.contains(name) && want.contains(name))
        name,
  ];
  if (next.join('\u0001') == current.join('\u0001')) {
    return form;
  }
  return proposalSyncCostSelection(
    form: form,
    names: next,
    catalog: catalog,
    namesKey: 'costItems',
    codesKey: 'costItemCodes',
    amountsKey: 'costItemAmounts',
    totalKey: 'projectCost',
  );
}

double? proposalEstimateProjectCostAmount(
  Map<String, dynamic> form,
  String name, {
  List<ProposalCostItemOption> catalog = const [],
}) {
  final aliases = proposalProjectCostNamesOf(
    proposalProjectCostDisplayName(name),
  );
  var sum = 0.0;
  var any = false;
  for (final hit in proposalPayableProjectCostHits(form)) {
    if (!aliases.contains(hit.costName)) continue;
    final amount = proposalPayableCostLineAmount(form, hit.terms, hit.skuIds);
    if (amount <= 0) continue;
    any = true;
    sum += amount;
  }
  if (!any) return null;
  return proposalRoundWan(sum);
}

Map<String, dynamic> proposalApplyEstimatedProcurement(
  Map<String, dynamic> form,
) {
  if (form[kProposalProcurementManualKey] == true) return form;
  final estimated = proposalEstimatedProcurementCost(form);
  if (estimated == null) return form;
  return Map<String, dynamic>.from(form)
    ..[kProposalCouponProcurementCostKey] = estimated;
}

Map<String, dynamic> proposalApplyEstimatedProjectCosts(
  Map<String, dynamic> form, {
  List<ProposalCostItemOption> catalog = const [],
}) {
  var next = proposalEnsureProjectCostItems(form, catalog: catalog);
  final names = proposalCostSelectedNames(next, 'costItems');
  if (names.isEmpty) return next;
  final amounts = proposalCostAmountMap(next['costItemAmounts']);
  final manual = proposalCostManualIdSet(next[kProposalProjectCostManualKey]);
  var changed = false;
  for (final name in names) {
    final id = proposalCostAmountId(name, catalog);
    if (manual.contains(id) || manual.contains(name)) continue;
    final estimated = proposalEstimateProjectCostAmount(
      next,
      name,
      catalog: catalog,
    );
    if (estimated == null) continue;
    if (amounts[id] == estimated) continue;
    amounts[id] = estimated;
    changed = true;
  }
  if (!changed && identical(next, form)) return form;
  if (!changed) return next;
  return Map<String, dynamic>.from(next)
    ..['costItemAmounts'] = {
      for (final entry in amounts.entries) entry.key: entry.value,
    }
    ..['projectCost'] = proposalCostAmountTotal(amounts);
}

List<String> proposalEnsureAutoTaxItemNames(Map<String, dynamic> form) {
  final names = [...proposalCostSelectedNames(form, 'taxCostItems')];
  final hasStampBase = proposalEffectiveSalesScale(form) > 0;
  final hasVatBase =
      proposalSalesOutputTaxRate(form) > 0 &&
      (proposalEffectiveRevenue(form) != 0 ||
          proposalEffectiveSalesScale(form) > 0);
  if (hasStampBase && !names.contains(kProposalStampTaxName)) {
    names.add(kProposalStampTaxName);
  }
  final hasOperator = names.contains(kProposalVatOperatorName);
  final hasEnergy = names.contains(kProposalVatEnergyName);
  if (hasVatBase && !hasOperator && !hasEnergy) {
    names.add(proposalDefaultVatItemName(form));
  }
  if (hasOperator && hasEnergy) {
    names.remove(kProposalVatEnergyName);
  }
  return names;
}

Map<String, dynamic> proposalEnsureAutoTaxItems(Map<String, dynamic> form) {
  final names = proposalEnsureAutoTaxItemNames(form);
  final current = proposalCostSelectedNames(form, 'taxCostItems');
  if (names.length == current.length && names.every(current.contains)) {
    return form;
  }
  return Map<String, dynamic>.from(form)..['taxCostItems'] = names;
}

Map<String, dynamic> proposalApplyEstimatedFinanceCosts(
  Map<String, dynamic> form, {
  List<ProposalCostItemOption> businessCatalog = const [],
  List<ProposalCostItemOption> costCatalog = const [],
}) {
  var next = proposalApplyTurnoverCash(proposalApplyProductScaleRollup(form));
  next = proposalApplyEstimatedProcurement(next);
  next = proposalApplyEstimatedProjectCosts(next, catalog: costCatalog);
  next = proposalWriteDerivedProfit(next);
  next = proposalEnsureAutoTaxItems(next);
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
  'costItemAmounts' => kProposalProjectCostManualKey,
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
