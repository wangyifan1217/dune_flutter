// ═════════════════════════════════════════════════════════════════════════════
// 灯塔 · 简报引擎（读数规则）
//
//   目标：把「日报 / 周报 / 月报 / 季报 / 年报」变成一套确定的算术，而不是让
//   人对着一屏环比自己猜。整个文件不依赖 Flutter、不依赖网络、不碰数据库 ——
//   输入两期指标，输出几句话。同一套规则搬到 lighthouse-go 里也成立。
//
// ── 第一原则：差额型指标不能比百分比 ─────────────────────────────────────────
//
//   净利 = 收入 − 成本合计       毛利 = 收入 − 项目成本
//   ⟹ 毛利 − 净利 = 成本合计 − 项目成本 ≡ W（项目成本以外那块成本）
//   ⟹ ΔW = 毛利₀ × g毛利 − 净利₀ × g净利
//
//   所以「毛利涨 2.4%、净利涨 5.5%」这两个数**不足以**判断成本涨还是跌：
//     净利₀/毛利₀ > 43.6% → W 缩小（成本降了）
//     净利₀/毛利₀ < 43.6% → W 扩大（成本涨了）
//   同样两个百分比，结论可以完全相反。分母不一样，百分比就不可比。
//
//   规则：**凡是相减关系（毛利/净利/利差/现金流），推论跑在增量金额 Δ 上；
//   只有相除关系（毛利率/ROI/变现率/核销率）才可以拿百分比相减。**
//   这条被 test/lighthouse_readout_test.dart 的第一组用例钉死。
//
// ── 第二原则：说不准就闭嘴 ───────────────────────────────────────────────────
//
//   每条结论必须同时过三关才允许上屏：
//     ① 基数够大（[LhReadoutGate.minBase]）—— 0.01 万涨到 0.03 万不是「暴涨 200%」
//     ② 变动够显著（[LhReadoutGate.minRel]）
//     ③ 方向确定（不在噪声带里，见 [LhReadoutInput.noiseFloor]）
//   过不了就不出这一条。宁可少说，不能说错。
//
// ── 第三原则：粒度决定能说什么 ───────────────────────────────────────────────
//
//   一天的波动支撑不起「成本结构恶化」这种话。所以：
//     日 / 周 → 只报**事实**：哪里断崖、谁逾期、核销停了、现金没回来
//     月 / 季 / 年 → 才出**结论**：成本结构、效率、结构位移、贡献度
//   由 [LhReadoutGate.allowsConclusion] 一处控制，不散落在各条规则里。
// ═════════════════════════════════════════════════════════════════════════════

/// 简报粒度。与灯塔周期条一一对应。
enum LhReadoutPeriod { day, week, month, quarter, year }

extension LhReadoutPeriodX on LhReadoutPeriod {
  String get label => switch (this) {
    LhReadoutPeriod.day => '日报',
    LhReadoutPeriod.week => '周报',
    LhReadoutPeriod.month => '月报',
    LhReadoutPeriod.quarter => '季报',
    LhReadoutPeriod.year => '年报',
  };

  /// 环比在这个粒度上叫什么。年是同比。
  String get compareWord =>
      this == LhReadoutPeriod.year ? '同比' : '环比';

  static LhReadoutPeriod parse(String? raw) => switch (raw?.trim()) {
    'week' => LhReadoutPeriod.week,
    'month' => LhReadoutPeriod.month,
    'quarter' => LhReadoutPeriod.quarter,
    'year' => LhReadoutPeriod.year,
    _ => LhReadoutPeriod.day,
  };
}

/// 显著性门槛。数值随粒度收紧：一天的噪声比一年大得多。
abstract final class LhReadoutGate {
  /// 基数门槛（元）。低于此基数的指标一律不参与结论，只允许报绝对额。
  static double minBase(LhReadoutPeriod p) => switch (p) {
    LhReadoutPeriod.day => 5e4,
    LhReadoutPeriod.week => 2e5,
    LhReadoutPeriod.month => 5e5,
    LhReadoutPeriod.quarter => 1.5e6,
    LhReadoutPeriod.year => 5e6,
  };

  /// 利润类指标的基数门槛。
  ///
  /// 利润天生比规模小一到两个数量级：销售 1810 万对应的毛利可能只有 24 万，
  /// 这是正常利润率，不是小基数噪声。拿规模的门槛去卡它，「毛利 24 万上多了
  /// 3.6 万成本」这种最该说的话会被整条吞掉 —— 样本日报就是这么发现的。
  /// 所以利润 / 现金流 / 成本这一族单独走 1/10 的门槛。
  static double minProfitBase(LhReadoutPeriod p) => minBase(p) / 10;

