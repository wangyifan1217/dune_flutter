import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_profit_split.dart' show lhProfitSplitNameTag;
import 'lighthouse_theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
// 灯塔 · 今日油价（2026-11-25 · 原型「今日油价 · 精修」）
//
//   入口：产品汇总卡头右侧一颗小药丸「💧 92# 8.44 ▼」，点开从药丸那一点画圆盖满主 Hero
//   （同利润分布 / 今日异动，三个只开一个；上面「利润 | 资金 · 今日 | 本月」那行不动）。
//   面板从上到下：
//     · 主价：{全国均价 / 某省} · 92 号汽油 —— 8.44 元/升 + 较上次调价胶囊；92# / 95# / 98# / 0# 分段切油号
//     · 下次调价：11月26日 24 时 · 明晚 | 预计下调 0.35–0.42（有人手填才有）+ 本轮 10 个工作日刻度
//     · 近 8 次调价：阶梯图，点圆点看那次的价和涨跌
//     · 各省：点图（全国最低 → 最高，竖线 = 全国均价），最贵 / 最便宜排序，点一行切到那个省
//     · 加油类产品今天（名字里带中石化 / 中石油 / 加油的产品，今天利润 + 异动标签）
//
//   数据：GET /lighthouse/oil-price（lighthouse-go oil_price.go）。调价窗口按发改委「10 个工作日」
//   + 法定节假日在后端算；「较上次」「近 8 次」靠后端每天存的快照，所以上线头几天没有。
//   涨 = 红 ▲，降 = 绿 ▼（和异动一致）。
// ═════════════════════════════════════════════════════════════════════════════

const _kInkStrong = Color(0xFF231D38);
const _kInk = Color(0xFF3A3352);
const _kMute = Color(0xFF6E6890);
const _kSoftMute = Color(0xFF8C87A3);
const _kFaint = Color(0xFFAAA5BF);
const _kDeep = Color(0xFF4B36A8);
const _kPurple = Color(0xFF6A4FC9);
const _kLilac = Color(0xFFB7A6F0);
const _kUp = Color(0xFFD23C3C);
const _kUpBg = Color(0xFFFDECEA);
const _kDown = Color(0xFF1F8A5C);
const _kDownBg = Color(0xFFE6F5EC);
const _kEdge = Color(0xFFEFEAFB);
const _kRule = Color(0xFFF1EEF7);

/// 四个油号（顺序 = 接口字段 p92 / p95 / p98 / p0）。
const kLhOilGrades = ['92#', '95#', '98#', '0#'];
const kLhOilGradeNames = ['92 号汽油', '95 号汽油', '98 号汽油', '0 号柴油'];

double? _num(Object? v) {
  if (v == null) return null;
  final d = v is num ? v.toDouble() : double.tryParse('$v');
  if (d == null || d.isNaN || d <= -50 || d >= 50) return null;
  return d;
}

DateTime? _date(Object? v) {
  final s = v?.toString() ?? '';
  if (s.length < 10) return null;
  return DateTime.tryParse(s.substring(0, 10));
}

@immutable
class LhOilPrices {
  const LhOilPrices({this.p92, this.p95, this.p98, this.p0});

  factory LhOilPrices.fromJson(Object? raw) {
    if (raw is! Map) return const LhOilPrices();
    return LhOilPrices(p92: _num(raw['p92']), p95: _num(raw['p95']), p98: _num(raw['p98']), p0: _num(raw['p0']));
  }

  final double? p92;
  final double? p95;
  final double? p98;
  final double? p0;

  double? grade(int i) => switch (i) { 0 => p92, 1 => p95, 2 => p98, _ => p0 };

  bool get isEmpty => p92 == null && p95 == null && p98 == null && p0 == null;
}

@immutable
class LhOilProvince {
  const LhOilProvince({required this.prov, this.prices = const LhOilPrices(), this.delta = const LhOilPrices()});

  factory LhOilProvince.fromJson(Object? raw) {
    final m = raw is Map ? raw : const {};
    return LhOilProvince(
      prov: m['prov']?.toString() ?? '',
      prices: LhOilPrices.fromJson(m),
      delta: LhOilPrices.fromJson(m['delta']),
    );
  }

  final String prov;
  final LhOilPrices prices;

  /// 较上次调价（元/升）；还没攒到历史时为空。
  final LhOilPrices delta;
}

@immutable
class LhOilPoint {
  const LhOilPoint({required this.window, required this.effective, required this.prices});

  factory LhOilPoint.fromJson(Object? raw) {
    final m = raw is Map ? raw : const {};
    return LhOilPoint(
      window: _date(m['window']),
      effective: _date(m['effective']),
      prices: LhOilPrices.fromJson(m),
    );
  }

  /// 那次调价的窗口日（24 时）；第一个点是「开始记录」那天，不是调价。
  final DateTime? window;
  final DateTime? effective;
  final LhOilPrices prices;
}

@immutable
class LhOilWindow {
  const LhOilWindow({this.last, this.next, this.daysLeft = 0, this.workday = 0, this.workdays = 10, this.calendarStale = false});

