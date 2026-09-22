// ═════════════════════════════════════════════════════════════════════════════
// 月末预测 · 量化报告（底部弹层）
//
//   入口：主 Hero 预测条右侧「报告 ›」，或在图上连点两下月末预测点。
//   读法自上而下：结论 → 累计走势（本月 vs 典型节奏 vs 上月）→ 三种方法对比
//   → 月里越晚越准 → 回测明细 → 模型学到的参数 → 口径说明。
//   只用竖向图形（柱 / 线），不用横向进度条。
// ═════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'lighthouse_forecast_model.dart';
import 'lighthouse_product_ordinal.dart';
import 'lighthouse_product_ordinal_view.dart';
import 'lighthouse_theme.dart';

String _money(double v) {
  final a = v.abs();
  final sign = v < 0 ? '−' : '';
  if (a >= 1e8) return '$sign${(a / 1e8).toStringAsFixed(2)}亿';
  final w = a / 1e4;
  return '$sign${w >= 100 ? w.toStringAsFixed(1) : w.toStringAsFixed(2)}万';
}

String _pct(double? v, {int digits = 1}) =>
    v == null || !v.isFinite ? '—' : '${(v * 100).toStringAsFixed(digits)}%';

String _signedPct(double? v) {
  if (v == null || !v.isFinite) return '—';
  return '${v >= 0 ? '偏高' : '偏低'} ${(v.abs() * 100).toStringAsFixed(1)}%';
}

class LighthouseForecastReportSheet extends StatelessWidget {
  const LighthouseForecastReportSheet({
    super.key,
    required this.report,
    required this.metricLabel,
    this.profit = false,
    this.accent = const Color(0xFF7565C7),
    this.ordinalLoader,
    this.productMetric = 'verify',
  });

  /// 月末结构预测：按维度（product / supply / channel）异步拉数并打分。
  final Future<LighthouseOrdinalBundle?> Function(String dim)? ordinalLoader;

  /// 分产品一节默认显示的指标：verify / sales / revenue / profit。
  final String productMetric;

  final LighthouseForecastReport report;
  final String metricLabel;
  final bool profit;
  final Color accent;