  /// 相对变动门槛。低于此幅度视为没动。
  static double minRel(LhReadoutPeriod p) => switch (p) {
    LhReadoutPeriod.day => 0.15,
    LhReadoutPeriod.week => 0.10,
    LhReadoutPeriod.month => 0.05,
    LhReadoutPeriod.quarter => 0.05,
    LhReadoutPeriod.year => 0.03,
  };

  /// 日 / 周只报事实，不下结论。
  static bool allowsConclusion(LhReadoutPeriod p) =>
      p != LhReadoutPeriod.day && p != LhReadoutPeriod.week;

  /// 结构位移（辛普森）只在月及以上做 —— 短周期的行间排序本身就在抖。
  static bool allowsStructural(LhReadoutPeriod p) => allowsConclusion(p);

  /// 单行断崖只在日 / 周报，月报里这属于常态波动。
  static bool allowsOutlier(LhReadoutPeriod p) =>
      p == LhReadoutPeriod.day || p == LhReadoutPeriod.week;
}

/// 一期的指标快照。金额单位统一为**元**，比率为百分数（8.7 表示 8.7%）。
/// 全部可空：拿不到就是 null，绝不用 0 冒充。
class LhReadoutTotals {
  const LhReadoutTotals({
    this.sales,
    this.verifiedSales,
    this.gmv,
    this.revenue,
    this.projectCost,
    this.businessCost,
    this.costTotal,
    this.profit,
    this.netProfit,
    this.prepaid,
    this.spread,
  });

  final double? sales; // 销售额
  final double? verifiedSales; // 核销额
  final double? gmv;
  final double? revenue; // 收入
  final double? projectCost; // 项目成本
  final double? businessCost; // 业务成本
  final double? costTotal; // 成本合计（≠ 项目 + 业务，见下方 note）
  final double? profit; // 毛利润 = 收入 − 项目成本
  final double? netProfit; // 净利润 = 收入 − 成本合计
  final double? prepaid; // 经营性净现金流
  final double? spread; // 利差

  /// 毛利率 = 毛利 ÷ 核销额。
  double? get grossMargin =>
      (profit == null || verifiedSales == null || verifiedSales!.abs() < 1e-9)
      ? null
      : profit! / verifiedSales! * 100;

  /// ROI = 毛利 ÷ 成本合计。
  double? get roi =>
      (profit == null || costTotal == null || costTotal!.abs() < 1e-9)
      ? null
      : profit! / costTotal! * 100;

  /// 变现率 = 收入 ÷ 核销额。核销一块钱能收上来多少。
  double? get takeRate =>
      (revenue == null || verifiedSales == null || verifiedSales!.abs() < 1e-9)
      ? null
      : revenue! / verifiedSales! * 100;

  /// 核销率 = 核销额 ÷ 销售额。
  double? get settleRate =>
      (verifiedSales == null || sales == null || sales!.abs() < 1e-9)
      ? null
      : verifiedSales! / sales! * 100;

  double? metric(String key) => switch (key) {
    'sales' => sales,
    'verifiedSales' => verifiedSales,
    'gmv' => gmv,
    'revenue' => revenue,
    'projectCost' => projectCost,
    'businessCost' || 'cost' => businessCost,
    'costTotal' || 'totalCost' => costTotal,
    'profit' => profit,
    'netProfit' => netProfit,
    'prepaid' => prepaid,
    'spread' => spread,
    'grossMargin' => grossMargin,
    'rate' => roi,
    _ => null,
  };
}

/// 上期数据的来源。这决定 Δ 能不能信。
enum LhPrevSource {
  /// 后端直接下发的上期实测值。Δ 可信到分。
  measured,

  /// 由「本期 ÷ (1+环比)」反推。环比是四舍五入过的，Δ 带误差，
  /// 小额变动必须落进噪声带丢弃，否则会拿舍入误差当结论。
  derivedFromPct,
}

/// 一个实体（省份 / 产品 / 渠道）两期的数。用于贡献度与结构位移。
class LhReadoutEntity {
  const LhReadoutEntity({
    required this.name,
    this.group = '',
    required this.cur,
    this.prev,
  });

  final String name;
  final String group;
  final LhReadoutTotals cur;
  final LhReadoutTotals? prev;
}

/// 简报输入。
class LhReadoutInput {
  const LhReadoutInput({
    required this.period,
    required this.cur,
    required this.prev,
    this.prevSource = LhPrevSource.measured,
    this.entities = const <LhReadoutEntity>[],
    this.dimensionLabel = '',
    this.entityWord = '行',
    this.windowNote = '',
    this.overdueCount,
    this.prevOverdueCount,
    this.tierReachableCount,
    this.tierMissCount,
  });

  final LhReadoutPeriod period;
  final LhReadoutTotals cur;
  final LhReadoutTotals prev;
  final LhPrevSource prevSource;
  final List<LhReadoutEntity> entities;

