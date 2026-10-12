import 'dart:convert';

import 'proposal_cost_estimate.dart';
import 'proposal_finance_formula.dart';
import 'proposal_intake_models.dart';

/// 本地调试：把一份提案改成「复核中 · 财务填完整」的 mock 表单。
///
/// - 产品太多看不清：只留前 [keepProducts] 个产品；每个产品结算留 1 条收入 + 最多 3 条应付；
///   关联产品只留挂在这些产品下面的。
/// - 所有负责人都是自己（[me] / [myName]），一个人就能把每个复核按钮都点一遍。
/// - 市场部、科技部、财务部的必填项空着就补一份示例值，已有的保留。
/// - 供给侧结算没有比例就补一条 0.9（采购成本才算得出来），勾上留下来的产品。
/// - 每个产品都选好收入公式、税务成本；业务成本由后端在新建时清掉，复核时由市场部负责人一选。
/// - 财务技术接口全部勾上（提交复核要求必填接口齐全）。
///
/// 生成后由页面调 `notify_tech` → `confirm_tech` 两步把它送进「复核中」。
Map<String, dynamic> proposalIntakeReviewMockForm(
  Map<String, dynamic> source, {
  required int me,
  required String myName,
  ProposalIntakeOptions? options,
  int keepProducts = 2,
}) {
  final form = _deepCopy(source);

  // ---- 产品：只留前几个，结算精简 ----
  final rawSkus = [
    for (final item in (form['skuDetails'] is List
        ? form['skuDetails'] as List
        : const []))
      if (item is Map) Map<String, dynamic>.from(item),
  ];
  if (rawSkus.isEmpty) rawSkus.addAll(_fallbackSkus());
  final kept = [
    for (final raw in rawSkus.take(keepProducts)) _trimSku(raw),
  ];
  form['skuDetails'] = kept;
  final keptIds = [
    for (final raw in kept)
      if ('${raw['id'] ?? ''}'.trim().isNotEmpty) '${raw['id']}'.trim(),
  ];
  form['childProducts'] = [
    for (final child in proposalIntakeChildProducts(form))
      if (keptIds.contains(child.parentSkuId)) child.toJson(),
  ];
  final scale = proposalIntakeSkuDetails(form).fold<double>(
    0,
    (sum, sku) => sum + proposalIntakeSkuScaleTotal(sku),
  );
  if (scale > 0) form['salesScale'] = scale;

  // ---- 负责人：全是自己 ----
  for (final prefix in const [
    'marketOwner1',
    'marketOwner2',
    'technologyOwner',
    'financeOwner1',
    'financeOwner2',
    'operator',
  ]) {
    form['${prefix}UserId'] = me;
    form[prefix] = myName;
  }

  // ---- 市场部 ----
  void fill(String key, Object value) {
    final current = form[key];
    final blank =
        current == null ||
        (current is String && current.trim().isEmpty) ||
        (current is List && current.isEmpty) ||
        (current is Map && current.isEmpty);
    if (blank) form[key] = value;
  }

  final title = '${form['proposalName'] ?? ''}'.trim();
  form['proposalName'] = title.isEmpty
      ? '湖北中石油50元加油权益包（复核mock）'
      : (title.contains('复核mock') ? title : '$title（复核mock）');
  fill('sector', '能源');
  fill('proposalType', '新增');
  fill('product', '加油权益包');
  fill('projectName', '湖北中石油');
  fill('supplies', ['中石油电子券']);
  fill('purchaseName', '中石油电子券采购框架合同（mock）');
  fill('purchaseCoreTerms', '按核销月结，M+2 付款；面值 50 元电子券，采购比例 0.9');
  fill('salesName', '湖北电信中石油权益包销售合同（mock）');
  fill('salesCoreTerms', '按核销月结，M+1 回款；结算比例 0.926');
  fill('supplierPolicy', '供货商按核销量月结，季度对账');
  fill('channelPolicy', '渠道按核销面值 × 0.926 结算');
  fill('profitModes', ['利差']);
  fill('profitFormula', '利差 = 渠道结算 0.926 − 采购 0.9，扣平台服务费、返佣、手续费');
  fill('executionPlan', '11 月上线，首月 50 万规模，3 个月爬坡到 80 万 / 月');
  fill('riskPoints', '核销率低于预期；渠道回款延迟');

  // ---- 科技部 ----
  fill('technologyPlatform', '三桶油');
  fill('outputForms', ['API']);
  fill('developmentTypes', ['配置']);
  fill('hasRdCost', '否');
  fill('deliveryDate', '2026-11-30');
  final interfaces = <String, dynamic>{
    if (form['financeInterfaces'] is Map)
      ...Map<String, dynamic>.from(form['financeInterfaces'] as Map),
    for (final item in options?.financeInterfaces ?? const [])
      item.key: true,
  };
  form['financeInterfaces'] = interfaces;

  // ---- 财务部：结算规则与账户 ----
  fill('channelSettleMode', '按核销月结');
  fill('channelSettleCycle', 'M+1');
  fill('channelPayee', '广州宇天供应链科技有限公司');
  fill('channelReceiveAccount', '招商银行 6214 **** 1024');
  fill('supplySettleMode', '按核销月结');
  fill('supplySettleCycle', 'M+2');
  fill('supplyPayer', '广州宇天供应链科技有限公司');
  fill('supplyPayAccount', '招商银行 6214 **** 2048');
  fill('generalBusinessAccount', '普通业务账（mock）');
  fill('prepaidAccount', '预付款账户（mock）');
  fill(kProposalOperatingCostItemsKey, ['差旅成本']);
  fill(kProposalTurnoverTimesKey, 8);

  // ---- 供给侧采购结算：有比例、勾上留下来的产品 ----
  final supplies = [
    for (final item in (form['supplyProducts'] is List
        ? form['supplyProducts'] as List
        : const []))
      if (item is Map) Map<String, dynamic>.from(item),
  ];
  if (supplies.isEmpty) {
    supplies.add({
      'id': 'mock-sup-1',
      'supplierCode': 'MOCK-SUPPLIER',
      'productCode': 'MOCK-COUPON-50',
      'productName': '中石油50元电子券',
      'settlements': <Map<String, dynamic>>[],
    });
  }
  for (final supply in supplies) {
    final rows = [
      for (final item in (supply['settlements'] is List
          ? supply['settlements'] as List
          : const []))
        if (item is Map) Map<String, dynamic>.from(item),
    ];
    if (rows.isEmpty) rows.add({'id': '${supply['id'] ?? 'sup'}-st'});
    for (final row in rows) {
      final terms = ProposalFinanceSettleTerms.fromJson(row);
      if (terms.displayRatio.trim().isEmpty &&
          terms.displayUnitPrice.trim().isEmpty) {
        row['settleRatio'] = '0.9';
      }
      if ('${row['taxRate'] ?? ''}'.trim().isEmpty) row['taxRate'] = '6%';
      if (!terms.skuIds.any(keptIds.contains)) row['skuIds'] = keptIds;
    }
    supply['settlements'] = rows;
  }
  form['supplyProducts'] = supplies;

  // ---- 每个产品的公式选择 ----
  final formulas = <String, dynamic>{
    if (form[kProposalProductFormulasKey] is Map)
      ...Map<String, dynamic>.from(form[kProposalProductFormulasKey] as Map),
  };
  final next = <String, dynamic>{};
  for (final id in keptIds) {
    final entry = <String, dynamic>{
      if (formulas[id] is Map) ...Map<String, dynamic>.from(formulas[id] as Map),
    };
    entry['owner'] = kProposalProductFinanceMain;
    if ('${entry[kProposalRevenueFormulaKey] ?? ''}'.trim().isEmpty) {
      entry[kProposalRevenueFormulaKey] = '1';
      entry[kProposalRevenueFormulaGroupKey] = 'ENERGY';
    }
    entry['taxCostItems'] = [
      kProposalVatEnergyName,
      kProposalStampTaxName,
      '所得税',
    ];
    entry['businessCostItems'] = ['渠道侧N'];
    entry['businessCostItemFormulas'] = {'渠道侧N': 'BIZ_NET_10'};
    next[id] = entry;
  }
  for (final child in proposalIntakeChildProducts(form)) {
    if (formulas[child.id] is Map) next[child.id] = formulas[child.id];
  }
  form[kProposalProductFormulasKey] = next;
  form[kProposalFinanceFormulaTouchedKey] = {
    kProposalCostCategoryTax: true,
    kProposalCostCategoryBusiness: true,
  };
  return form;
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> source) {
  try {
    final copy = jsonDecode(jsonEncode(source));
    if (copy is Map) return Map<String, dynamic>.from(copy);
  } catch (_) {}
  return Map<String, dynamic>.from(source);
}

