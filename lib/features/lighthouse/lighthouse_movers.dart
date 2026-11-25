import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_intraday_hero.dart' show LhIntradayData, LhIntradayPoint;
import 'lighthouse_profit_split.dart' show lhProfitSplitNameTag;
import 'lighthouse_theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
// 灯塔 · 今日异动（2026-11-25 · 原型「今日盈利右侧 · 今日异动」）
//
//   「今日盈利」大数右边一张小卡：今日异动 ③ / ● 整体 ↓ 慢 31%。
//   点开在大数下面就地展开（不弹窗，小尖角对准小卡）：
//     · 结论卡：−2.30 万元 · 整体比平常慢 31% | 今日 5.05 万 / 同期基准 7.35 万
//     · 小图：同期基准范围带 + 中位虚线，今日红线画到此刻
//     · 产品异动：名称 [口径] …… ±金额 / [↓ 慢 48%] …… 实际 · 基准
//
//   数全在后端算（lighthouse-go · intraday_movers.go，GET /lighthouse/intraday/movers）：
//   同期基准 = 前 7 天同一时刻累计的中位数；整体偏离 ≥ 20% 且 ≥ 1 万、
//   产品偏离 ≥ 50% 且 ≥ 0.3 万（由盈转亏直接算）才报；此刻太早（通常不到全天 15%）不报。
//   颜色按涨跌：比平常多 = 红 ↑，比平常少 = 绿 ↓。金额单位：元，显示成万。
//
//   模拟：基准不到 2 个完整日时后端标 simulated（照算，基准只有昨天）；后端还没有基准 /
//   取不到时前端按同样规则用「昨日同一时刻」自己估一份（[lhSimulateMovers]）。
//   两种都在面板上写明「今天为模拟，x/x 起正式」。
//   连分时快照都没有（比如本地没配 Postgres）：按时间进度粗估（昨日全天 × 今天已过时间比例），
//   面板上写明是粗估、要等分时快照记满 2 天才正式（simBasis = time）。
//   示例（simBasis = demo，[lhDemoMovers]）：正式数据出来之前，页面上放一份示例看效果——
//   整体按今天真实利润推，产品 / 项目是示例数；小卡、面板都写「示例 · 明日起真实」，不能点进详情。
// ═════════════════════════════════════════════════════════════════════════════

const _kInkStrong = Color(0xFF231D38);
const _kInk = Color(0xFF3A3352);
const _kMute = Color(0xFF6E6890);
const _kSoftMute = Color(0xFF8C87A3);
const _kDeep = Color(0xFF4B36A8);
const _kPurple = Color(0xFF5B3FD0);
const _kUp = Color(0xFFD23C3C);
const _kUpBg = Color(0xFFFDECEA);
const _kDown = Color(0xFF1F8A5C);
const _kDownBg = Color(0xFFE6F5EC);
const _kEdge = Color(0xFFE6E0F5);
const _kRule = Color(0xFFEFECF6);

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
List<double> _ds(Object? v) => v is List ? [for (final e in v) _d(e)] : const <double>[];
List<int> _is(Object? v) => v is List ? [for (final e in v) _i(e)] : const <int>[];

@immutable
class LhMoverOverall {
  const LhMoverOverall({
    this.today = 0,
    this.baseline = 0,
    this.diff = 0,
    this.pct = 0,
    this.flagged = false,
  });

  factory LhMoverOverall.fromJson(Map<String, dynamic> j) => LhMoverOverall(
    today: _d(j['today']),
    baseline: _d(j['baseline']),
    diff: _d(j['diff']),
    pct: _d(j['pct']),
    flagged: j['flagged'] == true,
  );

  final double today;
  final double baseline;
  final double diff;

  /// −0.31 = 比平常慢 31%。
  final double pct;
  final bool flagged;
}

/// 异动产品里的一个项目（这次偏离的原因之一）。
@immutable
class LhProjectMover {
  const LhProjectMover({
    required this.name,
    required this.actual,
    required this.baseline,
    required this.diff,
    this.pct = 0,
  });

  factory LhProjectMover.fromJson(Map<String, dynamic> j) => LhProjectMover(
    name: '${j['name'] ?? ''}'.trim(),
    actual: _d(j['actual']),
    baseline: _d(j['baseline']),
    diff: _d(j['diff']),
    pct: _d(j['pct']),
  );

  final String name;
  final double actual;
  final double baseline;
  final double diff;
  final double pct;
}

/// 藏在产品里的项目：所在产品整体没触发，项目自己偏得多（差额 ≥ 1 万）。
@immutable
class LhHiddenProject {
  const LhHiddenProject({
    required this.product,
    required this.name,
    required this.kind,
    required this.actual,
    required this.baseline,
    required this.diff,
    this.pct = 0,
    this.productPct = 0,
  });

  factory LhHiddenProject.fromJson(Map<String, dynamic> j) => LhHiddenProject(
    product: '${j['product'] ?? ''}'.trim(),
    name: '${j['name'] ?? ''}'.trim(),
    kind: '${j['kind'] ?? ''}',
    actual: _d(j['actual']),
    baseline: _d(j['baseline']),
    diff: _d(j['diff']),
    pct: _d(j['pct']),
    productPct: _d(j['productPct']),
  );

  final String product;
  final String name;
  final String kind;
  final double actual;
  final double baseline;
  final double diff;
  final double pct;

  /// 所在产品整体的偏离（−0.08 = 只慢 8%）。
  final double productPct;

  bool get up => kind == 'faster' || kind == 'turnProfit';
  String get badge => _moverBadge(kind, pct);
}

String _moverBadge(String kind, double pct) {
  final p = (pct.abs() * 100).round();
  return switch (kind) {
    'turnLoss' => '由盈转亏',
    'turnProfit' => '由亏转盈',
    'faster' => pct == 0 ? '↑ 明显多' : '↑ 高 $p%',
    _ => pct == 0 ? '↓ 明显少' : '↓ 低 $p%',
  };
}

@immutable
class LhProductMover {
  const LhProductMover({
    required this.name,
    required this.kind,
    required this.actual,
    required this.baseline,
    required this.diff,
    required this.pct,
    this.projects = const <LhProjectMover>[],
    this.cover = 0,
  });

  factory LhProductMover.fromJson(Map<String, dynamic> j) => LhProductMover(
    name: '${j['name'] ?? ''}'.trim(),
    kind: '${j['kind'] ?? ''}',
    actual: _d(j['actual']),
    baseline: _d(j['baseline']),
    diff: _d(j['diff']),
    pct: _d(j['pct']),
    projects: [
      if (j['projects'] is List)
        for (final e in j['projects'] as List)
          if (e is Map) LhProjectMover.fromJson(Map<String, dynamic>.from(e)),
    ],
    cover: _d(j['cover']),
  );

  /// 这次偏离主要来自哪几个项目（后端已按差额排好，最多 3 个）。
  final List<LhProjectMover> projects;

  /// 上面几个项目合计解释了这次偏离的几成（0–1）。
  final double cover;

  final String name;

  /// faster / slower / turnLoss / turnProfit
  final String kind;
  final double actual;
  final double baseline;
  final double diff;

  /// 基准太小或由盈转亏时为 0：不写百分比。
  final double pct;

  bool get up => kind == 'faster' || kind == 'turnProfit';

  String get badge => _moverBadge(kind, pct);
}