  /// 当前维度名，如「供给方」。用于文案。
  final String dimensionLabel;

  /// 实体的量词，如「省份」「产品」「渠道」。
  final String entityWord;

  /// 同期对齐窗口说明，原样带进简报头。
  final String windowNote;

  final int? overdueCount;
  final int? prevOverdueCount;
  final int? tierReachableCount;
  final int? tierMissCount;

  /// Δ 的噪声地板：小于它的增量一律当没变。
  ///
  /// 反推的上期值带舍入误差 —— 环比只精确到 0.1%，一个 1000 万的基数就能
  /// 反推出上万元的误差。所以反推来源的地板取「较大一期的 0.5%」，
  /// 实测来源只留一个很小的绝对值防浮点噪声。
  double noiseFloor(double curV, double prevV) {
    if (prevSource == LhPrevSource.measured) return 1.0;
    final scale = curV.abs() > prevV.abs() ? curV.abs() : prevV.abs();
    return scale * 0.005;
  }
}

enum LhFactLevel { critical, warning, info }

/// 事实 vs 结论。日 / 周只出 fact。
enum LhFactKind { fact, conclusion }

class LhFact {
  const LhFact({
    required this.id,
    required this.kind,
    required this.level,
    required this.text,
    this.derivation = '',
    this.amount,
  });

  /// 规则 id，与下方规则表一一对应，便于埋点与回归。
  final String id;
  final LhFactKind kind;
  final LhFactLevel level;

  /// 一句话，主谓宾齐全，带金额和方向。
  final String text;

  /// 推导过程。点开可验算 —— 一个不能验算的结论不该让人相信。
  final String derivation;

  /// 这条结论对应的金额（元），没有则 null。
  final double? amount;

  int get rank => switch (level) {
    LhFactLevel.critical => 0,
    LhFactLevel.warning => 1,
    LhFactLevel.info => 2,
  };
}

class LhReadout {
  const LhReadout({
    required this.period,
    required this.headline,
    required this.facts,
    this.windowNote = '',
  });

  final LhReadoutPeriod period;

  /// 一句总结。没有任何显著变化时是「本期无显著变化」，不硬凑。
  final String headline;
  final List<LhFact> facts;
  final String windowNote;

  bool get isQuiet => facts.isEmpty;

  List<LhFact> get conclusions =>
      facts.where((f) => f.kind == LhFactKind.conclusion).toList();
  List<LhFact> get plainFacts =>
      facts.where((f) => f.kind == LhFactKind.fact).toList();
}

/// 金额格式化由调用方注入 —— 引擎保持纯逻辑，不关心「万」还是「亿」。
typedef LhMoneyFormat = String Function(double yuan);

String _defaultMoney(double v) {
  final a = v.abs();
  if (a >= 1e8) return '${(v / 1e8).toStringAsFixed(2)}亿';
  final wan = v / 1e4;
  return '${wan.toStringAsFixed(wan.abs() >= 100 ? 1 : 2)}万';
}

String _pct(double v, {int digits = 1}) =>
    '${v >= 0 ? '+' : ''}${v.toStringAsFixed(digits)}%';

String _pp(double v, {int digits = 1}) =>
    '${v >= 0 ? '+' : ''}${v.toStringAsFixed(digits)}pp';

/// 环比。上期为 0 时不返回百分比 —— 零基数没有「增长率」这回事。
double? lhGrowth(double? cur, double? prev) {
  if (cur == null || prev == null) return null;
  if (prev.abs() < 1e-9) return null;
  return (cur - prev) / prev.abs();
}

// ── 核心恒等式，单独抽出来 ────────────────────────────────────────────────
//   规则函数会被门槛挡掉，但这两个函数是纯算术，永远成立。
//   它们是这套简报的地基，也是唯一必须逐位回归的部分。

/// W = 成本合计 − 项目成本，即「项目成本以外那块成本」。
/// 由 毛利 − 净利 恒等推出，不需要拿到 costTotal / projectCost 也算得出来。
double? lhWedge(double? profit, double? netProfit) =>
    (profit == null || netProfit == null) ? null : profit - netProfit;

/// ΔW = Δ毛利 − Δ净利。**正数 = 成本涨了**，负数 = 成本降了。
///
/// 这就是「毛利涨 2.4%、净利涨 5.5%」的正解：不能比百分比，要比增量。
double? lhWedgeDelta({
  required double? profitCur,
  required double? profitPrev,
  required double? netCur,
  required double? netPrev,
}) {
  if (profitCur == null || profitPrev == null) return null;
  if (netCur == null || netPrev == null) return null;
  return (profitCur - profitPrev) - (netCur - netPrev);
}

