// ═════════════════════════════════════════════════════════════════════════════
// 灯塔 · 人效维度 —— 模型与算分引擎
//
//   人效不是一套新数据，是账本换一个分组键：产品 / 供给方 / 渠道 是按业务实体
//   分组，人效是按「负责人 × 任务」分组。指标口径、环比口径、账本版式全部沿用。
//
//   算分公式来自人事《月度绩效考评表》的「评分标准」列，原文是：
//     「（本月收入-上月收入）/上月收入，基准分 25 分，每增长 1% 加 0.5 分，
//       最高加 10 分；每下降 1%，扣 0.5 分，最低扣至 0 分」
//   反推成一条式子就是 clamp(base + 增长百分点 × step, 0, cap)。已用 M4 两张表
//   的真实得分回归：王轩内蒙古 −10.31% → 19.85、湖南利润 −115.96% → 0、
//   徐朝平安民营 +3.70% → 26.85，逐项对上（见 test/lighthouse_people_test.dart）。
//
//   前端只做「拿到指标→出分」这一步，是为了让日/周/季/年也能实时出分；
//   服务端下发 score 时以服务端为准（[LhPeopleRow.fromJson] 优先取 score）。
// ═════════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

/// 人效指标模板 —— 挂在**任务**上，不是挂在人身上。
/// 李同池同时背陕西移动（会员型）和陕西中石油（省份型），两个任务两套模板。
enum LhPeopleTemplate {
  /// 省份 / 渠道型（能源板块）：营收 + 利润 + 折扣达标 + 绝对值利润率。
  province,

  /// 会员 / 用户型（通信板块）：营收 + 利润 + 真实用户 + 新增用户 + 利润率 + 回款。
  member,
}

extension LhPeopleTemplateX on LhPeopleTemplate {
  String get code => this == LhPeopleTemplate.province ? 'A' : 'B';
  String get label => this == LhPeopleTemplate.province ? '省份/渠道型' : '会员/用户型';

  /// 该模板的满分。两套不一致是人事表本身的问题，不是这里算错了 ——
  /// 所以列表提供「标准百分制」口径开关，否则能源和通信没法放一起排。
  double get fullMark => this == LhPeopleTemplate.province ? 115 : 120;

  static LhPeopleTemplate parse(Object? v) {
    final s = v?.toString().trim().toUpperCase() ?? '';
    if (s == 'A' || s == 'PROVINCE' || s == '省份' || s == '能源') {
      return LhPeopleTemplate.province;
    }
    return LhPeopleTemplate.member;
  }
}

/// 一个评分分项的规则：基准分 / 每百分点加减 / 封顶。
@immutable
class LhScoreRule {
  const LhScoreRule({
    required this.key,
    required this.label,
    required this.base,
    required this.step,
    required this.cap,
  });

  final String key;
  final String label;

  /// 增长为 0 时得几分。
  final double base;

  /// 每 1 个百分点加减几分。
  final double step;

  /// 封顶。注意不是 base + 最高加分：人事表里营收基准 25、最高加 10，
  /// 但下降时最低扣到 0，所以只需要一个 cap 和一个 0 下界。
  final double cap;

  /// [growth] 传增长率（小数，0.12 = +12%）。null 表示无同期基数。
  double score(double? growth) {
    if (growth == null) return 0;
    final v = base + growth * 100 * step;
    if (v.isNaN || !v.isFinite) return cap;
    return v.clamp(0, cap).toDouble();
  }
}

/// 零基数：上期为 0、本期有量时环比是 ∞。人事表当时按满分处理（徐朝的积分返费
/// 因此拿满 35，李钧庚全年 112 分）。这里保留原口径但打 [LhPeopleFlag.zeroBase]
/// 标记，让列表能把这种分数标出来，而不是让它安静地混在排行里。
const double kLhZeroBaseGrowth = 999.0;