@immutable
class LhMovers {
  const LhMovers({
    this.available = false,
    this.restricted = false,
    this.at = '',
    this.minute = 0,
    this.baselineDays = 0,
    this.productDays = 0,
    this.productBasis = 'none',
    this.early = false,
    this.overall = const LhMoverOverall(),
    this.products = const <LhProductMover>[],
    this.count = 0,
    this.seriesMinutes = const <int>[],
    this.seriesMedian = const <double>[],
    this.seriesLow = const <double>[],
    this.seriesHigh = const <double>[],
    this.todayMinutes = const <int>[],
    this.today = const <double>[],
    this.simulated = false,
    this.formalFrom = '',
    this.projectDays = 0,
    this.projectBasis = 'none',
    this.hiddenProjects = const <LhHiddenProject>[],
    this.simBasis = '',
  });

  factory LhMovers.fromJson(Map<String, dynamic> j) {
    final series = j['series'] is Map
        ? Map<String, dynamic>.from(j['series'] as Map)
        : const <String, dynamic>{};
    return LhMovers(
      available: j['available'] == true,
      restricted: j['restricted'] == true,
      at: '${j['at'] ?? ''}',
      minute: _i(j['minute']),
      baselineDays: _i(j['baselineDays']),
      productDays: _i(j['productDays']),
      productBasis: '${j['productBasis'] ?? 'none'}',
      early: j['early'] == true,
      overall: j['overall'] is Map
          ? LhMoverOverall.fromJson(Map<String, dynamic>.from(j['overall'] as Map))
          : const LhMoverOverall(),
      products: [
        if (j['products'] is List)
          for (final e in j['products'] as List)
            if (e is Map) LhProductMover.fromJson(Map<String, dynamic>.from(e)),
      ],
      count: _i(j['count']),
      seriesMinutes: _is(series['minutes']),
      seriesMedian: _ds(series['median']),
      seriesLow: _ds(series['low']),
      seriesHigh: _ds(series['high']),
      todayMinutes: _is(series['todayMinutes']),
      today: _ds(series['today']),
      simulated: j['simulated'] == true,
      formalFrom: '${j['formalFrom'] ?? ''}',
      projectDays: _i(j['projectDays']),
      projectBasis: '${j['projectBasis'] ?? 'none'}',
      hiddenProjects: [
        if (j['hiddenProjects'] is List)
          for (final e in j['hiddenProjects'] as List)
            if (e is Map) LhHiddenProject.fromJson(Map<String, dynamic>.from(e)),
      ],
    );
  }

  final bool available;
  final bool restricted;
  final String at;
  final int minute;
  final int baselineDays;
  final int productDays;

  /// snapshot = 产品按同一时刻中位数；yesterday = 按昨日节奏估算；none = 没有产品基准。
  final String productBasis;
  final bool early;
  final LhMoverOverall overall;
  final List<LhProductMover> products;
  final int count;
  final List<int> seriesMinutes;
  final List<double> seriesMedian;
  final List<double> seriesLow;
  final List<double> seriesHigh;
  final List<int> todayMinutes;
  final List<double> today;

  /// 项目层：基准天数 / 依据（snapshot / yesterday / none）。
  final int projectDays;
  final String projectBasis;

  /// 藏在产品里的项目（所在产品整体没触发）。
  final List<LhHiddenProject> hiddenProjects;

  /// 前端模拟的依据：snapshot = 昨日同一时刻；time = 没有分时快照，按时间进度粗估；
  /// demo = 示例数（看效果用）。后端给的为空。
  final String simBasis;

  bool get isDemo => simBasis == 'demo';

  /// 正式：后端按够天数的同期基准算出来的（不是模拟、不是示例）。
  bool get isFormal => usable && !simulated;

  /// 基准天数不够，这份是模拟；[formalFrom]（YYYY-MM-DD）起正式。
  final bool simulated;
  final String formalFrom;

  /// 「11/26」；没给就写「明天」。
  String get formalLabel {
    final m = RegExp(r'^\d{4}-(\d{2})-(\d{2})$').firstMatch(formalFrom);
    if (m == null) return '明天';
    return '${int.parse(m.group(1)!)}/${int.parse(m.group(2)!)}';
  }

  /// 能判断异动：有今天的快照和至少一天基准，且账号可查看。
  bool get usable => available && !restricted && baselineDays > 0;
  bool get hasMovers => usable && !early && count > 0;
  bool get hasSeries =>
      seriesMinutes.length >= 2 &&
      seriesMedian.length == seriesMinutes.length &&
      seriesLow.length == seriesMinutes.length &&
      seriesHigh.length == seriesMinutes.length;

  String get compareLabel =>
      baselineDays <= 1 ? '对比昨日同一时刻' : '对比近 $baselineDays 天同一时刻';
}

/// 元 → 「2.30」（万，两位小数）；带号的用 −（不是 -）。
String _wan(double yuan) => (yuan.abs() / 1e4).toStringAsFixed(2);
String _signedWan(double yuan) =>
    '${yuan < 0 ? '−' : (yuan > 0 ? '+' : '')}${_wan(yuan)}';
String _plainWan(double yuan) => '${yuan < 0 ? '−' : ''}${_wan(yuan)}';

TextStyle _sans(
  BuildContext context,
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = _kInk,
  bool tabular = false,
  double? height,
  double? letterSpacing,
}) {
  final s = LhTypography.sans(
    context: context,
    size: size,
    weight: weight,
    color: DunesColors.resolve(context, color),
    height: height,
    letterSpacing: letterSpacing,
  );
  return tabular ? s.copyWith(fontFeatures: const [ui.FontFeature.tabularFigures()]) : s;
}

Color _surface(BuildContext context, Color c) =>
    DunesColors.resolve(context, c, role: DunesColorRole.surface);

Color _border(BuildContext context, Color c) =>
    DunesColors.resolve(context, c, role: DunesColorRole.border);

// ─────────────────────────────────────────────────────────────────────────────
// 小卡（大数右边）
// ─────────────────────────────────────────────────────────────────────────────

/// 小卡宽度固定：展开面板上的小尖角按它的中线对。
const double kLhMoversChipWidth = 112;

class LhMoversChip extends StatelessWidget {
  const LhMoversChip({
    super.key,
    required this.movers,
    required this.open,
    required this.onTap,
  });

  final LhMovers movers;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = movers;
    final o = m.overall;
    if (!m.hasMovers) {
      final pct = (o.pct.abs() * 100).round();
      final title = m.usable && !m.early ? '今日平稳' : '今日异动';
      final message = switch ((m.available, m.baselineDays, m.early)) {
        (false, _, _) => '暂无分时快照',
        (true, 0, _) => '平常数据不足',
        (true, _, true) => '数据还少，稍晚再看',
        _ when m.simulated && m.simBasis == 'time' => '模拟 · 按时间粗估',
        _ when m.simulated => '模拟 · ${m.formalLabel} 起正式',
        _ => '和平常只差 $pct%',
      };
      return Container(
        width: kLhMoversChipWidth,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: _surface(context, const Color(0xFFFAF9FD)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border(context, const Color(0xFFECE8F4))),
        ),
        child: Semantics(
          label: '$title，$message',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.horizontal_rule_rounded, size: 13, color: DunesColors.resolve(context, _kSoftMute)),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _sans(context, 11.5, weight: FontWeight.w700, color: _kInk),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sans(context, 11, color: _kMute),
              ),
            ],
          ),
        ),
      );
    }
    final up = o.pct > 0;
    final tone = up ? _kUp : _kDown;
    final pct = (o.pct.abs() * 100).round();
    return Semantics(
      button: true,
      expanded: open,
      label: m.isDemo
          ? '今日异动示例，${m.formalLabel}起显示真实数据。${open ? '点一下收起' : '点开看效果'}'
          : '今日异动 ${m.count} 项：整体比平常这个时候${up ? '高' : '低'} $pct%。${open ? '点一下收起' : '点开查看'}',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          // 示例不在小卡上标（2026-11-25 去掉角标），说明只放在展开后的面板里。
          child: Stack(
            clipBehavior: Clip.none,
            children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: kLhMoversChipWidth,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: _surface(context, open ? const Color(0xFFF1EDFD) : const Color(0xFFF7F5FE)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _border(context, open ? const Color(0xFFC9BCF3) : _kEdge),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.monitor_heart_outlined, size: 13, color: DunesColors.resolve(context, _kPurple)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '今日异动',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: _sans(context, 11.5, weight: FontWeight.w700, color: _kDeep),
                      ),
                    ),
                    Container(
                      constraints: const BoxConstraints(minWidth: 17),
                      height: 17,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: DunesColors.resolve(context, _kPurple),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '${m.count}',
                        style: _sans(context, 10, weight: FontWeight.w700, color: Colors.white, height: 1.0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _PulseDot(color: DunesColors.resolve(context, up ? const Color(0xFFE5554F) : const Color(0xFF1F9D6B))),
                    const SizedBox(width: 5),
                    Text('整体', style: _sans(context, 11, color: _kInk)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${up ? '↑ 高' : '↓ 低'} $pct%',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: _sans(context, 11, weight: FontWeight.w700, color: tone, tabular: true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一颗往外扩散的小圆点（「此刻还在动」）。减弱动效时不动。
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});
  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 7,
      height: 7,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_c.value);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + 1.6 * t,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.55 * (1 - t)),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 展开面板