  factory LhOilWindow.fromJson(Object? raw) {
    final m = raw is Map ? raw : const {};
    return LhOilWindow(
      last: _date(m['last']),
      next: _date(m['next']),
      daysLeft: (m['daysLeft'] as num?)?.toInt() ?? 0,
      workday: (m['workday'] as num?)?.toInt() ?? 0,
      workdays: (m['workdays'] as num?)?.toInt() ?? 10,
      calendarStale: m['calendarStale'] == true,
    );
  }

  final DateTime? last;
  final DateTime? next;

  /// 0 = 今晚 24 时。
  final int daysLeft;
  final int workday;
  final int workdays;
  final bool calendarStale;

  String get relativeLabel => switch (daysLeft) {
        <= 0 => '今晚',
        1 => '明晚',
        2 => '后天',
        _ => '$daysLeft 天后',
      };
}

@immutable
class LhOilForecast {
  const LhOilForecast({required this.direction, this.min = 0, this.max = 0, this.source = '', this.note = ''});

  static LhOilForecast? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final dir = raw['direction']?.toString() ?? '';
    if (dir.isEmpty) return null;
    return LhOilForecast(
      direction: dir,
      min: _num(raw['min']) ?? 0,
      max: _num(raw['max']) ?? 0,
      source: raw['source']?.toString() ?? '',
      note: raw['note']?.toString() ?? '',
    );
  }

  /// down / up / flat
  final String direction;
  final double min;
  final double max;
  final String source;
  final String note;

  bool get down => direction == 'down';
  bool get up => direction == 'up';

  String get title => down ? '预计下调' : (up ? '预计上调' : '预计不调');

  /// 0.35–0.42 / 0.35 / —
  String get range {
    if (min <= 0 && max <= 0) return '—';
    if ((max - min).abs() < 0.005) return max.toStringAsFixed(2);
    return '${min.toStringAsFixed(2)}–${max.toStringAsFixed(2)}';
  }
}

@immutable
class LhOilReport {
  const LhOilReport({
    this.available = false,
    this.reason = '',
    this.provider = '',
    this.date,
    this.fetchedAt = '',
    this.national = const LhOilProvince(prov: '全国'),
    this.provinces = const [],
    this.history = const {},
    this.historySince,
    this.window = const LhOilWindow(),
    this.forecast,
  });

  factory LhOilReport.fromJson(Map<String, dynamic> raw) {
    final hist = <String, List<LhOilPoint>>{};
    final h = raw['history'];
    if (h is Map) {
      for (final e in h.entries) {
        final list = e.value;
        if (list is List) hist['${e.key}'] = [for (final p in list) LhOilPoint.fromJson(p)];
      }
    }
    final provs = raw['provinces'];
    return LhOilReport(
      available: raw['available'] == true,
      reason: raw['reason']?.toString() ?? '',
      provider: raw['provider']?.toString() ?? '',
      date: _date(raw['date']),
      fetchedAt: raw['fetchedAt']?.toString() ?? '',
      national: raw['national'] is Map ? LhOilProvince.fromJson(raw['national']) : const LhOilProvince(prov: '全国'),
      provinces: provs is List
          ? [for (final p in provs) LhOilProvince.fromJson(p)].where((p) => p.prov.isNotEmpty && !p.prices.isEmpty).toList()
          : const [],
      history: hist,
      historySince: _date(raw['historySince']),
      window: LhOilWindow.fromJson(raw['window']),
      forecast: LhOilForecast.tryParse(raw['forecast']),
    );
  }

  final bool available;

  /// no_provider（没配接口 key）/ no_data（还没拉到）。
  final String reason;
  final String provider;
  final DateTime? date;
  final String fetchedAt;
  final LhOilProvince national;
  final List<LhOilProvince> provinces;

  /// 省名 / 「全国」→ 价格变动点（升序，最后一个 = 现价）。
  final Map<String, List<LhOilPoint>> history;
  final DateTime? historySince;
  final LhOilWindow window;
  final LhOilForecast? forecast;

  bool get hasPrices => available && !national.prices.isEmpty;

  LhOilProvince? province(String prov) {
    for (final p in provinces) {
      if (p.prov == prov) return p;
    }
    return null;
  }

  String get providerLabel => switch (provider) {
        'tianapi' => '天行数据',
        'juhe' => '聚合数据',
        _ => '',
      };
}

/// 「加油类产品今天」一格。
@immutable
class LhOilProduct {
  const LhOilProduct({required this.name, required this.profit, this.badge, this.up});

  /// 接口原名（含口径括号）。
  final String name;

  /// 元。
  final double profit;

  /// 今日异动里的标签（↓ 低 8% / 由盈转亏…），没有就不画。
  final String? badge;
  final bool? up;
}

/// 产品名里带这些字的算加油类。
const kLhOilProductKeywords = ['中石化', '中石油', '加油', '石化', '油卡', '油品'];

bool lhIsOilProduct(String name) => kLhOilProductKeywords.any(name.contains);

// ─────────────────────────────────────────────────────────────────────────────
// 小工具
// ─────────────────────────────────────────────────────────────────────────────

