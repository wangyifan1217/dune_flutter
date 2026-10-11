import 'dart:math' as math;

import 'proposal_cost_estimate.dart';
import 'proposal_intake_models.dart';

/// 销售提案「财务部」按公式测算。
///
/// 财务部不再手填金额：收入按所选渠道侧结算公式算，四类成本各自选成本项和公式，
/// 利润 = 收入 − 项目成本 − 业务成本 − 经营成本 − 税务成本。
/// 字典（收入公式、成本项、成本公式）由后端 `options.finance.formulaCatalog`
/// 下发；后端没给时用本文件里的兜底字典。

const kProposalRevenueFormulaKey = 'revenueFormula';
const kProposalRevenueFormulaGroupKey = 'revenueFormulaGroup';
const kProposalFinanceFormulaTouchedKey = 'financeFormulaTouched';

/// 推广费阶梯：{basis: monthly|annual, mode: whole|excess, tiers: [{from, rate}]}。
const kProposalPromotionTiersKey = 'promotionTiers';

const kProposalCostCategoryProject = 'project';
const kProposalCostCategoryBusiness = 'business';
const kProposalCostCategoryOperating = 'operating';
const kProposalCostCategoryTax = 'tax';

/// 计算顺序：项目 → 经营 → 业务 → 税务。后面的公式会用到前面的合计。
const kProposalCostCategoryOrder = <String>[
  kProposalCostCategoryProject,
  kProposalCostCategoryOperating,
  kProposalCostCategoryBusiness,
  kProposalCostCategoryTax,
];

/// 页面展示顺序：项目 → 业务 → 经营 → 税务（与利润公式里的顺序一致）。
const kProposalCostCategoryDisplayOrder = <String>[
  kProposalCostCategoryProject,
  kProposalCostCategoryBusiness,
  kProposalCostCategoryOperating,
  kProposalCostCategoryTax,
];

/// 公式写入表单的字段（每个产品财务组各存一份）。
const kProposalFinanceFormulaFormKeys = <String>[
  kProposalRevenueFormulaKey,
  kProposalRevenueFormulaGroupKey,
  kProposalFinanceFormulaTouchedKey,
  kProposalPromotionTiersKey,
  'costItemFormulas',
  'businessCostItemFormulas',
  'operatingCostItemFormulas',
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

  static final ProposalFinanceFormulaCatalog fallback =
      _buildFallbackCatalog();
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
  expression: '按规模分档计费：全额累进（整笔按达到的档位比例）或超额累进（每段按各自档位比例）',
  kind: ProposalFinanceFormulaKind.tiered,
);

const _kBusinessCostFormulas = <ProposalFinanceFormula>[
  ProposalFinanceFormula(
    code: 'BIZ_NET_10',
    name: '（收入 − 项目 − 经营）× 10%',
    expression: '(收入 − 项目成本 − 经营成本) × 10%',
    kind: ProposalFinanceFormulaKind.netOpRate,
    rate: 0.10,
  ),
  ProposalFinanceFormula(
    code: 'BIZ_NET_45',
    name: '（收入 − 项目 − 经营）× 45%',
    expression: '(收入 − 项目成本 − 经营成本) × 45%',
    kind: ProposalFinanceFormulaKind.netOpRate,
    rate: 0.45,
  ),
];