// ─────────────────────────────────────────────────────────────────────────────

/// 就地展开 / 收起：高度跟着长，内容淡入并轻轻往下落。
class LhMoversReveal extends StatelessWidget {
  const LhMoversReveal({super.key, required this.open, required this.child});

  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedSize(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, -0.03), end: Offset.zero).animate(a),
            child: c,
          ),
        ),
        layoutBuilder: (cur, prev) => Stack(
          alignment: Alignment.topCenter,
          children: [...prev, ?cur],
        ),
        child: open
            ? KeyedSubtree(
                key: const ValueKey('movers-open'),
                child: Padding(padding: const EdgeInsets.only(top: 14), child: child),
              )
            : const SizedBox(key: ValueKey('movers-closed'), width: double.infinity),
      ),
    );
  }
}

/// 面板字号按实际宽度等比：原型在 ~470 宽下的字号为 1.0；手机双栏不小于 0.86，宽屏不超过 1.12。
double _moverScale(double width) =>
    width.isFinite ? (width / 470).clamp(0.86, 1.12).toDouble() : 1.0;

/// 金额：数字字体（等宽数位），「万」跟着同一个字号，整串一行。
TextStyle _money(BuildContext context, double size, Color color) =>
    LhTypography.number(context: context, size: size, color: DunesColors.resolve(context, color))
        .copyWith(height: 1.15, letterSpacing: -0.2, fontFeatures: const [ui.FontFeature.tabularFigures()]);

class LhMoversPanel extends StatefulWidget {
  const LhMoversPanel({
    super.key,
    required this.movers,
    this.caretFromRight = kLhMoversChipWidth / 2,
    this.onProductTap,
    this.onClose,
  });

  final LhMovers movers;

  /// 给了就是「盖满主 Hero」的模式（同利润分布）：右上角 ×、不画小尖角。
  final VoidCallback? onClose;

  /// 小尖角离右边多远（对准小卡中线）。
  final double caretFromRight;
  final ValueChanged<String>? onProductTap;

  @override
  State<LhMoversPanel> createState() => _LhMoversPanelState();
}