/// 结论翻转的临界基数比。
///
/// ΔW = 毛利₀·g毛利 − 净利₀·g净利 = 0  ⟹  净利₀/毛利₀ = g毛利 / g净利
///
/// 即：只给两个环比百分比，结论取决于「净利占毛利多少」。
/// 例：g毛利 = 2.4%、g净利 = 5.5% ⟹ 临界比 43.6%。
/// 净利占毛利超过 43.6% → 成本降了；不到 → 成本涨了。**同样两个百分比，
/// 结论完全相反** —— 这是简报里最容易说反的一句，所以单独钉一个函数。
/// 两个环比同号才有意义；异号时结论由符号本身决定，返回 null。
double? lhWedgeCrossoverRatio(double? gProfit, double? gNet) {
  if (gProfit == null || gNet == null) return null;
  if (gNet.abs() < 1e-12) return null;
  if (gProfit.sign != gNet.sign) return null;
  return gProfit / gNet;
}

/// 一对指标的两期视图，规则里反复用到。
class _Pair {
  _Pair(this.cur, this.prev);
  final double? cur;
  final double? prev;

  bool get ok => cur != null && prev != null;
  double get c => cur ?? 0;
  double get p => prev ?? 0;
  double get delta => c - p;
  double? get growth => lhGrowth(cur, prev);

  /// 基数够不够大。取两期里大的那个 —— 从 0 涨起来同样值得说。
  double get base => c.abs() > p.abs() ? c.abs() : p.abs();
}

_Pair _pair(LhReadoutInput i, String key) =>
    _Pair(i.cur.metric(key), i.prev.metric(key));

// ═════════════════════════════════════════════════════════════════════════════
// 规则表
//
//   每条规则一个函数，返回 null = 这一期不该说这句话。
//   id 命名：R{序号}-{主题}，出现在埋点里，改文案不改 id。
// ═════════════════════════════════════════════════════════════════════════════

/// R1 · 亏损。任何粒度都报，级别最高。
LhFact? _r1Loss(LhReadoutInput i, LhMoneyFormat m) {
  final np = _pair(i, 'netProfit');
  if (np.cur == null || np.c >= 0) return null;
  final wasPositive = np.prev != null && np.p >= 0;
  return LhFact(
    id: 'R1-loss',
    kind: LhFactKind.fact,
    level: LhFactLevel.critical,
    text: wasPositive
        ? '净利润转负，本期亏 ${m(np.c.abs())}（上期还盈 ${m(np.p)}）'
        : '净利润仍为负，本期亏 ${m(np.c.abs())}',
    derivation: '净利润 = 收入 − 成本合计 = ${m(i.cur.revenue ?? 0)} − '
        '${m(i.cur.costTotal ?? 0)}',
    amount: np.c,
  );
}

/// R2 · 利润质量：利润涨而经营性净现金流跌，说明钱没回来。
/// 资管的优先级是 规模 > 现金流 > 利润，这条比任何效率指标都该先看。
LhFact? _r2CashQuality(LhReadoutInput i, LhMoneyFormat m) {
  final pf = _pair(i, 'profit');
  final cash = _pair(i, 'prepaid');
  if (!pf.ok || !cash.ok) return null;
  if (pf.base < LhReadoutGate.minProfitBase(i.period)) return null;
  final gp = pf.growth, gc = cash.growth;
  if (gp == null || gc == null) return null;
  // 只在方向相反时开口。同向一涨一跌幅度不同不算「质量问题」。
  if (!(gp > 0 && gc < 0)) return null;
  if (gp.abs() < LhReadoutGate.minRel(i.period)) return null;
  if (gc.abs() < LhReadoutGate.minRel(i.period)) return null;
  return LhFact(
    id: 'R2-cash-quality',
    kind: LhFactKind.fact,
    level: LhFactLevel.critical,
    text: '毛利 ${_pct(gp * 100)} 但经营性净现金流 ${_pct(gc * 100)}，'
        '利润没变成现金，现金净流出 ${m(cash.delta.abs())}',
    derivation: '毛利 ${m(pf.p)} → ${m(pf.c)}；'
        '经营性净现金流 ${m(cash.p)} → ${m(cash.c)}',
    amount: cash.delta,
  );
}