TextStyle _sans(
  BuildContext context,
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = _kInk,
  double? height,
  double? letterSpacing,
}) {
  return LhTypography.sans(
    context: context,
    size: size,
    weight: weight,
    color: DunesColors.resolve(context, color),
    height: height,
    letterSpacing: letterSpacing,
  ).copyWith(fontFeatures: const [ui.FontFeature.tabularFigures()]);
}

TextStyle _num2(BuildContext context, double size, {Color color = _kInkStrong}) =>
    LhTypography.number(context: context, size: size, color: DunesColors.resolve(context, color))
        .copyWith(height: 1, fontFeatures: const [ui.FontFeature.tabularFigures()]);

Color _surface(BuildContext context, Color c) => DunesColors.resolve(context, c, role: DunesColorRole.surface);

Color _border(BuildContext context, Color c) => DunesColors.resolve(context, c, role: DunesColorRole.border);

String _md(DateTime? d) => d == null ? '—' : '${d.month}/${d.day.toString().padLeft(2, '0')}';

String _cnDate(DateTime? d) => d == null ? '—' : '${d.month}月${d.day}日';

String _price(double? v) => v == null ? '—' : v.toStringAsFixed(2);

/// ▼0.51 / ▲0.12 / 持平；没有数返回 null。
String? _deltaText(double? d) {
  if (d == null) return null;
  if (d.abs() < 0.005) return '持平';
  return '${d < 0 ? '↓' : '↑'}${d.abs().toStringAsFixed(2)}';
}

Color _deltaColor(double? d) => d == null || d.abs() < 0.005 ? _kSoftMute : (d < 0 ? _kDown : _kUp);

/// 小三角（朝下 = 降）。
class _Tri extends StatelessWidget {
  const _Tri({required this.color, this.up = false, this.size = 8});
  final Color color;
  final bool up;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: up ? math.pi : 0,
      child: CustomPaint(size: Size.square(size), painter: _TriPainter(DunesColors.resolve(context, color))),
    );
  }
}

class _TriPainter extends CustomPainter {
  _TriPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.5, h * 0.85)
        ..lineTo(w * 0.15, h * 0.3)
        ..lineTo(w * 0.85, h * 0.3)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TriPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// 卡头药丸
// ─────────────────────────────────────────────────────────────────────────────

class LhOilPill extends StatelessWidget {
  const LhOilPill({super.key, required this.report, required this.open, required this.onTap, this.compact = false});

  final LhOilReport report;
  final bool open;
  final VoidCallback onTap;