/// 交互：
///   · 打开时各块依次浮上来（标题 → 说明 → 结论卡 → 小图 → 产品逐行），减弱动效时直接出现；
///   · 产品一次只展开一行（手风琴），第一行有项目明细时默认展开；
///   · 行、卡片按下轻轻一缩；展开的项目条从 0 长到占比。
class _LhMoversPanelState extends State<LhMoversPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );
  bool _entered = false;
  int? _open;

  @override
  void initState() {
    super.initState();
    _open = _defaultOpen(widget.movers);
  }

  int? _defaultOpen(LhMovers m) =>
      m.products.isNotEmpty && m.products.first.projects.isNotEmpty ? 0 : null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entered) return;
    _entered = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
  }

  @override
  void didUpdateWidget(LhMoversPanel old) {
    super.didUpdateWidget(old);
    final n = widget.movers.products.length;
    if (_open != null && _open! >= n) _open = null;
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  void _toggle(int i) {
    HapticFeedback.selectionClick();
    setState(() => _open = _open == i ? null : i);
  }

  /// 第 [i] 块的入场（按序错开 70ms 左右）。
  Widget _rise(int i, Widget child) {
    final start = math.min(0.55, i * 0.09);
    return _Rise(controller: _enter, interval: Interval(start, math.min(1.0, start + 0.45), curve: Curves.easeOutCubic), child: child);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.movers;
    final overlay = widget.onClose != null;
    return LayoutBuilder(
      builder: (context, box) {
        final k = _moverScale(box.maxWidth);
        final pad = k < 0.95 ? 10.0 : 14.0;
        final card = Container(
          margin: EdgeInsets.only(top: overlay ? 0 : 7),
          padding: EdgeInsets.fromLTRB(pad, pad - 2, pad, pad),
          decoration: BoxDecoration(
            color: _surface(context, Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border(context, _kEdge)),
            boxShadow: [
              BoxShadow(color: const Color(0xFF4A3A7A).withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 6)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _rise(0, _header(context, m, k)),
              if (m.simulated) ...[
                SizedBox(height: 8 * k),
                _rise(1, _notice(context, m, k)),
              ],
              SizedBox(height: 12 * k),
              _columns(context, m, k),
            ],
          ),
        );
        final panel = Stack(
          clipBehavior: Clip.none,
          children: [
            card,
            if (!overlay)
              Positioned(
                top: 0,
                right: widget.caretFromRight - 7,
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: _surface(context, Colors.white),
                      border: Border(
                        left: BorderSide(color: _border(context, _kEdge)),
                        top: BorderSide(color: _border(context, _kEdge)),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
        // 盖满主 Hero 时整块铺白：圆形展开读得出「这是一张面」，也盖住底下渐隐的 Hero。
        return overlay ? ColoredBox(color: _surface(context, Colors.white), child: panel) : panel;
      },
    );
  }

  // ── 头：今日异动 [5 项] [示例] …… 对比近 7 天同一时刻 (×) ──
  Widget _header(BuildContext context, LhMovers m, double k) {
    return Row(
      children: [
        Text('今日异动', style: _sans(context, 16 * k, weight: FontWeight.w700, color: _kInkStrong, letterSpacing: -0.2)),
        SizedBox(width: 8 * k),
        _chip(context, '${m.count} 项', const Color(0xFFEEE9FB), _kDeep, k),
        if (m.simulated) ...[
          SizedBox(width: 6 * k),
          _chip(context, m.isDemo ? '示例' : '模拟', const Color(0xFFFFF1D6), const Color(0xFFA86A12), k),
        ],
        SizedBox(width: 8 * k),
        Expanded(
          child: Text(
            m.compareLabel,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _sans(context, 11.5 * k, color: _kSoftMute, height: 1.3),
          ),
        ),
        if (widget.onClose != null) ...[
          SizedBox(width: 6 * k),
          _closeButton(context, k),
        ],
      ],
    );
  }

  Widget _chip(BuildContext context, String text, Color bg, Color fg, double k) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 * k, vertical: 2.5 * k),
      decoration: BoxDecoration(color: _surface(context, bg), borderRadius: BorderRadius.circular(8 * k)),
      child: Text(text, style: _sans(context, 11.5 * k, weight: FontWeight.w700, color: fg, height: 1.3)),
    );
  }

  /// 右上角 ×：原路收回到小卡（外圈 4 的透明边，点击区到 ~40）。
  Widget _closeButton(BuildContext context, double k) {
    final d = 30 * k;
    return Semantics(
      button: true,
      label: '收起今日异动',
      excludeSemantics: true,
      child: _Press(
        onTap: widget.onClose!,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            width: d,
            height: d,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _surface(context, const Color(0xFFF4F1FB)),
              border: Border.all(color: _border(context, _kEdge), width: 0.8),
            ),
            child: Icon(Icons.close_rounded, size: 15 * k, color: DunesColors.resolve(context, _kInkStrong)),
          ),
        ),
      ),
    );
  }

  /// 示例 / 模拟说明：一句话，琥珀底。
  Widget _notice(BuildContext context, LhMovers m, double k) {
    const ink = Color(0xFF8A5A12);
    final text = m.isDemo
        ? '以下为示例效果，数字不代表今天的真实情况。${m.formalLabel} 起显示真实异动。'
        : m.simBasis == 'time'
        ? '今天为模拟：还没有分时快照，先按时间进度粗估。快照记满 2 天后正式启用。'
        : '今天为模拟：平常数据只有昨天，先按昨日同一时刻估算。${m.formalLabel} 起正式启用。';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * k, vertical: 7 * k),
      decoration: BoxDecoration(
        color: _surface(context, const Color(0xFFFFF7E6)),
        borderRadius: BorderRadius.circular(10 * k),
        border: Border.all(color: _border(context, const Color(0xFFF6E3BC))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1 * k),
            child: Icon(Icons.warning_amber_rounded, size: 14 * k, color: DunesColors.resolve(context, const Color(0xFFA86A12))),
          ),
          SizedBox(width: 7 * k),
          Expanded(child: Text(text, style: _sans(context, 11.5 * k, color: ink, height: 1.45))),
        ],
      ),
    );
  }

  // ── 双栏：左 结论 + 小图 + 单个项目异动 ｜ 右 产品异动 ──
  Widget _columns(BuildContext context, LhMovers m, double k) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = k < 0.95 ? 14.0 : 22.0;
        final left = (constraints.maxWidth - gap) * 0.41;
        return Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: left, child: _overviewColumn(context, m, k, left)),
                SizedBox(width: gap),
                Expanded(child: _productsColumn(context, m, k)),
              ],
            ),
            Positioned(
              left: left + (gap - 1) / 2,
              top: 2,
              bottom: 2,
              width: 1,
              child: ColoredBox(color: _border(context, _kRule)),
            ),
          ],
        );
      },
    );
  }

  Widget _overviewColumn(BuildContext context, LhMovers m, double k, double width) {
    return Column(
      key: const ValueKey('movers-overview-column'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rise(2, _summary(context, m.overall, k)),
        if (m.hasSeries)
          _rise(
            3,
            Padding(
              padding: EdgeInsets.only(top: 12 * k),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MoversChart(movers: m, height: (width * 0.5).clamp(64.0, 120.0)),
                  SizedBox(height: 6 * k),
                  _legend(context, k),
                ],
              ),
            ),
          ),
        if (m.hiddenProjects.isNotEmpty)
          _rise(
            4,
            Padding(
              padding: EdgeInsets.only(top: 12 * k),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ColoredBox(color: _border(context, _kRule), child: const SizedBox(height: 1)),
                  SizedBox(height: 12 * k),
                  Text('单个项目异动', style: _sans(context, 14 * k, weight: FontWeight.w700, color: _kInkStrong)),
                  SizedBox(height: 3 * k),
                  Text('所在产品整体正常', style: _sans(context, 11 * k, color: _kSoftMute)),
                  SizedBox(height: 9 * k),
                  for (final h in m.hiddenProjects) ...[
                    _HiddenProjectCard(project: h, onTap: widget.onProductTap, k: k),
                    SizedBox(height: 8 * k),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _productsColumn(BuildContext context, LhMovers m, double k) {
    return Column(
      key: const ValueKey('movers-products-column'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rise(
          2,
          Padding(
            padding: EdgeInsets.only(top: 2 * k, bottom: 9 * k),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('产品异动', style: _sans(context, 14 * k, weight: FontWeight.w700, color: _kInkStrong)),
                SizedBox(width: 6 * k),
                Expanded(
                  child: Text(
                    '按差额大小排序',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(context, 11 * k, color: _kSoftMute),
                  ),
                ),
              ],
            ),
          ),
        ),
        ColoredBox(color: _border(context, _kRule), child: const SizedBox(height: 1)),
        if (m.products.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12 * k),
            child: Text(
              m.productBasis == 'none' ? '产品基准还在积累，明天起可看' : '没有明显异动的产品',
              style: _sans(context, 11.5 * k, color: _kMute),
            ),
          )
        else
          for (var i = 0; i < m.products.length; i++)
            _rise(
              3 + i,
              _ProductMoverRow(
                key: ValueKey('mover-${m.products[i].name}'),
                mover: m.products[i],
                last: i == m.products.length - 1,
                open: _open == i,
                onToggle: () => _toggle(i),
                projectBasis: m.projectBasis,
                onTap: widget.onProductTap,
                k: k,
              ),
            ),
        if (m.productBasis == 'yesterday')
          Padding(
            padding: EdgeInsets.only(top: 6 * k),
            child: Text('产品的「平常」暂按昨日节奏估算（快照积累中）', style: _sans(context, 10 * k, color: _kSoftMute)),
          ),
      ],
    );
  }

  Widget _summary(BuildContext context, LhMoverOverall o, double k) {
    final up = o.diff > 0;
    final tone = up ? _kUp : _kDown;
    final pct = (o.pct.abs() * 100).round();
    final rule = _border(context, up ? const Color(0xFFF3D9D5) : const Color(0xFFD3E9DD));
    return Semantics(
      label: '整体比平常${up ? '高' : '低'} $pct%，${up ? '多赚' : '少赚'} ${_wan(o.diff)} 万元；今日 ${_wan(o.today)} 万，平常 ${_wan(o.baseline)} 万',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(12 * k, 13 * k, 12 * k, 12 * k),
        decoration: BoxDecoration(
          color: _surface(context, up ? const Color(0xFFFDF1EF) : const Color(0xFFEDF7F1)),
          borderRadius: BorderRadius.circular(14 * k),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: _signedWan(o.diff),
                      style: LhTypography.number(context: context, size: 30 * k, color: DunesColors.resolve(context, tone))
                          .copyWith(letterSpacing: -0.9, height: 1),
                    ),
                    TextSpan(text: ' 万元', style: _sans(context, 12.5 * k, weight: FontWeight.w700, color: tone)),
                  ],
                ),
                maxLines: 1,
              ),
            ),
            SizedBox(height: 7 * k),
            Text(
              '整体比平常${up ? '高' : '低'} $pct%',
              style: _sans(context, 12 * k, color: up ? const Color(0xFF7A4B47) : const Color(0xFF3F5E50)),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10 * k),
              child: ColoredBox(color: rule, child: const SizedBox(height: 1, width: double.infinity)),
            ),
            _kv(context, '今日', o.today, k),
            SizedBox(height: 6 * k),
            _kv(context, '平常', o.baseline, k),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String label, double yuan, double k) {
    return Row(
      children: [
        SizedBox(width: 34 * k, child: Text(label, style: _sans(context, 12 * k, color: const Color(0xFF5E6B66)))),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: _plainWan(yuan), style: _money(context, 14.5 * k, _kInkStrong)),
                  TextSpan(text: ' 万', style: _sans(context, 12 * k, weight: FontWeight.w700, color: _kInkStrong)),
                ],
              ),
              maxLines: 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _legend(BuildContext context, double k) {
    Widget item(Widget mark, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: 6 * k),
        Text(text, style: _sans(context, 10.5 * k, color: _kMute)),
      ],
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          item(
            Container(
              width: 14 * k,
              height: 2.5,
              decoration: BoxDecoration(
                color: DunesColors.resolve(context, const Color(0xFFE5554F)),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            '今日',
          ),
          SizedBox(width: 16 * k),
          item(
            SizedBox(
              width: 14 * k,
              height: 2,
              child: CustomPaint(painter: _DashPainter(DunesColors.resolve(context, const Color(0xFFB3A6EA)))),
            ),
            '平常同一时刻',
          ),
        ],
      ),
    );
  }
}