  Color get _ink {
    if (!profit) return accent;
    return report.summary.forecast >= 0 ? LhColors.neg : LhColors.pos;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 1,
      minChildSize: 0.55,
      maxChildSize: 1,
      expand: true,
      builder: (ctx, scroll) {
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: LhColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _header(),
            const SizedBox(height: 14),
            _conclusion(),
            if (ordinalLoader != null)
              _section(
                '月末结构预测 · 产品 / 供给 / 渠道',
                '每个实体本月全月比上月全月：下降超 5% / ±5% 内 / 增长超 5% 的概率（贝叶斯多层有序 logit）',
                LighthouseProductOrdinalSection(
                  loader: ordinalLoader!,
                  initialMetric: productMetric,
                  accent: accent,
                ),
              ),
            _section('累计走势', '本月已发生 · 模型预测 · 80% 区间 · 上月同期', _cumChart()),
            _section('三种方法对比', '回测误差越小越好，组合权重按误差倒数分配', _methodTable()),
            if (report.checkpoints.isNotEmpty)
              _section('月里越晚越准', '第 N 天预测时，过去几个月的平均误差', _checkpointChart()),
            if (report.rows.isNotEmpty)
              _section(
                '回测明细',
                '把过去每个整月退回到同一天，只用当时能看到的数据预测',
                _backtestTable(),
              ),
            _section('模型学到的规律', '来自近 56 天日数据与前 6 个整月', _params()),
            const SizedBox(height: 14),
            _footnote(),
          ],
        );
      },
    );
  }

  // ── 头部：大数 + 区间 + 概率 ─────────────────────────────────────────
  Widget _header() {
    final s = report.summary;
    final prev = s.prevMonthTotal;
    final vs = prev == null || prev.abs() < 1e-9
        ? null
        : (s.forecast - prev) / prev.abs();
    final pm = DateTime(DateTime.now().year, DateTime.now().month - 1, 1);
    final prevName = '${pm.month}月';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withAlpha(22),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '量化报告',
                style: LhTypography.mono(
                  size: 9,
                  color: accent,
                  weight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$metricLabel · 月末预测',
                style: LhTypography.sans(size: 14, weight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '截至 ${s.cutoffDay} 日（T+1）· 当月 ${s.totalDays} 天 · '
          '回测 ${s.backtestMonths} 个月',
          style: LhTypography.mono(size: 9, color: LhColors.mute2),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_money(s.forecast), style: LhTypography.number(size: 30, color: _ink)),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                '80% 区间  ${_money(s.lo)} – ${_money(s.hi)}',
                style: LhTypography.mono(
                  size: 10,
                  color: LhColors.ink2,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (s.beatPrevProb != null)
              _chip(
                '超$prevName概率 ${(s.beatPrevProb! * 100).round()}%',
                s.beatPrevProb! >= 0.5 ? LhColors.neg : LhColors.pos,
              ),
            if (vs != null)
              _chip(
                '较$prevName ${vs >= 0 ? '↑' : '↓'}${(vs.abs() * 100).toStringAsFixed(1)}%',
                vs >= 0 ? LhColors.neg : LhColors.pos,
              ),
            _chip(
              s.usedModel ? '采用：组合模型' : '采用：原算法（模型未跑赢）',
              s.usedModel ? accent : LhColors.mute2,
            ),
          ],
        ),
      ],
    );
  }

  Widget _chip(String text, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: c.withAlpha(18),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: c.withAlpha(50), width: 0.6),
    ),
    child: Text(
      text,
      style: LhTypography.mono(size: 9, color: c, weight: FontWeight.w700),
    ),
  );

  // ── 结论：三句人话，全部由数字推出 ─────────────────────────────────────
  Widget _conclusion() {
    final s = report.summary;
    final left = s.totalDays - s.cutoffDay;
    final need = s.forecast - s.actual;
    final needDaily = left <= 0 ? 0.0 : need / left;
    final lines = <String>[
      '照现在的节奏，月末约 ${_money(s.forecast)}'
          '${s.beatPrevProb != null ? '，有 ${(s.beatPrevProb! * 100).round()}% 的把握超过上月（${_money(s.prevMonthTotal ?? 0)}）' : ''}。',
      if (left > 0)
        '还剩 $left 天，要再做 ${_money(need)}，折合日均 ${_money(needDaily)}；'
            '近期去掉星期效应后的日均是 ${_money(report.dailyLevel)}。',
      s.usedModel
          ? '过去 ${s.backtestMonths} 个月回测：模型平均误差 ${_pct(s.modelMape)}，'
                '原算法 ${_pct(s.linearMape)}。'
          : '过去 ${s.backtestMonths} 个月回测里模型没跑赢原算法（${_pct(report.mapeEnsemble)} vs ${_pct(s.linearMape)}），本月沿用原算法。',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: accent.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(34), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    '${i + 1}',
                    style: LhTypography.mono(
                      size: 9,
                      color: accent,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lines[i],
                    style: LhTypography.sans(
                      size: 12,
                      color: LhColors.ink,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(String title, String sub, Widget child) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(title, style: LhTypography.sans(size: 13, weight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 9),
          child: Text(sub, style: LhTypography.mono(size: 8.5, color: LhColors.mute2)),
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );

  // ── 累计走势图 ─────────────────────────────────────────────────────────
  Widget _cumChart() {
    Widget key(Widget mark, String t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 4),
        Text(t, style: LhTypography.mono(size: 8.5, color: LhColors.ink2)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 190,
          width: double.infinity,
          child: CustomPaint(
            size: Size.infinite,
            painter: _CumPainter(report: report, color: _ink),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            key(Container(width: 12, height: 2, color: _ink), '本月已发生'),
            key(
              SizedBox(
                width: 12,
                height: 2,
                child: Row(
                  children: [
                    Container(width: 4, height: 1.6, color: _ink),
                    const SizedBox(width: 2),
                    Container(width: 4, height: 1.6, color: _ink),
                  ],
                ),
              ),
              '模型预测',
            ),
            key(
              Container(width: 10, height: 10, color: _ink.withAlpha(30)),
              '80% 区间',
            ),
            key(
              Container(width: 12, height: 1.2, color: LhColors.mute2),
              '上月同期',
            ),
          ],
        ),
      ],
    );
  }

  // ── 方法对比表 ─────────────────────────────────────────────────────────
  Widget _methodTable() {
    final s = report.summary;
    final rows = <({String name, String sub, double? v, double? mape, String w, bool used})>[
      (
        name: '原算法',
        sub: '已发生 ÷ 天数 × 当月天数',
        v: s.linear,
        mape: report.mapeLinear,
        w: '—',
        used: !s.usedModel,
      ),
      (
        name: '月内节奏曲线',
        sub: '已发生 ÷ 第 d 天典型完成比例',
        v: report.pace,
        mape: report.mapePace,
        w: _pct(report.weightPace, digits: 0),
        used: false,
      ),
      (
        name: '剩余天数逐日加总',
        sub: '日均 × 星期系数 × 月末系数',
        v: report.daily,
        mape: report.mapeDaily,
        w: _pct(report.weightDaily, digits: 0),
        used: false,
      ),
      (
        name: '组合模型',
        sub: '两个模型按误差加权',
        v: s.usedModel ? s.forecast : null,
        mape: report.mapeEnsemble,
        w: '100%',
        used: s.usedModel,
      ),
    ];
    final best = rows
        .map((r) => r.mape)
        .whereType<double>()
        .fold<double?>(null, (a, b) => a == null || b < a ? b : a);
    final head = LhTypography.mono(size: 8.5, color: LhColors.mute2, weight: FontWeight.w700);
    return Column(
      children: [
        Row(
          children: [
            Expanded(flex: 5, child: Text('方法', style: head)),
            Expanded(flex: 3, child: Text('本月预测', style: head, textAlign: TextAlign.right)),
            Expanded(flex: 3, child: Text('回测误差', style: head, textAlign: TextAlign.right)),
            Expanded(flex: 2, child: Text('权重', style: head, textAlign: TextAlign.right)),
          ],
        ),
        const SizedBox(height: 6),
        for (final r in rows)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: r.used ? accent.withAlpha(14) : LhColors.mist,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: r.used ? accent.withAlpha(90) : LhColors.line2,
                width: r.used ? 0.9 : 0.5,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              r.name,
                              overflow: TextOverflow.ellipsis,
                              style: LhTypography.sans(size: 11.5, weight: FontWeight.w700),
                            ),
                          ),
                          if (r.used) ...[
                            const SizedBox(width: 4),
                            Text(
                              '采用',
                              style: LhTypography.mono(size: 8, color: accent, weight: FontWeight.w800),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        r.sub,
                        overflow: TextOverflow.ellipsis,
                        style: LhTypography.mono(size: 8, color: LhColors.mute2),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    r.v == null ? '—' : _money(r.v!),
                    textAlign: TextAlign.right,
                    style: LhTypography.mono(size: 10.5, color: LhColors.ink, weight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    _pct(r.mape),
                    textAlign: TextAlign.right,
                    style: LhTypography.mono(
                      size: 10.5,
                      color: r.mape != null && r.mape == best ? LhColors.neg : LhColors.ink2,
                      weight: r.mape != null && r.mape == best ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    r.w,
                    textAlign: TextAlign.right,
                    style: LhTypography.mono(size: 10, color: LhColors.ink2),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── 月里越晚越准：误差随天数的两条线 ───────────────────────────────────
  Widget _checkpointChart() {
    return SizedBox(
      height: 150,
      width: double.infinity,
      child: CustomPaint(
        size: Size.infinite,
        painter: _CheckpointPainter(
          rows: report.checkpoints,
          color: accent,
          nowDay: report.summary.cutoffDay,
        ),
      ),
    );
  }

  // ── 回测明细 ───────────────────────────────────────────────────────────
  Widget _backtestTable() {
    final head = LhTypography.mono(size: 8.5, color: LhColors.mute2, weight: FontWeight.w700);
    Widget errCell(double? f, double truth, bool better) {
      final e = LighthouseBacktestRow.err(f, truth);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            f == null ? '—' : _money(f),
            style: LhTypography.mono(size: 10, color: LhColors.ink, weight: FontWeight.w600),
          ),
          Text(
            _signedPct(e),
            style: LhTypography.mono(
              size: 8.5,
              color: better ? LhColors.neg : LhColors.mute2,
              weight: better ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(flex: 3, child: Text('月份', style: head)),
            Expanded(flex: 3, child: Text('实际全月', style: head, textAlign: TextAlign.right)),
            Expanded(flex: 3, child: Text('原算法', style: head, textAlign: TextAlign.right)),
            Expanded(flex: 3, child: Text('组合模型', style: head, textAlign: TextAlign.right)),
          ],
        ),
        const SizedBox(height: 4),
        for (final r in report.rows)
          () {
            final eLin = LighthouseBacktestRow.err(r.linear, r.truth)?.abs();
            final eEns = LighthouseBacktestRow.err(r.ensemble, r.truth)?.abs();
            final ensBetter = eEns != null && (eLin == null || eEns < eLin);
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: LhColors.line2, width: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${r.month.year % 100}年${r.month.month}月',
                          style: LhTypography.sans(size: 11.5, weight: FontWeight.w600),
                        ),
                        Text(
                          '退回第 ${r.asOfDay} 天',
                          style: LhTypography.mono(size: 8, color: LhColors.mute2),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      _money(r.truth),
                      textAlign: TextAlign.right,
                      style: LhTypography.mono(size: 10, color: LhColors.ink, weight: FontWeight.w700),
                    ),
                  ),
                  Expanded(flex: 3, child: errCell(r.linear, r.truth, !ensBetter && eLin != null)),
                  Expanded(flex: 3, child: errCell(r.ensemble, r.truth, ensBetter)),
                ],
              ),
            );
          }(),
      ],
    );
  }

  // ── 参数：星期系数（竖柱）+ 三个关键数 ─────────────────────────────────
  Widget _params() {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    final wf = report.weekdayFactors;
    final maxF = wf.fold<double>(1.2, (a, b) => math.max(a, b));
    Widget stat(String k, String v, String note) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
        decoration: BoxDecoration(
          color: LhColors.mist,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: LhColors.line2, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: LhTypography.mono(size: 8, color: LhColors.mute2, weight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(v, style: LhTypography.sans(size: 13, weight: FontWeight.w800)),
            Text(note, maxLines: 2, style: LhTypography.mono(size: 7.5, color: LhColors.mute2)),
          ],
        ),
      ),
    );
    final share = report.paceShare;
    final s = report.summary;
    final linShare = s.cutoffDay / s.totalDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('星期系数（1.00 = 平均一天）', style: LhTypography.mono(size: 8.5, color: LhColors.ink2, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        SizedBox(
          height: 78,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 7 && i < wf.length; i++)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        wf[i].toStringAsFixed(2),
                        style: LhTypography.mono(
                          size: 8,
                          color: wf[i] >= 1.1
                              ? LhColors.neg
                              : (wf[i] <= 0.9 ? LhColors.pos : LhColors.ink2),
                          weight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 14,
                        height: (wf[i] / maxF * 44).clamp(2.0, 44.0).toDouble(),
                        decoration: BoxDecoration(
                          color: accent.withAlpha(i >= 5 ? 90 : 170),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text('周${names[i]}', style: LhTypography.mono(size: 8, color: LhColors.mute2)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            stat(
              '月末三天',
              '×${report.monthEndFactor.toStringAsFixed(2)}',
              '末三天日均是全月日均的倍数',
            ),
            const SizedBox(width: 6),
            stat('近期日均', _money(report.dailyLevel), '近 28 天去星期效应'),
            const SizedBox(width: 6),
            stat(
              '第 ${s.cutoffDay} 天完成',
              share == null ? '—' : _pct(share, digits: 0),
              '原算法假设 ${_pct(linShare, digits: 0)}',
            ),
          ],
        ),
      ],
    );
  }

  Widget _footnote() => Text(
    '口径说明\n'
    '· 数据按 T+1 只用到昨天；今天的部分数据不参与建模。\n'
    '· 80% 区间 = 回测中「实际 ÷ 预测」的 10% 与 90% 分位 × 本月预测。\n'
    '· 超上月概率 = 回测误差分布下本月超过上月全月的比例。\n'
    '· 组合模型回测不如原算法时自动沿用原算法。本模型为试行，'
    '正式口径仍为运营会确定的线性日均外推。',
    style: LhTypography.mono(size: 8.5, color: LhColors.mute2, height: 1.6),
  );
}

