import 'dart:math' as math;

import 'proposal_cost_estimate.dart';
import 'proposal_intake_models.dart';

/// 销售提案「财务部」按公式测算。
///
/// 财务部不再手填金额：每个产品（主产品、子产品都拆）各选收入公式和
/// 项目 / 业务 / 税务成本项及公式，按产品分别测算再加总，
/// 利润 = 收入 − 项目成本 − 业务成本 − 税务成本。
/// 经营成本整单只选类型，不计金额、不进利润。
/// 字典（收入公式、成本项、成本公式）由后端 `options.finance.formulaCatalog`
/// 下发；后端没给时用本文件里的兜底字典。

/// 利润是否测算。收入公式里的业务量、补贴、利差等提案取不到真实值（见 test/proposal_finance_formula_mock_test.dart），
/// 算出的利润不可信，先停掉：不显示利润 / 毛利率；项目、业务、税务成本和利润仍按当前口径测算回写。
/// 改成 true 即恢复利润块和各处利润数字。
const kProposalFinanceShowProfit = false;

const kProposalRevenueFormulaKey = 'revenueFormula';
const kProposalRevenueFormulaGroupKey = 'revenueFormulaGroup';
const kProposalFinanceFormulaTouchedKey = 'financeFormulaTouched';

/// 旧版单套推广费阶梯：{basis, mode, tiers: [{from, rate}]}。只读兼容，新数据写 [kProposalPromotionPlansKey]。
const kProposalPromotionTiersKey = 'promotionTiers';

/// 推广费方案列表（每个产品一个推广商）：
/// [{id, promoter, strategy: fixed|monthSeq, segments: [{fromMonth, toMonth, type: tier|fixed, mode, tiers: [{from, rate}], rate}]}]。
/// 档位起点单位万元（月规模），比例为小数（0.5 即 50%）。
const kProposalPromotionPlansKey = 'promotionPlans';

/// 按产品存的公式选择：{skuId: {revenueFormula, costItems, promotionPlans, …}}。
const kProposalProductFormulasKey = 'productFormulas';

/// 经营成本类型（整单一份，只选类型）。
const kProposalOperatingCostItemsKey = 'operatingCostItems';

const kProposalCostCategoryProject = 'project';
const kProposalCostCategoryBusiness = 'business';
const kProposalCostCategoryOperating = 'operating';
const kProposalCostCategoryTax = 'tax';

/// 参与测算的成本类，按计算顺序：项目 → 业务 → 税务。后面的公式会用到前面的合计。
/// 经营成本只选类型，不参与测算。
const kProposalCostCategoryOrder = <String>[
  kProposalCostCategoryProject,
  kProposalCostCategoryBusiness,
  kProposalCostCategoryTax,
];

/// 字典里的成本类顺序：项目 → 业务 → 经营 → 税务。
const kProposalCostCategoryDisplayOrder = <String>[
  kProposalCostCategoryProject,
  kProposalCostCategoryBusiness,
  kProposalCostCategoryOperating,
  kProposalCostCategoryTax,
];

/// 每个产品自己的公式选择字段（存在 `productFormulas[skuId]` 里）。
const kProposalProductFormulaEntryKeys = <String>[
  kProposalRevenueFormulaKey,
  kProposalRevenueFormulaGroupKey,
  kProposalFinanceFormulaTouchedKey,
  kProposalPromotionPlansKey,
  'costItems',
  'costItemFormulas',
  'businessCostItems',
  'businessCostItemFormulas',
  'taxCostItems',
  'taxCostItemFormulas',
];

const kProposalProductFormulaBusinessKeys = <String>[
  'businessCostItems',
  'businessCostItemFormulas',
];

/// 公式写入表单的字段。
const kProposalFinanceFormulaFormKeys = <String>[
  kProposalProductFormulasKey,
  kProposalRevenueFormulaKey,
  kProposalRevenueFormulaGroupKey,
  kProposalFinanceFormulaTouchedKey,
  kProposalPromotionTiersKey,
  'costItemFormulas',
  'businessCostItemFormulas',
  'taxCostItemFormulas',
];

abstract final class ProposalFinanceFormulaKind {
  static const expression = 'EXPRESSION';
  static const settleScale = 'SETTLE_SCALE';
  static const settleRevenue = 'SETTLE_REVENUE';
  static const scaleRate = 'SCALE_RATE';
  static const revenueRate = 'REVENUE_RATE';
  static const grossRate = 'GROSS_RATE';
  static const netOpRate = 'NET_OP_RATE';
  static const pretaxRate = 'PRETAX_RATE';
  static const vat = 'VAT';
  static const tiered = 'TIERED';
  static const profit = 'PROFIT';
  static const margin = 'MARGIN';
}

String _str(Object? raw) => raw == null ? '' : '$raw'.trim();

List<dynamic> _listOf(Object? raw) => raw is List ? raw : const [];