/// 入场：跟着面板的总进度在自己的区间里淡入、上浮 10px。
class _Rise extends StatelessWidget {
  const _Rise({required this.controller, required this.interval, required this.child});

  final AnimationController controller;
  final Interval interval;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final t = interval.transform(controller.value);
        if (t >= 1) return child!;
        return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child));
      },
    );
  }
}

/// 按下轻轻一缩（0.985），松开弹回；桌面上显示手型。
class _Press extends StatefulWidget {
  const _Press({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down && !reduce ? 0.985 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 一行产品异动：点一下展开主要拖累 / 拉动的项目（同时只开一行，状态在面板上）。
class _ProductMoverRow extends StatelessWidget {
  const _ProductMoverRow({
    super.key,
    required this.mover,
    required this.last,
    required this.open,
    required this.onToggle,
    required this.projectBasis,
    required this.k,
    this.onTap,
  });

  final LhProductMover mover;
  final bool last;
  final bool open;
  final VoidCallback onToggle;
  final String projectBasis;
  final double k;

  /// 「查看产品详情」。
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final m = mover;
    final (name, tag) = lhProfitSplitNameTag(m.name);
    final tone = m.up ? _kUp : _kDown;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final chevron = Container(
      width: 22 * k,
      height: 22 * k,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _surface(context, open ? const Color(0xFFEDE8FB) : const Color(0xFFF4F1FB)),
        shape: BoxShape.circle,
      ),
      child: AnimatedRotation(
        turns: open ? 0.5 : 0,
        duration: reduce ? Duration.zero : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: Icon(Icons.keyboard_arrow_down_rounded, size: 16 * k, color: DunesColors.resolve(context, open ? _kDeep : _kMute)),
      ),
    );
    final head = Padding(
      padding: EdgeInsets.symmetric(vertical: 11 * k),
      child: LayoutBuilder(
        builder: (context, box) {
          // 窄的时候「今日 · 平常」挪到徽标下面一行，不挤成两行小字。
          final narrow = box.maxWidth < 230 * k;
          final comparison = _comparison(context, m.actual, m.baseline, k, align: narrow ? TextAlign.left : TextAlign.right);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _nameTag(context, name, tag, k)),
                  SizedBox(width: 8 * k),
                  Text('${_signedWan(m.diff)}万', maxLines: 1, style: _money(context, 15 * k, tone)),
                ],
              ),
              SizedBox(height: 7 * k),
              Row(
                children: [
                  _badge(context, m.badge, m.up, k),
                  SizedBox(width: 8 * k),
                  Expanded(child: narrow ? const SizedBox.shrink() : comparison),
                  SizedBox(width: 6 * k),
                  chevron,
                ],
              ),
              if (narrow) ...[SizedBox(height: 5 * k), comparison],
            ],
          );
        },
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: _border(context, _kRule))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            label: '$name${tag == null ? '' : '（$tag）'}，${m.badge}，'
                '${m.diff < 0 ? '少' : '多'} ${_wan(m.diff)} 万；今日 ${_plainWan(m.actual)} 万，平常 ${_plainWan(m.baseline)} 万。'
                '${open ? '点一下收起' : '点开看是哪些项目'}',
            excludeSemantics: true,
            child: _Press(onTap: onToggle, child: head),
          ),
          AnimatedSize(
            duration: reduce ? Duration.zero : const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero).animate(a),
                  child: c,
                ),
              ),
              layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topCenter, children: [...prev, ?cur]),
              child: open
                  ? KeyedSubtree(key: const ValueKey('open'), child: _projects(context, m))
                  : const SizedBox(key: ValueKey('closed'), width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }

  /// 展开：「主要拖累的项目 …… 合计占差额 93%」+ 2–3 个项目 + 「查看产品详情 ›」。
  Widget _projects(BuildContext context, LhProductMover m) {
    final tone = m.up ? _kUp : _kDown;
    final dot = m.up ? const Color(0xFFE5554F) : const Color(0xFF3DAF7E);
    final empty = m.projects.isEmpty;
    return Container(
      margin: EdgeInsets.only(bottom: 11 * k),
      padding: EdgeInsets.fromLTRB(12 * k, 10 * k, 12 * k, 4 * k),
      decoration: BoxDecoration(
        color: _surface(context, const Color(0xFFF8F6FD)),
        borderRadius: BorderRadius.circular(12 * k),
        border: Border.all(color: _border(context, const Color(0xFFEEEAF8))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(m.up ? '主要拉动的项目' : '主要拖累的项目', style: _sans(context, 11.5 * k, weight: FontWeight.w700, color: _kInk)),
              SizedBox(width: 6 * k),
              if (!empty && m.cover > 0)
                Expanded(
                  child: Text(
                    '合计占差额 ${(m.cover * 100).round()}%',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(context, 10.5 * k, color: _kSoftMute, tabular: true),
                  ),
                ),
            ],
          ),
          if (empty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10 * k),
              child: Text(
                projectBasis == 'none' ? '项目明细积累中，明天起可看' : '差额分散在很多小项目里，没有单个主要原因',
                style: _sans(context, 11.5 * k, color: _kMute, height: 1.4),
              ),
            )
          else
            for (var i = 0; i < m.projects.length; i++)
              _projectLine(context, m.projects[i], m.diff, dot, tone, last: i == m.projects.length - 1),
          if (onTap != null)
            Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                button: true,
                label: '查看${m.name}详情',
                excludeSemantics: true,
                child: _Press(
                  onTap: () => onTap!(m.name),
                  child: SizedBox(
                    height: 36,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('查看产品详情', style: _sans(context, 11.5 * k, weight: FontWeight.w600, color: _kDeep)),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, size: 15 * k, color: DunesColors.resolve(context, _kDeep)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _projectLine(BuildContext context, LhProjectMover p, double productDiff, Color dot, Color tone, {required bool last}) {
    final share = productDiff == 0 ? 0.0 : (p.diff / productDiff).clamp(0.0, 1.0).toDouble();
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: '项目 ${p.name}，${p.diff < 0 ? '少' : '多'} ${_wan(p.diff)} 万，今日 ${_plainWan(p.actual)} 万，平常 ${_plainWan(p.baseline)} 万',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 9 * k),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: _border(context, const Color(0xFFECE8F5)))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 6 * k,
                  height: 6 * k,
                  decoration: BoxDecoration(color: DunesColors.resolve(context, dot), shape: BoxShape.circle),
                ),
                SizedBox(width: 8 * k),
                Expanded(
                  child: Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(context, 12.5 * k, weight: FontWeight.w700, color: _kInkStrong),
                  ),
                ),
                SizedBox(width: 6 * k),
                Text('${_signedWan(p.diff)}万', maxLines: 1, style: _money(context, 13 * k, tone)),
              ],
            ),
            SizedBox(height: 7 * k),
            Padding(
              padding: EdgeInsets.only(left: 14 * k),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 0.82,
                child: Container(
                  height: 4,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: _surface(context, const Color(0xFFE9E5F3)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: reduce ? share : 0, end: share),
                    duration: reduce ? Duration.zero : const Duration(milliseconds: 620),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => FractionallySizedBox(
                      widthFactor: v,
                      child: Container(
                        decoration: BoxDecoration(
                          color: DunesColors.resolve(context, dot),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 5 * k),
            _comparison(context, p.actual, p.baseline, k, align: TextAlign.right),
          ],
        ),
      ),
    );
  }
}