const _kOperatingCostFormulas = <ProposalFinanceFormula>[
  ProposalFinanceFormula(
    code: 'OP_GROSS_2',
    name: '（收入 − 项目成本）× 2%',
    expression: '(收入 − 项目成本) × 2%',
    kind: ProposalFinanceFormulaKind.grossRate,
    rate: 0.02,
  ),
  ProposalFinanceFormula(
    code: 'OP_REVENUE_2',
    name: '收入 × 2%',
    expression: '收入 × 2%',
    kind: ProposalFinanceFormulaKind.revenueRate,
    rate: 0.02,
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
    expression: '(收入 − 项目成本 − 业务成本 − 经营成本) × 25%',
    kind: ProposalFinanceFormulaKind.pretaxRate,
    rate: 0.25,
  ),
  ProposalFinanceFormula(
    code: 'TAX_INCOME_15',
    name: '应税利润 × 15%（高新技术企业）',
    expression: '(收入 − 项目成本 − 业务成本 − 经营成本) × 15%',
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
      hint: '推广费按阶梯计费：在下面配置档位（起点 + 比例），选按月或按年规模、全额或超额累进。',
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
        _f(
          '9',
          '按下发统计结算单价*结算比例',
          '按下发统计结算单价 * 结算比例',
          _kUnitRatioMethod,
        ),
        _f('11', '兑换金额*结算比例', '兑换金额 * 结算比例'),
        _f('12', '积分/返费采购款*结算比例', '积分/返费采购款 * 结算比例'),
        _f('21', '（券包销售款-推广费+利差）*结算比例', '（券包销售款-推广费+利差） * 结算比例'),
        _f('23', '按下发统计结算单价', '按下发统计结算单价', _kUnitMethod),
        _f('24', '按核销统计结算单价', '按核销统计结算单价', _kUnitMethod),
        _f(
          '34',
          '（券包销售款-推广费+利差-渠道侧N）*结算比例',
          '（券包销售款-推广费+利差-渠道侧N）*结算比例',
        ),
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
        items: [for (final name in _kDefaultProjectCostNames) _projectCostOption(name)],
      ),
      ProposalCostCategory(
        key: kProposalCostCategoryBusiness,
        name: '业务成本',
        namesKey: 'businessCostItems',
        amountsKey: 'businessCostItemAmounts',
        totalKey: 'businessCost',
        formulasKey: 'businessCostItemFormulas',
        filler: '市场部负责人一在财务复核时选择；负责人二不可见',
        items: [
          for (final name in _kDefaultBusinessCostNames) _businessCostOption(name),
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
        items: [
          ProposalCostTypeOption(
            code: '差旅成本',
            name: '差旅成本',
            formulas: _kOperatingCostFormulas,
            defaultFormula: 'OP_GROSS_2',
          ),
          ProposalCostTypeOption(
            code: '招待费',
            name: '招待费',
            formulas: _kOperatingCostFormulas,
            defaultFormula: 'OP_GROSS_2',
          ),
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

/// 一档：规模达到 [from]（万元）起，按 [rate]（%）计。
class ProposalPromotionTier {
  const ProposalPromotionTier({required this.from, required this.rate});

  final double from;
  final double rate;

  Map<String, dynamic> toJson() => {'from': from, 'rate': rate};
}

/// 推广费阶梯方案。
///
/// - 计量 [basis]：`monthly` 按月规模（年化 ÷ 12）分档，算出月费 × 12；`annual` 按年规模分档。
/// - 计费 [mode]：`whole` 全额累进——落在哪档，整笔规模按该档比例；
///   `excess` 超额累进——每一段规模按各自档位比例，再加总。
class ProposalPromotionTierPlan {
  const ProposalPromotionTierPlan({
    this.basis = 'monthly',
    this.mode = 'whole',
    this.tiers = const [],
  });

  final String basis;
  final String mode;
  final List<ProposalPromotionTier> tiers;

  bool get monthly => basis != 'annual';
  bool get excess => mode == 'excess';
  bool get isEmpty => tiers.isEmpty;

  List<ProposalPromotionTier> get sorted =>
      [...tiers]..sort((a, b) => a.from.compareTo(b.from));

  factory ProposalPromotionTierPlan.fromJson(Object? raw) {
    final map = _mapOf(raw);
    return ProposalPromotionTierPlan(
      basis: _str(map['basis']) == 'annual' ? 'annual' : 'monthly',
      mode: _str(map['mode']) == 'excess' ? 'excess' : 'whole',
      tiers: [
        for (final item in _listOf(map['tiers']))
          ProposalPromotionTier(
            from: _num(_mapOf(item)['from']),
            rate: _num(_mapOf(item)['rate']),
          ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'basis': basis,
    'mode': mode,
    'tiers': [for (final tier in tiers) tier.toJson()],
  };

  ProposalPromotionTierPlan copyWith({
    String? basis,
    String? mode,
    List<ProposalPromotionTier>? tiers,
  }) => ProposalPromotionTierPlan(
    basis: basis ?? this.basis,
    mode: mode ?? this.mode,
    tiers: tiers ?? this.tiers,
  );

  /// 落在第几档（按 [sorted] 的下标）；一档都没到为 -1。
  int hitIndex(double annualScale) {
    final volume = monthly ? annualScale / 12 : annualScale;
    final list = sorted;
    var hit = -1;
    for (var i = 0; i < list.length; i++) {
      if (volume >= list[i].from) hit = i;
    }
    return hit;
  }

  /// 年化推广费（万元）和代入过程。
  ({double amount, String substitution, int hit}) evaluate(double annualScale) {
    final list = sorted;
    final volume = monthly ? annualScale / 12 : annualScale;
    final unit = monthly ? '月规模' : '年规模';
    final hit = hitIndex(annualScale);
    if (list.isEmpty || hit < 0) {
      return (
        amount: 0,
        substitution: list.isEmpty
            ? '还没配置阶梯，按 0 计'
            : '$unit ${_wan(volume)} 万，未达到第 1 档（≥ ${_wan(list.first.from)} 万），按 0 计',
        hit: hit,
      );
    }
    double fee;
    String detail;
    if (excess) {
      fee = 0;
      final parts = <String>[];
      for (var i = 0; i <= hit; i++) {
        final lower = list[i].from;
        final upper = i + 1 < list.length ? list[i + 1].from : double.infinity;
        final part = (volume < upper ? volume : upper) - lower;
        if (part <= 0) continue;
        fee += part * list[i].rate / 100;
        parts.add('${_wan(part)} × ${_wan(list[i].rate)}%');
      }
      detail = '$unit ${_wan(volume)} 万，超额累进：${parts.join(' + ')} = ${_wan(fee)} 万';
    } else {
      fee = volume * list[hit].rate / 100;
      detail =
          '$unit ${_wan(volume)} 万，落在第 ${hit + 1} 档（≥ ${_wan(list[hit].from)} 万，${_wan(list[hit].rate)}%），全额累进：${_wan(volume)} × ${_wan(list[hit].rate)}% = ${_wan(fee)} 万';
    }
    final annual = monthly ? fee * 12 : fee;
    return (
      amount: proposalRoundWan(annual),
      substitution: monthly ? '$detail/月 × 12 = ${_wan(annual)} 万元' : '$detail元',
      hit: hit,
    );
  }
}

ProposalPromotionTierPlan proposalPromotionTierPlanOf(
  Map<String, dynamic> form,
) => ProposalPromotionTierPlan.fromJson(form[kProposalPromotionTiersKey]);

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
    this.tierHit = -1,
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

  /// 推广费阶梯命中的档位（排序后下标），未命中 / 非阶梯为 -1。
  final int tierHit;
}

class ProposalFinanceBucket {
  const ProposalFinanceBucket({required this.category, required this.lines});

  final ProposalCostCategory category;
  final List<ProposalFinanceLine> lines;

  double get total => proposalRoundWan(
    lines.fold<double>(0, (sum, line) => sum + line.amount),
  );

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
  });

  final double salesScale;

  /// 当前收入公式所在组；对不上业务平台时为 null。
  final ProposalRevenueFormulaGroup? revenueGroup;

  /// 收入公式下拉里可选的组（按产品业务平台筛过）。
  final List<ProposalRevenueFormulaGroup> revenueGroups;
  final ProposalFinanceLine revenue;
  final Map<String, ProposalFinanceBucket> buckets;
  final double profit;
  final String profitSubstitution;
  final double? margin;
  final String marginSubstitution;

  ProposalFinanceBucket? bucket(String key) => buckets[key];

  double total(String key) => buckets[key]?.total ?? 0;

  double get costTotal => proposalRoundWan(
    buckets.values.fold<double>(0, (sum, bucket) => sum + bucket.total),
  );
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
    for (final name in proposalMatchedProjectCostNames(form, costNames: costNames))
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
  for (final hit in proposalPayableProjectCostHits(form, costNames: costNames)) {
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

ProposalFinanceEvaluation proposalEvaluateFinance(
  Map<String, dynamic> form, {
  ProposalFinanceFormulaCatalog? catalog,
  List<ProposalCostItemOption> costCatalog = const [],
  List<String> costNames = const [],
}) {
  final dict = catalog ?? ProposalFinanceFormulaCatalog.fallback;
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
    final names = proposalFinanceSelectedNames(form, category);
    if (key == kProposalCostCategoryProject) {
      // 产品结算里有的项目成本一律带出，不依赖有没有勾选。
      for (final name in settledNames) {
        if (!names.contains(name)) names.add(name);
      }
    }
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
      lines.add(
        _evaluateCostLine(
          form,
          name: name,
          formula: proposalFinanceItemFormula(form, category, name),
          scale: scale,
          revenue: revenue,
          project: totals[kProposalCostCategoryProject] ?? 0,
          operating: totals[kProposalCostCategoryOperating] ?? 0,
          business: totals[kProposalCostCategoryBusiness] ?? 0,
          settleCost: settleCost,
        ),
      );
    }
    final bucket = ProposalFinanceBucket(category: category, lines: lines);
    buckets[key] = bucket;
    totals[key] = bucket.total;
  }

  // ---- 利润 ----
  final p = totals[kProposalCostCategoryProject] ?? 0;
  final b = totals[kProposalCostCategoryBusiness] ?? 0;
  final o = totals[kProposalCostCategoryOperating] ?? 0;
  final t = totals[kProposalCostCategoryTax] ?? 0;
  final profit = proposalRoundWan(revenue - p - b - o - t);
  final margin = scale > 0 ? proposalRoundWan(profit / scale * 100) : null;
  return ProposalFinanceEvaluation(
    salesScale: scale,
    revenueGroup: resolved.group,
    revenueGroups: dict.groupsForSources(proposalFinanceSyncSources(form)),
    revenue: revenueLine,
    buckets: {
      for (final key in kProposalCostCategoryDisplayOrder)
        if (buckets[key] != null) key: buckets[key]!,
    },
    profit: profit,
    profitSubstitution:
        '${_wan(revenue)} − ${_wan(p)} − ${_wan(b)} − ${_wan(o)} − ${_wan(t)} = ${_wan(profit)} 万元',
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
  if (item.tiered) {
    // 推广费：配了阶梯按阶梯算；没配但产品结算里有应付行，按产品结算；都没有按 0 计。
    final plan = proposalPromotionTierPlanOf(form);
    if (!plan.isEmpty || !settled) {
      final result = plan.evaluate(proposalEffectiveSalesScale(form));
      return ProposalFinanceLine(
        name: name,
        formula: item.defaultFormulaRef,
        amount: result.amount,
        pending: plan.isEmpty,
        substitution: result.substitution,
        source: plan.isEmpty
            ? ''
            : '阶梯 ${plan.tiers.length} 档 · ${plan.monthly ? '按月规模' : '按年规模'} · ${plan.excess ? '超额累进' : '全额累进'}',
        tierHit: result.hit,
      );
    }
  }
  final formula =
      item.formulaOf(kProposalProjectSettleFormulaCode) ??
      item.defaultFormulaRef;
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
    return ProposalFinanceLine(
      name: name,
      amount: 0,
      missing: const ['计算公式'],
    );
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
        return line(
          settled,
          detail.isEmpty ? '= ${_wan(settled)} 万元' : detail,
        );
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
          '(${_wan(revenue)} − ${_wan(project)} − ${_wan(operating)}) × ${_pct(rate)} = ${_wan(amount)} 万元',
        );
      }
    case ProposalFinanceFormulaKind.pretaxRate:
      {
        final amount =
            math.max(0.0, revenue - project - business - operating) * rate;
        return line(
          amount,
          '(${_wan(revenue)} − ${_wan(project)} − ${_wan(business)} − ${_wan(operating)}) × ${_pct(rate)} = ${_wan(amount)} 万元',
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
  final tax = catalog.category(kProposalCostCategoryTax);
  if (tax != null &&
      !proposalFinanceCategoryTouched(form, tax.key) &&
      proposalFinanceSelectedNames(form, tax).isEmpty) {
    final suggested = proposalEnsureAutoTaxItemNames(next);
    if (suggested.isNotEmpty) {
      next = Map<String, dynamic>.from(next)..[tax.namesKey] = suggested;
    }
  }
  return next;
}

/// 按公式算出收入、各项成本、利润、毛利率，写回表单。
///
/// 业务成本被加密时（负责人二），这里看不到业务成本，算出的利润不完整，
/// 所以不写业务成本、利润和毛利率，保留服务端已有值。
Map<String, dynamic> proposalApplyFinanceFormulas(
  Map<String, dynamic> form, {
  ProposalFinanceFormulaCatalog? catalog,
  List<ProposalCostItemOption> costCatalog = const [],
  List<ProposalCostItemOption> businessCatalog = const [],
  List<String> costNames = const [],
}) {
  final dict = catalog ?? ProposalFinanceFormulaCatalog.fallback;
  final seeded = _seedSuggestedItems(form, dict, costNames: costNames);
  final eval = proposalEvaluateFinance(
    seeded,
    catalog: dict,
    costCatalog: costCatalog,
    costNames: costNames,
  );
  final redacted = form['businessCostRedacted'] == true;
  final next = Map<String, dynamic>.from(seeded)
    ..remove(kProposalCouponProcurementCostKey)
    ..remove(kProposalProcurementManualKey)
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
      line.pending
          ? '${line.name} 未配置阶梯'
          : '${line.name} ${_wan(line.amount)}',
  ].join(' · ');
}
