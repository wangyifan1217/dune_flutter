// ═════════════════════════════════════════════════════════════════════════════
// 灯塔 · 人效账本
//
//   刻意不新造版式：一条行仍是「冻结首列 + 指标网格」，收起态 2 列 × 3 行圆角格、
//   展开态 3 列裸格、环比固定 36pt 走中国金融色（涨红跌绿）、结果区淡蓝底加
//   2pt 竖轨 —— 常量全部来自 lighthouse_hero_metric.dart，和产品/供给/渠道/净TA
//   同一批。人效唯一新增的是冻结列里占了「对账状态」那一槽的绩效等级，
//   和占了「毛利率」那一槽的得分。
//
//   两处人效独有：
//     · 口径开关。模板 A 满分 115、模板 B 满分 120，却共用 95/85/70 分档，
//       不切标准百分制就没法把能源和通信放进同一个排序。
//     · dataFlags。任何来源不明的分数必须挂标记，宁可难看也不许安静上屏。
// ═════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'lighthouse_hero_metric.dart';
import 'lighthouse_people.dart';
import 'lighthouse_theme.dart';

// ── 与账本共用的排版常量 ─────────────────────────────────────────────────────
const double _kGridCellHBase = 43; // 收起态格高（_ledgerSummaryCellH）
const double _kGridPlainCellH = 18; // 展开态格高（_kLedgerGridCellHBase）
const double _kGridRowGap = 3;
const double _kGridPadV = 8;
const double _kDeltaW = 36;
const double _kPinnedMinH = 104;
const int _kPlainCols = 3;

double _scaleOf(double w) => (w / 390).clamp(0.94, 1.08).toDouble();

/// 收起态两列：左＝规模，右＝结果（走淡蓝竖轨那一块）。
const List<List<String>> _kSummaryRows = <List<String>>[
  <String>['revenue', 'profit'],
  <String>['realUsers', 'marginPct'],
  <String>['newUsers', 'bonusScore'],
];

/// 展开态全量列序 —— 固定，缺值画「—」，不因板块抖动（同 _kUnifiedLedgerMetrics）。
const List<String> _kAllMetrics = <String>[
  'revenue',
  'profit',
  'realUsers',
  'marginPct',
  'newUsers',
  'bonusScore',
  'revScore',
  'profitScore',
  'realScore',
  'newScore',
  'marginScore',
];

const Map<String, String> _kMetricLabel = <String, String>{
  'revenue': '收入',
  'profit': '利润',
  'realUsers': '真实用户',
  'newUsers': '新增用户',
  'marginPct': '利润率',
  'bonusScore': '回款折扣',
  'revScore': '营收得分',
  'profitScore': '利润得分',
  'realScore': '用户得分',
  'newScore': '新增得分',
  'marginScore': '利润率得分',
};

/// 结果类指标 —— 右列，共用一层淡蓝底 + 竖轨（lighthouseLedgerIsResultMetric 同义）。
bool _isResult(String key) =>
    key == 'profit' || key == 'marginPct' || key == 'bonusScore';

enum _Kind { money, user, rate, score }

_Kind _kindOf(String key) {
  if (key == 'revenue' || key == 'profit') return _Kind.money;
  if (key == 'realUsers' || key == 'newUsers') return _Kind.user;
  if (key == 'marginPct') return _Kind.rate;
  return _Kind.score;
}

// ── 数字格式：与 native_lighthouse_page 的 _fmtMoney / _unit 同口径 ──────────
({String number, String unit}) _fmtCell(String key, double? v) {
  if (v == null || v.isNaN || !v.isFinite) return (number: '—', unit: '');
  switch (_kindOf(key)) {
    case _Kind.money:
      final a = v.abs();
      if (a >= 10000) return (number: (v / 10000).toStringAsFixed(2), unit: '亿');
      if (a >= 100) return (number: v.toStringAsFixed(1), unit: '万');
      return (number: v.toStringAsFixed(2), unit: '万');
    case _Kind.user:
      return (number: v.toStringAsFixed(2), unit: '万');
    case _Kind.rate:
      return (number: v.toStringAsFixed(1), unit: '%');
    case _Kind.score:
      return (number: v.toStringAsFixed(1), unit: '');
  }
}

/// 与 _ledgerFmtDelta 同款：`↑12.3%` / `↓5.1%` / `↑3.2pp`，|Δ| < 0.05 视同无变化。
String? _fmtDelta(double? pct, {required bool isRate}) {
  if (pct == null || pct.isNaN || !pct.isFinite) return null;
  if (pct.abs() < 0.05) return null;
  final a = pct.abs();
  return '${pct >= 0 ? '↑' : '↓'}'
      '${a.toStringAsFixed(a >= 10 ? 0 : 1)}'
      '${isRate ? 'pp' : '%'}';
}