abstract final class LhPeopleRules {
  static const revenue = LhScoreRule(
    key: 'rev',
    label: '营收环比增长',
    base: 25,
    step: 0.5,
    cap: 35,
  );
  static const profit = LhScoreRule(
    key: 'profit',
    label: '利润环比增长',
    base: 25,
    step: 0.5,
    cap: 35,
  );
  static const realUsers = LhScoreRule(
    key: 'real',
    label: '真实用户环比',
    base: 18,
    step: 0.5,
    cap: 20,
  );
  static const newUsers = LhScoreRule(
    key: 'new',
    label: '新增用户环比',
    base: 8,
    step: 0.2,
    cap: 10,
  );

  /// 绝对值利润率：省份型基准 15 封顶 25，会员型基准 8 封顶 10。
  static const marginProvince = LhScoreRule(
    key: 'margin',
    label: '绝对值利润率',
    base: 15,
    step: 0.2,
    cap: 25,
  );
  static const marginMember = LhScoreRule(
    key: 'margin',
    label: '绝对值利润率',
    base: 8,
    step: 0.2,
    cap: 10,
  );

  static const double discountFull = 20;
  static const double receivableFull = 10;
}

/// 数据健康标记 —— 分数旁边必须挂标记，不允许来源不明的分数上屏。
enum LhPeopleFlag {
  /// 个人页没有任何收入 / 利润填报，分数无法回溯。
  noSource,

  /// 本期列整片空白，公式会算成 −100%，和真的跌到 0 必须分开。
  missingCurrent,

  /// 任务权重填 0 / 权重合计 ≠ 100%。
  badWeight,

  /// 上期基数为 0，环比无意义。
  zeroBase,

  /// 填报单位与其余人不一致（元 vs 万元）。
  badUnit,
}

extension LhPeopleFlagX on LhPeopleFlag {
  String get label => switch (this) {
    LhPeopleFlag.noSource => '无底表数据',
    LhPeopleFlag.missingCurrent => '本期未填',
    LhPeopleFlag.badWeight => '权重异常',
    LhPeopleFlag.zeroBase => '零基数',
    LhPeopleFlag.badUnit => '单位口径',
  };

  static LhPeopleFlag? parse(Object? v) {
    switch (v?.toString().trim()) {
      case 'noSource':
      case '无底表数据':
        return LhPeopleFlag.noSource;
      case 'missingCurrent':
      case '本期未填':
      case '本月未填':
        return LhPeopleFlag.missingCurrent;
      case 'badWeight':
      case '权重异常':
      case '权重为0':
        return LhPeopleFlag.badWeight;
      case 'zeroBase':
      case '零基数':
        return LhPeopleFlag.zeroBase;
      case 'badUnit':
      case '单位口径':
      case '单位口径不一致':
        return LhPeopleFlag.badUnit;
    }
    return null;
  }
}

/// 绩效等级。分档取自考评表底部「考核结果」那一行。
@immutable
class LhPeopleGrade {
  const LhPeopleGrade(this.label, this.coefficient);

  final String label;
  final double coefficient;

  static const excellent = LhPeopleGrade('优', 1.1);
  static const good = LhPeopleGrade('良', 1.0);
  static const below = LhPeopleGrade('低于预期', 0.9);
  static const improve = LhPeopleGrade('待改进', 0.8);
  static const risk = LhPeopleGrade('危', 0.7);
  static const out = LhPeopleGrade('汰', 0.6);

  static LhPeopleGrade of(double score) {
    if (score >= 95) return excellent;
    if (score >= 85) return good;
    if (score >= 80) return below;
    if (score >= 75) return improve;
    if (score >= 70) return risk;
    return out;
  }

  bool get isAlert => coefficient <= 0.7;
}

double? _num(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  if (s.isEmpty || s == '—' || s == '/') return null;
  return double.tryParse(s);
}

/// 环比 —— 同期对齐窗口由服务端给，这里只做除法。
/// 上期为 0：本期有量视同满分增长，双零视同持平。
double? lhPeopleGrowth(double? cur, double? prev) {
  if (cur == null || prev == null) return null;
  if (prev.abs() < 1e-9) return cur.abs() < 1e-9 ? 0 : kLhZeroBaseGrowth;
  return (cur - prev) / prev.abs();
}