Map<String, dynamic> _mapOf(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

double _num(Object? raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse(_str(raw)) ?? 0;
}

class ProposalFinanceFormula {
  const ProposalFinanceFormula({
    required this.code,
    required this.name,
    this.expression = '',
    this.kind = ProposalFinanceFormulaKind.expression,
    this.rate = 0,
    this.settleMethodName = '',
    this.syncSources = const [],
    this.pending = false,
  });

  final String code;
  final String name;
  final String expression;
  final String kind;
  final double rate;
  final String settleMethodName;
  final List<String> syncSources;

  /// 规则还在设计中（如阶梯推广费），金额按 0 计、页面标「设计中」。
  final bool pending;

  bool get isEmpty => code.isEmpty;

  /// 资管公式名和表达式大多相同，只有不同时才在下拉里多显示一行。
  String get detail =>
      expression.isEmpty || expression == name ? '' : expression;

  factory ProposalFinanceFormula.fromJson(Object? raw) {
    final map = _mapOf(raw);
    final kind = _str(map['kind']);
    return ProposalFinanceFormula(
      code: _str(map['code'] ?? map['formulaCode']),
      name: _str(map['name'] ?? map['formulaName']),
      expression: _str(map['expression'] ?? map['formulaExpression']),
      kind: kind.isEmpty ? ProposalFinanceFormulaKind.expression : kind,
      rate: _num(map['rate']),
      settleMethodName: _str(map['settleMethodName']),
      syncSources: [
        for (final item in _listOf(map['syncSources']))
          if (_str(item).isNotEmpty) _str(item),
      ],
      pending: map['pending'] == true,
    );
  }
}

class ProposalRevenueFormulaGroup {
  const ProposalRevenueFormulaGroup({
    required this.key,
    required this.name,
    this.syncSources = const [],
    this.formulas = const [],
  });

  final String key;
  final String name;
  final List<String> syncSources;
  final List<ProposalFinanceFormula> formulas;

  ProposalFinanceFormula? formulaOf(String code) {
    for (final formula in formulas) {
      if (formula.code == code) return formula;
    }
    return null;
  }

  factory ProposalRevenueFormulaGroup.fromJson(Object? raw) {
    final map = _mapOf(raw);
    return ProposalRevenueFormulaGroup(
      key: _str(map['key']),
      name: _str(map['name']),
      syncSources: [
        for (final item in _listOf(map['syncSources']))
          if (_str(item).isNotEmpty) _str(item),
      ],
      formulas: [
        for (final item in _listOf(map['formulas']))
          ProposalFinanceFormula.fromJson(item),
      ].where((item) => !item.isEmpty).toList(growable: false),
    );
  }
}

class ProposalCostTypeOption {
  const ProposalCostTypeOption({
    required this.code,
    required this.name,
    this.formulas = const [],
    this.defaultFormula = '',
    this.tiered = false,
    this.exclusiveGroup = '',
    this.hint = '',
  });

  final String code;
  final String name;
  final List<ProposalFinanceFormula> formulas;
  final String defaultFormula;
  final bool tiered;
  final String exclusiveGroup;
  final String hint;

  ProposalFinanceFormula? formulaOf(String code) {
    for (final formula in formulas) {
      if (formula.code == code) return formula;
    }
    return null;
  }

  ProposalFinanceFormula? get defaultFormulaRef =>
      formulaOf(defaultFormula) ?? (formulas.isEmpty ? null : formulas.first);

  factory ProposalCostTypeOption.fromJson(Object? raw) {
    final map = _mapOf(raw);
    final name = _str(map['name']);
    final code = _str(map['code']);
    return ProposalCostTypeOption(
      code: code.isEmpty ? name : code,
      name: name,
      formulas: [
        for (final item in _listOf(map['formulas']))
          ProposalFinanceFormula.fromJson(item),
      ].where((item) => !item.isEmpty).toList(growable: false),
      defaultFormula: _str(map['defaultFormula']),
      tiered: map['tiered'] == true,
      exclusiveGroup: _str(map['exclusiveGroup']),
      hint: _str(map['hint']),
    );
  }
}

class ProposalCostCategory {
  const ProposalCostCategory({
    required this.key,
    required this.name,
    required this.namesKey,
    required this.amountsKey,
    required this.totalKey,
    required this.formulasKey,
    this.filler = '',
    this.hint = '',
    this.items = const [],
  });

  final String key;
  final String name;
  final String namesKey;
  final String amountsKey;
  final String totalKey;
  final String formulasKey;

  /// 谁来选这一类，例如「市场部负责人一在财务复核时选择」。
  final String filler;
  final String hint;
  final List<ProposalCostTypeOption> items;

  ProposalCostTypeOption? itemOf(String name) {
    final display = proposalProjectCostDisplayName(name);
    for (final item in items) {
      if (item.name == name || item.name == display) return item;
    }
    return null;
  }

  /// 名单里没有的历史成本项：按本类第一项的公式处理，保证还能算。
  ProposalCostTypeOption resolveItem(String name) {
    final hit = itemOf(name);
    if (hit != null) return hit;
    final template = items.isEmpty ? null : items.first;
    return ProposalCostTypeOption(
      code: name,
      name: name,
      formulas: template?.formulas ?? const [],
      defaultFormula: template?.defaultFormula ?? '',
    );
  }

  factory ProposalCostCategory.fromJson(Object? raw) {
    final map = _mapOf(raw);
    return ProposalCostCategory(
      key: _str(map['key']),
      name: _str(map['name']),
      namesKey: _str(map['namesKey']),
      amountsKey: _str(map['amountsKey']),
      totalKey: _str(map['totalKey']),
      formulasKey: _str(map['formulasKey']),
      filler: _str(map['filler']),
      hint: _str(map['hint']),
      items: [
        for (final item in _listOf(map['items']))
          ProposalCostTypeOption.fromJson(item),
      ].where((item) => item.name.isNotEmpty).toList(growable: false),
    );
  }
}

class ProposalFinanceFormulaCatalog {
  const ProposalFinanceFormulaCatalog({
    this.source = '',
    this.revenueGroups = const [],
    this.profitFormula = const ProposalFinanceFormula(
      code: 'PROFIT_STD',
      name: '利润',
      expression: kProposalProfitFormula,
      kind: ProposalFinanceFormulaKind.profit,
    ),
    this.marginFormula = const ProposalFinanceFormula(
      code: 'MARGIN_STD',
      name: '毛利率',
      expression: '利润 ÷ 销售规模 × 100%',
      kind: ProposalFinanceFormulaKind.margin,
    ),
    this.costCategories = const [],
  });

  /// `asset`：收入公式来自资管实时字典；`fallback`：资管不可达，用快照。
  final String source;
  final List<ProposalRevenueFormulaGroup> revenueGroups;
  final ProposalFinanceFormula profitFormula;
  final ProposalFinanceFormula marginFormula;
  final List<ProposalCostCategory> costCategories;

  bool get isFallback => source != 'asset';

  ProposalCostCategory? category(String key) {
    for (final item in costCategories) {
      if (item.key == key) return item;
    }
    return null;
  }

  ProposalRevenueFormulaGroup? group(String key) {
    for (final item in revenueGroups) {
      if (item.key == key) return item;
    }
    return null;
  }

  /// 收入、项目成本、业务成本共用的计算公式，按编码去重。
  List<ProposalFinanceFormula> get settlementFormulas {
    final byCode = <String, ProposalFinanceFormula>{};
    for (final group in revenueGroups) {
      for (final formula in group.formulas) {
        if (formula.code.trim().isEmpty) continue;
        byCode.putIfAbsent(formula.code, () => formula);
      }
    }
    return byCode.values.toList(growable: false);
  }

  ProposalFinanceFormula? formulaByCode(String code) {
    final key = code.trim();
    if (key.isEmpty) return null;
    for (final formula in settlementFormulas) {
      if (formula.code == key) return formula;
    }
    return null;
  }

  /// 产品业务平台对应的公式组；一个都对不上时返回全部组。
  List<ProposalRevenueFormulaGroup> groupsForSources(Set<String> sources) {
    final hits = [
      for (final group in revenueGroups)
        if (group.syncSources.any(sources.contains)) group,
    ];
    return hits.isEmpty ? revenueGroups : hits;
  }

  /// 后端字典缺哪块就用兜底补哪块，页面永远有得选。
  factory ProposalFinanceFormulaCatalog.fromJson(Object? raw) {
    final map = _mapOf(raw);
    final fallback = ProposalFinanceFormulaCatalog.fallback;
    if (map.isEmpty) return fallback;
    final groups = [
      for (final item in _listOf(map['revenueGroups']))
        ProposalRevenueFormulaGroup.fromJson(item),
    ].where((item) => item.key.isNotEmpty).toList(growable: false);
    final categories = [
      for (final item in _listOf(map['costCategories']))
        ProposalCostCategory.fromJson(item),
    ].where((item) => item.key.isNotEmpty).toList(growable: false);
    final profit = ProposalFinanceFormula.fromJson(map['profitFormula']);
    final margin = ProposalFinanceFormula.fromJson(map['marginFormula']);
    final resolved = <ProposalCostCategory>[];
    for (final key in kProposalCostCategoryDisplayOrder) {
      final hit = categories.where((item) => item.key == key).firstOrNull;
      final picked = hit ?? fallback.category(key);
      if (picked != null) resolved.add(picked);
    }
    return ProposalFinanceFormulaCatalog(
      source: _str(map['source']),
      revenueGroups: groups.isEmpty ? fallback.revenueGroups : groups,
      profitFormula: profit.isEmpty ? fallback.profitFormula : profit,
      marginFormula: margin.isEmpty ? fallback.marginFormula : margin,
      costCategories: resolved,
    );
  }

  static final ProposalFinanceFormulaCatalog fallback = _buildFallbackCatalog();
}

// ---------------------------------------------------------------------------
// 兜底字典：与后端 proposal_intake_finance_formula.go 保持一致。
// 收入公式为 2026-10-11 资管生产环境渠道侧快照。
// ---------------------------------------------------------------------------

const _kRatioMethod = '按结算比例结算';
const _kUnitMethod = '按结算单价';
const _kUnitRatioMethod = '按结算单价*结算比例';
const _kFormula4 =
    '（利差+SaaS服务费+抵扣延期分润-机构返佣-平台服务费-支付手续费-渠道侧N-渠道侧H-供给侧N-供给侧H）*结算比例';

ProposalFinanceFormula _f(
  String code,
  String name,
  String expression, [
  String method = _kRatioMethod,
]) => ProposalFinanceFormula(
  code: code,
  name: name,
  expression: expression,
  settleMethodName: method,
);

/// 项目成本只有一种算法：按产品结算里对应的「应付」行（规模 × 比例）。
/// 比例、票种、税率都在产品结算里，这里不再重复让人选公式。
const kProposalProjectSettleFormulaCode = 'PRJ_SETTLE_SCALE';

const _kProjectCostFormulas = <ProposalFinanceFormula>[
  ProposalFinanceFormula(
    code: kProposalProjectSettleFormulaCode,
    name: '按产品结算',
    expression: '关联产品年化规模 × 产品结算里该应付行的比例（单价结算为 单价 ÷ 面值）',
    kind: ProposalFinanceFormulaKind.settleScale,
  ),
];

const _kPromotionTierFormula = ProposalFinanceFormula(
  code: 'PROMO_TIER',
  name: '阶梯推广费',
  expression:
      '按推广商配置：按固定比例（年化规模 × 比例），或年阶梯（按年化规模分档），或连续月序配置（各月份段按月规模阶梯或固定比例，逐月加总 12 个月）',
  kind: ProposalFinanceFormulaKind.tiered,
);

const _kBusinessCostFormulas = <ProposalFinanceFormula>[
  ProposalFinanceFormula(
    code: 'BIZ_NET_10',
    name: '（收入 − 项目成本）× 10%',
    expression: '(收入 − 项目成本) × 10%',
    kind: ProposalFinanceFormulaKind.netOpRate,
    rate: 0.10,
  ),
  ProposalFinanceFormula(
    code: 'BIZ_NET_45',
    name: '（收入 − 项目成本）× 45%',
    expression: '(收入 − 项目成本) × 45%',
    kind: ProposalFinanceFormulaKind.netOpRate,
    rate: 0.45,
  ),
];

const _kVatFormulas = <ProposalFinanceFormula>[
  ProposalFinanceFormula(
    code: 'TAX_VAT',
    name: '（销项税 − 进项税）× 1.12',
    expression: '(销项税 − 进项税) × 1.12；销项按各销售结算规模 × 比例 × 税率，进项按项目成本 × 可抵扣税率',
    kind: ProposalFinanceFormulaKind.vat,
  ),
];

const _kStampFormulas = <ProposalFinanceFormula>[
  ProposalFinanceFormula(
    code: 'TAX_STAMP_SCALE',
    name: '销售规模 × 0.06%',
    expression: '销售规模 × 0.0006',
    kind: ProposalFinanceFormulaKind.scaleRate,
    rate: 0.0006,
  ),
];

const _kIncomeTaxFormulas = <ProposalFinanceFormula>[
  ProposalFinanceFormula(
    code: 'TAX_INCOME_25',
    name: '应税利润 × 25%',
    expression: '(收入 − 项目成本 − 业务成本) × 25%',
    kind: ProposalFinanceFormulaKind.pretaxRate,
    rate: 0.25,
  ),
  ProposalFinanceFormula(
    code: 'TAX_INCOME_15',
    name: '应税利润 × 15%（高新技术企业）',
    expression: '(收入 − 项目成本 − 业务成本) × 15%',
    kind: ProposalFinanceFormulaKind.pretaxRate,
    rate: 0.15,
  ),
];

const _kDefaultProjectCostNames = <String>[
  '机构返佣',
  '万里通返佣',
  '补贴款分润',
  '平台交易服务费',
  '渠道服务费分润',
  '支付手续费',
  '推广费',
  '券使用成本',
  '技术对接费',
];

const _kDefaultBusinessCostNames = <String>[
  '渠道侧N',
  '渠道侧H',
  '供给侧N',
  '供给侧H',
  '渠道侧U',
  '供给侧U',
];

ProposalCostTypeOption _projectCostOption(String name) {
  if (name == '推广费') {
    return const ProposalCostTypeOption(
      code: '推广费',
      name: '推广费',
      formulas: [_kPromotionTierFormula],
      defaultFormula: 'PROMO_TIER',
      tiered: true,
      hint:
          '推广费按推广商配置：选按固定比例、年阶梯，或连续月序配置（如第 1–3 个月阶梯、第 4 个月及以后固定比例）。年阶梯按年化规模分档；月序档位按月规模。档位单位万元，比例写小数（0.5 即 50%）。',
    );
  }
  return ProposalCostTypeOption(
    code: name,
    name: name,
    formulas: _kProjectCostFormulas,
    defaultFormula: kProposalProjectSettleFormulaCode,
  );
}

ProposalCostTypeOption _businessCostOption(String name) {
  return ProposalCostTypeOption(
    code: name,
    name: name,
    formulas: _kBusinessCostFormulas,
    defaultFormula: name.toUpperCase().endsWith('U')
        ? 'BIZ_NET_45'
        : 'BIZ_NET_10',
  );
}

ProposalFinanceFormulaCatalog _buildFallbackCatalog() {
  final groups = <ProposalRevenueFormulaGroup>[
    ProposalRevenueFormulaGroup(
      key: 'OPERATOR',
      name: '运营商',
      syncSources: const ['CX_BENEFIT', 'CX_CARD_DATA', 'CX_MEMBER'],
      formulas: [
        _f('3', '销售面值*结算比例', '销售(面值) * 结算比例'),
        _f('15', '（会员销售款-推广费-利差）*结算比例', '（会员销售款-推广费-利差）*结算比例'),
        _f('23', '按下发统计结算单价', '按下发统计结算单价', _kUnitMethod),
      ],
    ),
    ProposalRevenueFormulaGroup(
      key: 'ENERGY',
      name: '能源',
      syncSources: const ['DIGITALG', 'MY'],
      formulas: [
        _f('1', '核销面值*结算比例', '核销(面值) * 结算比例'),
        _f('2', '（销售-退款）*结算比例', '(销售-退款) * 结算比例'),
        _f('3', '销售面值*结算比例', '销售(面值) * 结算比例'),
        _f('4', _kFormula4, _kFormula4),
        _f('8', '核销实际支付金额*结算比例', '核销实际支付金额 * 结算比例'),
        _f('16', '现金*结算比例', '现金 × 结算比例'),
        _f('17', '补贴*结算比例', '补贴 × 结算比例'),
        _f('18', '（现金+补贴）*结算比例', '（现金+补贴）× 结算比例'),
        _f('19', '油枪价*结算比例', '油枪价 × 结算比例'),
        _f('23', '按下发统计结算单价', '按下发统计结算单价', _kUnitMethod),
        _f('24', '按核销统计结算单价', '按核销统计结算单价', _kUnitMethod),
        _f('35', '渠道服务费*结算比例', '渠道服务费 × 结算比例'),
        _f(
          '37',
          '引流金额*结算比例-(销售-退款)*(1-电子券销售款结算比例)',
          '引流金额 * 结算比例 - (销售-退款) * (1 - 电子券销售款结算比例)',
        ),
        _f('38', '溢价*结算比例', '溢价 × 结算比例'),
        _f('39', '（销售-退款）实际支付金额*结算比例', '（销售-退款）实际支付金额 × 结算比例'),
      ],
    ),
    ProposalRevenueFormulaGroup(
      key: 'REBATE_POWER_MOBILE',
      name: '积分返费 / 星和动力 / 移动运营商',
      syncSources: const [
        'POINTS_REBATE',
        'POWER_PACKET',
        'POWER_COUPON',
        'POWER_MEMBER',
        'YD',
      ],
      formulas: [
        _f('1', '核销面值*结算比例', '核销(面值) * 结算比例'),
        _f('2', '（销售-退款）*结算比例', '(销售-退款) * 结算比例'),
        _f('3', '销售面值*结算比例', '销售(面值) * 结算比例'),
        _f('4', _kFormula4, _kFormula4),
        _f('8', '核销实际支付金额*结算比例', '核销实际支付金额 * 结算比例'),
        _f('9', '按下发统计结算单价*结算比例', '按下发统计结算单价 * 结算比例', _kUnitRatioMethod),
        _f('11', '兑换金额*结算比例', '兑换金额 * 结算比例'),
        _f('12', '积分/返费采购款*结算比例', '积分/返费采购款 * 结算比例'),
        _f('21', '（券包销售款-推广费+利差）*结算比例', '（券包销售款-推广费+利差） * 结算比例'),
        _f('23', '按下发统计结算单价', '按下发统计结算单价', _kUnitMethod),
        _f('24', '按核销统计结算单价', '按核销统计结算单价', _kUnitMethod),
        _f('34', '（券包销售款-推广费+利差-渠道侧N）*结算比例', '（券包销售款-推广费+利差-渠道侧N）*结算比例'),
        _f('39', '（销售-退款）实际支付金额*结算比例', '（销售-退款）实际支付金额 × 结算比例'),
      ],
    ),
  ];

  return ProposalFinanceFormulaCatalog(
    source: 'fallback',
    revenueGroups: groups,
    costCategories: [
      ProposalCostCategory(
        key: kProposalCostCategoryProject,
        name: '项目成本',
        namesKey: 'costItems',
        amountsKey: 'costItemAmounts',
        totalKey: 'projectCost',
        formulasKey: 'costItemFormulas',
        filler: '产品结算里的应付行自动带出；其余由填写人补选，提交后财务部负责人二确认',
        hint: '金额按产品结算算，比例、票种、税率以产品结算为准。',
        items: [
          for (final name in _kDefaultProjectCostNames)
            _projectCostOption(name),
        ],
      ),
      ProposalCostCategory(
        key: kProposalCostCategoryBusiness,
        name: '业务成本',
        namesKey: 'businessCostItems',
        amountsKey: 'businessCostItemAmounts',
        totalKey: 'businessCost',
        formulasKey: 'businessCostItemFormulas',
        filler: '财务部负责人一多选公式；仅财务部负责人一和最终审批人可见',
        items: [
          for (final name in _kDefaultBusinessCostNames)
            _businessCostOption(name),
        ],
      ),
      const ProposalCostCategory(
        key: kProposalCostCategoryOperating,
        name: '经营成本',
        namesKey: 'operatingCostItems',
        amountsKey: 'operatingCostItemAmounts',
        totalKey: 'operatingCost',
        formulasKey: 'operatingCostItemFormulas',
        filler: '填写人选择',
        hint: '只选类型，不计金额。',
        items: [
          ProposalCostTypeOption(code: '差旅成本', name: '差旅成本'),
          ProposalCostTypeOption(code: '招待费', name: '招待费'),
        ],
      ),
      const ProposalCostCategory(
        key: kProposalCostCategoryTax,
        name: '税务成本',
        namesKey: 'taxCostItems',
        amountsKey: 'taxCostItemAmounts',
        totalKey: 'taxCost',
        formulasKey: 'taxCostItemFormulas',
        filler: '填写人选择',
        hint: '增值税及附加两种口径只选一种；印花税、所得税可另选。',
        items: [
          ProposalCostTypeOption(
            code: kProposalVatEnergyName,
            name: kProposalVatEnergyName,
            formulas: _kVatFormulas,
            defaultFormula: 'TAX_VAT',
            exclusiveGroup: 'VAT',
            hint: '与「增值税及附加（运营商+公共出行）」二选一',
          ),
          ProposalCostTypeOption(
            code: kProposalVatOperatorName,
            name: kProposalVatOperatorName,
            formulas: _kVatFormulas,
            defaultFormula: 'TAX_VAT',
            exclusiveGroup: 'VAT',
            hint: '与「增值税及附加（能源）」二选一',
          ),
          ProposalCostTypeOption(
            code: kProposalStampTaxName,
            name: kProposalStampTaxName,
            formulas: _kStampFormulas,
            defaultFormula: 'TAX_STAMP_SCALE',
          ),
          ProposalCostTypeOption(
            code: '所得税',
            name: '所得税',
            formulas: _kIncomeTaxFormulas,
            defaultFormula: 'TAX_INCOME_25',
          ),
        ],
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// 推广费阶梯
// ---------------------------------------------------------------------------

/// 测算按 12 个月算：月份段超出第 12 个月的部分不计。
const kProposalPromotionMonths = 12;

const kProposalPromotionStrategyFixed = 'fixed';
const kProposalPromotionStrategyAnnual = 'annual';
const kProposalPromotionStrategyMonthSeq = 'monthSeq';

const _promotionUnset = Object();

/// 推广费比例按小数写，0.5 即 50%。
String proposalFormatPromotionRate(double rate) {
  if (rate.isNaN || rate.isInfinite || rate == 0) return '0';
  var text = rate.toStringAsFixed(6);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  return text.replaceFirst(RegExp(r'\.$'), '');
}

/// 一档：月规模达到 [from]（万元）起，按 [rate] 计（小数，0.5 即 50%）。
class ProposalPromotionTier {
  const ProposalPromotionTier({required this.from, required this.rate});

  final double from;
  final double rate;

  Map<String, dynamic> toJson() => {'from': from, 'rate': rate};
}

/// 一段月份规则：第 [fromMonth] 到第 [toMonth] 个月（[toMonth] 为空表示及以后）。
///
/// - [type] `tier` 按月规模分档：[mode] `whole` 全额累进——落在哪档，整月规模按该档比例；
///   `excess` 超额累进——每一段规模按各自档位比例，再加总。
/// - [type] `fixed` 月规模 × 固定比例 [rate]。
class ProposalPromotionSegment {
  const ProposalPromotionSegment({
    this.fromMonth = 1,
    this.toMonth,
    this.type = 'tier',
    this.mode = 'whole',
    this.tiers = const [],
    this.rate = 0,
  });

  final int fromMonth;
  final int? toMonth;
  final String type;
  final String mode;
  final List<ProposalPromotionTier> tiers;
  final double rate;

  bool get tiered => type != 'fixed';
  bool get excess => mode == 'excess';

  bool covers(int month) =>
      month >= fromMonth && (toMonth == null || month <= toMonth!);

  String get monthsLabel {
    if (toMonth == null) return '第 $fromMonth 个月及以后';
    if (toMonth == fromMonth) return '第 $fromMonth 个月';
    return '第 $fromMonth–$toMonth 个月';
  }

  String get summary => tiered
      ? '${tiers.length} 档${excess ? '超额累进' : '全额累进'}'
      : '固定比例 ${proposalFormatPromotionRate(rate)}';

  List<ProposalPromotionTier> get sorted =>
      [...tiers]..sort((a, b) => a.from.compareTo(b.from));

  factory ProposalPromotionSegment.fromJson(Object? raw) {
    final map = _mapOf(raw);
    final from = _num(map['fromMonth']).round();
    final to = _str(map['toMonth']).isEmpty
        ? null
        : _num(map['toMonth']).round();
    return ProposalPromotionSegment(
      fromMonth: from < 1 ? 1 : from,
      toMonth: to,
      type: _str(map['type']) == 'fixed' ? 'fixed' : 'tier',
      mode: _str(map['mode']) == 'excess' ? 'excess' : 'whole',
      tiers: [
        for (final item in _listOf(map['tiers']))
          ProposalPromotionTier(
            from: _num(_mapOf(item)['from']),
            rate: _num(_mapOf(item)['rate']),
          ),
      ],
      rate: _num(map['rate']),
    );
  }

  Map<String, dynamic> toJson() => {
    'fromMonth': fromMonth,
    'toMonth': toMonth,
    'type': type,
    if (tiered) 'mode': mode,
    if (tiered) 'tiers': [for (final tier in tiers) tier.toJson()],
    if (!tiered) 'rate': rate,
  };

  ProposalPromotionSegment copyWith({
    int? fromMonth,
    Object? toMonth = _promotionUnset,
    String? type,
    String? mode,
    List<ProposalPromotionTier>? tiers,
    double? rate,
  }) => ProposalPromotionSegment(
    fromMonth: fromMonth ?? this.fromMonth,
    toMonth: identical(toMonth, _promotionUnset)
        ? this.toMonth
        : toMonth as int?,
    type: type ?? this.type,
    mode: mode ?? this.mode,
    tiers: tiers ?? this.tiers,
    rate: rate ?? this.rate,
  );

  /// 月规模落在第几档（按 [sorted] 的下标）；一档都没到或不是阶梯为 -1。
  int hitIndex(double monthlyScale) {
    if (!tiered) return -1;
    final list = sorted;
    var hit = -1;
    for (var i = 0; i < list.length; i++) {
      if (monthlyScale >= list[i].from) hit = i;
    }
    return hit;
  }

  /// 一个月的推广费（万元）和代入过程。档位按月规模比较。
  ({double fee, String detail}) monthlyFee(double monthlyScale) =>
      scaledFee(monthlyScale, volumeName: '月规模');

  /// 按 [volume]（万元）套档位。[volumeName] 写进代入过程，月阶梯用「月规模」，年阶梯用「年化规模」。
  ({double fee, String detail}) scaledFee(
    double volume, {
    required String volumeName,
  }) {
    final volumeText = _wan(volume);
    if (!tiered) {
      final fee = volume * rate;
      return (
        fee: fee,
        detail:
            '固定比例：$volumeText × ${proposalFormatPromotionRate(rate)} = ${_wan(fee)} 万',
      );
    }
    final list = sorted;
    final hit = hitIndex(volume);
    if (list.isEmpty) return (fee: 0, detail: '未配置档位，按 0 计');
    if (hit < 0) {
      return (
        fee: 0,
        detail:
            '$volumeName $volumeText 万，未达到第 1 档（≥ ${_wan(list.first.from)} 万），按 0 计',
      );
    }
    if (excess) {
      var fee = 0.0;
      final parts = <String>[];
      for (var i = 0; i <= hit; i++) {
        final lower = list[i].from;
        final upper = i + 1 < list.length ? list[i + 1].from : double.infinity;
        final part = (volume < upper ? volume : upper) - lower;
        if (part <= 0) continue;
        fee += part * list[i].rate;
        parts.add(
          '${_wan(part)} × ${proposalFormatPromotionRate(list[i].rate)}',
        );
      }
      return (
        fee: fee,
        detail:
            '$volumeName $volumeText 万，超额累进：${parts.join(' + ')} = ${_wan(fee)} 万',
      );
    }
    final rateLabel = proposalFormatPromotionRate(list[hit].rate);
    final fee = volume * list[hit].rate;
    return (
      fee: fee,
      detail:
          '$volumeName $volumeText 万，落在第 ${hit + 1} 档（≥ ${_wan(list[hit].from)} 万，$rateLabel），全额累进：$volumeText × $rateLabel = ${_wan(fee)} 万',
    );
  }
}

/// 推广费方案：每个产品配一个推广商。
///
/// - [strategy] `fixed` 按固定比例：年化规模 × 比例，存成一段 `fixed` 的 [segments]。
/// - [strategy] `annual` 年阶梯：档位按年化规模（万元）比较，全额或超额累进，只算一次，不分月份。
/// - [strategy] `monthSeq` 连续月序配置：按月份段分别配阶梯或固定比例，例如第 1–3 个月阶梯、
///   第 4 个月及以后固定 0.5；月规模 = 年化规模 ÷ 12，逐月算出后加总 [kProposalPromotionMonths] 个月。
///
/// 旧数据 `{basis, mode, tiers}` 的比例是百分数，读的时候转成小数，按年规模分档的档位折成月规模。
class ProposalPromotionTierPlan {
  const ProposalPromotionTierPlan({
    this.id = '',
    this.name = '',
    this.promoter = '',
    this.strategy = kProposalPromotionStrategyMonthSeq,
    this.segments = const [],
  });

  /// 新建时的默认：按固定比例一段。
  static const fixedSegments = [ProposalPromotionSegment(type: 'fixed')];

  /// 新建时的默认：年阶梯一档，起点 0。
  static const annualSegments = [
    ProposalPromotionSegment(tiers: [ProposalPromotionTier(from: 0, rate: 0)]),
  ];

  /// 新建时的默认：第 1–3 个月阶梯，第 4 个月及以后固定比例。
  static const monthSeqSegments = [
    ProposalPromotionSegment(
      fromMonth: 1,
      toMonth: 3,
      tiers: [ProposalPromotionTier(from: 0, rate: 0)],
    ),
    ProposalPromotionSegment(fromMonth: 4, type: 'fixed'),
  ];

  final String id;
  final String name;
  final String promoter;
  final String strategy;
  final List<ProposalPromotionSegment> segments;

  bool get fixed => strategy == kProposalPromotionStrategyFixed;

  bool get annual => strategy == kProposalPromotionStrategyAnnual;

  bool get isEmpty =>
      segments.isEmpty ||
      segments.every((segment) => segment.tiered && segment.tiers.isEmpty);

  String get label =>
      promoter.isNotEmpty ? promoter : (name.isNotEmpty ? name : '推广商未填');

  double get fixedRate => segments.isEmpty ? 0 : segments.first.rate;

  String get summary => fixed
      ? '按固定比例 ${proposalFormatPromotionRate(fixedRate)}'
      : annual
      ? '年阶梯：${segments.isEmpty ? '未配置档位' : segments.first.summary}'
      : '连续月序配置：${[for (final s in segments) '${s.monthsLabel} ${s.summary}'].join('，')}';

  factory ProposalPromotionTierPlan.fromJson(Object? raw) {
    final map = _mapOf(raw);
    final id = _str(map['id']);
    final name = _str(map['name']);
    if (map.containsKey('segments') || map.containsKey('strategy')) {
      final strategy = switch (_str(map['strategy'])) {
        kProposalPromotionStrategyFixed => kProposalPromotionStrategyFixed,
        kProposalPromotionStrategyAnnual => kProposalPromotionStrategyAnnual,
        _ => kProposalPromotionStrategyMonthSeq,
      };
      final segments = [
        for (final item in _listOf(map['segments']))
          ProposalPromotionSegment.fromJson(item),
      ];
      return ProposalPromotionTierPlan(
        id: id,
        name: name,
        promoter: _str(map['promoter']),
        strategy: strategy,
        segments:
            strategy == kProposalPromotionStrategyFixed && segments.isNotEmpty
            ? [
                ProposalPromotionSegment(
                  type: 'fixed',
                  rate: segments.first.rate,
                ),
              ]
            : segments,
      );
    }
    final annual = _str(map['basis']) == 'annual';
    final tiers = [
      for (final item in _listOf(map['tiers']))
        ProposalPromotionTier(
          from: annual
              ? _num(_mapOf(item)['from']) / 12
              : _num(_mapOf(item)['from']),
          rate: _num(_mapOf(item)['rate']) / 100,
        ),
    ];
    return ProposalPromotionTierPlan(
      id: id,
      name: name,
      segments: tiers.isEmpty
          ? const []
          : [
              ProposalPromotionSegment(
                mode: _str(map['mode']) == 'excess' ? 'excess' : 'whole',
                tiers: tiers,
              ),
            ],
    );
  }

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    if (name.isNotEmpty) 'name': name,
    'promoter': promoter,
    'strategy': strategy,
    'segments': [for (final segment in segments) segment.toJson()],
  };

  ProposalPromotionTierPlan copyWith({
    String? id,
    String? name,
    String? promoter,
    String? strategy,
    List<ProposalPromotionSegment>? segments,
  }) => ProposalPromotionTierPlan(
    id: id ?? this.id,
    name: name ?? this.name,
    promoter: promoter ?? this.promoter,
    strategy: strategy ?? this.strategy,
    segments: segments ?? this.segments,
  );

  /// 年化推广费（万元）和代入过程。
  ({double amount, String substitution}) evaluate(double annualScale) {
    if (fixed) {
      final rate = fixedRate;
      final amount = annualScale * rate;
      return (
        amount: proposalRoundWan(amount),
        substitution:
            '按固定比例：年化规模 ${_wan(annualScale)} 万 × ${proposalFormatPromotionRate(rate)} = ${_wan(amount)} 万元',
      );
    }
    if (annual) {
      final segment = segments.isEmpty
          ? const ProposalPromotionSegment()
          : segments.first;
      final result = segment.scaledFee(annualScale, volumeName: '年化规模');
      return (
        amount: proposalRoundWan(result.fee),
        substitution: '年阶梯：${result.detail}',
      );
    }
    final monthly = annualScale / 12;
    final counts = List<int>.filled(segments.length, 0);
    final uncovered = <int>[];
    for (var month = 1; month <= kProposalPromotionMonths; month++) {
      final index = segments.indexWhere((segment) => segment.covers(month));
      if (index < 0) {
        uncovered.add(month);
      } else {
        counts[index]++;
      }
    }
    var total = 0.0;
    final parts = <String>[];
    for (var i = 0; i < segments.length; i++) {
      if (counts[i] == 0) continue;
      final month = segments[i].monthlyFee(monthly);
      final subtotal = month.fee * counts[i];
      total += subtotal;
      parts.add(
        '${segments[i].monthsLabel}：${month.detail}/月 × ${counts[i]} 个月 = ${_wan(subtotal)} 万',
      );
    }
    if (parts.isEmpty) {
      return (amount: 0, substitution: '还没配置月份规则，按 0 计');
    }
    if (uncovered.isNotEmpty) {
      parts.add('第 ${uncovered.join('、')} 个月没有配置，按 0 计');
    }
    parts.add('合计 ${_wan(total)} 万元');
    return (amount: proposalRoundWan(total), substitution: parts.join('\n'));
  }
}

ProposalPromotionTierPlan proposalPromotionTierPlanOf(
  Map<String, dynamic> form,
) => ProposalPromotionTierPlan.fromJson(form[kProposalPromotionTiersKey]);

String proposalPromotionPlanDefaultName(int index) => '方案${index + 1}';

/// 推广费阶梯方案列表；没有新字段时把旧的单套阶梯当作第一套。
List<ProposalPromotionTierPlan> proposalPromotionPlansOf(
  Map<String, dynamic> form,
) {
  final raw = form[kProposalPromotionPlansKey];
  if (raw is List) {
    return [
      for (var i = 0; i < raw.length; i++)
        if (raw[i] is Map)
          _namedPlan(ProposalPromotionTierPlan.fromJson(raw[i]), i),
    ];
  }
  final legacy = proposalPromotionTierPlanOf(form);
  if (legacy.isEmpty) return const [];
  return [_namedPlan(legacy, 0)];
}

ProposalPromotionTierPlan _namedPlan(
  ProposalPromotionTierPlan plan,
  int index,
) => plan.copyWith(
  id: plan.id.isEmpty ? 'p${index + 1}' : plan.id,
  name: plan.name.isEmpty ? proposalPromotionPlanDefaultName(index) : plan.name,
);

/// 新增一套阶梯方案时用的 id：不与已有的重复。
String proposalPromotionPlanNextId(List<ProposalPromotionTierPlan> plans) {
  final used = {for (final plan in plans) plan.id};
  var n = plans.length + 1;
  while (used.contains('p$n')) {
    n++;
  }
  return 'p$n';
}

/// All settlement costs share the promotion tier editor and evaluation rules.
List<ProposalPromotionTierPlan> proposalSettleTierPlans(
  ProposalFinanceSettleTerms terms,
) {
  if (terms.tierPlans.isNotEmpty) return terms.tierPlans;
  if (terms.settleTiers.isEmpty) return const [];
  return [
    ProposalPromotionTierPlan(
      id: 'legacy',
      strategy: kProposalPromotionStrategyAnnual,
      segments: [
        ProposalPromotionSegment(
          tiers: [
            for (final tier in terms.settleTiers)
              ProposalPromotionTier(
                from: double.tryParse(tier.from) ?? 0,
                rate: double.tryParse(tier.rate) ?? 0,
              ),
          ],
        ),
      ],
    ),
  ];
}

// ---------------------------------------------------------------------------
// 测算结果
// ---------------------------------------------------------------------------

class ProposalFinanceLine {
  const ProposalFinanceLine({
    required this.name,
    required this.amount,
    this.formula,
    this.substitution = '',
    this.pending = false,
    this.missing = const [],
    this.source = '',
    this.locked = false,
    this.promotionMonthlyScale,
  });

  final String name;
  final ProposalFinanceFormula? formula;
  final double amount;

  /// 代入后的算式，例如「1000 × 98.5% = 985 万元」。
  final String substitution;
  final bool pending;

  /// 提案里取不到、按 0 计的变量，页面上提示。
  final List<String> missing;

  /// 金额出处，例如「取自产品结算 · 应付 · 机构返佣 比例 0.01」。
  final String source;

  /// 产品结算里已有的项目成本：自动带出，不能删、不能换公式。
  final bool locked;

  /// 推广费按阶梯算时用的月规模（万元），页面据此高亮各月份段命中的档位；非推广费为 null。
  final double? promotionMonthlyScale;
}

class ProposalFinanceBucket {
  const ProposalFinanceBucket({required this.category, required this.lines, this.computedTotal});

  final ProposalCostCategory category;
  final List<ProposalFinanceLine> lines;
  final double? computedTotal;

  double get total =>
      computedTotal ?? proposalRoundWan(lines.fold<double>(0, (sum, line) => sum + line.amount));

  List<String> get names => [for (final line in lines) line.name];
}

class ProposalFinanceEvaluation {
  const ProposalFinanceEvaluation({
    required this.salesScale,
    required this.revenueGroup,
    required this.revenueGroups,
    required this.revenue,
    required this.buckets,
    required this.profit,
    required this.profitSubstitution,
    required this.margin,
    required this.marginSubstitution,
    this.products = const [],
    this.procurement = const ProposalFinanceLine(name: '采购成本', amount: 0),
    this.computedCostTotal,
  });

  final double salesScale;

  /// 采购成本：付给供给侧的采购款（供给侧结算「关联产品年化规模 × 比例」）。
  /// 兼容旧结构；当前销售提案已取消采购成本，此项始终为 0。
  final ProposalFinanceLine procurement;

  /// 按产品的测算；整组的收入、成本、利润是它们的加总。
  final List<ProposalProductFinanceEvaluation> products;

  /// 当前收入公式所在组；对不上业务平台时为 null。
  final ProposalRevenueFormulaGroup? revenueGroup;

  /// 收入公式下拉里可选的组（按产品业务平台筛过）。
  final List<ProposalRevenueFormulaGroup> revenueGroups;
  final ProposalFinanceLine revenue;
  final Map<String, ProposalFinanceBucket> buckets;
  final double profit;
  final String profitSubstitution;
  final double? margin;
  final double? computedCostTotal;
  final String marginSubstitution;

  ProposalFinanceBucket? bucket(String key) => buckets[key];

  double total(String key) => buckets[key]?.total ?? 0;

  /// 成本合计 = 项目 / 业务 / 税务（经营成本只选类型，金额为 0）。
  double get costTotal => computedCostTotal ?? proposalRoundWan(
    buckets.values.fold<double>(0, (sum, bucket) => sum + bucket.total),
  );
}

/// 一个产品的测算：它自己的公式选择、规模和结算算出来的收入与成本。
class ProposalProductFinanceEvaluation {
  const ProposalProductFinanceEvaluation({
    required this.sku,
    required this.owner,
    required this.evaluation,
    this.promotionPlans = const [],
  });

  final ProposalSkuDetailRow sku;

  /// `main` / `children`。
  final String owner;
  final ProposalFinanceEvaluation evaluation;
  final List<ProposalPromotionTierPlan> promotionPlans;

  String get skuId => sku.id;

  bool get isChild => owner == kProposalProductFinanceChildren;

  String get name {
    final name = sku.displayName.trim();
    return name.isEmpty ? '未命名产品' : name;
  }

  bool get hasPromotion =>
      evaluation
          .bucket(kProposalCostCategoryProject)
          ?.lines
          .any((line) => line.name == '推广费') ??
      false;
}

String _wan(double value) => proposalFormatWan(value);

String _pct(double ratio) => '${proposalFormatWan(ratio * 100)}%';

/// 本组产品用到的业务平台编码。
Set<String> proposalFinanceSyncSources(Map<String, dynamic> form) {
  return {
    for (final sku in proposalIntakeSkuDetails(form))
      if (sku.syncSourceCode.isNotEmpty) sku.syncSourceCode,
  };
}

/// 产品销售结算里已经选过的公式编码（资管 formulaContent），作为收入公式默认值。
List<String> _settleFormulaCodes(Map<String, dynamic> form) {
  final out = <String>[];
  for (final terms in proposalIntakeProductSalesSettleTerms(form)) {
    final code = (terms.formulaRef?.code ?? terms.formula).trim();
    if (code.isNotEmpty && !out.contains(code)) out.add(code);
  }
  return out;
}

/// 解析当前收入公式：表单已选 → 产品销售结算的公式 → 所在组第一条。
({ProposalRevenueFormulaGroup? group, ProposalFinanceFormula? formula})
proposalResolveRevenueFormula(
  Map<String, dynamic> form,
  ProposalFinanceFormulaCatalog catalog,
) {
  final groups = catalog.groupsForSources(proposalFinanceSyncSources(form));
  final storedCode = _str(form[kProposalRevenueFormulaKey]);
  final storedGroup = _str(form[kProposalRevenueFormulaGroupKey]);
  if (storedCode.isNotEmpty) {
    final preferred = catalog.group(storedGroup);
    final hit = preferred?.formulaOf(storedCode);
    if (preferred != null && hit != null) {
      return (group: preferred, formula: hit);
    }
    for (final group in [...groups, ...catalog.revenueGroups]) {
      final formula = group.formulaOf(storedCode);
      if (formula != null) return (group: group, formula: formula);
    }
  }
  for (final code in _settleFormulaCodes(form)) {
    for (final group in groups) {
      final formula = group.formulaOf(code);
      if (formula != null) return (group: group, formula: formula);
    }
  }
  for (final group in groups) {
    if (group.formulas.isNotEmpty) {
      return (group: group, formula: group.formulas.first);
    }
  }
  return (group: null, formula: null);
}

/// 已选成本项（按类）。
List<String> proposalFinanceSelectedNames(
  Map<String, dynamic> form,
  ProposalCostCategory category,
) {
  final names = <String>[];
  for (final raw in proposalCostSelectedNames(form, category.namesKey)) {
    final name = category.key == kProposalCostCategoryProject
        ? proposalProjectCostDisplayName(raw)
        : raw;
    if (name.isNotEmpty && !names.contains(name)) names.add(name);
  }
  return names;
}

Map<String, String> proposalFinanceFormulaChoices(
  Map<String, dynamic> form,
  ProposalCostCategory category,
) {
  final raw = form[category.formulasKey];
  if (raw is! Map) return <String, String>{};
  return <String, String>{
    for (final entry in raw.entries)
      if (_str(entry.key).isNotEmpty && _str(entry.value).isNotEmpty)
        _str(entry.key): _str(entry.value),
  };
}

ProposalFinanceFormula? proposalFinanceItemFormula(
  Map<String, dynamic> form,
  ProposalCostCategory category,
  String name,
) {
  final item = category.resolveItem(name);
  final chosen = proposalFinanceFormulaChoices(form, category)[name];
  return (chosen == null ? null : item.formulaOf(chosen)) ??
      item.defaultFormulaRef;
}

/// 产品结算里有应付行的项目成本名（显示名）。这些成本自动带出、锁定公式。
Set<String> proposalFinanceSettledProjectNames(
  Map<String, dynamic> form, {
  List<String> costNames = const [],
}) {
  return {
    for (final name in proposalMatchedProjectCostNames(
      form,
      costNames: costNames,
    ))
      proposalProjectCostDisplayName(name),
  };
}

String _projectSettleSource(
  Map<String, dynamic> form,
  String name, {
  List<String> costNames = const [],
}) {
  final display = proposalProjectCostDisplayName(name);
  final aliases = proposalProjectCostNamesOf(display);
  final labels = <String>[];
  for (final hit in proposalPayableProjectCostHits(
    form,
    costNames: costNames,
  )) {
    if (!aliases.contains(hit.costName)) continue;
    final ratio = hit.terms.displayRatio.trim();
    final price = hit.terms.displayUnitPrice.trim();
    final label = ratio.isNotEmpty
        ? '比例 $ratio'
        : (price.isNotEmpty ? '单价 $price' : '');
    if (label.isNotEmpty && !labels.contains(label)) labels.add(label);
  }
  return labels.isEmpty
      ? '取自产品结算 · 应付 · $display'
      : '取自产品结算 · 应付 · $display ${labels.join(' / ')}';
}

/// 产品结算应付行上选的计算公式。财务模块直接展示这个，不再改写成「按产品结算」。
String _projectSettleFormulaLabel(
  Map<String, dynamic> form,
  String name, {
  List<String> costNames = const [],
}) {
  final aliases = proposalProjectCostNamesOf(
    proposalProjectCostDisplayName(name),
  );
  final labels = <String>[];
  for (final hit in proposalPayableProjectCostHits(
    form,
    costNames: costNames,
  )) {
    if (!aliases.contains(hit.costName)) continue;
    final text = hit.terms.displayFormula.trim();
    if (text.isNotEmpty && !labels.contains(text)) labels.add(text);
  }
  return labels.join(' / ');
}

// ---------------------------------------------------------------------------
// 收入表达式：把资管公式里的业务量、比例、成本代入后计算。
// ---------------------------------------------------------------------------

enum _TokKind { number, op, base, ratio, zero, cost, unknown }

class _Tok {
  const _Tok(this.kind, this.text, [this.value = 0]);
  final _TokKind kind;
  final String text;
  final double value;
}

/// 业务量类变量：测算阶段都取产品年化规模。
const _kBasePhrases = <String>[
  '(销售-退款)实际支付金额',
  '核销实际支付金额',
  '积分/返费采购款',
  '会员销售款',
  '券包销售款',
  '销售(面值)',
  '核销(面值)',
  '兑换金额',
  '引流金额',
  '油枪价',
  '现金',
  '销售',
  '核销',
];

const _kRatioPhrases = <String>['电子券销售款结算比例', '结算比例'];

/// 测算不计退款。
const _kZeroPhrases = <String>['退款'];

/// 可从已选项目成本取数的变量（按产品成本结算匹配）。
const _kCostPhrases = <String>[
  '平台交易服务费',
  '平台服务费',
  '支付手续费',
  '机构返佣',
  '推广费',
  '渠道侧N',
  '渠道侧H',
  '供给侧N',
  '供给侧H',
];

String _normalizeExpression(String raw) => raw
    .replaceAll('（', '(')
    .replaceAll('）', ')')
    .replaceAll('×', '*')
    .replaceAll('÷', '/')
    .replaceAll('−', '-')
    .replaceAll('－', '-')
    .replaceAll('＋', '+')
    .replaceAll(RegExp(r'\s+'), '');

class _RevenueEval {
  const _RevenueEval(this.amount, this.display, this.missing, {this.ok = true});
  final double amount;
  final String display;
  final List<String> missing;
  final bool ok;
}

final _kDigit = RegExp(r'[0-9.]');

_RevenueEval _evaluateRevenueExpression(
  String expression, {
  required double base,
  required double ratio,
  required double? Function(String name) costOf,
}) {
  final text = _normalizeExpression(expression);
  final phrases = <(String, _TokKind)>[
    for (final p in _kBasePhrases) (p, _TokKind.base),
    for (final p in _kRatioPhrases) (p, _TokKind.ratio),
    for (final p in _kZeroPhrases) (p, _TokKind.zero),
    for (final p in _kCostPhrases) (p, _TokKind.cost),
  ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));

  (String, _TokKind)? phraseAt(int index) {
    for (final phrase in phrases) {
      if (text.startsWith(phrase.$1, index)) return phrase;
    }
    return null;
  }

  final tokens = <_Tok>[];
  var unknown = StringBuffer();
  void flushUnknown() {
    if (unknown.isEmpty) return;
    tokens.add(_Tok(_TokKind.unknown, unknown.toString()));
    unknown = StringBuffer();
  }

  var i = 0;
  while (i < text.length) {
    final ch = text[i];
    // 「(销售-退款)实际支付金额」这类以括号开头的短语优先整体匹配。
    final phrase = phraseAt(i);
    if (phrase != null) {
      flushUnknown();
      tokens.add(_Tok(phrase.$2, phrase.$1));
      i += phrase.$1.length;
      continue;
    }
    if ('+-*/()'.contains(ch)) {
      flushUnknown();
      tokens.add(_Tok(_TokKind.op, ch));
      i++;
      continue;
    }
    if (_kDigit.hasMatch(ch)) {
      flushUnknown();
      final start = i;
      while (i < text.length && _kDigit.hasMatch(text[i])) {
        i++;
      }
      final literal = text.substring(start, i);
      tokens.add(_Tok(_TokKind.number, literal, double.tryParse(literal) ?? 0));
      continue;
    }
    unknown.write(ch);
    i++;
  }
  flushUnknown();

  // 只有一个业务量变量、且资管写的是提案里没有的叫法（如「补贴」「溢价」）时，
  // 它就是这条公式的业务量，按年化规模估。
  final quantityVars = <String>{
    for (final tok in tokens)
      if (tok.kind == _TokKind.base ||
          tok.kind == _TokKind.unknown ||
          tok.kind == _TokKind.cost)
        tok.text,
  };
  final soleUnknownIsBase =
      quantityVars.length == 1 &&
      tokens.any((tok) => tok.kind == _TokKind.unknown);

  final missing = <String>[];
  final valued = <_Tok>[];
  for (final tok in tokens) {
    switch (tok.kind) {
      case _TokKind.base:
        valued.add(_Tok(tok.kind, tok.text, base));
      case _TokKind.ratio:
        valued.add(_Tok(tok.kind, tok.text, ratio));
      case _TokKind.zero:
        valued.add(_Tok(tok.kind, tok.text, 0));
      case _TokKind.cost:
        {
          final value = costOf(tok.text);
          if (value == null && !missing.contains(tok.text)) {
            missing.add(tok.text);
          }
          valued.add(_Tok(tok.kind, tok.text, value ?? 0));
        }
      case _TokKind.unknown:
        if (soleUnknownIsBase) {
          valued.add(_Tok(_TokKind.base, tok.text, base));
        } else {
          if (!missing.contains(tok.text)) missing.add(tok.text);
          valued.add(_Tok(tok.kind, tok.text, 0));
        }
      case _TokKind.number:
      case _TokKind.op:
        valued.add(tok);
    }
  }

  var pos = 0;
  var failed = false;
  bool isOp(String op) =>
      pos < valued.length &&
      valued[pos].kind == _TokKind.op &&
      valued[pos].text == op;

  late double Function() parseExpr;
  double parseFactor() {
    if (pos >= valued.length) {
      failed = true;
      return 0;
    }
    final tok = valued[pos];
    if (isOp('(')) {
      pos++;
      final value = parseExpr();
      if (isOp(')')) {
        pos++;
      } else {
        failed = true;
      }
      return value;
    }
    if (isOp('-')) {
      pos++;
      return -parseFactor();
    }
    if (tok.kind == _TokKind.op) {
      failed = true;
      pos++;
      return 0;
    }
    pos++;
    return tok.value;
  }

  double parseTerm() {
    var value = parseFactor();
    while (isOp('*') || isOp('/')) {
      final op = valued[pos].text;
      pos++;
      final rhs = parseFactor();
      value = op == '*' ? value * rhs : (rhs == 0 ? 0 : value / rhs);
    }
    return value;
  }

  parseExpr = () {
    var value = parseTerm();
    while (isOp('+') || isOp('-')) {
      final op = valued[pos].text;
      pos++;
      final rhs = parseTerm();
      value = op == '+' ? value + rhs : value - rhs;
    }
    return value;
  };

  final amount = valued.isEmpty ? 0.0 : parseExpr();
  if (pos < valued.length) failed = true;

  final display = StringBuffer();
  for (final tok in valued) {
    switch (tok.kind) {
      case _TokKind.op:
        display.write(switch (tok.text) {
          '*' => ' × ',
          '/' => ' ÷ ',
          '-' => ' − ',
          '+' => ' + ',
          _ => tok.text,
        });
      case _TokKind.number:
        display.write(tok.text);
      case _TokKind.ratio:
        display.write(_pct(tok.value));
      case _TokKind.base:
      case _TokKind.zero:
      case _TokKind.cost:
      case _TokKind.unknown:
        display.write(_wan(tok.value));
    }
  }
  return _RevenueEval(
    proposalRoundWan(amount),
    display.toString().trim(),
    missing,
    ok: !failed && valued.isNotEmpty,
  );
}

// ---------------------------------------------------------------------------
// 整体测算
// ---------------------------------------------------------------------------

/// 收入公式里的「结算比例」：产品结算算出的收入 ÷ 年化规模（多产品时为加权比例）。
double _effectiveSettleRatio(
  Map<String, dynamic> form,
  double scale,
  double rollupRevenue,
) {
  if (scale > 0 && rollupRevenue > 0) return rollupRevenue / scale;
  for (final terms in proposalIntakeProductSalesSettleTerms(form)) {
    final ratio = terms.displayRatio.trim();
    if (ratio.isNotEmpty) return proposalParseSettleRatio(ratio);
  }
  return 0;
}

bool _isUnitPriceFormula(ProposalFinanceFormula formula) =>
    formula.expression.contains('单价') || formula.name.contains('单价');

// ---------------------------------------------------------------------------
// 按产品的公式选择
// ---------------------------------------------------------------------------

Map<String, dynamic> _productFormulasOf(Map<String, dynamic> form) =>
    _mapOf(form[kProposalProductFormulasKey]);

/// `productFormulas[skuId]` 原样（可能缺字段）。
Map<String, dynamic> proposalProductFormulaRawEntry(
  Map<String, dynamic> form,
  String skuId,
) => _mapOf(_productFormulasOf(form)[skuId]);

/// 产品属于主产品还是子产品。
String proposalProductFormulaOwnerOf(Map<String, dynamic> form, String skuId) {
  for (final sku in proposalIntakeChildProducts(form)) {
    if (sku.id == skuId) return kProposalProductFinanceChildren;
  }
  return kProposalProductFinanceMain;
}

/// 一个产品完整的公式选择：自己存了的字段用自己的，没存的沿用所在组（主 / 子产品组）的旧选择。
///
/// [group] 是所在组的财务字段（主产品组即顶层）；旧的单套 `promotionTiers` 转成 `promotionPlans`。
Map<String, dynamic> proposalProductFormulaEntryWithFallback(
  Map<String, dynamic> entry,
  Map<String, dynamic> group, {
  bool skipBusiness = false,
}) {
  final out = <String, dynamic>{};
  for (final key in kProposalProductFormulaEntryKeys) {
    if (skipBusiness && kProposalProductFormulaBusinessKeys.contains(key)) {
      if (entry.containsKey(key)) out[key] = entry[key];
      continue;
    }
    if (entry.containsKey(key)) {
      out[key] = entry[key];
    } else if (key == kProposalPromotionPlansKey) {
      final plans = proposalPromotionPlansOf(group);
      if (plans.isNotEmpty) {
        out[key] = [for (final plan in plans) plan.toJson()];
      }
    } else if (group.containsKey(key)) {
      out[key] = group[key];
    }
  }
  return out;
}

Map<String, dynamic> proposalProductFormulaEntry(
  Map<String, dynamic> form,
  String skuId,
) {
  final owner = proposalProductFormulaOwnerOf(form, skuId);
  return proposalProductFormulaEntryWithFallback(
    proposalProductFormulaRawEntry(form, skuId),
    proposalIntakeProductFinance(form, owner: owner),
  );
}

/// 把每个产品的选择补全写进 `productFormulas`，并清掉已删除产品的条目。
///
/// 补全后各产品不再依赖组上的旧字段，组上写回的合计也就不会反过来影响某个产品。
/// 业务成本对当前用户加密时，不替它补业务成本字段（服务端会保留原值）。
Map<String, dynamic> proposalMaterializeProductFormulas(
  Map<String, dynamic> form,
) {
  final skus = proposalIntakeAllSellableSkus(form);
  final existing = _productFormulasOf(form);
  if (skus.isEmpty && existing.isEmpty) return form;
  final redacted = form['businessCostRedacted'] == true;
  final next = <String, dynamic>{};
  for (final sku in skus) {
    if (sku.id.isEmpty) continue;
    final owner = proposalProductFormulaOwnerOf(form, sku.id);
    next[sku.id] = proposalProductFormulaEntryWithFallback(
      proposalProductFormulaRawEntry(form, sku.id),
      proposalIntakeProductFinance(form, owner: owner),
      skipBusiness: redacted,
    )..['owner'] = owner;
  }
  return Map<String, dynamic>.from(form)..[kProposalProductFormulasKey] = next;
}

/// 改某个产品的公式选择：先补全再改，金额由测算统一重算后回写。
Map<String, dynamic> proposalFinanceWriteProductEntry(
  Map<String, dynamic> form,
  String skuId,
  Map<String, dynamic> Function(Map<String, dynamic> entry) mutate,
) {
  final materialized = proposalMaterializeProductFormulas(form);
  final all = _productFormulasOf(materialized);
  final entry = _mapOf(all[skuId]);
  all[skuId] = mutate(entry);
  return Map<String, dynamic>.from(materialized)
    ..[kProposalProductFormulasKey] = all;
}

/// 每个产品只留一个推广商方案；多套旧数据再保存时只保留第一套。
Map<String, dynamic> proposalFinanceWritePromotionPlans(
  Map<String, dynamic> entry,
  List<ProposalPromotionTierPlan> plans,
) {
  return Map<String, dynamic>.from(entry)
    ..[kProposalPromotionPlansKey] = [
      for (final plan in plans.take(1)) plan.toJson(),
    ]
    ..remove(kProposalPromotionTiersKey);
}

/// 一个产品的测算输入：只留这个产品和它的结算，公式选择换成这个产品自己的。
Map<String, dynamic> proposalFinanceSkuScope(
  Map<String, dynamic> scope,
  ProposalSkuDetailRow sku, {
  required double scale,
}) {
  final entry = proposalProductFormulaEntryWithFallback(
    proposalProductFormulaRawEntry(scope, sku.id),
    scope,
  );
  final next = <String, dynamic>{
    ...scope,
    'skuDetails': [sku.toJson()],
    'childProducts': const <Map<String, dynamic>>[],
    'channelSkus': const <Map<String, dynamic>>[],
    'products': const <Map<String, dynamic>>[],
    // 「products」也是供给产品的旧别名：清掉之前先把供给产品落到 supplyProducts，采购成本才算得到。
    'supplyProducts': [
      for (final row in proposalIntakeSupplyProducts(scope)) row.toJson(),
    ],
    'packs': const <Map<String, dynamic>>[],
    'couponPacks': const <Map<String, dynamic>>[],
    'sharedSettlements': [
      for (final group in proposalIntakeSharedSettlements(scope))
        if (group.skuIds.contains(sku.id))
          group.copyWith(skuIds: [sku.id]).toJson(),
    ],
  };
  for (final key in kProposalProductFormulaEntryKeys) {
    if (entry.containsKey(key)) {
      next[key] = entry[key];
    } else {
      next.remove(key);
    }
  }
  next.remove(kProposalPromotionTiersKey);
  if (scale > 0) {
    next[kProposalSalesScaleKey] = scale;
  } else {
    next.remove(kProposalSalesScaleKey);
  }
  return next;
}

/// 共用销售结算的产品之间，一个产品上的应付行对同组其他产品同样生效；
/// 单产品测算时把这些行补到该产品的结算里（不带规模，避免计入产品规模）。
Map<String, dynamic> _withInheritedPayables(
  Map<String, dynamic> scope,
  ProposalSkuDetailRow sku,
  List<ProposalPayableCostHit> groupHits, {
  List<String> costNames = const [],
}) {
  final own = {
    for (final hit in proposalPayableProjectCostHits(
      scope,
      costNames: costNames,
    ))
      hit.costName,
  };
  final inherited = [
    for (final hit in groupHits)
      if (hit.skuIds.contains(sku.id) && !own.contains(hit.costName)) hit,
  ];
  if (inherited.isEmpty) return scope;
  final rows = scope['skuDetails'];
  if (rows is! List || rows.length != 1 || rows.single is! Map) return scope;
  final row = Map<String, dynamic>.from(rows.single as Map);
  final settlements = row['settlements'];
  row['settlements'] = [
    if (settlements is List) ...settlements,
    for (var i = 0; i < inherited.length; i++)
      <String, dynamic>{
          ...inherited[i].terms.toJson(),
          'id': '${sku.id}-inherited-${i + 1}',
        }
        ..remove('scale')
        ..remove('scalePeriod'),
  ];
  return {
    ...scope,
    'skuDetails': [row],
  };
}

/// 各产品的年化规模：产品自己有规模用自己的；没有的平分组规模里剩下的部分。
List<double> _skuScales(
  Map<String, dynamic> scope,
  List<ProposalSkuDetailRow> skus,
) {
  final own = [for (final sku in skus) proposalIntakeSkuScaleTotal(sku)];
  final ownSum = own.fold<double>(0, (sum, v) => sum + (v > 0 ? v : 0));
  final groupScale = proposalEffectiveSalesScale(scope);
  final rest = math.max(0.0, groupScale - ownSum);
  final without = own.where((v) => v <= 0).length;
  return [
    for (final v in own)
      v > 0 ? v : (without > 0 ? proposalRoundWan(rest / without) : 0),
  ];
}

/// 按产品测算再加总。[form] 是一个产品组（主产品组或子产品组）的测算输入，
/// 组里每个产品用自己的公式选择、规模和结算各算一次。
ProposalFinanceEvaluation proposalEvaluateFinance(
  Map<String, dynamic> form, {
  ProposalFinanceFormulaCatalog? catalog,
  List<ProposalCostItemOption> costCatalog = const [],
  List<String> costNames = const [],
  String owner = kProposalProductFinanceMain,
}) {
  final dict = catalog ?? ProposalFinanceFormulaCatalog.fallback;
  ProposalFinanceEvaluation single(Map<String, dynamic> scope) =>
      _evaluateFinanceScope(
        _seedSuggestedItems(scope, dict, costNames: costNames),
        dict: dict,
        costCatalog: costCatalog,
        costNames: costNames,
        owner: owner,
      );
  final skus = [
    for (final sku in proposalIntakeSkuDetails(form))
      if (sku.id.isNotEmpty) sku,
  ];
  if (skus.isEmpty) return single(form);
  final scales = _skuScales(form, skus);
  final groupHits = proposalPayableProjectCostHits(form, costNames: costNames);
  final products = <ProposalProductFinanceEvaluation>[];
  for (var i = 0; i < skus.length; i++) {
    final scope = _withInheritedPayables(
      proposalFinanceSkuScope(form, skus[i], scale: scales[i]),
      skus[i],
      groupHits,
      costNames: costNames,
    );
    products.add(
      ProposalProductFinanceEvaluation(
        sku: skus[i],
        owner: owner,
        evaluation: single(scope),
        promotionPlans: proposalPromotionPlansOf(scope),
      ),
    );
  }
  return _aggregateFinance(
    salesScale: proposalEffectiveSalesScale(form),
    products: products,
    dict: dict,
    proposalForm: form,
  );
}

/// 把若干产品（可同时含主产品和子产品）的测算加总成一份，
/// 页面顶部的成本 / 利润和下面按产品列出的各行用同一份数，不会对不上。
ProposalFinanceEvaluation proposalAggregateProductFinance({
  required double salesScale,
  required List<ProposalProductFinanceEvaluation> products,
  ProposalFinanceFormulaCatalog? catalog,
  Map<String, dynamic>? proposalForm,
}) => _aggregateFinance(
  salesScale: salesScale,
  products: products,
  dict: catalog ?? ProposalFinanceFormulaCatalog.fallback,
  proposalForm: proposalForm,
);

ProposalFinanceEvaluation _aggregateFinance({
  required double salesScale,
  required List<ProposalProductFinanceEvaluation> products,
  required ProposalFinanceFormulaCatalog dict,
  Map<String, dynamic>? proposalForm,
}) {
  final evals = [for (final p in products) p.evaluation];
  final scale = salesScale > 0
      ? salesScale
      : evals.fold<double>(0, (sum, e) => sum + e.salesScale);
  final revenues = [for (final e in evals) e.revenue];
  final revenueAmount = proposalRoundWan(
    revenues.fold<double>(0, (sum, line) => sum + line.amount),
  );
  final codes = {for (final line in revenues) line.formula?.code ?? ''};
  final revenueLine = revenues.length == 1
      ? revenues.single
      : ProposalFinanceLine(
          name: '收入',
          formula: codes.length == 1 ? revenues.first.formula : null,
          amount: revenueAmount,
          substitution: [
            for (var i = 0; i < products.length; i++)
              '${products[i].name} ${_wan(revenues[i].amount)}',
          ].join(' + '),
          missing: {for (final line in revenues) ...line.missing}.toList(),
        );

  final buckets = <String, ProposalFinanceBucket>{};
  for (final key in kProposalCostCategoryDisplayOrder) {
    ProposalCostCategory? category;
    final byName = <String, List<ProposalFinanceLine>>{};
    for (final e in evals) {
      final bucket = e.bucket(key);
      if (bucket == null) continue;
      category ??= bucket.category;
      for (final line in bucket.lines) {
        byName.putIfAbsent(line.name, () => []).add(line);
      }
    }
    if (category == null) continue;
    buckets[key] = ProposalFinanceBucket(
      category: category,
      lines: [
        for (final entry in byName.entries)
          entry.value.length == 1
              ? entry.value.single
              : ProposalFinanceLine(
                  name: entry.key,
                  formula: entry.value.first.formula,
                  amount: proposalRoundWan(
                    entry.value.fold<double>(0, (s, l) => s + l.amount),
                  ),
                  pending: entry.value.every((l) => l.pending),
                  locked: entry.value.any((l) => l.locked),
                  missing: {for (final l in entry.value) ...l.missing}.toList(),
                ),
      ],
    );
  }
  double total(String key) => buckets[key]?.total ?? 0;
  if (proposalForm != null) {
    final business = dict.category(kProposalCostCategoryBusiness);
    if (business != null) {
      final ratio = _effectiveSettleRatio(proposalForm, scale, revenueAmount);
      final redacted = proposalForm['businessCostRedacted'] == true;
      final codes = [
        for (final item in _listOf(proposalForm['businessFormulaCodes']))
          if (_str(item).isNotEmpty) _str(item),
      ];
      buckets[kProposalCostCategoryBusiness] = ProposalFinanceBucket(
        category: business,
        lines: [
          for (final code in codes)
            if (dict.formulaByCode(code) case final formula?)
              _proposalBusinessFormulaLine(
                formula,
                scale: scale,
                ratio: ratio,
                redacted: redacted,
              ),
        ],
      );
    }
  }
  if (proposalForm != null) {
    final category = dict.category(kProposalCostCategoryTax);
    if (category != null) {
      final taxForm = proposalTaxForm(proposalForm);
      final names = proposalFinanceSelectedNames(
        _seedSuggestedItems(taxForm, dict, costNames: const []),
        category,
      );
      buckets[kProposalCostCategoryTax] = ProposalFinanceBucket(
        category: category,
        lines: [
          for (final name in names)
            if (proposalForm['businessCostRedacted'] == true &&
                proposalFinanceItemFormula(taxForm, category, name)?.kind ==
                    ProposalFinanceFormulaKind.pretaxRate)
              ProposalFinanceLine(
                name: name,
                formula: proposalFinanceItemFormula(taxForm, category, name),
                amount: 0,
                pending: true,
                substitution: '应税基数含受限业务成本，金额仅限授权人员查看',
              )
            else
              _evaluateCostLine(
                taxForm,
                name: name,
                formula: proposalFinanceItemFormula(taxForm, category, name),
                scale: scale,
                revenue: revenueAmount,
                project: total(kProposalCostCategoryProject),
                operating: 0,
                business: total(kProposalCostCategoryBusiness),
                settleCost: (name) =>
                    proposalEstimateProjectCostAmount(proposalForm, name),
              ),
        ],
      );
    }
  }
  const procurementLine = ProposalFinanceLine(name: '采购成本', amount: 0);
  final p = total(kProposalCostCategoryProject);
  final b = total(kProposalCostCategoryBusiness);
  final t = total(kProposalCostCategoryTax);
  final profit = proposalRoundWan(revenueAmount - p - b - t);
  final margin = scale > 0 ? proposalRoundWan(profit / scale * 100) : null;
  return ProposalFinanceEvaluation(
    salesScale: scale,
    revenueGroup: evals.first.revenueGroup,
    revenueGroups: evals.first.revenueGroups,
    revenue: revenueLine,
    procurement: procurementLine,
    buckets: buckets,
    profit: profit,
    profitSubstitution:
        '${_wan(revenueAmount)} − ${_wan(p)} − ${_wan(b)} − ${_wan(t)} = ${_wan(profit)} 万元',
    margin: margin,
    marginSubstitution: margin == null
        ? '销售规模为空，暂不能算'
        : '${_wan(profit)} ÷ ${_wan(scale)} × 100% = ${_wan(margin)}%',
    products: products,
  );
}

ProposalFinanceLine _proposalBusinessFormulaLine(
  ProposalFinanceFormula formula, {
  required double scale,
  required double ratio,
  required bool redacted,
}) {
  if (redacted) {
    return ProposalFinanceLine(
      name: formula.name,
      formula: formula,
      amount: 0,
      pending: true,
      substitution: '业务成本仅财务部负责人一和最终审批人可查看',
    );
  }
  if (_isUnitPriceFormula(formula)) {
    final amount = proposalRoundWan(scale * ratio);
    return ProposalFinanceLine(
      name: formula.name,
      formula: formula,
      amount: amount,
      substitution: scale > 0
          ? '年化规模 ${_wan(scale)} × 单价 ÷ 面值（折合 ${_pct(ratio)}）= ${_wan(amount)} 万元'
          : '',
      missing: scale > 0 ? const [] : const ['销售规模'],
    );
  }
  final eval = _evaluateRevenueExpression(
    formula.expression.isEmpty ? formula.name : formula.expression,
    base: scale,
    ratio: ratio,
    costOf: (_) => null,
  );
  final amount = eval.ok ? eval.amount : proposalRoundWan(scale * ratio);
  return ProposalFinanceLine(
    name: formula.name,
    formula: formula,
    amount: amount,
    substitution: eval.ok
        ? '${eval.display} = ${_wan(amount)} 万元'
        : '公式无法自动代入，按 年化规模 × 结算比例：${_wan(scale)} × ${_pct(ratio)} = ${_wan(amount)} 万元',
    missing: [
      if (scale <= 0) '销售规模',
      if (ratio <= 0) '结算比例',
      ...eval.missing,
    ],
  );
}

/// Prefer proposal selections; migrate old per-product tax choices only when no proposal choice exists.
Map<String, dynamic> proposalTaxForm(Map<String, dynamic> form) {
  if (form.containsKey('taxCostItems')) return Map<String, dynamic>.from(form);
  final names = <String>{};
  final formulas = <String, dynamic>{};
  for (final raw in _productFormulasOf(form).values) {
    final entry = _mapOf(raw);
    if (entry['taxCostItems'] is List)
      names.addAll((entry['taxCostItems'] as List).whereType<String>());
    formulas.addAll(_mapOf(entry['taxCostItemFormulas']));
  }
  return {
    ...form,
    if (names.isNotEmpty) 'taxCostItems': names.toList(),
    if (formulas.isNotEmpty) 'taxCostItemFormulas': formulas,
  };
}

/// 一个测算范围（通常是单个产品）按所选公式算收入、成本、利润。
ProposalFinanceEvaluation _evaluateFinanceScope(
  Map<String, dynamic> form, {
  required ProposalFinanceFormulaCatalog dict,
  List<ProposalCostItemOption> costCatalog = const [],
  List<String> costNames = const [],
  String owner = kProposalProductFinanceMain,
}) {
  final scale = proposalEffectiveSalesScale(form);
  final rollup = proposalProductScaleRollup(form);
  final rollupRevenue = rollup?.revenue ?? 0;
  final ratio = _effectiveSettleRatio(form, scale, rollupRevenue);

  double? settleCost(String name) => proposalEstimateProjectCostAmount(
    form,
    name,
    catalog: costCatalog,
    costNames: costNames,
  );

  // ---- 收入 ----
  final resolved = proposalResolveRevenueFormula(form, dict);
  final revenueFormula = resolved.formula;
  final ProposalFinanceLine revenueLine;
  if (revenueFormula == null) {
    revenueLine = ProposalFinanceLine(
      name: '收入',
      amount: proposalRoundWan(rollupRevenue),
      substitution: scale > 0
          ? '${_wan(scale)} × ${_pct(ratio)} = ${_wan(rollupRevenue)} 万元'
          : '',
      missing: const ['收入公式'],
    );
  } else if (_isUnitPriceFormula(revenueFormula)) {
    // 单价类公式：产品结算里已经按 单价 ÷ 面值 折成比例，直接用产品结算的收入。
    revenueLine = ProposalFinanceLine(
      name: '收入',
      formula: revenueFormula,
      amount: proposalRoundWan(rollupRevenue),
      substitution: scale > 0
          ? '年化规模 ${_wan(scale)} × 单价 ÷ 面值（折合 ${_pct(ratio)}）= ${_wan(rollupRevenue)} 万元'
          : '',
      missing: scale > 0 ? const [] : const ['销售规模'],
    );
  } else {
    final eval = _evaluateRevenueExpression(
      revenueFormula.expression.isEmpty
          ? revenueFormula.name
          : revenueFormula.expression,
      base: scale,
      ratio: ratio,
      costOf: (name) {
        for (final alias in proposalProjectCostNamesOf(name)) {
          final value = settleCost(alias);
          if (value != null) return value;
        }
        return null;
      },
    );
    final amount = eval.ok ? eval.amount : proposalRoundWan(scale * ratio);
    revenueLine = ProposalFinanceLine(
      name: '收入',
      formula: revenueFormula,
      amount: amount,
      substitution: eval.ok
          ? '${eval.display} = ${_wan(amount)} 万元'
          : '公式无法自动代入，按 年化规模 × 结算比例：${_wan(scale)} × ${_pct(ratio)} = ${_wan(amount)} 万元',
      missing: [
        if (scale <= 0) '销售规模',
        if (ratio <= 0) '结算比例',
        ...eval.missing,
      ],
    );
  }
  final revenue = revenueLine.amount;

  // 电子券采购款不进项目成本，但收入（利差）仍要扣掉这笔采购款。
  final couponPurchase = proposalCouponPurchaseAmount(form);
  final procurementLine = ProposalFinanceLine(
    name: '采购成本',
    amount: couponPurchase,
  );

  // ---- 成本 ----
  final totals = <String, double>{};
  final buckets = <String, ProposalFinanceBucket>{};
  final settledNames = proposalFinanceSettledProjectNames(
    form,
    costNames: costNames,
  );
  for (final key in kProposalCostCategoryOrder) {
    final category = dict.category(key);
    if (category == null) continue;
    final lines = <ProposalFinanceLine>[];
    final names = key == kProposalCostCategoryProject
        ? settledNames.toList()
        : proposalFinanceSelectedNames(form, category);
    for (final name in names) {
      if (key == kProposalCostCategoryProject) {
        lines.add(
          _evaluateProjectLine(
            form,
            category: category,
            name: name,
            settled: settledNames.contains(name),
            settleCost: settleCost,
            costNames: costNames,
          ),
        );
        continue;
      }
      if (key == kProposalCostCategoryTax &&
          form['businessCostRedacted'] == true &&
          proposalFinanceItemFormula(form, category, name)?.kind ==
              ProposalFinanceFormulaKind.pretaxRate) {
        lines.add(
          ProposalFinanceLine(
            name: name,
            formula: proposalFinanceItemFormula(form, category, name),
            amount: 0,
            pending: true,
            substitution: '应税基数含受限业务成本，仅财务部负责人一和最终审批人可查看金额',
          ),
        );
        continue;
      }
      lines.add(
        _evaluateCostLine(
          form,
          name: name,
          formula: proposalFinanceItemFormula(form, category, name),
          scale: scale,
          revenue: revenue,
          project: (totals[kProposalCostCategoryProject] ?? 0) +
              (key == kProposalCostCategoryProject ? 0 : couponPurchase),
          // 经营成本只选类型、不计金额，公式里按 0 计。
          operating: 0,
          business: totals[kProposalCostCategoryBusiness] ?? 0,
          settleCost: settleCost,
        ),
      );
    }
    final bucket = ProposalFinanceBucket(category: category, lines: lines);
    buckets[key] = bucket;
    totals[key] = bucket.total;
  }

  // ---- 利润 = 收入 − 采购款 − 项目 − 业务 − 税务 ----
  final p = totals[kProposalCostCategoryProject] ?? 0;
  final b = totals[kProposalCostCategoryBusiness] ?? 0;
  final t = totals[kProposalCostCategoryTax] ?? 0;
  final profit = proposalRoundWan(revenue - couponPurchase - p - b - t);
  final margin = scale > 0 ? proposalRoundWan(profit / scale * 100) : null;
  return ProposalFinanceEvaluation(
    salesScale: scale,
    revenueGroup: resolved.group,
    revenueGroups: dict.groupsForSources(proposalFinanceSyncSources(form)),
    revenue: revenueLine,
    procurement: procurementLine,
    buckets: {
      for (final key in kProposalCostCategoryDisplayOrder)
        if (buckets[key] != null) key: buckets[key]!,
    },
    profit: profit,
    profitSubstitution: couponPurchase > 0
        ? '${_wan(revenue)} − ${_wan(couponPurchase)} − ${_wan(p)} − ${_wan(b)} − ${_wan(t)} = ${_wan(profit)} 万元'
        : '${_wan(revenue)} − ${_wan(p)} − ${_wan(b)} − ${_wan(t)} = ${_wan(profit)} 万元',
    margin: margin,
    marginSubstitution: margin == null
        ? '销售规模为空，暂不能算'
        : '${_wan(profit)} ÷ ${_wan(scale)} × 100% = ${_wan(margin)}%',
  );
}

/// 项目成本：产品结算里有 → 按结算算、锁定；没有 → 提示去产品结算补应付行。
ProposalFinanceLine _evaluateProjectLine(
  Map<String, dynamic> form, {
  required ProposalCostCategory category,
  required String name,
  required bool settled,
  required double? Function(String name) settleCost,
  required List<String> costNames,
}) {
  final item = category.resolveItem(name);
  final tierHits = proposalPayableProjectCostHits(
    form,
    costNames: costNames,
  ).where((hit) => hit.costName == name && hit.terms.settleByTier).toList();
  if (tierHits.isNotEmpty) {
    final scale = proposalEffectiveSalesScale(form);
    final results = [
      for (final hit in tierHits)
        for (final plan in proposalSettleTierPlans(hit.terms))
          plan.evaluate(scale),
    ];
    final amount = proposalRoundWan(
      results.fold<double>(0, (sum, result) => sum + result.amount),
    );
    return ProposalFinanceLine(
      name: name,
      formula: ProposalFinanceFormula(
        code: 'SETTLEMENT_TIER',
        name: '按结算阶梯规则计算',
        expression: '年化规模 × 阶梯或月份折扣',
        kind: ProposalFinanceFormulaKind.tiered,
      ),
      amount: amount,
      locked: true,
      pending: results.isEmpty,
      source: [
        for (final hit in tierHits)
          for (final plan in proposalSettleTierPlans(hit.terms))
            '${plan.promoter.isEmpty ? name : plan.promoter} · ${plan.summary}',
      ].join('；'),
      substitution: results.isEmpty
          ? '尚未配置阶梯规则'
          : results.map((r) => r.substitution).join('\n'),
      missing: results.isEmpty ? const ['阶梯规则'] : const [],
    );
  }
  if (item.tiered) {
    // 推广费：每个产品一个推广商；没配但产品结算里有应付行，按产品结算；都没有按 0 计。
    final allPlans = proposalPromotionPlansOf(form);
    final plans = [
      for (final plan in allPlans)
        if (!plan.isEmpty) plan,
    ].take(1).toList();
    if (plans.isNotEmpty || !settled) {
      final scale = proposalEffectiveSalesScale(form);
      final results = [for (final plan in plans) plan.evaluate(scale)];
      final amount = proposalRoundWan(
        results.fold<double>(0, (sum, r) => sum + r.amount),
      );
      return ProposalFinanceLine(
        name: name,
        formula: item.defaultFormulaRef,
        amount: amount,
        pending: plans.isEmpty,
        substitution: plans.isEmpty
            ? '还没配置推广商方案，按 0 计'
            : plans.length == 1
            ? results.single.substitution
            : [
                for (var i = 0; i < plans.length; i++)
                  '${plans[i].label}：${results[i].substitution}',
                '合计 ${_wan(amount)} 万元',
              ].join('\n'),
        source: plans.isEmpty
            ? ''
            : [
                for (final plan in plans) '推广商 ${plan.label} · ${plan.summary}',
              ].join('；'),
        promotionMonthlyScale: scale / 12,
      );
    }
  }
  final generic =
      item.formulaOf(kProposalProjectSettleFormulaCode) ??
      item.defaultFormulaRef;
  final picked = _projectSettleFormulaLabel(form, name, costNames: costNames);
  final formula = picked.isEmpty || generic == null
      ? generic
      : ProposalFinanceFormula(
          code: generic.code,
          name: picked,
          expression: generic.expression,
          kind: generic.kind,
        );
  final amount = settled ? settleCost(name) : null;
  if (amount == null) {
    return ProposalFinanceLine(
      name: name,
      formula: formula,
      amount: 0,
      substitution: '产品结算里还没有「$name」的应付行，按 0 计；请在上方产品结算补一行',
    );
  }
  final detail = proposalProjectCostFormulaSubstitution(form, name);
  return ProposalFinanceLine(
    name: name,
    formula: formula,
    amount: proposalRoundWan(amount),
    substitution: detail.isEmpty ? '= ${_wan(amount)} 万元' : detail,
    source: _projectSettleSource(form, name, costNames: costNames),
    locked: true,
  );
}

ProposalFinanceLine _evaluateCostLine(
  Map<String, dynamic> form, {
  required String name,
  required ProposalFinanceFormula? formula,
  required double scale,
  required double revenue,
  required double project,
  required double operating,
  required double business,
  required double? Function(String name) settleCost,
}) {
  if (formula == null) {
    return ProposalFinanceLine(name: name, amount: 0, missing: const ['计算公式']);
  }
  final rate = formula.rate;
  ProposalFinanceLine line(
    double amount,
    String substitution, [
    List<String> missing = const [],
  ]) => ProposalFinanceLine(
    name: name,
    formula: formula,
    amount: proposalRoundWan(amount),
    substitution: substitution,
    missing: missing,
  );

  switch (formula.kind) {
    case ProposalFinanceFormulaKind.tiered:
      {
        return ProposalFinanceLine(
          name: name,
          formula: formula,
          amount: 0,
          pending: true,
          substitution: '还没配置阶梯，按 0 计',
        );
      }
    case ProposalFinanceFormulaKind.settleScale:
      {
        final settled = settleCost(name);
        if (settled == null) {
          return line(0, '产品成本结算里没有「$name」，按 0 计', ['「$name」成本结算']);
        }
        final detail = proposalProjectCostFormulaSubstitution(form, name);
        return line(settled, detail.isEmpty ? '= ${_wan(settled)} 万元' : detail);
      }
    case ProposalFinanceFormulaKind.settleRevenue:
      {
        final settled = settleCost(name);
        if (settled == null || scale <= 0) {
          return line(0, '产品成本结算里没有「$name」，按 0 计', ['「$name」成本结算']);
        }
        final share = settled / scale;
        final amount = revenue * share;
        return line(
          amount,
          '${_wan(revenue)} × ${_pct(share)} = ${_wan(amount)} 万元',
        );
      }
    case ProposalFinanceFormulaKind.scaleRate:
      {
        final amount = scale * rate;
        return line(
          amount,
          '${_wan(scale)} × ${_pct(rate)} = ${_wan(amount)} 万元',
          scale > 0 ? const [] : const ['销售规模'],
        );
      }
    case ProposalFinanceFormulaKind.revenueRate:
      {
        final amount = revenue * rate;
        return line(
          amount,
          '${_wan(revenue)} × ${_pct(rate)} = ${_wan(amount)} 万元',
        );
      }
    case ProposalFinanceFormulaKind.grossRate:
      {
        final amount = math.max(0.0, revenue - project) * rate;
        return line(
          amount,
          '(${_wan(revenue)} − ${_wan(project)}) × ${_pct(rate)} = ${_wan(amount)} 万元',
        );
      }
    case ProposalFinanceFormulaKind.netOpRate:
      {
        final amount = math.max(0.0, revenue - project - operating) * rate;
        return line(
          amount,
          operating > 0
              ? '(${_wan(revenue)} − ${_wan(project)} − ${_wan(operating)}) × ${_pct(rate)} = ${_wan(amount)} 万元'
              : '(${_wan(revenue)} − ${_wan(project)}) × ${_pct(rate)} = ${_wan(amount)} 万元',
        );
      }
    case ProposalFinanceFormulaKind.pretaxRate:
      {
        final amount =
            math.max(0.0, revenue - project - business - operating) * rate;
        return line(
          amount,
          operating > 0
              ? '(${_wan(revenue)} − ${_wan(project)} − ${_wan(business)} − ${_wan(operating)}) × ${_pct(rate)} = ${_wan(amount)} 万元'
              : '(${_wan(revenue)} − ${_wan(project)} − ${_wan(business)}) × ${_pct(rate)} = ${_wan(amount)} 万元',
        );
      }
    case ProposalFinanceFormulaKind.vat:
      {
        final vat = proposalVatEstimate(
          Map<String, dynamic>.from(form)
            ..['revenue'] = revenue
            ..[kProposalRevenueManualKey] = true
            ..['projectCost'] = project,
        );
        return line(
          vat.payable,
          '(销项 ${_wan(vat.outputTax)} − 进项 ${_wan(vat.inputTax)}) × 1.12 = ${_wan(vat.payable)} 万元',
          vat.outputRate > 0 ? const [] : const ['销售结算税率'],
        );
      }
    default:
      return line(0, '暂不支持的公式类型 ${formula.kind}，按 0 计', ['计算公式']);
  }
}

// ---------------------------------------------------------------------------
// 写回表单
// ---------------------------------------------------------------------------

bool proposalFinanceCategoryTouched(Map<String, dynamic> form, String key) {
  final raw = form[kProposalFinanceFormulaTouchedKey];
  return raw is Map && raw[key] == true;
}

/// 用户没动过的类，按产品结算预选一次建议项：项目成本取成本结算里匹配到的类型，
/// 税务成本预选印花税和对应口径的增值税。用户改过之后不再自动加回。
Map<String, dynamic> _seedSuggestedItems(
  Map<String, dynamic> form,
  ProposalFinanceFormulaCatalog catalog, {
  required List<String> costNames,
}) {
  var next = form;
  final project = catalog.category(kProposalCostCategoryProject);
  if (project != null &&
      !proposalFinanceCategoryTouched(form, project.key) &&
      proposalFinanceSelectedNames(form, project).isEmpty) {
    final matched = proposalMatchedProjectCostNames(form, costNames: costNames);
    if (matched.isNotEmpty) {
      next = Map<String, dynamic>.from(next)..[project.namesKey] = matched;
    }
  }
  // 税务成本仅在用户尚未选择时提供建议；手动取消后不再自动加回。
  final tax = catalog.category(kProposalCostCategoryTax);
  if (tax != null && !proposalFinanceCategoryTouched(form, tax.key)) {
    final suggested = proposalEnsureAutoTaxItemNames(next);
    if (suggested.isNotEmpty) {
      next = Map<String, dynamic>.from(next)..[tax.namesKey] = suggested;
    }
  }
  return next;
}

/// 按公式算出收入、各项成本、利润、毛利率，写回表单（组上写各产品加总）。
///
/// 业务成本被加密时（负责人二），这里看不到业务成本，算出的利润不完整，
/// 所以不写业务成本、利润和毛利率，保留服务端已有值。
Map<String, dynamic> proposalApplyFinanceFormulas(
  Map<String, dynamic> form, {
  ProposalFinanceFormulaCatalog? catalog,
  List<ProposalCostItemOption> costCatalog = const [],
  List<ProposalCostItemOption> businessCatalog = const [],
  List<String> costNames = const [],
  String owner = kProposalProductFinanceMain,
}) {
  final dict = catalog ?? ProposalFinanceFormulaCatalog.fallback;
  final eval = proposalEvaluateFinance(
    form,
    catalog: dict,
    costCatalog: costCatalog,
    costNames: costNames,
    owner: owner,
  );
  final redacted = form['businessCostRedacted'] == true;
  final next = Map<String, dynamic>.from(form)
    ..remove(kProposalCouponProcurementCostKey)
    ..remove(kProposalProcurementManualKey)
    ..remove('operatingCostItemFormulas')
    ..['operatingCostItemAmounts'] = <String, dynamic>{}
    ..['operatingCost'] = 0
    ..['revenue'] = eval.revenue.amount
    ..[kProposalRevenueManualKey] = false;
  final revenueFormula = eval.revenue.formula;
  if (revenueFormula != null) {
    next[kProposalRevenueFormulaKey] = revenueFormula.code;
    next[kProposalRevenueFormulaGroupKey] = eval.revenueGroup?.key ?? '';
  }
  for (final bucket in eval.buckets.values) {
    final category = bucket.category;
    if (redacted && category.key == kProposalCostCategoryBusiness) continue;
    final idCatalog = switch (category.key) {
      kProposalCostCategoryProject => costCatalog,
      kProposalCostCategoryBusiness => businessCatalog,
      _ => const <ProposalCostItemOption>[],
    };
    next[category.namesKey] = bucket.names;
    next[category.amountsKey] = <String, dynamic>{
      for (final line in bucket.lines)
        proposalCostAmountId(line.name, idCatalog): line.amount,
    };
    next[category.formulasKey] = <String, dynamic>{
      for (final line in bucket.lines)
        if (line.formula != null) line.name: line.formula!.code,
    };
    next[category.totalKey] = bucket.total;
  }
  // 展示开关不影响测算回写；脱敏用户不覆盖服务端利润。
  if (!redacted) {
    next['profit'] = eval.profit;
    next['margin'] = eval.margin ?? 0;
  }
  return next;
}

/// 改选成本项：维持增值税二选一，并记下「用户动过」，之后不再自动预选。
Map<String, dynamic> proposalFinanceWriteSelection(
  Map<String, dynamic> finance,
  ProposalCostCategory category,
  List<String> names,
) {
  var list = <String>[
    for (final name in names)
      if (name.trim().isNotEmpty) name.trim(),
  ];
  if (category.key == kProposalCostCategoryTax) {
    list = proposalExclusiveVatTaxNames(list);
  }
  final formulas = proposalFinanceFormulaChoices(finance, category)
    ..removeWhere((name, _) => !list.contains(name));
  final touched = _mapOf(finance[kProposalFinanceFormulaTouchedKey])
    ..[category.key] = true;
  return Map<String, dynamic>.from(finance)
    ..[category.namesKey] = list
    ..[category.formulasKey] = formulas
    ..[kProposalFinanceFormulaTouchedKey] = touched;
}

Map<String, dynamic> proposalFinanceWriteItemFormula(
  Map<String, dynamic> finance,
  ProposalCostCategory category,
  String name,
  String code,
) {
  final formulas = proposalFinanceFormulaChoices(finance, category)
    ..[name] = code;
  return Map<String, dynamic>.from(finance)..[category.formulasKey] = formulas;
}

Map<String, dynamic> proposalFinanceWriteRevenueFormula(
  Map<String, dynamic> finance, {
  required String groupKey,
  required String code,
}) {
  return Map<String, dynamic>.from(finance)
    ..[kProposalRevenueFormulaKey] = code
    ..[kProposalRevenueFormulaGroupKey] = groupKey
    ..[kProposalRevenueManualKey] = false;
}

/// 简单行 / 摘要里用的一行文字：「合计 12 万元 · 机构返佣 8 · 支付手续费 4」。
String proposalFinanceBucketSummary(ProposalFinanceBucket? bucket) {
  if (bucket == null || bucket.lines.isEmpty) return '';
  return [
    '合计 ${_wan(bucket.total)} 万元',
    for (final line in bucket.lines)
      line.pending ? '${line.name} 未配置阶梯' : '${line.name} ${_wan(line.amount)}',
  ].join(' · ');
}