Widget _comparison(BuildContext context, double today, double baseline, double k, {TextAlign align = TextAlign.right}) {
  return Text(
    '今日 ${_plainWan(today)}万 · 平常 ${_plainWan(baseline)}万',
    textAlign: align,
    maxLines: 2,
    style: _sans(context, 10.5 * k, color: _kMute, tabular: true, height: 1.3),
  );
}

/// 名称 + 口径小标签（「（交易）」拆出来）。
Widget _nameTag(BuildContext context, String name, String? tag, double k) {
  return Wrap(
    spacing: 6 * k,
    runSpacing: 3 * k,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _sans(context, 13.5 * k, weight: FontWeight.w700, color: _kInkStrong, height: 1.25),
      ),
      if (tag != null)
        Container(
          padding: EdgeInsets.symmetric(horizontal: 6 * k, vertical: 1.5 * k),
          decoration: BoxDecoration(color: _surface(context, const Color(0xFFF2EFF7)), borderRadius: BorderRadius.circular(6 * k)),
          child: Text(tag, style: _sans(context, 10 * k, color: _kMute, height: 1.25)),
        ),
    ],
  );
}

Widget _badge(BuildContext context, String text, bool up, double k) {
  return Container(
    padding: EdgeInsets.symmetric(horizontal: 8 * k, vertical: 3 * k),
    decoration: BoxDecoration(color: _surface(context, up ? _kUpBg : _kDownBg), borderRadius: BorderRadius.circular(8 * k)),
    child: Text(text, maxLines: 1, style: _sans(context, 11.5 * k, weight: FontWeight.w700, color: up ? _kUp : _kDown, tabular: true, height: 1.2)),
  );
}

/// 单个项目异动（所在产品整体正常）：
///   [项目] …… −1.12万 / 湖南中石油加油 / 属于中石油特惠现金券 · 产品整体仅低 8% / [↓ 低 64%] / 今日 · 平常。
class _HiddenProjectCard extends StatelessWidget {
  const _HiddenProjectCard({required this.project, required this.k, this.onTap});

  final LhHiddenProject project;
  final double k;

  /// 点卡片 = 打开它所在的产品。
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final h = project;
    final tone = h.up ? _kUp : _kDown;
    final (productName, _) = lhProfitSplitNameTag(h.product);
    final ppct = (h.productPct.abs() * 100).round();
    final productNote = h.productPct == 0
        ? '属于$productName · 产品整体正常'
        : '属于$productName · 产品整体仅${h.productPct < 0 ? '低' : '高'} $ppct%';
    final card = Container(
      padding: EdgeInsets.fromLTRB(12 * k, 11 * k, 12 * k, 12 * k),
      decoration: BoxDecoration(
        color: _surface(context, h.up ? const Color(0xFFFFF7F6) : const Color(0xFFF4FAF7)),
        borderRadius: BorderRadius.circular(14 * k),
        border: Border.all(color: _border(context, h.up ? const Color(0xFFF6DEDA) : const Color(0xFFD9EDE2))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6 * k, vertical: 1.5 * k),
                decoration: BoxDecoration(color: _surface(context, const Color(0xFFEEE9FB)), borderRadius: BorderRadius.circular(6 * k)),
                child: Text('项目', style: _sans(context, 10 * k, weight: FontWeight.w700, color: _kDeep, height: 1.3)),
              ),
              const Spacer(),
              Flexible(
                flex: 4,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text('${_signedWan(h.diff)}万', maxLines: 1, style: _money(context, 15 * k, tone)),
                ),
              ),
            ],
          ),
          SizedBox(height: 7 * k),
          Text(
            h.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _sans(context, 13.5 * k, weight: FontWeight.w700, color: _kInkStrong, height: 1.25),
          ),
          SizedBox(height: 5 * k),
          Text(productNote, style: _sans(context, 11 * k, color: _kMute, height: 1.45)),
          SizedBox(height: 9 * k),
          _badge(context, h.badge, h.up, k),
          SizedBox(height: 7 * k),
          _comparison(context, h.actual, h.baseline, k, align: TextAlign.left),
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: '项目 ${h.name}，$productNote${h.productPct == 0 ? '' : '，被其他项目抵消了'}，${h.badge}，${h.diff < 0 ? '少' : '多'} ${_wan(h.diff)} 万',
      excludeSemantics: true,
      child: onTap == null ? card : _Press(onTap: () => onTap!(h.product), child: card),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 小图：同期基准范围带 + 中位虚线，今日红线画到此刻
// ─────────────────────────────────────────────────────────────────────────────