/// 一项任务（= 该人负责的一个省份 / 渠道 / 会员产品坐标点）。
@immutable
class LhPeopleTask {
  const LhPeopleTask({
    required this.name,
    required this.weight,
    required this.template,
    this.revenue,
    this.prevRevenue,
    this.profit,
    this.prevProfit,
    this.realUsers,
    this.prevRealUsers,
    this.newUsers,
    this.prevNewUsers,
    this.overdue = false,
    this.discountAchieved = 1,
    this.discountTotal = 1,
    this.flags = const <LhPeopleFlag>{},
    this.serverScore,
  });

  final String name;

  /// 任务权重（0–1）。权重合计 ≠ 1 时打 [LhPeopleFlag.badWeight]。
  final double weight;
  final LhPeopleTemplate template;

  final double? revenue;
  final double? prevRevenue;
  final double? profit;
  final double? prevProfit;
  final double? realUsers;
  final double? prevRealUsers;
  final double? newUsers;
  final double? prevNewUsers;

  final bool overdue;
  final int discountAchieved;
  final int discountTotal;
  final Set<LhPeopleFlag> flags;

  /// 服务端已经算好的任务分；给了就不再本地算。
  final double? serverScore;

  bool get isMember => template == LhPeopleTemplate.member;

  double? get revGrowth => lhPeopleGrowth(revenue, prevRevenue);
  double? get profitGrowth => lhPeopleGrowth(profit, prevProfit);
  double? get realGrowth => lhPeopleGrowth(realUsers, prevRealUsers);
  double? get newGrowth => lhPeopleGrowth(newUsers, prevNewUsers);

  /// 本期利润率（%）。
  double? get marginPct =>
      (revenue == null || profit == null || revenue!.abs() < 1e-9)
      ? null
      : profit! / revenue! * 100;

  /// 绝对值利润率 = 本期利润/本期收入 − 同期利润/同期收入，单位是百分点。
  double? get marginDeltaPp {
    if (revenue == null || profit == null) return null;
    if (prevRevenue == null || prevProfit == null) return null;
    if (revenue!.abs() < 1e-9 || prevRevenue!.abs() < 1e-9) return null;
    return (profit! / revenue! - prevProfit! / prevRevenue!) * 100;
  }

  /// 各分项得分。key 与 [LhScoreRule.key] 一致，另有 discount / receivable。
  Map<String, double> get components {
    final marginRule = isMember
        ? LhPeopleRules.marginMember
        : LhPeopleRules.marginProvince;
    final out = <String, double>{
      'rev': LhPeopleRules.revenue.score(revGrowth),
      'profit': LhPeopleRules.profit.score(profitGrowth),
      // 绝对值利润率的入参是百分点差，不是增长率 —— 除以 100 还原成小数
      // 再乘回 100，等价于直接按百分点计；写成这样是为了和其他分项同一条式子。
      'margin': marginRule.score(
        marginDeltaPp == null ? null : marginDeltaPp! / 100,
      ),
    };
    if (isMember) {
      out['real'] = LhPeopleRules.realUsers.score(realGrowth);
      out['new'] = LhPeopleRules.newUsers.score(newGrowth);
      out['receivable'] = overdue ? 0 : LhPeopleRules.receivableFull;
    } else {
      out['discount'] =
          LhPeopleRules.discountFull *
          (discountAchieved.clamp(0, discountTotal)) /
          (discountTotal <= 0 ? 1 : discountTotal);
    }
    return out;
  }

  /// 该任务总分（未乘权重）。
  double get score =>
      serverScore ?? components.values.fold<double>(0, (a, b) => a + b);

  /// 计入个人加权总分的部分。
  double get weightedScore => score * weight;