// ── 画布：累计走势 ──────────────────────────────────────────────────────────
class _CumPainter extends CustomPainter {
  _CumPainter({required this.report, required this.color});
  final LighthouseForecastReport report;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = report.summary;
    final total = s.totalDays;
    final c = s.cutoffDay;
    final cum = report.cumActual;
    if (cum.isEmpty || total < 2) return;
    const padL = 4.0;
    const padR = 58.0;
    const padT = 10.0;
    const padB = 18.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    final typ = report.typicalShare;
    final actual = cum.last;
    // 预测延长线：沿典型节奏从「已发生」走到「预测」。
    double projAt(int j, double target) {
      if (j <= c) return cum[j - 1];
      final t = typ;
      if (t != null && t.length >= total) {
        final a = t[c - 1];
        final span = 1 - a;
        if (span.abs() > 1e-6) {
          final r = ((t[j - 1] - a) / span).clamp(0.0, 1.0).toDouble();
          return actual + (target - actual) * r;
        }
      }
      return actual + (target - actual) * (j - c) / (total - c);
    }

    final prev = report.prevCum;
    var lo = math.min(0.0, math.min(s.lo, cum.reduce(math.min)));
    var hi = math.max(s.hi, cum.reduce(math.max));
    if (prev != null && prev.isNotEmpty) {
      lo = math.min(lo, prev.reduce(math.min));
      hi = math.max(hi, prev.reduce(math.max));
    }
    if ((hi - lo).abs() < 1e-9) hi = lo + 1;
    double x(int j) => padL + (j - 1) / (total - 1) * w;
    double y(double v) => padT + (hi - v) / (hi - lo) * h;