double? _metricValue(LhPeopleRow r, String key) {
  final c = r.components;
  switch (key) {
    case 'revenue':
      return r.revenue;
    case 'profit':
      return r.profit;
    case 'realUsers':
      return r.realUsers;
    case 'newUsers':
      return r.newUsers;
    case 'marginPct':
      return r.marginPct;
    case 'bonusScore':
      return r.isMember ? c['receivable'] : c['discount'];
    case 'revScore':
      return c['rev'];
    case 'profitScore':
      return c['profit'];
    case 'realScore':
      return r.isMember ? c['real'] : null;
    case 'newScore':
      return r.isMember ? c['new'] : null;
    case 'marginScore':
      return c['margin'];
  }
  return null;
}

/// 环比（百分点）。得分类没有同期基数，返回 null → 画「·」。
double? _metricDelta(LhPeopleRow r, String key) {
  double? pct(double? g) => g == null
      ? null
      : (g >= kLhZeroBaseGrowth ? null : g * 100);
  switch (key) {
    case 'revenue':
      return pct(r.revGrowth);
    case 'profit':
      return pct(r.profitGrowth);
    case 'realUsers':
      return pct(r.realGrowth);
    case 'newUsers':
      return pct(r.newGrowth);
    case 'marginPct':
      return r.marginDeltaPp;
  }
  return null;
}

double? _taskValue(LhPeopleTask t, String key) {
  final c = t.components;
  switch (key) {
    case 'revenue':
      return t.revenue;
    case 'profit':
      return t.profit;
    case 'realUsers':
      return t.realUsers;
    case 'newUsers':
      return t.newUsers;
    case 'marginPct':
      return t.marginPct;
    case 'bonusScore':
      return t.isMember ? c['receivable'] : c['discount'];
  }
  return null;
}

double? _taskDelta(LhPeopleTask t, String key) {
  double? pct(double? g) => g == null
      ? null
      : (g >= kLhZeroBaseGrowth ? null : g * 100);
  switch (key) {
    case 'revenue':
      return pct(t.revGrowth);
    case 'profit':
      return pct(t.profitGrowth);
    case 'realUsers':
      return pct(t.realGrowth);
    case 'newUsers':
      return pct(t.newGrowth);
    case 'marginPct':
      return t.marginDeltaPp;
  }
  return null;
}

Color _gradeColor(LhPeopleGrade g) {
  if (g.label == '优') return LhColors.pos;
  if (g.label == '良') return LhColors.accent;
  if (g.label == '汰') return LhColors.neg;
  return LhColors.copper;
}

TextStyle _tabularOf(TextStyle s) =>
    s.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

// ═════════════════════════════════════════════════════════════════════════════
// 账本本体
// ═════════════════════════════════════════════════════════════════════════════
class LhPeopleLedger extends StatefulWidget {
  const LhPeopleLedger({
    super.key,
    required this.rows,
    required this.standardCaliber,
    this.isFallback = false,
  });

  final List<LhPeopleRow> rows;
  final bool standardCaliber;
  final bool isFallback;

  @override
  State<LhPeopleLedger> createState() => _LhPeopleLedgerState();
}