  static LhPeopleTask fromJson(
    Map<String, dynamic> json, {
    required LhPeopleTemplate fallbackTemplate,
  }) {
    final m = (json['metrics'] as Map?)?.cast<String, dynamic>() ?? json;
    final p = (json['prev'] as Map?)?.cast<String, dynamic>() ?? const {};
    final tier = json['discountTier']?.toString() ?? '';
    var achieved = 1, total = 1;
    final match = RegExp(r'(\d+)\s*[/\-]\s*(\d+)').firstMatch(tier);
    if (match != null) {
      achieved = int.tryParse(match.group(1)!) ?? 1;
      total = int.tryParse(match.group(2)!) ?? 1;
    }
    return LhPeopleTask(
      name: json['name']?.toString() ?? '未命名任务',
      weight: _num(json['weight']) ?? 0,
      template: json['template'] == null
          ? fallbackTemplate
          : LhPeopleTemplateX.parse(json['template']),
      revenue: _num(m['revenue']),
      prevRevenue: _num(p['revenue'] ?? m['prevRevenue']),
      profit: _num(m['profit']),
      prevProfit: _num(p['profit'] ?? m['prevProfit']),
      realUsers: _num(m['realUsers']),
      prevRealUsers: _num(p['realUsers'] ?? m['prevRealUsers']),
      newUsers: _num(m['newUsers']),
      prevNewUsers: _num(p['newUsers'] ?? m['prevNewUsers']),
      overdue: json['receivable']?.toString().contains('逾期') == true &&
          json['receivable']?.toString().contains('未逾期') != true,
      discountAchieved: achieved,
      discountTotal: total,
      flags: ((json['dataFlags'] as List?) ?? const [])
          .map(LhPeopleFlagX.parse)
          .whereType<LhPeopleFlag>()
          .toSet(),
      serverScore: _num(json['score']),
    );
  }
}

/// 一个人 = 账本里的一行。
@immutable
class LhPeopleRow {
  const LhPeopleRow({
    required this.id,
    required this.name,
    required this.group,
    required this.role,
    required this.tasks,
    this.serverScore,
    this.sheetScore,
    this.sheetGrade = '',
  });

  final String id;
  final String name;

  /// 板块 —— 走账本同一个 lhGroupColor / 分类筛选。
  final String group;
  final String role;
  final List<LhPeopleTask> tasks;

  /// 服务端下发的加权总分；给了就不本地算。
  final double? serverScore;

  /// 人事表 M4 的表内分，用于展开区对照（整月口径 vs 同期对齐口径）。
  final double? sheetScore;
  final String sheetGrade;

  LhPeopleTemplate get template =>
      tasks.isEmpty ? LhPeopleTemplate.member : tasks.first.template;

  bool get isMember => template == LhPeopleTemplate.member;
  double get fullMark => template.fullMark;

  double get weightSum => tasks.fold<double>(0, (a, t) => a + t.weight);

  /// 加权总分（原始分，满分 115 / 120）。
  double get score =>
      serverScore ?? tasks.fold<double>(0, (a, t) => a + t.weightedScore);

  /// 标准百分制 —— 两套模板满分不同，跨板块排序要用这个。
  double get standardScore => fullMark <= 0 ? 0 : score / fullMark * 100;

  LhPeopleGrade grade({bool standard = false}) =>
      LhPeopleGrade.of(standard ? standardScore : score);

  double _sum(double? Function(LhPeopleTask t) pick) {
    var any = false;
    var total = 0.0;
    for (final t in tasks) {
      final v = pick(t);
      if (v == null) continue;
      any = true;
      total += v;
    }
    return any ? total : double.nan;
  }

  double? _sumOrNull(double? Function(LhPeopleTask t) pick) {
    final v = _sum(pick);
    return v.isNaN ? null : v;
  }

  double? get revenue => _sumOrNull((t) => t.revenue);
  double? get prevRevenue => _sumOrNull((t) => t.prevRevenue);
  double? get profit => _sumOrNull((t) => t.profit);
  double? get prevProfit => _sumOrNull((t) => t.prevProfit);
  double? get realUsers => isMember ? _sumOrNull((t) => t.realUsers) : null;
  double? get prevRealUsers =>
      isMember ? _sumOrNull((t) => t.prevRealUsers) : null;
  double? get newUsers => isMember ? _sumOrNull((t) => t.newUsers) : null;
  double? get prevNewUsers =>
      isMember ? _sumOrNull((t) => t.prevNewUsers) : null;

