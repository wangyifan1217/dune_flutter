// 量化报告 ·「月末结构预测 · 产品 / 供给 / 渠道」一节。
//   读法：维度 Tab → 指标 → 一句话总览 → 回测可信度 → 实体卡片（结论句 +
//   三档概率竖柱 + 依据 + 实体效应）→ 模型卡（可展开）。
//   只用竖向小柱，不用横向进度条。

import 'package:flutter/material.dart';

import 'lighthouse_product_ordinal.dart';
import 'lighthouse_theme.dart';

String _m(double v) {
  final a = v.abs();
  final sign = v < 0 ? '−' : '';
  if (a >= 1e8) return '$sign${(a / 1e8).toStringAsFixed(2)}亿';
  final w = a / 1e4;
  return '$sign${w >= 100 ? w.toStringAsFixed(1) : w.toStringAsFixed(2)}万';
}

/// 「比上月同期 ↓10.2%」这类相对变化。
String _chg(double a, double b) {
  if (b.abs() < 1e-9) return '—';
  final r = (a - b) / b.abs();
  return '${r >= 0 ? '↑' : '↓'}${(r.abs() * 100).toStringAsFixed(1)}%';
}

String _p(double v) => '${(v * 100).round()}%';

const _kVerdict = ['下滑', '持平', '增长'];
Color _vColor(int v) =>
    v == 2 ? LhColors.neg : (v == 0 ? LhColors.pos : LhColors.mute2);

class LighthouseProductOrdinalSection extends StatefulWidget {
  const LighthouseProductOrdinalSection({
    super.key,
    required this.loader,
    required this.initialMetric,
    required this.accent,
    this.fixedDim,
  });

  /// 非空时锁定维度、不显示「产品 / 供给 / 渠道」切换（BI 面板里跟随外面的视角）。
  final String? fixedDim;

  final Future<LighthouseOrdinalBundle?> Function(String dim) loader;
  final String initialMetric;
  final Color accent;

  @override
  State<LighthouseProductOrdinalSection> createState() =>
      _LighthouseProductOrdinalSectionState();
}