/// R3 · 核销进度：销售跑在前面、核销没跟上 = 待核销在积压，下期毛利有补涨。
/// 这条是比值口径，日报就能说，不用等月底。
LhFact? _r3Settlement(LhReadoutInput i, LhMoneyFormat m) {
  final s = _pair(i, 'sales');
  final v = _pair(i, 'verifiedSales');
  if (!s.ok || !v.ok) return null;
  if (s.base < LhReadoutGate.minBase(i.period)) return null;
  final gs = s.growth, gv = v.growth;
  if (gs == null || gv == null) return null;
  final gapPp = (gv - gs) * 100;
  if (gapPp.abs() < LhReadoutGate.minRel(i.period) * 100) return null;
  final r0 = i.prev.settleRate, r1 = i.cur.settleRate;
  final rateNote = (r0 != null && r1 != null)
      ? '核销率 ${r0.toStringAsFixed(1)}% → ${r1.toStringAsFixed(1)}%'
      : '';
  return LhFact(
    id: 'R3-settlement',
    kind: LhFactKind.fact,
    level: gapPp < 0 ? LhFactLevel.warning : LhFactLevel.info,
    text: gapPp < 0
        ? '销售 ${_pct(gs * 100)} 但核销只 ${_pct(gv * 100)}，'
            '待核销在积压，下期毛利有补涨空间'
        : '核销 ${_pct(gv * 100)} 跑赢销售 ${_pct(gs * 100)}，往期待核销在回补',
    derivation: '核销率 = 核销额 ÷ 销售额；$rateNote'
        '（差 ${_pp(gapPp)}）',
    amount: v.delta,
  );
}

/// R4 · 逾期。事实，全粒度。
LhFact? _r4Overdue(LhReadoutInput i, LhMoneyFormat m) {
  final n = i.overdueCount;
  if (n == null || n <= 0) return null;
  final was = i.prevOverdueCount;
  final trend = (was == null || was == n)
      ? ''
      : (n > was ? '，比上期多 ${n - was} 项' : '，比上期少 ${was - n} 项');
  return LhFact(
    id: 'R4-overdue',
    kind: LhFactKind.fact,
    level: LhFactLevel.warning,
    text: '$n 项回款逾期$trend',
    derivation: 'calc_record 回款状态',
    amount: null,
  );
}

/// R5 · 单行断崖。仅日 / 周报 —— 月报里这属于常态波动。
LhFact? _r5Outlier(LhReadoutInput i, LhMoneyFormat m) {
  if (!LhReadoutGate.allowsOutlier(i.period)) return null;
  if (i.entities.isEmpty) return null;
  // 同样走利润类门槛：一个省一天的毛利本来就是几万量级，
  // 拿销售额的门槛去卡，毛利腰斩的省会被整条漏掉。
  final gate = LhReadoutGate.minProfitBase(i.period);
  LhReadoutEntity? worst;
  double worstG = 0;
  for (final e in i.entities) {
    final p = _Pair(e.cur.profit, e.prev?.profit);
    if (!p.ok || p.base < gate) continue;
    final g = p.growth;
    if (g == null) continue;
    if (g < worstG) {
      worstG = g;
      worst = e;
    }
  }
  if (worst == null || worstG > -0.4) return null;
  final p = _Pair(worst.cur.profit, worst.prev?.profit);
  return LhFact(
    id: 'R5-outlier',
    kind: LhFactKind.fact,
    level: LhFactLevel.warning,
    text: '${worst.name} 毛利 ${_pct(worstG * 100)}，'
        '${m(p.p)} 掉到 ${m(p.c)}，是本期最大的单${i.entityWord}跌幅',
    derivation: '按${i.entityWord}毛利${i.period.compareWord}降序取首位，'
        '基数下限 ${m(gate)}',
    amount: p.delta,
  );
}

/// R6 · 项目成本变动。**用 Δ 不用百分比**。
/// 毛利 = 收入 − 项目成本 ⟹ Δ项目成本 = Δ收入 − Δ毛利
LhFact? _r6ProjectCost(LhReadoutInput i, LhMoneyFormat m) {
  if (!LhReadoutGate.allowsConclusion(i.period)) return null;
  final rev = _pair(i, 'revenue');
  final pf = _pair(i, 'profit');
  if (!rev.ok || !pf.ok) return null;
  if (rev.base < LhReadoutGate.minBase(i.period)) return null;
  // 有实测项目成本就直接用，没有才靠恒等式反推。
  final direct = _pair(i, 'projectCost');
  final delta = direct.ok ? direct.delta : rev.delta - pf.delta;
  final floor = i.noiseFloor(rev.c, rev.p);
  if (delta.abs() < floor) return null;
  if (delta.abs() < rev.base * 0.01) return null;
  final up = delta > 0;
  return LhFact(
    id: 'R6-project-cost',
    kind: LhFactKind.conclusion,
    level: up ? LhFactLevel.warning : LhFactLevel.info,
    text: '收入${rev.delta >= 0 ? '增' : '减'} ${m(rev.delta.abs())}、'
        '毛利${pf.delta >= 0 ? '增' : '减'} ${m(pf.delta.abs())}，'
        '项目成本净${up ? '增' : '减'} ${m(delta.abs())}',
    derivation: direct.ok
        ? '项目成本 ${m(direct.p)} → ${m(direct.c)}'
        : 'Δ项目成本 = Δ收入 − Δ毛利 = ${m(rev.delta)} − ${m(pf.delta)}'
            '（毛利 = 收入 − 项目成本）',
    amount: delta,
  );
}