  double? get revGrowth => lhPeopleGrowth(revenue, prevRevenue);
  double? get profitGrowth => lhPeopleGrowth(profit, prevProfit);
  double? get realGrowth => lhPeopleGrowth(realUsers, prevRealUsers);
  double? get newGrowth => lhPeopleGrowth(newUsers, prevNewUsers);

  double? get marginPct => (revenue == null || profit == null || revenue!.abs() < 1e-9)
      ? null
      : profit! / revenue! * 100;

  double? get marginDeltaPp {
    final r = revenue, p = profit, pr = prevRevenue, pp = prevProfit;
    if (r == null || p == null || pr == null || pp == null) return null;
    if (r.abs() < 1e-9 || pr.abs() < 1e-9) return null;
    return (p / r - pp / pr) * 100;
  }

  /// 按任务权重加权后的分项得分，用于展开区的分项条。
  Map<String, double> get components {
    final out = <String, double>{};
    for (final t in tasks) {
      t.components.forEach((k, v) => out[k] = (out[k] ?? 0) + v * t.weight);
    }
    return out;
  }

  int get overdueCount => tasks.where((t) => t.overdue).length;

  Set<LhPeopleFlag> get flags {
    final out = <LhPeopleFlag>{for (final t in tasks) ...t.flags};
    if (tasks.isNotEmpty && (weightSum - 1).abs() > 0.02) {
      out.add(LhPeopleFlag.badWeight);
    }
    return out;
  }

  static LhPeopleRow fromJson(Map<String, dynamic> json) {
    final tpl = LhPeopleTemplateX.parse(json['template']);
    final tasks =
        ((json['children'] ?? json['tasks']) as List? ?? const [])
            .whereType<Map>()
            .map(
              (e) => LhPeopleTask.fromJson(
                e.cast<String, dynamic>(),
                fallbackTemplate: tpl,
              ),
            )
            .toList(growable: false);
    return LhPeopleRow(
      id: json['id']?.toString() ?? json['name']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名',
      group: json['group']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      tasks: tasks,
      serverScore: _num((json['metrics'] as Map?)?['score'] ?? json['score']),
      sheetScore: _num(json['sheetScore']),
      sheetGrade: json['sheetGrade']?.toString() ?? '',
    );
  }
}

/// 一页人效数据。
@immutable
class LhPeopleBundle {
  const LhPeopleBundle({
    required this.rows,
    this.windowNote = '',
    this.periodLabel = '',
    this.isFallback = false,
  });

  const LhPeopleBundle.empty()
    : rows = const <LhPeopleRow>[],
      windowNote = '',
      periodLabel = '',
      isFallback = false;

  final List<LhPeopleRow> rows;

  /// 同期对齐窗口文案，如「本月 1–30 日 vs 上月 1–30 日」。服务端下发。
  final String windowNote;
  final String periodLabel;

  /// true = 接口没通，用的是本地兜底数据，列表要显式标出来。
  final bool isFallback;

  List<String> get groups {
    final seen = <String>{};
    final out = <String>['全部'];
    for (final r in rows) {
      if (r.group.isEmpty || !seen.add(r.group)) continue;
      out.add(r.group);
    }
    return out;
  }

  static LhPeopleBundle fromJson(Map<String, dynamic> json) {
    final win = (json['window'] as Map?)?.cast<String, dynamic>();
    return LhPeopleBundle(
      rows: ((json['rows'] ?? json['people']) as List? ?? const [])
          .whereType<Map>()
          .map((e) => LhPeopleRow.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
      windowNote: win?['note']?.toString() ?? '',
      periodLabel: win?['label']?.toString() ?? '',
    );
  }
}

/// 人效 Hero 汇总。金额在模型里是万元，产品 Hero 的 `_fmtMoney` 吃元，
/// [totals] 已经乘过 10000，才能和产品 / 供给 / 渠道同一套大数格式。
@immutable
class LhPeopleHeroSnapshot {
  const LhPeopleHeroSnapshot({
    required this.revenueWan,
    required this.profitWan,
    required this.prevRevenueWan,
    required this.prevProfitWan,
    required this.avgScore,
    required this.peopleCount,
    required this.passCount,
    required this.riskCount,
  });