    final grid = Paint()
      ..color = LhColors.line2
      ..strokeWidth = 0.6;
    for (var k = 0; k <= 3; k++) {
      final gy = padT + h * k / 3;
      canvas.drawLine(Offset(padL, gy), Offset(padL + w, gy), grid);
    }

    // 上月同期
    if (prev != null && prev.length >= total) {
      final p = Path()..moveTo(x(1), y(prev[0]));
      for (var j = 2; j <= total; j++) {
        p.lineTo(x(j), y(prev[j - 1]));
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = LhColors.mute2.withAlpha(170)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke,
      );
    }

    // 80% 扇形区间
    final fan = Path()..moveTo(x(c), y(actual));
    for (var j = c + 1; j <= total; j++) {
      fan.lineTo(x(j), y(projAt(j, s.hi)));
    }
    for (var j = total; j >= c; j--) {
      fan.lineTo(x(j), y(projAt(j, s.lo)));
    }
    fan.close();
    canvas.drawPath(fan, Paint()..color = color.withAlpha(28));

    // 本月已发生：实线 + 淡面
    final solid = Path()..moveTo(x(1), y(cum[0]));
    for (var j = 2; j <= c; j++) {
      solid.lineTo(x(j), y(cum[j - 1]));
    }
    final area = Path.from(solid)
      ..lineTo(x(c), y(lo))
      ..lineTo(x(1), y(lo))
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withAlpha(40), color.withAlpha(0)],
        ).createShader(Rect.fromLTWH(0, padT, size.width, h)),
    );
    canvas.drawPath(
      solid,
      Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // 模型预测：虚线
    final dash = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var j = c; j < total; j++) {
      final a = Offset(x(j), y(projAt(j, s.forecast)));
      final b = Offset(x(j + 1), y(projAt(j + 1, s.forecast)));
      final len = (b - a).distance;
      if (len < 0.5) continue;
      final u = (b - a) / len;
      var t = 0.0;
      while (t < len) {
        final e = math.min(t + 4, len);
        canvas.drawLine(a + u * t, a + u * e, dash);
        t += 7;
      }
    }

    // 今天分界 + 端点
    _dashedV(canvas, x(c), padT, padT + h);
    canvas.drawCircle(Offset(x(c), y(actual)), 3.2, Paint()..color = color);
    final end = Offset(x(total), y(s.forecast));
    canvas.drawCircle(end, 3.4, Paint()..color = Colors.white);
    canvas.drawCircle(
      end,
      3.4,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // 右侧读数
    void label(String text, double yy, Color col, {bool bold = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: LhTypography.mono(
            size: 8.5,
            color: col,
            weight: bold ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: padR - 4);
      tp.paint(
        canvas,
        Offset(padL + w + 5, (yy - tp.height / 2).clamp(0.0, size.height - tp.height).toDouble()),
      );
    }

    label(_money(s.forecast), y(s.forecast), color, bold: true);
    if ((y(s.hi) - y(s.forecast)).abs() > 11) {
      label(_money(s.hi), y(s.hi), LhColors.mute2);
    }
    if ((y(s.lo) - y(s.forecast)).abs() > 11) {
      label(_money(s.lo), y(s.lo), LhColors.mute2);
    }
    if (prev != null && prev.length >= total) {
      final py = y(prev[total - 1]);
      if ((py - y(s.forecast)).abs() > 11) {
        label('上月 ${_money(prev[total - 1])}', py, LhColors.mute2);
      }
    }

    // 横轴
    void xl(int j, String t, {Color col = LhColors.mute2}) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: LhTypography.mono(size: 8, color: col)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (x(j) - tp.width / 2).clamp(0.0, size.width - tp.width).toDouble(),
          size.height - tp.height,
        ),
      );
    }

    xl(1, '1日');
    if (c > 4 && c < total - 4) xl(c, '截至$c日', col: color);
    xl(total, '$total日');
  }

  void _dashedV(Canvas canvas, double x, double top, double bottom) {
    final p = Paint()
      ..color = LhColors.mute2.withAlpha(140)
      ..strokeWidth = 0.7;
    var y = top;
    while (y < bottom) {
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 2, bottom)), p);
      y += 4;
    }
  }

  @override
  bool shouldRepaint(_CumPainter old) =>
      !identical(old.report, report) || old.color != color;
}