/// R7 · 项目成本以外那块成本。这条就是「毛利涨 2.4%、净利涨 5.5%」的正解。
/// 毛利 − 净利 = 成本合计 − 项目成本 ≡ W ⟹ ΔW = Δ毛利 − Δ净利
LhFact? _r7WedgeCost(LhReadoutInput i, LhMoneyFormat m) {
  if (!LhReadoutGate.allowsConclusion(i.period)) return null;
  final pf = _pair(i, 'profit');
  final np = _pair(i, 'netProfit');
  if (!pf.ok || !np.ok) return null;
  if (pf.base < LhReadoutGate.minProfitBase(i.period)) return null;
  final delta = pf.delta - np.delta;
  final floor = i.noiseFloor(pf.c, pf.p);
  if (delta.abs() < floor) return null;
  // 1% 是「值得说」与「噪声」的分界：毛利 100 万上 1 万的成本摆动，
  // 业务能感知；再低就是账期错位和四舍五入的合成物。
  if (delta.abs() < pf.base * 0.01) return null;
  final up = delta > 0;
  final gp = pf.growth, gn = np.growth;
  final pctNote = (gp != null && gn != null)
      ? '毛利 ${_pct(gp * 100)}、净利 ${_pct(gn * 100)}，'
            '但这两个百分比的分母不同，结论看 Δ：'
      : '';
  return LhFact(
    id: 'R7-wedge-cost',
    kind: LhFactKind.conclusion,
    level: up ? LhFactLevel.warning : LhFactLevel.info,
    text: '项目成本以外的成本净${up ? '增' : '减'} ${m(delta.abs())}'
        '${up ? '，吃掉了这部分毛利' : '，多留下这部分利润'}',
    derivation: '$pctNote'
        'ΔW = Δ毛利 − Δ净利 = ${m(pf.delta)} − ${m(np.delta)} = ${m(delta)}'
        '（W = 成本合计 − 项目成本）',
    amount: delta,
  );
}

/// R8 · 变现率。比值口径，允许用百分比相减。
LhFact? _r8TakeRate(LhReadoutInput i, LhMoneyFormat m) {
  if (!LhReadoutGate.allowsConclusion(i.period)) return null;
  final rev = _pair(i, 'revenue');
  final v = _pair(i, 'verifiedSales');
  if (!rev.ok || !v.ok) return null;
  if (v.base < LhReadoutGate.minBase(i.period)) return null;
  final t0 = i.prev.takeRate, t1 = i.cur.takeRate;
  if (t0 == null || t1 == null) return null;
  final diff = t1 - t0;
  if (diff.abs() < 0.3) return null;
  return LhFact(
    id: 'R8-take-rate',
    kind: LhFactKind.conclusion,
    level: diff < 0 ? LhFactLevel.warning : LhFactLevel.info,
    text: '单位变现率 ${_pp(diff)}'
        '${diff < 0 ? '，同样的核销量收上来的钱变少了' : '，同样的核销量收上来的钱变多了'}',
    derivation: '变现率 = 收入 ÷ 核销额 = '
        '${t0.toStringAsFixed(2)}% → ${t1.toStringAsFixed(2)}%',
    amount: null,
  );
}

/// R9 · ROI。比值口径。
LhFact? _r9Roi(LhReadoutInput i, LhMoneyFormat m) {
  if (!LhReadoutGate.allowsConclusion(i.period)) return null;
  final r0 = i.prev.roi, r1 = i.cur.roi;
  if (r0 == null || r1 == null) return null;
  final ct = _pair(i, 'costTotal');
  if (ct.base < LhReadoutGate.minBase(i.period)) return null;
  final diff = r1 - r0;
  if (diff.abs() < 1.0) return null;
  final gp = _pair(i, 'profit').growth;
  final gc = ct.growth;
  final note = (gp != null && gc != null)
      ? '毛利 ${_pct(gp * 100)}、成本合计 ${_pct(gc * 100)}'
      : '';
  return LhFact(
    id: 'R9-roi',
    kind: LhFactKind.conclusion,
    level: diff < 0 ? LhFactLevel.warning : LhFactLevel.info,
    text: diff < 0
        ? 'ROI ${_pp(diff)}，这一期的利润是花钱换来的'
        : 'ROI ${_pp(diff)}，同样的成本产出更多利润',
    derivation: 'ROI = 毛利 ÷ 成本合计 = '
        '${r0.toStringAsFixed(1)}% → ${r1.toStringAsFixed(1)}%；$note',
    amount: null,
  );
}