class _MoversChart extends StatelessWidget {
  const _MoversChart({required this.movers, required this.height});
  final LhMovers movers;
  final double height;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label:
          '今日累计曲线与平常对比：今日 ${_wan(movers.overall.today)} 万，平常 ${_wan(movers.overall.baseline)} 万',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: reduce ? 1.0 : 0.0, end: 1.0),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => CustomPaint(
            size: Size.infinite,
            painter: _MoversChartPainter(
              movers: movers,
              t: t,
              band: _surface(context, const Color(0xFFE6E0F8)),
              median: DunesColors.resolve(context, const Color(0xFFB3A6EA)),
              today: DunesColors.resolve(context, const Color(0xFFE5554F)),
              nowLine: DunesColors.resolve(context, const Color(0xFFF2A9A3)),
              ring: _surface(context, Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoversChartPainter extends CustomPainter {
  _MoversChartPainter({
    required this.movers,
    required this.t,
    required this.band,
    required this.median,
    required this.today,
    required this.nowLine,
    required this.ring,
  });

  final LhMovers movers;
  final double t;
  final Color band;
  final Color median;
  final Color today;
  final Color nowLine;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final m = movers;
    const padX = 6.0;
    const top = 6.0;
    final bottom = size.height - 6;
    var hi = 0.0;
    var lo = 0.0;
    for (final v in [...m.seriesHigh, ...m.today]) {
      hi = math.max(hi, v);
      lo = math.min(lo, v);
    }
    if (hi <= lo) hi = lo + 1;
    hi += (hi - lo) * 0.06;
    double x(int minute) => padX + (size.width - padX * 2) * (minute.clamp(0, 1440) / 1440);
    double y(double v) => bottom - (bottom - top) * ((v - lo) / (hi - lo));

    Path smooth(List<Offset> p) {
      final path = Path();
      if (p.isEmpty) return path;
      path.moveTo(p.first.dx, p.first.dy);
      for (var i = 0; i < p.length - 1; i++) {
        final p0 = p[math.max(0, i - 1)];
        final p1 = p[i];
        final p2 = p[i + 1];
        final p3 = p[math.min(p.length - 1, i + 2)];
        path.cubicTo(
          p1.dx + (p2.dx - p0.dx) / 6,
          p1.dy + (p2.dy - p0.dy) / 6,
          p2.dx - (p3.dx - p1.dx) / 6,
          p2.dy - (p3.dy - p1.dy) / 6,
          p2.dx,
          p2.dy,
        );
      }
      return path;
    }

    // 范围带（从左往右长出来）
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * t, size.height));
    final n = m.seriesMinutes.length;
    final highPts = [for (var i = 0; i < n; i++) Offset(x(m.seriesMinutes[i]), y(m.seriesHigh[i]))];
    final lowPts = [for (var i = n - 1; i >= 0; i--) Offset(x(m.seriesMinutes[i]), y(m.seriesLow[i]))];
    final bandPath = smooth(highPts);
    final lowPath = smooth(lowPts);
    bandPath.lineTo(lowPts.first.dx, lowPts.first.dy);
    bandPath.extendWithPath(lowPath, Offset.zero);
    bandPath.close();
    canvas.drawPath(
      bandPath,
      Paint()
        ..shader = LinearGradient(
          colors: [band.withValues(alpha: band.a * 0.45), band],
        ).createShader(Offset.zero & size),
    );

    // 同期基准：中位虚线
    final medianPath = smooth([for (var i = 0; i < n; i++) Offset(x(m.seriesMinutes[i]), y(m.seriesMedian[i]))]);
    final dash = Paint()
      ..color = median
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (final metric in medianPath.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), dash);
        d += 9;
      }
    }
    canvas.restore();

    // 此刻竖线
    final nowX = x(m.minute);
    final nowPaint = Paint()
      ..color = nowLine
      ..strokeWidth = 1;
    var dy = 2.0;
    while (dy < size.height - 2) {
      canvas.drawLine(Offset(nowX, dy), Offset(nowX, math.min(dy + 3, size.height - 2)), nowPaint);
      dy += 6;
    }

    // 今日：红线从 0 点画到此刻（跟着 t 往前走）
    if (m.today.isEmpty) return;
    final pts = <Offset>[
      Offset(x(0), y(0)),
      for (var i = 0; i < m.today.length && i < m.todayMinutes.length; i++)
        Offset(x(m.todayMinutes[i]), y(m.today[i])),
    ];
    final todayPath = smooth(pts);
    final metrics = todayPath.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final shown = metric.extractPath(0, metric.length * t);
    canvas.drawPath(
      shown,
      Paint()
        ..color = today
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    final tip = metric.getTangentForOffset(metric.length * t)?.position ?? pts.last;
    canvas.drawCircle(tip, 4.2 + 1.8, Paint()..color = ring);
    canvas.drawCircle(tip, 4.2, Paint()..color = today);
  }

  @override
  bool shouldRepaint(_MoversChartPainter old) =>
      old.t != t ||
      old.movers != movers ||
      old.band != band ||
      old.median != median ||
      old.today != today;
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = size.height;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(math.min(x + 4, size.width), size.height / 2), p);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}


// ─────────────────────────────────────────────────────────────────────────────
// 前端模拟（后端还没有基准 / 取不到时）：规则和后端 intraday_movers.go 一致，
// 基准只用昨天：整体 = 昨日同一时刻；产品 = 昨日全天 × 昨日此刻完成度。
// ─────────────────────────────────────────────────────────────────────────────

const _kSimOverallPct = 0.20;
const _kSimOverallAmount = 10000.0;
const _kSimProductPct = 0.50;
const _kSimProductAmount = 3000.0;
const _kSimSmallBase = 1000.0;
const _kSimEarlyProgress = 0.15;
const _kSimEarlyMinute = 8 * 60;
const _kSimMaxProducts = 5;
const _kSimStep = 20;

Map<String, double> _byName(List<Map<String, dynamic>> rows) {
  final out = <String, double>{};
  for (final r in rows) {
    final name = (r['name']?.toString() ?? '').trim();
    if (name.isEmpty) continue;
    out[name] = (out[name] ?? 0) + _d(r['profit']);
  }
  return out;
}

double _cumAt(List<LhIntradayPoint> pts, int minute) {
  var v = 0.0;
  for (final p in pts) {
    if (p.minute > minute) break;
    v = p.profit;
  }
  return v;
}

/// 产品异动判定（同后端 classifyProductMover）。不算异动返回 null。
LhProductMover? lhClassifyProductMover(String name, double actual, double base) {
  final diff = actual - base;
  if (diff.abs() < _kSimProductAmount) return null;
  String kind;
  var pct = 0.0;
  if (base > 0 && actual < 0) {
    kind = 'turnLoss';
  } else if (base < 0 && actual > 0) {
    kind = 'turnProfit';
  } else {
    if (base.abs() >= _kSimSmallBase) {
      pct = diff / base.abs();
      if (pct.abs() < _kSimProductPct) return null;
    }
    kind = diff > 0 ? 'faster' : 'slower';
  }
  return LhProductMover(name: name, kind: kind, actual: actual, baseline: base, diff: diff, pct: pct);
}