class _LighthouseProductOrdinalSectionState
    extends State<LighthouseProductOrdinalSection> {
  late String _dim = widget.fixedDim ?? 'product';

  @override
  void didUpdateWidget(covariant LighthouseProductOrdinalSection old) {
    super.didUpdateWidget(old);
    final f = widget.fixedDim;
    if (f != null && f != _dim) setState(() => _dim = f);
  }
  late String _metric = widget.initialMetric;
  bool _cardOpen = false;
  final Map<String, Future<LighthouseOrdinalBundle?>> _futures = {};

  Future<LighthouseOrdinalBundle?> _future(String dim) =>
      _futures[dim] ??= widget.loader(dim);

  Widget _pill(String text, bool on, VoidCallback onTap, {bool big = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: big ? 14 : 10,
          vertical: big ? 6 : 4,
        ),
        decoration: BoxDecoration(
          color: on ? (big ? widget.accent : widget.accent.withAlpha(22)) : LhColors.mist,
          borderRadius: BorderRadius.circular(big ? 8 : 14),
          border: Border.all(
            color: on ? widget.accent : LhColors.line2,
            width: 0.7,
          ),
        ),
        child: Text(
          text,
          style: LhTypography.sans(
            size: big ? 12 : 11,
            color: on ? (big ? Colors.white : widget.accent) : LhColors.ink2,
            weight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 维度 Tab
        if (widget.fixedDim == null)
        Row(
          children: [
            for (final e in lighthouseOrdinalDims.entries) ...[
              _pill(e.value.label, _dim == e.key, () {
                setState(() => _dim = e.key);
              }, big: true),
              const SizedBox(width: 6),
            ],
          ],
        ),
        if (widget.fixedDim == null) const SizedBox(height: 10),
        FutureBuilder<LighthouseOrdinalBundle?>(
          future: _future(_dim),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: widget.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '正在拉取各${lighthouseOrdinalDims[_dim]!.label}本月 / 上月数据…',
                      style: LhTypography.mono(size: 9, color: LhColors.mute2),
                    ),
                  ],
                ),
              );
            }
            final b = snap.data;
            if (b == null) {
              return Text(
                '暂时拉不到数据（或今天是 1 号，本月还没有 T+1 数据）。',
                style: LhTypography.mono(size: 9, color: LhColors.mute2),
              );
            }
            return _body(b);
          },
        ),
      ],
    );
  }

  Widget _body(LighthouseOrdinalBundle b) {
    final metrics = b.model.metricsOf(b.dim);
    if (metrics.isEmpty) {
      return Text(
        '这个维度的样本不足，暂未建模。',
        style: LhTypography.mono(size: 9, color: LhColors.mute2),
      );
    }
    final metric = metrics.contains(_metric) ? _metric : metrics.first;
    final list = b.byMetric[metric] ?? const <LighthouseOrdinalResult>[];
    final card = b.model.card(b.dim, metric);
    final bt = card?.backtest;
    final dimInfo = lighthouseOrdinalDims[b.dim]!;
    final label = b.model.labelOf(metric);
    final cur = '${b.month.month}月';
    final prev = '${DateTime(b.month.year, b.month.month - 1, 1).month}月';
    final counts = [0, 0, 0];
    for (final r in list) {
      counts[r.verdict]++;
    }
    final risk = list.where((r) => r.verdict == 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final k in metrics)
              _pill(b.model.labelOf(k), k == metric, () {
                setState(() => _metric = k);
              }),
          ],
        ),
        const SizedBox(height: 10),
        // 一句话总览
        Text.rich(
          TextSpan(
            style: LhTypography.sans(size: 12, color: LhColors.ink, height: 1.5),
            children: [
              TextSpan(text: '截至 ${b.day} 日，${list.length} ${dimInfo.unit}里，预计$cur全月$label比$prev：'),
              TextSpan(
                text: '增长 ${counts[2]} 个',
                style: const TextStyle(color: LhColors.neg, fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: '、'),
              TextSpan(
                text: '持平 ${counts[1]} 个',
                style: const TextStyle(color: LhColors.mute, fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: '、'),
              TextSpan(
                text: '下滑 ${counts[0]} 个',
                style: const TextStyle(color: LhColors.pos, fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text: risk.isEmpty
                    ? '。'
                    : '。下滑风险金额最大的是「${risk.first.name}」'
                          '（$prev ${_m(risk.first.features.prevTotal)}，下降超 5% 的概率 ${_p(risk.first.pDown)}）。',
              ),
            ],
          ),
        ),
        if (bt != null) ...[const SizedBox(height: 8), _trust(bt)],
        const SizedBox(height: 10),
        if (list.isEmpty)
          Text(
            '上月体量达标（≥ ${_m(b.model.minPrevTotal)}）的${dimInfo.label}为 0。',
            style: LhTypography.mono(size: 9, color: LhColors.mute2),
          )
        else
          for (final r in list) _entityCard(r, b, label, cur, prev),
        if ((b.skippedSmall[metric] ?? const []).isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '上月不足 ${_m(b.model.minPrevTotal)}、变化率噪声过大未建模：'
            '${b.skippedSmall[metric]!.join('、')}',
            style: LhTypography.mono(size: 8.5, color: LhColors.mute2, height: 1.5),
          ),
        ],
        const SizedBox(height: 10),
        if (card != null) _modelCard(card, b, label),
      ],
    );
  }

  // 回测可信度一行
  Widget _trust(LighthouseOrdinalBacktest bt) {
    final ok = bt.beatsBaseline;
    final c = ok ? widget.accent : LhColors.copper;
    String mon(String s) => '${int.tryParse(s.split('-').last) ?? s}月';
    final span = bt.months.isEmpty ? '' : '${mon(bt.months.first)}–${mon(bt.months.last)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
      decoration: BoxDecoration(
        color: c.withAlpha(14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withAlpha(50), width: 0.6),
      ),
      child: Text(
        '可信度：滚动回测 $span 共 ${bt.n} 次判断，模型命中 ${_p(bt.acc)}'
        '（线性外推基准 ${_p(bt.baseAcc)}），Brier ${bt.brier.toStringAsFixed(2)}'
        '${bt.baseBrier.isFinite ? '（基准 ${bt.baseBrier.toStringAsFixed(2)}）' : ''}。'
        '${ok ? '' : '该维度 × 指标模型未跑赢基准，结论仅供参考。'}',
        style: LhTypography.mono(
          size: 8.5,
          color: ok ? LhColors.ink2 : LhColors.copper,
          weight: FontWeight.w600,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _entityCard(
    LighthouseOrdinalResult r,
    LighthouseOrdinalBundle b,
    String label,
    String cur,
    String prev,
  ) {
    final v = r.verdict;
    final vc = _vColor(v);
    final f = r.features;
    final probs = [r.pDown, r.pFlat, r.pUp];
    final what = switch (v) {
      0 => '下降超过 5%',
      2 => '增长超过 5%',
      _ => '基本持平（±5% 内）',
    };
    final others = [
      for (var i = 2; i >= 0; i--)
        if (i != v) '${_kVerdict[i]} ${_p(probs[i])}',
    ].join(' · ');
    final effectText = !r.knownEntity
        ? (r.knownGroup
              ? '训练期没见过这个名字（新上线或改名），按所在分组「${r.group}」的平均效应估计。'
              : '训练期没见过这个实体和分组，只用月中信号估计。')
        : (r.effect >= 0.5
              ? '实体效应 +${r.effect.toStringAsFixed(1)}：历史上同样的月中信号下，它月底更容易走高。'
              : (r.effect <= -0.5
                    ? '实体效应 ${r.effect.toStringAsFixed(1)}：历史上同样的月中信号下，它月底更容易回落。'
                    : '实体效应 ${r.effect.toStringAsFixed(1)}：接近分组平均，没有明显的月底偏向。'));
    Widget why(String k, String val, String d) => Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                style: LhTypography.mono(size: 8.5, color: LhColors.mute2, height: 1.35),
                children: [
                  TextSpan(text: '$k '),
                  TextSpan(
                    text: val,
                    style: LhTypography.mono(size: 9, color: LhColors.ink, weight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          Text(
            d,
            style: LhTypography.mono(
              size: 8.5,
              color: d.startsWith('↑')
                  ? LhColors.neg
                  : (d.startsWith('↓') ? LhColors.pos : LhColors.mute2),
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: LhColors.paper,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LhColors.line2, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  r.name,
                  overflow: TextOverflow.ellipsis,
                  style: LhTypography.sans(size: 12.5, weight: FontWeight.w700),
                ),
              ),
              if (r.group.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    r.group,
                    overflow: TextOverflow.ellipsis,
                    style: LhTypography.mono(size: 8.5, color: LhColors.mute2),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: vc.withAlpha(22),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '预计${_kVerdict[v]}',
                  style: LhTypography.mono(size: 9.5, color: vc, weight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 结论句
          Text.rich(
            TextSpan(
              style: LhTypography.sans(size: 11.5, color: LhColors.ink, height: 1.45),
              children: [
                TextSpan(text: '$cur全月$label比$prev（${_m(f.prevTotal)}）'),
                TextSpan(
                  text: what,
                  style: TextStyle(color: vc, fontWeight: FontWeight.w800),
                ),
                const TextSpan(text: ' 的概率 '),
                TextSpan(
                  text: _p(r.confidence),
                  style: TextStyle(color: vc, fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: '；$others。',
                  style: const TextStyle(color: LhColors.mute),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 三档概率竖柱
              SizedBox(
                width: 104,
                height: 62,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              _p(probs[i]),
                              style: LhTypography.mono(
                                size: 8,
                                color: i == v ? vc : LhColors.mute2,
                                weight: i == v ? FontWeight.w800 : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              width: 14,
                              height: (probs[i] * 28).clamp(1.5, 28.0).toDouble(),
                              decoration: BoxDecoration(
                                color: _vColor(i).withAlpha(i == v ? 220 : 90),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(2.5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _kVerdict[i],
                              style: LhTypography.mono(size: 7.5, color: LhColors.mute2),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // 依据：为什么这么判断
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    why('1–${b.day} 日已发生', _m(f.mtd), '比$prev同期 ${_chg(f.mtd, f.prevSameDay)}'),
                    why('日均外推月末', _m(f.linearForecast), '比$prev全月 ${_chg(f.linearForecast, f.prevTotal)}'),
                    why('近 7 天', _m(f.last7), '比前 7 天 ${_chg(f.last7, f.prev7)}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            effectText,
            style: LhTypography.mono(size: 8, color: LhColors.mute2, height: 1.45),
          ),
        ],
      ),
    );
  }

  // 模型卡：点开看完整统计口径
  Widget _modelCard(
    LighthouseOrdinalCard c,
    LighthouseOrdinalBundle b,
    String label,
  ) {
    final bt = c.backtest;
    final dimInfo = lighthouseOrdinalDims[b.dim]!;
    String f2(double v) => v.isFinite ? v.toStringAsFixed(2) : '—';
    String mon(String s) => '${int.tryParse(s.split('-').last) ?? s}月';
    final fm = c.fixedMean;
    final lines = <(String, String)>[
      ('模型', '贝叶斯多层（分层）有序 logistic 回归 · 累积 logit / 比例优势'),
      ('结果变量', '$label本月全月相对上月全月：下滑（< −5%）< 持平（±5%）< 增长（> +5%）'),
      (
        '线性预测',
        'η = β₁·x_lin + β₂·x_lin·prog + β₃·x_pace + β₄·x_pace·prog + β₅·x_mom + u[${dimInfo.group}] + v[${dimInfo.label}]',
      ),
      ('概率', 'P(≤下滑) = logistic(κ₁ − η)，P(≤持平) = logistic(κ₂ − η)，κ₁ < κ₂'),
      (
        '协变量',
        'x_lin =（日均外推月末 − 上月全月）/ |上月全月|；x_pace =（已发生 − 上月同期）/ |上月同期|；'
            'x_mom =（近 7 天 − 前 7 天）/ |前 7 天|；prog = 已过天数 / 当月天数；均截断到 [−2, 2]',
      ),
      (
        '分层',
        '${dimInfo.label}嵌套在${dimInfo.group}内：u ~ N(0, σ_g²)，v ~ N(0, σ_e²)，部分汇聚；'
            '后验 σ_g = ${f2(c.sigmaGroup)}，σ_e = ${f2(c.sigmaEntity)}',
      ),
      ('先验', 'β ~ N(0, 2.5²)，κ ~ N(±1, 2.5²) 有序约束，σ ~ HalfNormal(1)，随机效应非中心化'),
      (
        '估计',
        'NUTS 采样 2 链 × 800；R̂ 最大 ${c.rhat.isFinite ? c.rhat.toStringAsFixed(3) : '—'}，'
            '最小有效样本 ${c.essMin.isFinite ? c.essMin.round() : '—'}；App 内用 100 个后验样本做后验预测',
      ),
      (
        '固定效应均值',
        'β₁ ${f2(fm['x_lin'] ?? double.nan)} · β₂ ${f2(fm['x_lin_prog'] ?? double.nan)} · '
            'β₃ ${f2(fm['x_pace'] ?? double.nan)} · β₄ ${f2(fm['x_pace_prog'] ?? double.nan)} · β₅ ${f2(fm['x_mom'] ?? double.nan)}',
      ),
      (
        '样本',
        '训练 ${c.trainMonths.isEmpty ? '—' : '${mon(c.trainMonths.first)}–${mon(c.trainMonths.last)}'}，'
            '${c.nObs} 个观测（实体 × 月 × 第 5/10/15/20/25 天），${c.nEntity} 个${dimInfo.label}、${c.nGroup} 个分组；'
            '上月 < ${_m(b.model.minPrevTotal)} 的不建模',
      ),
      if (bt != null)
        (
          '回测',
          '扩展窗口滚动：预测第 m 月只用 m 之前的月训练；${bt.n} 次判断，命中率 ${_p(bt.acc)}（基准 ${_p(bt.baseAcc)}），'
              '多分类 Brier ${f2(bt.brier)}（基准 ${f2(bt.baseBrier)}），对数损失 ${f2(bt.logloss)}；'
              '按检查日命中率 ${bt.byDay.map((d) => '第${d.day}天 ${_p(d.acc)}/${_p(d.baseAcc)}').join('，')}（模型/基准）',
        ),
      (
        '局限',
        '训练期短（${b.model.trainedFrom}–${b.model.trainedThrough}）；改名或新上线的实体退回分组效应；'
            '档位相对上月而非目标；比例优势假设未单独检验',
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: LhColors.mist,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LhColors.line2, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _cardOpen = !_cardOpen),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                children: [
                  Text(
                    '模型卡',
                    style: LhTypography.sans(size: 11.5, weight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '贝叶斯多层有序 logit · ${dimInfo.label} × $label',
                      overflow: TextOverflow.ellipsis,
                      style: LhTypography.mono(size: 8.5, color: LhColors.mute2),
                    ),
                  ),
                  Icon(
                    _cardOpen ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: LhColors.mute2,
                  ),
                ],
              ),
            ),
          ),
          if (_cardOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (k, v) in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 64,
                            child: Text(
                              k,
                              style: LhTypography.mono(
                                size: 8.5,
                                color: widget.accent,
                                weight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              v,
                              style: LhTypography.mono(
                                size: 8.5,
                                color: LhColors.ink2,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