/// R10 · 增收不增利 / 缩量提效。
LhFact? _r10Divergence(LhReadoutInput i, LhMoneyFormat m) {
  if (!LhReadoutGate.allowsConclusion(i.period)) return null;
  final s = _pair(i, 'sales');
  final pf = _pair(i, 'profit');
  if (!s.ok || !pf.ok) return null;
  if (s.base < LhReadoutGate.minBase(i.period)) return null;
  final gs = s.growth, gp = pf.growth;
  if (gs == null || gp == null) return null;
  final rel = LhReadoutGate.minRel(i.period);
  if (gs.abs() < rel || gp.abs() < rel) return null;
  if (gs > 0 && gp < 0) {
    return LhFact(
      id: 'R10-scale-up-profit-down',
      kind: LhFactKind.conclusion,
      level: LhFactLevel.warning,
      text: '增收不增利：销售 ${_pct(gs * 100)}、毛利 ${_pct(gp * 100)}，'
          '多做的量没带来利润',
      derivation: '销售额 ${m(s.p)} → ${m(s.c)}；毛利 ${m(pf.p)} → ${m(pf.c)}',
      amount: pf.delta,
    );
  }
  if (gs < 0 && gp > 0) {
    return LhFact(
      id: 'R10-scale-down-profit-up',
      kind: LhFactKind.conclusion,
      level: LhFactLevel.info,
      text: '缩量提效：销售 ${_pct(gs * 100)} 但毛利 ${_pct(gp * 100)}，'
          '砍掉的是不赚钱的量',
      derivation: '销售额 ${m(s.p)} → ${m(s.c)}；毛利 ${m(pf.p)} → ${m(pf.c)}',
      amount: pf.delta,
    );
  }
  return null;
}

/// R11 · 贡献度：谁在拉、谁在拖。按 Δ毛利 排序，不按百分比。
LhFact? _r11Contribution(LhReadoutInput i, LhMoneyFormat m) {
  if (i.entities.length < 2) return null;
  final deltas = <({String name, double d})>[];
  for (final e in i.entities) {
    final p = _Pair(e.cur.profit, e.prev?.profit);
    if (!p.ok) continue;
    deltas.add((name: e.name, d: p.delta));
  }
  if (deltas.length < 2) return null;
  deltas.sort((a, b) => b.d.compareTo(a.d));
  final top = deltas.first, bottom = deltas.last;
  if (top.d <= 0 && bottom.d >= 0) return null;
  final parts = <String>[
    if (top.d > 0) '${top.name} 拉动 ${m(top.d)}',
    if (bottom.d < 0) '${bottom.name} 拖走 ${m(bottom.d.abs())}',
  ];
  if (parts.isEmpty) return null;
  return LhFact(
    id: 'R11-contribution',
    kind: LhFactKind.fact,
    level: LhFactLevel.info,
    text: '毛利增量里，${parts.join('，')}',
    derivation: '按${i.entityWord} Δ毛利 排序取首尾，共 ${deltas.length} ${i.entityWord}',
    amount: top.d,
  );
}

/// R12 · 结构位移（辛普森悖论）。
/// 整体毛利率在涨，但多数行的毛利率在跌 —— 那是结构变了，不是效率变好了。
/// 这是账本能做而 Excel 做不到的一条，也是最容易把人骗过去的一条。
LhFact? _r12Structural(LhReadoutInput i, LhMoneyFormat m) {
  if (!LhReadoutGate.allowsStructural(i.period)) return null;
  final g0 = i.prev.grossMargin, g1 = i.cur.grossMargin;
  if (g0 == null || g1 == null) return null;
  final overall = g1 - g0;
  if (overall.abs() < 0.5) return null;
  var same = 0, opposite = 0;
  for (final e in i.entities) {
    final a = e.prev?.grossMargin, b = e.cur.grossMargin;
    if (a == null || b == null) continue;
    final d = b - a;
    if (d.abs() < 0.2) continue;
    if (d.sign == overall.sign) {
      same++;
    } else {
      opposite++;
    }
  }
  final total = same + opposite;
  if (total < 3) return null;
  if (opposite <= same) return null;
  return LhFact(
    id: 'R12-structural',
    kind: LhFactKind.conclusion,
    level: LhFactLevel.warning,
    text: '整体毛利率 ${_pp(overall)}，但 $opposite/$total 个${i.entityWord}'
        '的毛利率是反方向的 —— 这是结构变了，不是效率变了',
    derivation: '整体 ${g0.toStringAsFixed(1)}% → ${g1.toStringAsFixed(1)}%；'
        '逐${i.entityWord}比对同向 $same / 反向 $opposite',
    amount: null,
  );
}