/// 一个产品：留 1 条收入 + 最多 3 条应付；收入那条缺规模 / 比例 / 税率就补示例值。
Map<String, dynamic> _trimSku(Map<String, dynamic> raw) {
  final settlements = [
    for (final item in (raw['settlements'] is List
        ? raw['settlements'] as List
        : const []))
      if (item is Map) Map<String, dynamic>.from(item),
  ];
  Map<String, dynamic>? income;
  final costs = <Map<String, dynamic>>[];
  for (final item in settlements) {
    final isCost = ProposalSkuSettleRow.fromJson(item).isCost;
    if (!isCost && income == null) income = item;
    if (isCost && costs.length < 3) costs.add(item);
  }
  final id = '${raw['id'] ?? 'mock-sku'}'.trim();
  income ??= {'id': '$id-in'};
  final terms = ProposalFinanceSettleTerms.fromJson(income);
  if (terms.scale.trim().isEmpty) income['scale'] = '300';
  if (terms.displayRatio.trim().isEmpty && terms.displayUnitPrice.trim().isEmpty) {
    income['settleRatio'] = '0.926';
  }
  if ('${income['taxRate'] ?? ''}'.trim().isEmpty) income['taxRate'] = '6%';
  if (costs.isEmpty) {
    costs.addAll([
      {'id': '$id-c1', 'kind': 'cost', 'billType': '平台交易服务费', 'settleRatio': '0.004'},
      {'id': '$id-c2', 'kind': 'cost', 'billType': '机构返佣', 'settleRatio': '0.01'},
      {'id': '$id-c3', 'kind': 'cost', 'billType': '支付手续费', 'settleRatio': '0.005'},
    ]);
  }
  return {
    ...raw,
    'settlements': [income, ...costs],
  };
}

List<Map<String, dynamic>> _fallbackSkus() => [
  {
    'id': 'mock-sku-1',
    'productName': '湖北中石油50元加油权益包',
    'faceValue': '50',
    'settlements': <Map<String, dynamic>>[],
  },
  {
    'id': 'mock-sku-2',
    'productName': '湖北中石油100元加油权益包',
    'faceValue': '100',
    'settlements': <Map<String, dynamic>>[],
  },
];