/// 用今天的分时快照（含昨天）+ 今天 / 昨天的产品行，按后端同一套规则估一份「模拟」异动。
/// 没有昨天的快照时返回不可用的空结果（[LhMovers.usable] 为 false）。
LhMovers lhSimulateMovers({
  required LhIntradayData? intraday,
  required List<Map<String, dynamic>> todayRows,
  required List<Map<String, dynamic>> yesterdayRows,
  required DateTime today,
  int? nowMinute,
}) {
  final last = intraday?.last;
  if (intraday == null || intraday.restricted) {
    if (intraday?.restricted == true) return const LhMovers();
    return _simulateByTime(todayRows, yesterdayRows, today, nowMinute);
  }
  if (!intraday.available || last == null || intraday.prev.isEmpty) {
    return _simulateByTime(todayRows, yesterdayRows, today, nowMinute);
  }
  final minute = last.minute;
  final base = _cumAt(intraday.prev, minute);
  final prevFull = intraday.prev.last.profit;
  final prevComplete = intraday.prev.last.minute >= 23 * 60 && prevFull > 0;
  final progress = prevComplete ? base / prevFull : null;
  final early = progress != null ? progress < _kSimEarlyProgress : minute < _kSimEarlyMinute;

  final diff = last.profit - base;
  final pct = base != 0 ? diff / base.abs() : 0.0;
  final overall = LhMoverOverall(
    today: last.profit,
    baseline: base,
    diff: diff,
    pct: pct,
    flagged: !early && base != 0 && pct.abs() >= _kSimOverallPct && diff.abs() >= _kSimOverallAmount,
  );

  final products = <LhProductMover>[];
  if (!early && progress != null && yesterdayRows.isNotEmpty) {
    final now = _byName(todayRows);
    final y = _byName(yesterdayRows);
    for (final name in {...now.keys, ...y.keys}) {
      final m = lhClassifyProductMover(name, now[name] ?? 0, (y[name] ?? 0) * progress);
      if (m != null) products.add(m);
    }
    products.sort((a, b) {
      final c = b.diff.abs().compareTo(a.diff.abs());
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    if (products.length > _kSimMaxProducts) {
      products.removeRange(_kSimMaxProducts, products.length);
    }
  }

  final minutes = <int>[for (var g = 0; g <= 1440; g += _kSimStep) g];
  final baseSeries = [for (final g in minutes) _cumAt(intraday.prev, g)];
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  String two(int v) => v.toString().padLeft(2, '0');
  return LhMovers(
    available: true,
    at: last.at,
    minute: minute,
    baselineDays: 1,
    productBasis: progress != null && yesterdayRows.isNotEmpty ? 'yesterday' : 'none',
    early: early,
    overall: overall,
    products: List<LhProductMover>.unmodifiable(products),
    count: early ? 0 : (overall.flagged ? 1 : 0) + products.length,
    seriesMinutes: minutes,
    seriesMedian: baseSeries,
    seriesLow: baseSeries,
    seriesHigh: baseSeries,
    todayMinutes: [for (final p in intraday.today) p.minute],
    today: [for (final p in intraday.today) p.profit],
    simulated: true,
    formalFrom: '${tomorrow.year}-${two(tomorrow.month)}-${two(tomorrow.day)}',
    simBasis: 'snapshot',
  );
}

/// 没有分时快照时的粗估：今天截至现在的产品合计 vs 昨日全天 × 今天已过时间比例。
/// 今天 / 昨天的产品行有一边是空的就不估（返回不可用）。
LhMovers _simulateByTime(
  List<Map<String, dynamic>> todayRows,
  List<Map<String, dynamic>> yesterdayRows,
  DateTime today,
  int? nowMinute,
) {
  if (todayRows.isEmpty || yesterdayRows.isEmpty) return const LhMovers();
  final minute = (nowMinute ?? today.hour * 60 + today.minute).clamp(0, 1440).toInt();
  final f = minute / 1440;
  final now = _byName(todayRows);
  final y = _byName(yesterdayRows);
  final todayTotal = now.values.fold<double>(0, (a, b) => a + b);
  final yTotal = y.values.fold<double>(0, (a, b) => a + b);
  final base = yTotal * f;
  final early = f < _kSimEarlyProgress;
  final diff = todayTotal - base;
  final pct = base != 0 ? diff / base.abs() : 0.0;
  final overall = LhMoverOverall(
    today: todayTotal,
    baseline: base,
    diff: diff,
    pct: pct,
    flagged: !early && base != 0 && pct.abs() >= _kSimOverallPct && diff.abs() >= _kSimOverallAmount,
  );
  final products = <LhProductMover>[];
  if (!early) {
    for (final name in {...now.keys, ...y.keys}) {
      final m = lhClassifyProductMover(name, now[name] ?? 0, (y[name] ?? 0) * f);
      if (m != null) products.add(m);
    }
    products.sort((a, b) {
      final c = b.diff.abs().compareTo(a.diff.abs());
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    if (products.length > _kSimMaxProducts) {
      products.removeRange(_kSimMaxProducts, products.length);
    }
  }
  // 小图：基准按时间直线累到昨日全天，今天只有「0 点 → 此刻」两个点。
  final minutes = <int>[for (var g = 0; g <= 1440; g += _kSimStep) g];
  final baseSeries = [for (final g in minutes) yTotal * g / 1440];
  String two(int v) => v.toString().padLeft(2, '0');
  return LhMovers(
    available: true,
    at: '${two(minute ~/ 60)}:${two(minute % 60)}',
    minute: minute,
    baselineDays: 1,
    productBasis: 'yesterday',
    early: early,
    overall: overall,
    products: List<LhProductMover>.unmodifiable(products),
    count: early ? 0 : (overall.flagged ? 1 : 0) + products.length,
    seriesMinutes: minutes,
    seriesMedian: baseSeries,
    seriesLow: baseSeries,
    seriesHigh: baseSeries,
    todayMinutes: [0, minute],
    today: [0, todayTotal],
    simulated: true,
    simBasis: 'time',
  );
}


// ─────────────────────────────────────────────────────────────────────────────
// 示例（正式数据出来之前看效果用）：整体按今天真实利润推（慢 31%），
// 产品 / 项目 / 藏在产品里的项目是示例数；小卡与面板都标「示例 · 明日起真实」。
// ─────────────────────────────────────────────────────────────────────────────

/// 一天里利润累计的典型形状（0–1）：上午慢、午后快，晚上收平。
double _demoShape(int minute) {
  double logistic(double m) => 1 / (1 + math.exp(-(m - 780) / 170));
  final lo = logistic(0);
  final hi = logistic(1440);
  return ((logistic(minute.toDouble()) - lo) / (hi - lo)).clamp(0.0, 1.0).toDouble();
}

/// [today] 今天截至现在的真实利润（元），[minute] 现在是第几分钟，[now] 用来算「明天」。
LhMovers lhDemoMovers({required double today, required int minute, required DateTime now}) {
  final m = minute.clamp(60, 1440).toInt();
  final shape = math.max(0.05, _demoShape(m));
  final todayNow = today == 0 ? 50500.0 : today;
  final baselineNow = todayNow / 0.69; // 示例：比平常慢 31%
  final fullDay = baselineNow / shape;
  final minutes = <int>[for (var g = 0; g <= 1440; g += _kSimStep) g];
  final median = [for (final g in minutes) fullDay * _demoShape(g)];
  final todayMinutes = <int>[for (var g = 0; g < m; g += 60) g, m];
  final todaySeries = [for (final g in todayMinutes) todayNow * _demoShape(g) / shape];
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  String two(int v) => v.toString().padLeft(2, '0');
  const products = <LhProductMover>[
    LhProductMover(
      name: '运营商点播（积分）', kind: 'slower', actual: 6200, baseline: 11900, diff: -5700, pct: -0.48, cover: 0.93,
      projects: [
        LhProjectMover(name: '联通视频会员', actual: 2200, baseline: 6300, diff: -4100, pct: -0.65),
        LhProjectMover(name: '移动流量包', actual: 1800, baseline: 3000, diff: -1200, pct: -0.40),
      ],
    ),
    LhProductMover(
      name: '满减券（交易）', kind: 'turnLoss', actual: -1600, baseline: 2200, diff: -3800, pct: 0, cover: 1,
      projects: [
        LhProjectMover(name: '美团满减合作', actual: -1900, baseline: 1200, diff: -3100),
        LhProjectMover(name: '饿了么满减', actual: 300, baseline: 1000, diff: -700),
      ],
    ),
    LhProductMover(
      name: '中石化普惠现金券（交易）', kind: 'faster', actual: 9600, baseline: 5900, diff: 3700, pct: 0.62, cover: 0.95,
      projects: [
        LhProjectMover(name: '广东中石化普惠', actual: 6100, baseline: 3200, diff: 2900, pct: 0.91),
        LhProjectMover(name: '江苏中石化普惠', actual: 1700, baseline: 1100, diff: 600, pct: 0.55),
      ],
    ),
  ];
  const hidden = <LhHiddenProject>[
    LhHiddenProject(
      product: '中石油特惠现金券（交易）', name: '湖南中石油加油', kind: 'slower',
      actual: 6300, baseline: 17500, diff: -11200, pct: -0.64, productPct: -0.08,
    ),
  ];
  return LhMovers(
    available: true,
    at: '${two(m ~/ 60)}:${two(m % 60)}',
    minute: m,
    baselineDays: 7,
    productDays: 7,
    productBasis: 'snapshot',
    projectDays: 7,
    projectBasis: 'snapshot',
    overall: LhMoverOverall(
      today: todayNow,
      baseline: baselineNow,
      diff: todayNow - baselineNow,
      pct: -0.31,
      flagged: true,
    ),
    products: products,
    hiddenProjects: hidden,
    count: 1 + products.length + hidden.length,
    seriesMinutes: minutes,
    seriesMedian: median,
    seriesLow: [for (final v in median) v * 0.88],
    seriesHigh: [for (final v in median) v * 1.1],
    todayMinutes: todayMinutes,
    today: todaySeries,
    simulated: true,
    formalFrom: '${tomorrow.year}-${two(tomorrow.month)}-${two(tomorrow.day)}',
    simBasis: 'demo',
  );
}