/// R13 · 折扣过档。供给维专用。
LhFact? _r13Discount(LhReadoutInput i, LhMoneyFormat m) {
  final ok = i.tierReachableCount ?? 0;
  final miss = i.tierMissCount ?? 0;
  if (ok == 0 && miss == 0) return null;
  final parts = <String>[
    if (ok > 0) '$ok 个${i.entityWord}本周期能过下一档',
    if (miss > 0) '$miss 个够不到',
  ];
  return LhFact(
    id: 'R13-discount',
    kind: LhFactKind.fact,
    level: miss > ok ? LhFactLevel.warning : LhFactLevel.info,
    text: '折扣档位：${parts.join('，')}',
    derivation: '按各行当前累计与下一档门槛、以及周期剩余天数外推',
    amount: null,
  );
}

/// 规模一句 —— 没有任何异常时至少让人知道盘子多大、动了多少。
LhFact? _r0Scale(LhReadoutInput i, LhMoneyFormat m) {
  final s = _pair(i, 'sales');
  if (!s.ok) return null;
  // 基数不够就只报绝对额 —— 0.01 万涨到 0.03 万是 +200%，
  // 把这个百分比说出口就是在骗人。坑二在这里落地。
  final tooSmall = s.base < LhReadoutGate.minBase(i.period);
  final g = tooSmall ? null : s.growth;
  return LhFact(
    id: 'R0-scale',
    kind: LhFactKind.fact,
    level: LhFactLevel.info,
    text: g == null
        ? '销售额 ${m(s.c)}${tooSmall ? '（基数过小，不做${i.period.compareWord}判断）' : ''}'
        : '销售额 ${m(s.c)}，${i.period.compareWord} ${_pct(g * 100)}',
    derivation: '销售额 ${m(s.p)} → ${m(s.c)}',
    amount: s.delta,
  );
}

/// 生成简报。
///
/// [maxFacts] 上限。简报不是全指标罗列，是「今天该管什么」。
/// 超过上限时按 level 保留最该管的几条。
LhReadout lhBuildReadout(
  LhReadoutInput input, {
  LhMoneyFormat money = _defaultMoney,
  int maxFacts = 6,
}) {
  final rules = <LhFact? Function(LhReadoutInput, LhMoneyFormat)>[
    _r1Loss,
    _r2CashQuality,
    _r7WedgeCost,
    _r6ProjectCost,
    _r10Divergence,
    _r12Structural,
    _r3Settlement,
    _r9Roi,
    _r8TakeRate,
    _r4Overdue,
    _r13Discount,
    _r5Outlier,
    _r11Contribution,
  ];

  final facts = <LhFact>[];
  for (final rule in rules) {
    final f = rule(input, money);
    if (f != null) facts.add(f);
  }
  // 稳定排序：先按级别，再保持规则表顺序（规则表顺序就是「该管的先后」）。
  final indexed = <MapEntry<int, LhFact>>[
    for (var k = 0; k < facts.length; k++) MapEntry(k, facts[k]),
  ];
  indexed.sort((a, b) {
    final c = a.value.rank.compareTo(b.value.rank);
    return c != 0 ? c : a.key.compareTo(b.key);
  });
  var picked = indexed.map((e) => e.value).toList();
  if (picked.length > maxFacts) picked = picked.sublist(0, maxFacts);

  // 全都不显著时补一句规模，别给一张空卡。
  if (picked.isEmpty) {
    final scale = _r0Scale(input, money);
    if (scale != null) picked = [scale];
  }

  return LhReadout(
    period: input.period,
    headline: _headline(input, picked, money),
    facts: picked,
    windowNote: input.windowNote,
  );
}

String _headline(LhReadoutInput i, List<LhFact> facts, LhMoneyFormat m) {
  final worst = facts.isEmpty ? null : facts.first;
  if (worst != null && worst.level == LhFactLevel.critical) {
    return worst.text;
  }
  final s = _pair(i, 'sales');
  final pf = _pair(i, 'profit');
  final gs = s.growth, gp = pf.growth;
  if (gs == null || gp == null) {
    return facts.isEmpty ? '本期无显著变化' : facts.first.text;
  }
  final rel = LhReadoutGate.minRel(i.period);
  if (gs.abs() < rel && gp.abs() < rel) {
    return '规模与利润都在${i.period.compareWord}${(rel * 100).toStringAsFixed(0)}%'
        '以内，本期无显著变化';
  }
  final dir = (double g) => g >= 0 ? '涨' : '跌';
  return '销售额$dir${(gs.abs() * 100).toStringAsFixed(1)}%、'
      '毛利$dir${(gp.abs() * 100).toStringAsFixed(1)}%'
      '${facts.length > 1 ? '，另有 ${facts.length - 1} 条待看' : ''}';
}