  /// 窄屏：不写「92#」。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p92 = report.hasPrices ? report.national.prices.p92 : null;
    final d92 = report.national.delta.p92;
    final fg = open ? Colors.white : DunesColors.resolve(context, _kInkStrong);
    final label = p92 == null
        ? '今日油价，下次调价${report.window.relativeLabel} 24 时'
        : '今日油价，92 号全国均价 ${p92.toStringAsFixed(2)} 元每升'
            '${d92 == null ? '' : '，较上次${d92 < 0 ? '下调' : '上调'} ${d92.abs().toStringAsFixed(2)} 元'}';
    return Semantics(
      button: true,
      expanded: open,
      label: '$label；${open ? '点一下收起' : '点开查看'}',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: 28,
            padding: const EdgeInsets.fromLTRB(3, 0, 9, 0),
            decoration: BoxDecoration(
              color: open ? DunesColors.resolve(context, _kPurple) : _surface(context, Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: open ? DunesColors.resolve(context, _kPurple) : _border(context, const Color(0xFFE9E4F5)),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: open ? _kPurple.withValues(alpha: 0.28) : _kInkStrong.withValues(alpha: 0.05),
                  blurRadius: open ? 12 : 2,
                  offset: Offset(0, open ? 4 : 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: open ? Colors.white.withValues(alpha: 0.2) : _surface(context, const Color(0xFFF1ECFD)),
                  ),
                  child: Icon(Icons.water_drop_rounded, size: 12.5, color: open ? Colors.white : DunesColors.resolve(context, _kPurple)),
                ),
                const SizedBox(width: 6),
                if (p92 == null)
                  Text('油价', style: _sans(context, 12, weight: FontWeight.w700, color: open ? Colors.white : _kInkStrong))
                else ...[
                  if (!compact) ...[
                    Text('92#', style: _sans(context, 10.5, weight: FontWeight.w600, color: open ? Colors.white : _kMute).copyWith(color: fg.withValues(alpha: 0.72))),
                    const SizedBox(width: 4),
                  ],
                  Text(p92.toStringAsFixed(2), style: _sans(context, 12.5, weight: FontWeight.w700, letterSpacing: -0.2).copyWith(color: fg)),
                  if (d92 != null && d92.abs() >= 0.005) ...[
                    const SizedBox(width: 4),
                    _Tri(
                      color: open ? (d92 < 0 ? const Color(0xFF9BE3BE) : const Color(0xFFFFB3AE)) : (d92 < 0 ? _kDown : _kUp),
                      up: d92 > 0,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 面板
// ─────────────────────────────────────────────────────────────────────────────

class LhOilPricePanel extends StatefulWidget {
  const LhOilPricePanel({super.key, required this.report, required this.onClose, this.loadProducts});

  final LhOilReport report;
  final VoidCallback onClose;

  /// 加油类产品今天；null 或取回空列表就不画那一节。
  final Future<List<LhOilProduct>> Function()? loadProducts;

  @override
  State<LhOilPricePanel> createState() => _LhOilPricePanelState();
}

class _LhOilPricePanelState extends State<LhOilPricePanel> {
  int _grade = 0;
  String? _prov; // null = 全国均价
  bool _desc = true;
  int? _sel; // 图上选中的点（null = 最后一个）
  bool _all = false;
  Future<List<LhOilProduct>>? _products;

  @override
  void initState() {
    super.initState();
    _products = widget.loadProducts?.call();
  }

  LhOilProvince get _focus => (_prov == null ? null : widget.report.province(_prov!)) ?? widget.report.national;

  List<LhOilPoint> get _history => widget.report.history[_prov ?? '全国'] ?? const [];

  void _pickGrade(int i) {
    if (i == _grade) return;
    HapticFeedback.selectionClick();
    setState(() {
      _grade = i;
      _sel = null;
    });
  }

  void _pickProv(String? prov) {
    HapticFeedback.selectionClick();
    setState(() {
      _prov = prov == _prov ? null : prov;
      _sel = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    return ColoredBox(
      color: _surface(context, Colors.white),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            const SizedBox(height: 10),
            _priceCard(context),
            const SizedBox(height: 12),
            _windowCard(context),
            _windowNote(context),
            if (r.hasPrices) ...[
              const SizedBox(height: 22),
              _historySection(context),
              if (r.provinces.length > 1) ...[
                const SizedBox(height: 22),
                _provinceSection(context),
              ],
            ],
            if (_products != null) _productsSection(context),
            const SizedBox(height: 14),
            _footer(context),
          ],
        ),
      ),
    );
  }

  // ── 头 ──
  Widget _header(BuildContext context) {
    return Row(
      children: [
        Text('今日油价', style: _sans(context, 15, weight: FontWeight.w700, color: _kInkStrong, letterSpacing: -0.1)),
        const Spacer(),
        Semantics(
          button: true,
          label: '收起今日油价',
          excludeSemantics: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onClose();
              },
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _surface(context, const Color(0xFFF4F1FB))),
                  child: Icon(Icons.close_rounded, size: 15, color: DunesColors.resolve(context, _kInk)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 主价 + 油号分段 ──
  Widget _priceCard(BuildContext context) {
    final r = widget.report;
    final focus = _focus;
    final price = focus.prices.grade(_grade);
    final delta = focus.delta.grade(_grade);
    final lastWindow = _lastChangeWindow();
    final sub = [
      if (delta != null) '较上次调价${lastWindow == null ? '' : '（${_md(lastWindow)} 24 时）'}',
      if (r.window.next != null) '下次 ${_md(r.window.next)} 24 时',
    ].join(' · ');
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border(context, _kEdge)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _surface(context, const Color(0xFFF6F2FF)),
            _surface(context, const Color(0xFFFBFAFF)),
            _surface(context, Colors.white),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -22,
            top: -26,
            child: Icon(Icons.water_drop_rounded, size: 120, color: _kPurple.withValues(alpha: 0.07)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${_prov ?? '全国均价'} · ${kLhOilGradeNames[_grade]}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _sans(context, 11.5, color: _kMute),
                      ),
                    ),
                    if (_prov != null) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _pickProv(null),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                          decoration: BoxDecoration(
                            color: _surface(context, Colors.white.withValues(alpha: 0.7)),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: _border(context, const Color(0xFFE4DEF3))),
                          ),
                          child: Text('看全国均价', style: _sans(context, 10, color: _kMute)),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (!r.hasPrices)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      r.reason == 'no_provider' ? '油价数据源还没接入' : '今天的油价还没拉到，稍后再看',
                      style: _sans(context, 14, weight: FontWeight.w600, color: _kInk),
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_price(price), style: _num2(context, 34).copyWith(letterSpacing: -1)),
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 3),
                        child: Text('元/升', style: _sans(context, 12, weight: FontWeight.w600, color: _kMute)),
                      ),
                      const Spacer(),
                      if (delta != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: _deltaCapsule(context, delta),
                        ),
                    ],
                  ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(sub, style: _sans(context, 10.5, color: const Color(0xFF9A94B3))),
                ],
                if (r.hasPrices && r.providerLabel.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text('油价来源：${r.providerLabel}', style: _sans(context, 10, color: _kFaint)),
                ],
                if (r.hasPrices) ...[
                  const SizedBox(height: 14),
                  _gradeSegments(context, focus),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _lastChangeWindow() {
    final h = _history;
    return h.length >= 2 ? h.last.window : null;
  }

  Widget _deltaCapsule(BuildContext context, double d) {
    final flat = d.abs() < 0.005;
    final fg = _deltaColor(d);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _surface(context, flat ? const Color(0xFFF2EFF7) : (d < 0 ? _kDownBg : _kUpBg)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!flat) ...[_Tri(color: fg, up: d > 0), const SizedBox(width: 3)],
          Text(flat ? '持平' : d.abs().toStringAsFixed(2), style: _sans(context, 11, weight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }

  Widget _gradeSegments(BuildContext context, LhOilProvince focus) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _kPurple.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: _grade == i,
                label: '${kLhOilGradeNames[i]} ${_price(focus.prices.grade(i))} 元',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _pickGrade(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.fromLTRB(0, 6, 0, 5),
                    decoration: BoxDecoration(
                      color: _grade == i ? _surface(context, Colors.white) : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: _grade == i
                          ? [
                              BoxShadow(color: _kInkStrong.withValues(alpha: 0.08), blurRadius: 2, offset: const Offset(0, 1)),
                              BoxShadow(color: const Color(0xFF4A3A7A).withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(0, 2)),
                            ]
                          : null,
                    ),
                    child: Column(
                      children: [
                        Text(kLhOilGrades[i], style: _sans(context, 10.5, weight: FontWeight.w700, color: _grade == i ? _kDeep : _kSoftMute)),
                        const SizedBox(height: 1),
                        Text(
                          _price(focus.prices.grade(i)),
                          style: _sans(context, 11.5, weight: _grade == i ? FontWeight.w700 : FontWeight.w500, color: _grade == i ? _kInkStrong : _kSoftMute),
                        ),
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

  // ── 下次调价 ──
  Widget _windowCard(BuildContext context) {
    final w = widget.report.window;
    final f = widget.report.forecast;
    final filled = w.workday.clamp(0, w.workdays);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: _surface(context, Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border(context, _kEdge)),
        boxShadow: [BoxShadow(color: const Color(0xFF4A3A7A).withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('下次调价', style: _sans(context, 11.5, color: _kMute)),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(_cnDate(w.next), style: _num2(context, 20).copyWith(letterSpacing: -0.3)),
                          const SizedBox(width: 5),
                          Text('24 时', style: _sans(context, 12, weight: FontWeight.w600, color: _kInk)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        _OilPulseDot(color: DunesColors.resolve(context, _kPurple)),
                        const SizedBox(width: 6),
                        Text(w.relativeLabel, style: _sans(context, 11, weight: FontWeight.w600, color: _kDeep)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: f != null
                    ? [
                        Text(f.title, style: _sans(context, 11.5, color: _kMute)),
                        const SizedBox(height: 6),
                        Text(
                          f.range,
                          style: _num2(context, 20, color: f.down ? _kDown : (f.up ? _kUp : _kInkStrong)).copyWith(letterSpacing: -0.3),
                        ),
                        const SizedBox(height: 7),
                        Text('元/升 · 机构测算', style: _sans(context, 11, color: _kSoftMute)),
                      ]
                    : [
                        Text('本轮进度', style: _sans(context, 11.5, color: _kMute)),
                        const SizedBox(height: 6),
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: '$filled', style: _num2(context, 20, color: _kDeep)),
                            TextSpan(text: ' / ${w.workdays}', style: _sans(context, 12, weight: FontWeight.w600, color: _kSoftMute)),
                          ]),
                        ),
                        const SizedBox(height: 7),
                        Text('个工作日', style: _sans(context, 11, color: _kSoftMute)),
                      ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < w.workdays; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: i < filled
                          ? Color.lerp(_kLilac, _kPurple, filled <= 1 ? 1 : i / (filled - 1))
                          : _surface(context, const Color(0xFFE9E4F5)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Text('${_md(w.last)} 上次', style: _sans(context, 10.5, color: const Color(0xFF9A94B3))),
              const Spacer(),
              Text(
                f != null ? '第 $filled / ${w.workdays} 个工作日' : '下次 ${_md(w.next)}',
                style: _sans(context, 10.5, color: const Color(0xFF9A94B3)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _windowNote(BuildContext context) {
    final w = widget.report.window;
    final f = widget.report.forecast;
    final effective = w.next?.add(const Duration(days: 1));
    final parts = <String>[
      if (f != null) '预测来源：${f.source.isEmpty ? '机构测算' : f.source}，以发改委公布为准',
      if (f == null && w.calendarStale) '节假日表待更新，以发改委公布为准',
      if (effective != null) '${_md(effective)} 0 点起加油站按新价${f == null ? '（如有调整）' : ''}',
      if (f != null && f.note.isNotEmpty) f.note,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Text(parts.join('；'), style: _sans(context, 10, color: _kFaint, height: 1.4)),
    );
  }

  // ── 近 8 次调价 ──
  Widget _historySection(BuildContext context) {
    final pts = [
      for (final p in _history)
        if (p.prices.grade(_grade) != null) p,
    ];
    final tail = pts.length > 8 ? pts.sublist(pts.length - 8) : pts;
    final since = widget.report.historySince;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('近 8 次调价', style: _sans(context, 13, weight: FontWeight.w700, color: _kInkStrong)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                textAlign: TextAlign.right,
                '${_prov ?? '全国均价'} · ${kLhOilGrades[_grade]}${tail.length >= 2 ? ' · 点圆点看' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sans(context, 11, color: _kSoftMute),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (tail.length < 2)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(color: _surface(context, const Color(0xFFFAF9FD)), borderRadius: BorderRadius.circular(12)),
            child: Text(
              '调价记录从 ${_cnDate(since)} 开始积累，${_cnDate(widget.report.window.next)}调价后就能看到走势。',
              style: _sans(context, 11.5, color: _kMute, height: 1.45),
            ),
          )
        else
          _OilStepChart(
            points: tail,
            grade: _grade,
            selected: (_sel ?? tail.length - 1).clamp(0, tail.length - 1),
            onSelect: (i) {
              HapticFeedback.selectionClick();
              setState(() => _sel = i);
            },
          ),
      ],
    );
  }

  // ── 各省 ──
  Widget _provinceSection(BuildContext context) {
    final r = widget.report;
    final g = _grade;
    final list = [
      for (final p in r.provinces)
        if (p.prices.grade(g) != null) p,
    ]..sort((a, b) => _desc ? b.prices.grade(g)!.compareTo(a.prices.grade(g)!) : a.prices.grade(g)!.compareTo(b.prices.grade(g)!));
    if (list.isEmpty) return const SizedBox.shrink();
    final lo = list.map((p) => p.prices.grade(g)!).reduce(math.min);
    final hi = list.map((p) => p.prices.grade(g)!).reduce(math.max);
    final avg = r.national.prices.grade(g);
    double pos(double v) => hi - lo < 0.001 ? 0.5 : (0.04 + (v - lo) / (hi - lo) * 0.92);
    final shown = _all ? list : list.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('各省 ${kLhOilGrades[g]}', style: _sans(context, 13, weight: FontWeight.w700, color: _kInkStrong)),
            const Spacer(),
            _sortToggle(context),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              const SizedBox(width: 14 + 10 + 40 + 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final w = box.maxWidth;
                    return SizedBox(
                      height: 13,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(left: 0, child: Text(lo.toStringAsFixed(2), style: _sans(context, 9.5, color: _kFaint))),
                          if (avg != null)
                            Positioned(
                              left: (w * pos(avg) - 12).clamp(30.0, math.max(30.0, w - 54)),
                              child: Text('均价', style: _sans(context, 9.5, color: _kSoftMute)),
                            ),
                          Positioned(right: 0, child: Text(hi.toStringAsFixed(2), style: _sans(context, 9.5, color: _kFaint))),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10 + 42 + 10 + 40),
            ],
          ),
        ),
        const SizedBox(height: 2),
        for (var i = 0; i < shown.length; i++) _provinceRow(context, i + 1, shown[i], pos, avg == null ? null : pos(avg)),
        if (list.length > 8)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _all = !_all);
              },
              child: Container(
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _surface(context, const Color(0xFFF8F6FD)), borderRadius: BorderRadius.circular(10)),
                child: Text(
                  _all ? '收起' : '展开全部 ${list.length} 个省区',
                  style: _sans(context, 11.5, weight: FontWeight.w600, color: _kDeep),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sortToggle(BuildContext context) {
    Widget seg(String label, bool on, VoidCallback tap) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: on ? _surface(context, Colors.white) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              boxShadow: on ? [BoxShadow(color: _kInkStrong.withValues(alpha: 0.10), blurRadius: 3, offset: const Offset(0, 1))] : null,
            ),
            child: Text(label, style: _sans(context, 10.5, weight: FontWeight.w600, color: on ? _kDeep : _kSoftMute)),
          ),
        );
    void set(bool desc) {
      if (_desc == desc) return;
      HapticFeedback.selectionClick();
      setState(() => _desc = desc);
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: _surface(context, const Color(0xFFF2EFF7)), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg('最贵', _desc, () => set(true)), seg('最便宜', !_desc, () => set(false))],
      ),
    );
  }

  Widget _provinceRow(BuildContext context, int rank, LhOilProvince p, double Function(double) pos, double? avgPos) {
    final on = _prov == p.prov;
    final v = p.prices.grade(_grade)!;
    final d = p.delta.grade(_grade);
    final dt = _deltaText(d);
    return Semantics(
      button: true,
      selected: on,
      label: '第 $rank 名 ${p.prov} ${v.toStringAsFixed(2)} 元${dt == null ? '' : '，较上次 $dt'}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pickProv(p.prov),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            color: on ? _surface(context, const Color(0xFFF5F1FE)) : Colors.transparent,
            borderRadius: on ? BorderRadius.circular(10) : null,
            border: on ? null : Border(bottom: BorderSide(color: _border(context, const Color(0xFFF5F3FA)))),
          ),
          child: Row(
            children: [
              SizedBox(width: 14, child: Text('$rank', style: _sans(context, 10, weight: FontWeight.w600, color: const Color(0xFFB4AFC8)))),
              const SizedBox(width: 10),
              SizedBox(
                width: 40,
                child: Text(
                  p.prov,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: _sans(context, 12.5, weight: on ? FontWeight.w700 : FontWeight.w500, color: on ? _kDeep : _kInk),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final w = box.maxWidth;
                    final size = on ? 10.0 : 7.0;
                    return SizedBox(
                      height: 12,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 5,
                            child: Container(height: 2, decoration: BoxDecoration(color: _surface(context, const Color(0xFFEFECF6)), borderRadius: BorderRadius.circular(1))),
                          ),
                          if (avgPos != null)
                            Positioned(left: w * avgPos, top: 1, child: Container(width: 1, height: 10, color: _border(context, const Color(0xFFD6CEEE)))),
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOutCubic,
                            left: w * pos(v) - size / 2,
                            top: 6 - size / 2,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: DunesColors.resolve(context, on ? _kPurple : _kLilac),
                                boxShadow: on ? [BoxShadow(color: _kPurple.withValues(alpha: 0.18), spreadRadius: 3)] : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 42,
                child: Text(v.toStringAsFixed(2), textAlign: TextAlign.right, style: _sans(context, 13, weight: FontWeight.w700, color: on ? _kDeep : _kInkStrong)),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 40,
                child: Text(dt ?? '', textAlign: TextAlign.right, style: _sans(context, 10.5, weight: FontWeight.w600, color: _deltaColor(d))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 加油类产品 ──
  Widget _productsSection(BuildContext context) {
    return FutureBuilder<List<LhOilProduct>>(
      future: _products,
      builder: (context, snap) {
        final list = snap.data ?? const <LhOilProduct>[];
        if (list.isEmpty) return const SizedBox.shrink();
        final shown = list.take(4).toList();
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('加油类产品今天', style: _sans(context, 13, weight: FontWeight.w700, color: _kInkStrong)),
                  const Spacer(),
                  Text('和油价一起看', style: _sans(context, 11, color: _kSoftMute)),
                ],
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, box) {
                  final w = (box.maxWidth - 8) / 2;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final p in shown) SizedBox(width: w, child: _productCell(context, p))],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _productCell(BuildContext context, LhOilProduct p) {
    final (name, _) = lhProfitSplitNameTag(p.name);
    final wan = p.profit / 10000;
    final badgeColor = p.up == null ? _kSoftMute : (p.up! ? _kUp : _kDown);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _surface(context, const Color(0xFFFBFAFE)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border(context, _kRule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, 11, color: _kMute)),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${wan < 0 ? '−' : ''}${wan.abs().toStringAsFixed(2)}', style: _sans(context, 15, weight: FontWeight.w700, color: _kInkStrong)),
              Text('万', style: _sans(context, 11, weight: FontWeight.w600, color: _kInkStrong)),
              if (p.badge != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(p.badge!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, 10.5, weight: FontWeight.w700, color: badgeColor)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final r = widget.report;
    final parts = <String>[
      if (r.fetchedAt.isNotEmpty) '${r.fetchedAt.length >= 16 ? r.fetchedAt.substring(5, 16) : r.fetchedAt} 更新',
      if (r.providerLabel.isNotEmpty) '来源 ${r.providerLabel}',
      '调价日按发改委 10 个工作日规则推算',
    ];
    return Text(parts.join(' · '), textAlign: TextAlign.center, style: _sans(context, 10, color: const Color(0xFFB4AFC8)));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 阶梯图
// ─────────────────────────────────────────────────────────────────────────────

class _OilStepChart extends StatelessWidget {
  const _OilStepChart({required this.points, required this.grade, required this.selected, required this.onSelect});

  final List<LhOilPoint> points;
  final int grade;
  final int selected;
  final ValueChanged<int> onSelect;

  static const double _h = 132;
  static const double _plotRight = 36; // 右边留给价格刻度
  static const double _top = 26; // 顶上给气泡
  static const double _base = 104; // 横轴

  @override
  Widget build(BuildContext context) {
    final vals = [for (final p in points) p.prices.grade(grade)!];
    final lo = vals.reduce(math.min) - 0.05;
    final hi = vals.reduce(math.max) + 0.05;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final plotW = w - _plotRight;
        double x(int i) => points.length == 1 ? plotW / 2 : 14 + i * (plotW - 28) / (points.length - 1);
        double y(double v) => _base - 8 - (v - lo) / (hi - lo) * (_base - 8 - _top);
        final sv = vals[selected];
        final prev = selected > 0 ? vals[selected - 1] : null;
        final d = prev == null ? null : sv - prev;
        final tipX = x(selected).clamp(36.0, math.max(36.0, plotW - 30));
        return SizedBox(
          height: _h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _OilStepPainter(
                    xs: [for (var i = 0; i < vals.length; i++) x(i)],
                    ys: [for (final v in vals) y(v)],
                    plotW: plotW,
                    base: _base,
                    selected: selected,
                    grid: [for (final f in [0.85, 0.45, 0.1]) (y(lo + (hi - lo) * f), (lo + (hi - lo) * f).toStringAsFixed(2))],
                    dates: [for (final p in points) _md(p.window ?? p.effective)],
                    line: DunesColors.resolve(context, _kPurple),
                    guide: DunesColors.resolve(context, _kLilac),
                    rule: _border(context, _kRule),
                    axis: _border(context, const Color(0xFFE8E3F3)),
                    label: DunesColors.resolve(context, _kFaint),
                    labelOn: DunesColors.resolve(context, _kDeep),
                    dot: _surface(context, Colors.white),
                    textStyle: _sans(context, 9),
                  ),
                ),
              ),
              // 读数气泡
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: tipX - 44,
                top: y(sv) - 34,
                width: 88,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF231D38),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [BoxShadow(color: _kInkStrong.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 4))],
                      ),
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: sv.toStringAsFixed(2), style: _sans(context, 11.5, weight: FontWeight.w700).copyWith(color: Colors.white)),
                          if (d != null)
                            TextSpan(
                              text: ' ${_deltaText(d)}',
                              style: _sans(context, 10.5, weight: FontWeight.w700).copyWith(
                                color: d.abs() < 0.005 ? Colors.white70 : (d < 0 ? const Color(0xFF9BE3BE) : const Color(0xFFFFB3AE)),
                              ),
                            ),
                        ]),
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              ),
              // 点击热区
              for (var i = 0; i < points.length; i++)
                Positioned(
                  left: x(i) - 20,
                  top: 0,
                  width: 40,
                  height: _h,
                  child: Semantics(
                    button: true,
                    label: '${_md(points[i].window ?? points[i].effective)} 调价后 ${vals[i].toStringAsFixed(2)} 元每升',
                    excludeSemantics: true,
                    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => onSelect(i)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _OilStepPainter extends CustomPainter {
  _OilStepPainter({
    required this.xs,
    required this.ys,
    required this.plotW,
    required this.base,
    required this.selected,
    required this.grid,
    required this.dates,
    required this.line,
    required this.guide,
    required this.rule,
    required this.axis,
    required this.label,
    required this.labelOn,
    required this.dot,
    required this.textStyle,
  });

  final List<double> xs;
  final List<double> ys;
  final double plotW;
  final double base;
  final int selected;
  final List<(double, String)> grid;
  final List<String> dates;
  final Color line;
  final Color guide;
  final Color rule;
  final Color axis;
  final Color label;
  final Color labelOn;
  final Color dot;
  final TextStyle textStyle;

  void _text(Canvas canvas, String s, Offset at, TextStyle style, {TextAlign align = TextAlign.center}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - tp.width,
      TextAlign.left => at.dx,
      _ => at.dx - tp.width / 2,
    };
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 网格 + 刻度
    final dash = Paint()
      ..color = rule
      ..strokeWidth = 1;
    for (final (gy, v) in grid.take(2)) {
      for (var x = 0.0; x < plotW; x += 5) {
        canvas.drawLine(Offset(x, gy), Offset(math.min(x + 2, plotW), gy), dash);
      }
      _text(canvas, v, Offset(size.width, gy), textStyle.copyWith(color: label), align: TextAlign.right);
    }
    canvas.drawLine(Offset(0, base), Offset(plotW, base), Paint()..color = axis);
    _text(canvas, grid.last.$2, Offset(size.width, base), textStyle.copyWith(color: label), align: TextAlign.right);

    // 阶梯 + 面积
    final step = Path()..moveTo(0, ys.first);
    for (var i = 0; i < xs.length; i++) {
      step
        ..lineTo(xs[i], i == 0 ? ys.first : ys[i - 1])
        ..lineTo(xs[i], ys[i]);
    }
    step.lineTo(plotW, ys.last);
    final area = Path.from(step)
      ..lineTo(plotW, base)
      ..lineTo(0, base)
      ..close();
    final top = ys.reduce(math.min);
    canvas.drawPath(
      area,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, base), [line.withValues(alpha: 0.16), line.withValues(alpha: 0)]),
    );
    canvas.drawPath(
      step,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // 选中点的引线
    final sx = xs[selected];
    for (var yy = ys[selected]; yy < base; yy += 5) {
      canvas.drawLine(Offset(sx, yy), Offset(sx, math.min(yy + 2, base)), Paint()..color = guide);
    }

    // 圆点 + 日期
    for (var i = 0; i < xs.length; i++) {
      final on = i == selected;
      final c = Offset(xs[i], ys[i]);
      canvas.drawCircle(c, on ? 4.5 : 2.8, Paint()..color = on ? line : dot);
      canvas.drawCircle(
        c,
        on ? 4.5 : 2.8,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
      if (on || i.isOdd || xs.length <= 4) {
        _text(
          canvas,
          dates[i],
          Offset(xs[i], base + 14),
          textStyle.copyWith(color: on ? labelOn : label, fontWeight: on ? FontWeight.w700 : FontWeight.w400),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_OilStepPainter old) =>
      old.selected != selected || old.xs != xs || old.ys != ys || old.line != line || old.plotW != plotW;
}

class _OilPulseDot extends StatefulWidget {
  const _OilPulseDot({required this.color});
  final Color color;

  @override
  State<_OilPulseDot> createState() => _OilPulseDotState();
}

class _OilPulseDotState extends State<_OilPulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

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
      width: 6,
      height: 6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_c.value);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + 1.4 * t,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.45 * (1 - t)), shape: BoxShape.circle),
                ),
              ),
              Container(width: 6, height: 6, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
            ],
          );
        },
      ),
    );
  }
}
