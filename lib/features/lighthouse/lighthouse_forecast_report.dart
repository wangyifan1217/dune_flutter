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
import 'lighthouse_forecast.dart';
import 'lighthouse_product_ordinal.dart';
import 'lighthouse_product_ordinal_view.dart';
import 'lighthouse_theme.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

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
  final LighthouseForecastReport report;
  final String metricLabel;
  final bool profit;
  final Color accent;
  final Future<LighthouseOrdinalBundle?> Function(String dim)? ordinalLoader;
  final String productMetric;

  static const _muted = Color(0xFF647083);
  static const _line = Color(0xFFE7EBF1);
  static const _wash = Color(0xFFF5F7FB);
  Color get _ink => profit
      ? (report.summary.forecast >= 0 ? LhColors.neg : LhColors.pos)
      : const Color(0xFF51418E);

  TextStyle _text([
    double size = 12,
    Color color = LhColors.ink,
    FontWeight weight = FontWeight.w500,
  ]) =>
      LhTypography.sans(size: size, color: color, weight: weight, height: 1.5);

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: 1,
    minChildSize: 0.55,
    maxChildSize: 1,
    expand: true,
    builder: (ctx, scroll) => ColoredBox(
      color: DunesColors.resolve(
        ctx,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
        children: [
          Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: DunesColors.resolveNullable(
                  ctx,
                  _line,
                  role: DunesColorRole.surface,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _header(),
          _section('本月判断', '预测是估计，不是承诺，也不改动已发生金额。', _conclusion()),
          _section('累计走势', '实线为已发生；虚线与浅色区间来自逐日模拟。', _cumChart()),
          _section('预测原理', '已发生固定，只对剩余日期建模。', _principles()),
          _section('模型对照', '动态日模型与原算法在相同历史月份比较 WAPE。', _methodTable()),
          _section('月内各时点回测', '每个时点重新拟合；不预设越晚一定越准。', _checkpointChart()),
          if (report.rows.isNotEmpty)
            _section('逐月回测', '退回同一月内进度，仅用截止日及以前的数据。', _backtestTable()),
          _section('学到的日节奏', '星期与月底效应联合估计，避免重复放大。', _params()),
          if (ordinalLoader != null)
            _section(
              '结构预测 · 产品 / 供给 / 渠道',
              '判断各实体比上月的涨跌概率；不是主金额预测的替代。',
              LighthouseProductOrdinalSection(
                loader: ordinalLoader!,
                initialMetric: productMetric,
                accent: accent,
              ),
            ),
          const SizedBox(height: 24),
          _footnote(),
        ],
      ),
    ),
  );

  Widget _header() {
    final s = report.summary;
    final prev = s.prevMonthTotal;
    final vs = prev == null || prev.abs() < 1e-9
        ? null
        : (s.forecast - prev) / prev.abs();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$metricLabel · 月末预测',
                style: _text(17, LhColors.ink, FontWeight.w700),
              ),
            ),
            _tag('预测', accent),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          '${s.month.year}年${s.month.month}月 · 截至${s.cutoffDay}日 · T+1',
          style: _text(11, _muted),
        ),
        const SizedBox(height: 16),
        Text(
          _money(s.forecast),
          style: LhTypography.number(size: 34, color: _ink),
        ),
        const SizedBox(height: 4),
        Text(
          '80% 近似预测区间  ${_money(s.lo)} — ${_money(s.hi)}',
          style: _text(12, _muted),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: _line),
              bottom: BorderSide(color: _line),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _stat(
                  '超上月概率',
                  lighthouseForecastProbabilityLabel(s.beatPrevProb),
                  '同一分布的模拟占比',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _stat(
                  '较上月预计',
                  vs == null ? '—' : '${vs >= 0 ? '+' : '−'}${_pct(vs.abs())}',
                  prev == null ? '上月数据不完整' : '上月全月 ${_money(prev)}',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _tag('采用：${s.modelLabel}', accent),
            _tag('${s.backtestMonths} 个有效回测月', _muted),
          ],
        ),
      ],
    );
  }

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withAlpha(15),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(label, style: _text(10, color, FontWeight.w600)),
  );

  Widget _stat(String label, String value, String note) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: _text(11, _muted)),
      const SizedBox(height: 3),
      Text(value, style: _text(18, LhColors.ink, FontWeight.w700)),
      Text(note, style: _text(10, _muted)),
    ],
  );

  Widget _section(String title, String note, Widget child) => Padding(
    padding: const EdgeInsets.only(top: 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: _text(14, LhColors.ink, FontWeight.w700)),
        const SizedBox(height: 3),
        Text(note, style: _text(11, _muted)),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  Widget _conclusion() {
    final s = report.summary;
    final days = s.totalDays - s.cutoffDay;
    final remaining = s.forecast - s.actual;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '已发生 ${_money(s.actual)}；剩余 $days 天预计净贡献 ${_money(remaining)}。',
          style: _text(),
        ),
        const SizedBox(height: 8),
        Text(
          s.usedModel
              ? '动态日模型回测 WAPE ${_pct(s.dynamicMape)}，低于或等于原算法 ${_pct(s.linearMape)}，本月采用动态日模型。'
              : s.dynamicMape == null
              ? '有效回测不足，主金额暂用原算法，动态模型区间仅作参考。'
              : '动态日模型回测 WAPE ${_pct(s.dynamicMape)}，高于原算法 ${_pct(s.linearMape)}，主金额暂用原算法。',
          style: _text(12, _muted),
        ),
        if (s.trial) ...[
          const SizedBox(height: 8),
          Text('独立月份较少：概率与区间是模型估计，不代表经过验证的覆盖率。', style: _text(11, _muted)),
        ],
      ],
    );
  }

  Widget _principles() {
    final s = report.summary;
    final rows = <(String, String)>[
      ('月末总额 = 已发生 + 剩余每日金额之和', '本月已发生不重新预测；把每个未来日期的金额加总。'),
      (
        s.signed
            ? '每日金额 = 动态水平 + 星期效应 + 月底效应'
            : 'log(日均金额) = 动态水平 + 星期效应 + 月底效应',
        s.signed
            ? '利润或存在负值的金额用 Gaussian 分布，允许未来亏损。'
            : '正金额用 Gamma 分布；真实零值单独估计发生概率，不把缺失当零。',
      ),
      (
        '水平逐日变化，日历效应分别学习',
        '把月初前三天的集中结算与星期、月末三天、最后一天分开估计，避免月初脉冲压低月底预测；当前未单独学习节假日。',
      ),
      (
        '${s.paths.length} 条未来路径 → 均值 / 区间 / 概率',
        '动态模型点预测为分布均值；10%/90% 分位给区间，超过上月全月的占比给概率。'
            '原算法保底时对剩余路径同口径校准，三项一起更新。',
      ),
      ('按时间前推回测，绝不读被预测月份的未来', 'WAPE = 总绝对误差 ÷ 实际金额绝对值之和。组合对照的权重仅由更早的回测月份决定。'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: _wash,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : const Border(
                        bottom: BorderSide(color: _line, width: 0.7),
                      ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    rows[i].$1,
                    style: _text(12, LhColors.ink, FontWeight.w600),
                  ),
                  const SizedBox(height: 5),
                  Text(rows[i].$2, style: _text(11, _muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cumChart() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: 200,
        child: CustomPaint(
          size: Size.infinite,
          painter: _CumPainter(report: report, color: _ink),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 14,
        runSpacing: 5,
        children: [
          _tag('— 已发生', _ink),
          _tag('··· 预测', _ink),
          _tag('80% 近似区间', accent),
          _tag('— 上月同期', _muted),
        ],
      ),
    ],
  );

  Widget _methodTable() {
    final s = report.summary;
    final common = report.rows
        .where((r) => r.pace != null && r.daily != null)
        .length;
    final ensMonths = report.rows.where((r) => r.ensemble != null).length;
    final methods =
        <
          ({
            String name,
            String sub,
            double? value,
            double? error,
            int months,
            bool used,
          })
        >[
          (
            name: '动态日模型',
            sub: '动态水平 + 星期 + 月底',
            value: s.dynamic.forecast,
            error: s.dynamicMape,
            months: s.backtestMonths,
            used: s.usedModel,
          ),
          (
            name: '原算法',
            sub: '已发生 ÷ 截止天数 × 月天数',
            value: s.linear,
            error: report.mapeLinear,
            months: s.backtestMonths,
            used: !s.usedModel,
          ),
          (
            name: 'M1 节奏曲线',
            sub: '历史累计完成比例',
            value: report.pace,
            error: report.mapePace,
            months: common,
            used: false,
          ),
          (
            name: 'M2 剩余逐日',
            sub: '近期日均 × 星期 × 月末',
            value: report.daily,
            error: report.mapeDaily,
            months: common,
            used: false,
          ),
          (
            name: 'M1 + M2 组合',
            sub: '更早回测误差倒数加权',
            value: report.ensemble,
            error: report.mapeEnsemble,
            months: ensMonths,
            used: false,
          ),
        ];
    return Column(
      children: [
        Row(
          children: [
            Expanded(flex: 5, child: Text('方法', style: _text(11, _muted))),
            Expanded(
              flex: 3,
              child: Text(
                '月末金额',
                textAlign: TextAlign.right,
                style: _text(11, _muted),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                'WAPE',
                textAlign: TextAlign.right,
                style: _text(11, _muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        for (final r in methods)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line, width: 0.7)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r.name}${r.used ? ' · 采用' : ''}',
                        style: _text(
                          12,
                          r.used ? accent : LhColors.ink,
                          FontWeight.w600,
                        ),
                      ),
                      Text(r.sub, style: _text(10, _muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  flex: 3,
                  child: Text(
                    r.value == null ? '—' : _money(r.value!),
                    textAlign: TextAlign.right,
                    style: _text(12, LhColors.ink, FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _pct(r.error),
                        style: _text(12, LhColors.ink, FontWeight.w600),
                      ),
                      Text('${r.months} 月', style: _text(10, _muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'M1、M2、组合仅作对照；回测折数不同，不能直接跨行排名。'
          '组合当前权重 M1 ${_pct(report.weightPace, digits: 0)} / M2 ${_pct(report.weightDaily, digits: 0)}。',
          style: _text(10, _muted),
        ),
      ],
    );
  }

  Widget _checkpointChart() => SizedBox(
    height: 160,
    child: CustomPaint(
      size: Size.infinite,
      painter: _CheckpointPainter(
        rows: report.checkpoints,
        color: accent,
        nowDay: report.summary.cutoffDay,
      ),
    ),
  );

  Widget _backtestTable() {
    Widget cell(double? value, double truth) => Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value == null ? '—' : _money(value),
          style: _text(11, LhColors.ink, FontWeight.w600),
        ),
        Text(
          _signedPct(LighthouseBacktestRow.err(value, truth)),
          style: _text(10, _muted),
        ),
      ],
    );
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text('月份 / 截止', style: _text(10, _muted))),
            Expanded(
              child: Text(
                '实际',
                textAlign: TextAlign.right,
                style: _text(10, _muted),
              ),
            ),
            Expanded(
              child: Text(
                '原算法',
                textAlign: TextAlign.right,
                style: _text(10, _muted),
              ),
            ),
            Expanded(
              child: Text(
                '动态模型',
                textAlign: TextAlign.right,
                style: _text(10, _muted),
              ),
            ),
          ],
        ),
        for (final r in report.rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line, width: 0.7)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r.month.year % 100}年${r.month.month}月',
                        style: _text(11),
                      ),
                      Text('第 ${r.asOfDay} 天', style: _text(10, _muted)),
                    ],
                  ),
                ),
                Expanded(
                  child: Text(
                    _money(r.truth),
                    textAlign: TextAlign.right,
                    style: _text(11, LhColors.ink, FontWeight.w600),
                  ),
                ),
                Expanded(child: cell(r.linear, r.truth)),
                Expanded(child: cell(r.dynamic, r.truth)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _params() {
    final s = report.summary;
    final wf = report.weekdayFactors;
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.signed ? '星期额外贡献（金额）' : '星期系数（相对基础日水平）',
          style: _text(11, _muted),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Column(
                  children: [
                    Text('周${names[i]}', style: _text(10, _muted)),
                    const SizedBox(height: 5),
                    Text(
                      s.signed ? _money(wf[i]) : '×${wf[i].toStringAsFixed(2)}',
                      style: _text(10, LhColors.ink, FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _parameter(
          '月末三天',
          s.signed
              ? _money(report.monthEndFactor)
              : '×${report.monthEndFactor.toStringAsFixed(2)}',
          '在星期效应之外',
        ),
        _parameter(
          '最后一天额外效应',
          s.signed
              ? _money(s.dynamic.lastDayFactor)
              : '×${s.dynamic.lastDayFactor.toStringAsFixed(2)}',
          '在月末三天效应之外',
        ),
        _parameter('当前基础日水平', _money(report.dailyLevel), '去掉星期、月底后的潜在水平'),
        _parameter('训练观测', '${s.dynamic.observations} 天', '最多使用近 240 个自然日'),
      ],
    );
  }

  Widget _parameter(String label, String value, String note) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _line, width: 0.7)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: _text(12)),
              Text(note, style: _text(10, _muted)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(value, style: _text(12, LhColors.ink, FontWeight.w600)),
      ],
    ),
  );

  Widget _footnote() => Text(
    '计算与数据口径\n'
    '只使用不晚于昨天的可用日数据。当前月缺失日期时暂停模型，历史缺失不填零。'
    '接口尚未提供完整性水位，“有数”不保证已完成业务对账。\n'
    '动态水平为随机游走，星期与月底参数带收缩先验；采用经验贝叶斯参数估计与 '
    'Laplace 后验近似，不是完整 MCMC。波动参数固定在训练窗估计值，区间尚未做外部覆盖率校准。\n'
    '原算法保底时，正金额缩放剩余模拟金额，有符号金额按未来进度平移；'
    '展示为 80% 近似预测区间，不能理解为保证 80% 命中。模型按历史回测选择，未来仍可能失准。\n'
    '预测仅对当前月的金额指标生效；比率、历史月份与原有财务确认流程不变。',
    style: _text(11, _muted),
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
    final actual = cum.last;
    double projAt(int j, double target) {
      if (j <= c) return cum[j - 1];
      if (target == s.hi) return s.cumulativeHi[j - 1];
      if (target == s.lo) return s.cumulativeLo[j - 1];
      return s.cumulativeMean[j - 1];
    }

    final prev = report.prevCum;
    var lo = math.min(0.0, s.cumulativeLo.reduce(math.min));
    var hi = s.cumulativeHi.reduce(math.max);
    lo = math.min(lo, s.cumulativeMean.reduce(math.min));
    hi = math.max(hi, s.cumulativeMean.reduce(math.max));
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
    final occupiedLabels = <Rect>[];
    void label(String text, double yy, Color col, {bool bold = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: LhTypography.sans(
            size: 8.5,
            color: col,
            weight: bold ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: padR - 4);
      final top = (yy - tp.height / 2)
          .clamp(0.0, size.height - tp.height)
          .toDouble();
      final bounds = Rect.fromLTWH(padL + w + 5, top, tp.width, tp.height);
      if (!bold && occupiedLabels.any((r) => r.inflate(3).overlaps(bounds))) {
        return;
      }
      occupiedLabels.add(bounds);
      tp.paint(canvas, Offset(padL + w + 5, top));
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
        label(_money(prev[total - 1]), py, LhColors.mute2);
      }
    }

    // 横轴
    void xl(int j, String t, {Color col = LhColors.mute2}) {
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: LhTypography.sans(size: 8, color: col),
        ),
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
      for (final v in [r.linear, r.dynamic]) {
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

    void series(
      double? Function(LighthouseCheckpointRow) pick,
      Color col,
      double width,
      bool labelAbove,
    ) {
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
            style: LhTypography.sans(
              size: 7.5,
              color: col,
              weight: FontWeight.w700,
            ),
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
    series((r) => r.dynamic, color, 2.0, true);

    for (var i = 0; i < n; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: '第${rows[i].day}天',
          style: LhTypography.sans(
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
            text: '— 动态日模型  ',
            style: LhTypography.sans(
              size: 8,
              color: color,
              weight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: '— 原算法',
            style: LhTypography.sans(size: 8, color: LhColors.mute2),
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