// ── 画布：月里越晚越准 ──────────────────────────────────────────────────────
class _CheckpointPainter extends CustomPainter {
  _CheckpointPainter({
    required this.rows,
    required this.color,
    required this.nowDay,
  });
  final List<LighthouseCheckpointRow> rows;
  final Color color;
  final int nowDay;

  @override
  void paint(Canvas canvas, Size size) {
    if (rows.isEmpty) return;
    const padL = 8.0;
    const padR = 8.0;
    const padT = 18.0;
    const padB = 30.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    var hi = 0.0;
    for (final r in rows) {
      for (final v in [r.linear, r.ensemble]) {
        if (v != null && v.isFinite) hi = math.max(hi, v);
      }
    }
    if (hi <= 0) hi = 0.1;
    hi *= 1.15;
    final n = rows.length;
    double x(int i) => n <= 1 ? padL + w / 2 : padL + i / (n - 1) * w;
    double y(double v) => padT + (hi - v) / hi * h;

    canvas.drawLine(
      Offset(padL, padT + h),
      Offset(padL + w, padT + h),
      Paint()
        ..color = LhColors.line
        ..strokeWidth = 0.7,
    );

    // 当前所处的检查点
    var nearest = 0;
    for (var i = 1; i < n; i++) {
      if ((rows[i].day - nowDay).abs() < (rows[nearest].day - nowDay).abs()) {
        nearest = i;
      }
    }
    canvas.drawRRect(
      RRect.fromLTRBR(
        x(nearest) - 16,
        padT - 14,
        x(nearest) + 16,
        padT + h + 26,
        const Radius.circular(6),
      ),
      Paint()..color = color.withAlpha(14),
    );

    void series(double? Function(LighthouseCheckpointRow) pick, Color col, double width, bool labelAbove) {
      Offset? last;
      for (var i = 0; i < n; i++) {
        final v = pick(rows[i]);
        if (v == null || !v.isFinite) {
          last = null;
          continue;
        }
        final o = Offset(x(i), y(v));
        if (last != null) {
          canvas.drawLine(
            last,
            o,
            Paint()
              ..color = col
              ..strokeWidth = width
              ..strokeCap = StrokeCap.round,
          );
        }
        canvas.drawCircle(o, 2.6, Paint()..color = Colors.white);
        canvas.drawCircle(
          o,
          2.6,
          Paint()
            ..color = col
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3,
        );
        final tp = TextPainter(
          text: TextSpan(
            text: '${(v * 100).toStringAsFixed(1)}%',
            style: LhTypography.mono(size: 7.5, color: col, weight: FontWeight.w700),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            (o.dx - tp.width / 2).clamp(0.0, size.width - tp.width).toDouble(),
            labelAbove ? o.dy - tp.height - 3 : o.dy + 4,
          ),
        );
        last = o;
      }
    }

    series((r) => r.linear, LhColors.mute2, 1.2, false);
    series((r) => r.ensemble, color, 2.0, true);

    for (var i = 0; i < n; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: '第${rows[i].day}天',
          style: LhTypography.mono(
            size: 8,
            color: i == nearest ? color : LhColors.mute2,
            weight: i == nearest ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (x(i) - tp.width / 2).clamp(0.0, size.width - tp.width).toDouble(),
          padT + h + 6,
        ),
      );
    }
    // 图例
    final lg = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '— 组合模型  ',
            style: LhTypography.mono(size: 8, color: color, weight: FontWeight.w700),
          ),
          TextSpan(
            text: '— 原算法',
            style: LhTypography.mono(size: 8, color: LhColors.mute2),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    lg.paint(canvas, Offset(size.width - lg.width, 0));
  }

  @override
  bool shouldRepaint(_CheckpointPainter old) =>
      !identical(old.rows, rows) || old.color != color || old.nowDay != nowDay;
}