  final double revenueWan;
  final double profitWan;
  final double prevRevenueWan;
  final double prevProfitWan;
  final double avgScore;
  final int peopleCount;
  final int passCount;
  final int riskCount;

  static const double yuanPerWan = 10000;

  double get revenueYuan => revenueWan * yuanPerWan;
  double get profitYuan => profitWan * yuanPerWan;

  double get grossMarginPct =>
      revenueWan.abs() < 1e-9 ? 0 : profitWan / revenueWan * 100;

  Map<String, double> get totals => {
        'profit': profitYuan,
        'revenue': revenueYuan,
        'grossMargin': grossMarginPct,
        'avgScore': avgScore,
        'peopleCount': peopleCount.toDouble(),
        'passCount': passCount.toDouble(),
        'riskCount': riskCount.toDouble(),
      };

  ({double pct, bool isUp})? deltaFor(String key) {
    switch (key) {
      case 'revenue':
        return lhPeopleHeroDelta(lhPeopleGrowth(revenueWan, prevRevenueWan));
      case 'profit':
        return lhPeopleHeroDelta(lhPeopleGrowth(profitWan, prevProfitWan));
      case 'grossMargin':
        return lhPeopleHeroMarginDelta(
          revenueWan: revenueWan,
          profitWan: profitWan,
          prevRevenueWan: prevRevenueWan,
          prevProfitWan: prevProfitWan,
        );
      default:
        return null;
    }
  }
}

/// 达标线 / 淘汰线与 [LhPeopleGrade.of] 同一套：≥85 良、<70 汰。
const double kLhPeoplePassScore = 85;
const double kLhPeopleRiskScore = 70;

LhPeopleHeroSnapshot lhPeopleHeroSnapshot(
  List<LhPeopleRow> rows, {
  required bool standardCaliber,
}) {
  final scores = rows
      .map((r) => standardCaliber ? r.standardScore : r.score)
      .toList(growable: false);
  final avg = scores.isEmpty
      ? 0.0
      : scores.reduce((a, b) => a + b) / scores.length;
  var revenue = 0.0, prevRevenue = 0.0, profit = 0.0, prevProfit = 0.0;
  for (final r in rows) {
    revenue += r.revenue ?? 0;
    prevRevenue += r.prevRevenue ?? 0;
    profit += r.profit ?? 0;
    prevProfit += r.prevProfit ?? 0;
  }
  return LhPeopleHeroSnapshot(
    revenueWan: revenue,
    profitWan: profit,
    prevRevenueWan: prevRevenue,
    prevProfitWan: prevProfit,
    avgScore: avg,
    peopleCount: rows.length,
    passCount: scores.where((s) => s >= kLhPeoplePassScore).length,
    riskCount: scores.where((s) => s < kLhPeopleRiskScore).length,
  );
}

/// 人效环比是小数（0.12 = +12%），Hero 大数吃百分点。零基数不当环比。
({double pct, bool isUp})? lhPeopleHeroDelta(double? growth) {
  if (growth == null || !growth.isFinite) return null;
  if (growth.abs() >= kLhZeroBaseGrowth - 1) return null;
  final pct = growth * 100;
  if (pct.abs() < 0.05) return null;
  return (pct: pct, isUp: pct >= 0);
}

({double pct, bool isUp})? lhPeopleHeroMarginDelta({
  required double revenueWan,
  required double profitWan,
  required double prevRevenueWan,
  required double prevProfitWan,
}) {
  if (revenueWan.abs() < 1e-9 || prevRevenueWan.abs() < 1e-9) return null;
  final pp =
      (profitWan / revenueWan - prevProfitWan / prevRevenueWan) * 100;
  if (!pp.isFinite || pp.abs() < 0.05) return null;
  return (pct: pp, isUp: pp >= 0);
}