class _LhPeopleLedgerState extends State<LhPeopleLedger> {
  String? _expanded;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final scale = _scaleOf(w);
    final pinnedW = lighthouseLedgerPinnedWidthFor(w, tab: 'people');
    final sorted = [...widget.rows]..sort((a, b) {
      final sa = widget.standardCaliber ? a.standardScore : a.score;
      final sb = widget.standardCaliber ? b.standardScore : b.score;
      return sb.compareTo(sa);
    });
    final flagged = sorted.where((r) => r.flags.isNotEmpty).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (flagged > 0 || widget.isFallback)
          _notice(flagged, sorted.length, scale),
        _header(pinnedW, scale),
        for (var i = 0; i < sorted.length; i++)
          _row(sorted[i], i, pinnedW, scale),
        if (sorted.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                '当前分类下没有人',
                style: LhTypography.sans(size: 12, color: LhColors.mute),
              ),
            ),
          ),
      ],
    );
  }

  Widget _notice(int flagged, int total, double scale) {
    final text = widget.isFallback
        ? '接口未接通，当前用 M4 考评表本地数据渲染；$flagged / $total 人底表有问题。'
        : '$flagged / $total 人底表数据有问题，展开对应行看具体标记。';
    return Container(
      margin: EdgeInsets.fromLTRB(12, 10 * scale, 12, 2 * scale),
      padding: EdgeInsets.symmetric(
        horizontal: 11 * scale,
        vertical: 9 * scale,
      ),
      decoration: BoxDecoration(
        color: LhColors.copperSoft,
        border: Border.all(color: LhColors.copper.withAlpha(70), width: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '!',
            style: LhTypography.mono(
              size: 11,
              color: LhColors.copper,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: LhTypography.sans(
                size: 11,
                color: LhColors.ink2,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(double pinnedW, double scale) {
    TextStyle kicker() => LhTypography.mono(
      size: 9,
      color: LhColors.mute2,
      weight: FontWeight.w500,
      letterSpacing: 0.6,
      height: 1.3,
    );
    return Container(
      color: LhColors.mist,
      padding: EdgeInsets.fromLTRB(0, 7 * scale, 0, 6 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: pinnedW,
            child: Padding(
              padding: const EdgeInsets.only(left: 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('人员', style: kicker()),
                  Text('得分 / 等级', style: kicker()),
                ],
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 11),
                    child: Text(
                      '规模',
                      textAlign: TextAlign.right,
                      style: kicker(),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 11),
                    child: Text(
                      '结果',
                      textAlign: TextAlign.right,
                      style: kicker(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(LhPeopleRow r, int index, double pinnedW, double scale) {
    final open = _expanded == r.id;
    final cellH = (_kGridCellHBase * scale).roundToDouble();
    final gridH =
        _kSummaryRows.length * cellH + (_kGridPadV * scale).roundToDouble() * 2;
    final rowH = gridH > (_kPinnedMinH * scale) ? gridH : _kPinnedMinH * scale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: rowH + 1,
          decoration: BoxDecoration(
            color: open ? LhColors.purple.withAlpha(10) : null,
            border: const Border(
              bottom: BorderSide(color: LhColors.line2, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: pinnedW,
                child: _pinned(r, index, scale, open),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: _kGridPadV * scale),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final pair in _kSummaryRows)
                        SizedBox(
                          height: cellH,
                          child: Row(
                            children: [
                              for (final key in pair)
                                Expanded(
                                  child: _tile(
                                    label: _kMetricLabel[key] ?? key,
                                    value: _metricValue(r, key),
                                    delta: _metricDelta(r, key),
                                    metricKey: key,
                                    scale: scale,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (open) _drawer(r, pinnedW, scale),
      ],
    );
  }

  // ── 冻结首列：序号 · 姓名 · 等级（占对账槽）· 得分（占毛利率槽）· 展开钮 ──
  Widget _pinned(LhPeopleRow r, int index, double scale, bool open) {
    final isTop3 = index < 3;
    final grade = r.grade(standard: widget.standardCaliber);
    final gColor = _gradeColor(grade);
    final score = widget.standardCaliber ? r.standardScore : r.score;

    return Padding(
      padding: const EdgeInsets.only(left: 11, right: 6),
      child: Row(
        children: [
          Container(
            width: 28 * scale,
            height: 28 * scale,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isTop3
                  ? LhColors.purple.withAlpha(18)
                  : const Color(0xFFF5F3F8),
              shape: BoxShape.circle,
              border: Border.all(
                color: isTop3
                    ? LhColors.purple.withAlpha(42)
                    : LhColors.line2,
                width: 0.7,
              ),
            ),
            child: Text(
              (index + 1).toString().padLeft(2, '0'),
              style: _tabularOf(
                LhTypography.mono(
                  size: 11.5 * scale,
                  color: isTop3
                      ? LhColors.purple
                      : LhColors.mute2.withAlpha(170),
                  weight: isTop3 ? FontWeight.w700 : FontWeight.w500,
                  height: 1.0,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LhScrollText(
                  r.name,
                  maxLines: 2,
                  style: LhTypography.sans(
                    size: 12.5 * scale,
                    weight: FontWeight.w600,
                    color: LhColors.ink,
                    height: 1.15,
                    letterSpacing: -0.1,
                  ),
                ),
                SizedBox(height: 5 * scale),
                // 绩效等级占的是供给/渠道「对账状态」那一槽：4.5pt 圆点 + 9pt 文字
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 4.5 * scale,
                      height: 4.5 * scale,
                      decoration: BoxDecoration(
                        color: gColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 4 * scale),
                    Flexible(
                      child: LhScrollText(
                        '${grade.label} ×${grade.coefficient}',
                        style: _tabularOf(
                          LhTypography.sans(
                            size: 9 * scale,
                            color: grade.isAlert ? gColor : LhColors.mute,
                            weight: grade.isAlert
                                ? FontWeight.w700
                                : FontWeight.w500,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 5 * scale),
                Row(
                  children: [
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '得分 ',
                              style: LhTypography.mono(
                                size: 9.5 * scale,
                                color: LhColors.mute,
                                weight: FontWeight.w500,
                                height: 1.0,
                              ),
                            ),
                            TextSpan(
                              text: score.toStringAsFixed(1),
                              style: _tabularOf(
                                LhTypography.mono(
                                  size: 10 * scale,
                                  color: LhColors.ink,
                                  weight: FontWeight.w700,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                      ),
                    ),
                    SizedBox(width: 4 * scale),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          setState(() => _expanded = open ? null : r.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 27 * scale,
                        height: 27 * scale,
                        decoration: BoxDecoration(
                          color: open
                              ? LhColors.purple.withAlpha(24)
                              : const Color(0xFFF4F1FA),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          open
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18 * scale,
                          color: LhColors.purple.withAlpha(open ? 255 : 185),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 指标格 ─────────────────────────────────────────────────────────────
  Widget _tile({
    required String label,
    required double? value,
    required double? delta,
    required String metricKey,
    required double scale,
    bool plain = false,
  }) {
    final parts = _fmtCell(metricKey, value);
    final missing = parts.number == '—';
    final isRate = _kindOf(metricKey) == _Kind.rate;
    final deltaText = missing ? null : _fmtDelta(delta, isRate: isRate);
    final up = delta == null || delta.abs() < 0.05 ? null : delta > 0;
    final negative = !missing && (value ?? 0) < 0;

    final valueRow = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: LhScrollRichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: parts.number,
                  style: _tabularOf(
                    LhTypography.mono(
                      size: lighthouseLedgerValueFontSize * scale,
                      // 负数染绿：中国金融色，和账本一致
                      color: missing
                          ? LhColors.mute2
                          : (negative ? LhColors.pos : LhColors.ink2),
                      weight: missing ? FontWeight.w500 : FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ),
                if (parts.unit.isNotEmpty)
                  TextSpan(
                    text: parts.unit,
                    style: LhTypography.mono(
                      size: lighthouseLedgerUnitFontSize * scale,
                      color: LhColors.mute,
                      weight: FontWeight.w500,
                      letterSpacing: 0.2,
                      height: 1.0,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            textAlign: TextAlign.right,
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: 2 * scale),
          child: SizedBox(
            width: _kDeltaW * scale,
            child: Text(
              deltaText ?? '·',
              maxLines: 1,
              textAlign: TextAlign.right,
              style: _tabularOf(
                LhTypography.mono(
                  size: lighthouseLedgerDeltaFontSize * scale,
                  color: up == null
                      ? LhColors.mute2.withAlpha(110)
                      : (up ? LhColors.neg : LhColors.pos),
                  weight: FontWeight.w600,
                  letterSpacing: -0.2,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (plain) {
      return Padding(
        padding: const EdgeInsets.only(left: 2, right: 4),
        child: Align(alignment: Alignment.centerRight, child: valueRow),
      );
    }

    final result = _isResult(metricKey);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 3 * scale, vertical: 2.5 * scale),
      decoration: BoxDecoration(
        color: result
            ? const Color(
                lighthouseLedgerResultBlockAccentValue,
              ).withAlpha(lighthouseLedgerResultBlockTintAlpha)
            : const Color(0xFFF9F8FC),
        borderRadius: BorderRadius.circular(10),
        border: result
            ? const Border(
                left: BorderSide(
                  color: Color(lighthouseLedgerResultBlockAccentValue),
                  width: lighthouseLedgerResultBlockRailWidth,
                ),
              )
            : null,
      ),
      padding: EdgeInsets.fromLTRB(8 * scale, 5 * scale, 7 * scale, 4 * scale),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LhScrollText(
            label,
            style: LhTypography.sans(
              size: lighthouseLedgerMetricLabelFontSize * scale,
              color: LhColors.mute,
              weight: FontWeight.w500,
              letterSpacing: 0.2,
              height: 1.0,
            ),
          ),
          SizedBox(height: 4 * scale),
          Expanded(child: Align(alignment: Alignment.centerRight, child: valueRow)),
        ],
      ),
    );
  }

  // ── 展开区：权重占比 · 全量指标 · 任务子行 · 对照人事表 ─────────────────
  Widget _drawer(LhPeopleRow r, double pinnedW, double scale) {
    const palette = <Color>[
      LhColors.purple,
      LhColors.accent,
      LhColors.copper,
      LhColors.pos,
      LhColors.mute2,
    ];
    return Container(
      padding: EdgeInsets.only(top: 11 * scale, bottom: 13 * scale),
      decoration: const BoxDecoration(
        color: LhColors.mist,
        border: Border(
          bottom: BorderSide(color: LhColors.line2, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _drawerLabel('任务权重占比'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Row(
                  children: [
                    for (var i = 0; i < r.tasks.length; i++)
                      Expanded(
                        flex: (r.tasks[i].weight * 1000).round().clamp(1, 1000),
                        child: Container(color: palette[i % palette.length]),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 6 * scale, 12, 0),
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                for (var i = 0; i < r.tasks.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: palette[i % palette.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${r.tasks[i].name} '
                        '${(r.tasks[i].weight * 100).toStringAsFixed(0)}%',
                        style: LhTypography.mono(
                          size: 9,
                          color: LhColors.mute,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          SizedBox(height: 14 * scale),
          _drawerLabel('全量指标'),
          for (var i = 0; i < _kAllMetrics.length; i += _kPlainCols)
            _plainGrid(
              _kAllMetrics.skip(i).take(_kPlainCols).toList(growable: false),
              (key) => _metricValue(r, key),
              (key) => _metricDelta(r, key),
              scale,
            ),
          SizedBox(height: 14 * scale),
          _drawerLabel('任务明细'),
          for (final t in r.tasks) _childRow(t, pinnedW, scale),
          if (r.sheetScore != null) ...[
            SizedBox(height: 14 * scale),
            _drawerLabel('对照人事表 · 整月口径'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '表内 ${r.sheetScore!.toStringAsFixed(2)}'
                '${r.sheetGrade.isEmpty ? '' : '（${r.sheetGrade}）'}'
                '　灯塔同期对齐 ${r.score.toStringAsFixed(2)}'
                '　模板 ${r.template.code} · 满分 ${r.fullMark.toStringAsFixed(0)}',
                style: _tabularOf(
                  LhTypography.mono(size: 10, color: LhColors.ink2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _drawerLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 7),
    child: Text(
      text,
      style: LhTypography.mono(
        size: 9,
        color: LhColors.mute2,
        letterSpacing: 0.6,
      ),
    ),
  );

  Widget _plainGrid(
    List<String> keys,
    double? Function(String) value,
    double? Function(String) delta,
    double scale,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < _kPlainCols; i++)
                Expanded(
                  child: i < keys.length
                      ? Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: LhScrollText(
                            _kMetricLabel[keys[i]] ?? keys[i],
                            textAlign: TextAlign.right,
                            style: LhTypography.mono(
                              size: 9,
                              color: LhColors.mute2,
                              weight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
          SizedBox(height: 2 * scale),
          SizedBox(
            height: _kGridPlainCellH * scale,
            child: Row(
              children: [
                for (var i = 0; i < _kPlainCols; i++)
                  Expanded(
                    // 末行不足一整行留白，不做跨列拉伸 —— 拉宽会把右对齐的
                    // 数字推离上一行的数字列。
                    child: i < keys.length
                        ? _tile(
                            label: '',
                            value: value(keys[i]),
                            delta: delta(keys[i]),
                            metricKey: keys[i],
                            scale: scale,
                            plain: true,
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
          SizedBox(height: _kGridRowGap * scale),
        ],
      ),
    );
  }

  Widget _childRow(LhPeopleTask t, double pinnedW, double scale) {
    return Container(
      constraints: BoxConstraints(minHeight: 44 * scale),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: LhColors.line2, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: pinnedW,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(25, 6, 6, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (t.flags.isNotEmpty) ...[
                        Container(
                          width: 4.5,
                          height: 4.5,
                          decoration: const BoxDecoration(
                            color: LhColors.copper,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: LhScrollText(
                          t.name,
                          style: LhTypography.sans(
                            size: 11.5 * scale,
                            weight: FontWeight.w500,
                            color: LhColors.ink2,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4 * scale),
                  LhScrollText(
                    '${(t.weight * 100).toStringAsFixed(0)}% · '
                    '${t.weightedScore.toStringAsFixed(1)}分',
                    style: _tabularOf(
                      LhTypography.mono(size: 9.5, color: LhColors.mute),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6 * scale),
              child: SizedBox(
                height: _kGridPlainCellH * scale,
                child: Row(
                  children: [
                    for (final key in const ['revenue', 'profit', 'marginPct'])
                      Expanded(
                        child: _tile(
                          label: '',
                          value: _taskValue(t, key),
                          delta: _taskDelta(t, key),
                          metricKey: key,
                          scale: scale,
                          plain: true,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
