import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'nova_personal_query.dart';

const _novaChartPalette = <Color>[
  Color(0xFF7C5CFF),
  Color(0xFFFF8A3D),
  Color(0xFF2BB673),
  Color(0xFF3D8BFF),
];
const _novaChartNegative = Color(0xFFFF6B4A);

/// 灯塔回答下面的小图。数据已经由后端算好，这里只负责画。
class NovaChartCard extends StatelessWidget {
  const NovaChartCard({super.key, required this.chart, this.dark = false});

  final NovaChart chart;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? const Color(0xFFF5F2FA) : const Color(0xFF1C1C1E);
    final muted = dark ? const Color(0xFF98989F) : const Color(0xFF8E8E93);
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1F1F22) : const Color(0xFFF8F7FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dark ? const Color(0xFF2C2C2E) : const Color(0xFFECEAF2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chart.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                chart.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
            ),
          if (chart.isLine)
            _NovaLineChart(chart: chart, ink: ink, muted: muted)
          else
            _NovaBarChart(chart: chart, ink: ink, muted: muted),
        ],
      ),
    );
  }
}

/// 打开小饕时的经营提醒卡片：几条变化 + 可以直接点的追问。
class NovaInsightCard extends StatelessWidget {
  const NovaInsightCard({
    super.key,
    required this.insight,
    required this.onAsk,
    required this.onDismiss,
    this.enabled = true,
    this.dark = false,
  });

  final NovaInsight insight;
  final ValueChanged<String> onAsk;
  final VoidCallback onDismiss;
  final bool enabled;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? const Color(0xFFF5F2FA) : const Color(0xFF1C1C1E);
    final muted = dark ? const Color(0xFFC7C7CC) : const Color(0xFF48484A);
    return Container(
      key: const ValueKey('nova-insight-card'),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF26222F) : const Color(0xFFF4F0FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.insights_rounded,
                size: 16,
                color: _novaChartPalette.first,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  insight.title.isEmpty ? '经营提醒' : insight.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('nova-insight-dismiss'),
                tooltip: '知道了',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: onDismiss,
                icon: Icon(Icons.close_rounded, color: muted),
              ),
            ],
          ),
          for (final line in insight.lines)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 2),
              child: Text(
                '· $line',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
              ),
            ),
          if (insight.suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final suggestion in insight.suggestions)
                    ActionChip(
                      label: Text(
                        suggestion,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: enabled ? () => onAsk(suggestion) : null,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NovaBarChart extends StatelessWidget {
  const _NovaBarChart({
    required this.chart,
    required this.ink,
    required this.muted,
  });

  final NovaChart chart;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final values = chart.series.first.values;
    var maxPos = 0.0;
    var maxNeg = 0.0;
    for (final value in values) {
      if (value == null) continue;
      maxPos = math.max(maxPos, value);
      maxNeg = math.max(maxNeg, -value);
    }
    final span = maxPos + maxNeg;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < chart.labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    chart.labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: ink),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final value = values[i];
                      final width = constraints.maxWidth;
                      if (value == null || span <= 0) {
                        return const SizedBox(height: 14);
                      }
                      final zero = width * maxNeg / span;
                      final length = math.max(2.0, width * value.abs() / span);
                      return SizedBox(
                        height: 14,
                        child: Stack(
                          children: [
                            Positioned(
                              left: value < 0 ? zero - length : zero,
                              width: length,
                              top: 0,
                              bottom: 0,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: value < 0
                                      ? _novaChartNegative
                                      : _novaChartPalette.first,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 64,
                  child: Text(
                    values[i] == null ? '—' : novaChartAmount(values[i]!),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      color: muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NovaLineChart extends StatelessWidget {
  const _NovaLineChart({
    required this.chart,
    required this.ink,
    required this.muted,
  });

  final NovaChart chart;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final series in chart.series) ...series.values.nonNulls,
    ];
    if (points.isEmpty) return const SizedBox.shrink();
    final lo = points.reduce(math.min);
    final hi = points.reduce(math.max);
    final labelStyle = TextStyle(fontSize: 11, color: muted);
    final last = chart.labels.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (chart.series.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (var i = 0; i < chart.series.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 3,
                        color: _novaChartPalette[i % _novaChartPalette.length],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        chart.series[i].name,
                        style: TextStyle(fontSize: 11, color: ink),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                height: 120,
                child: CustomPaint(
                  painter: _NovaLinePainter(
                    chart: chart,
                    lo: lo,
                    hi: hi,
                    grid: muted.withValues(alpha: 0.25),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(novaChartAmount(hi), style: labelStyle),
                  Text(novaChartAmount(lo), style: labelStyle),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(chart.labels.first, style: labelStyle),
            const Spacer(),
            if (last >= 4) Text(chart.labels[last ~/ 2], style: labelStyle),
            if (last >= 4) const Spacer(),
            Text(chart.labels[last], style: labelStyle),
          ],
        ),
      ],
    );
  }
}

class _NovaLinePainter extends CustomPainter {
  _NovaLinePainter({
    required this.chart,
    required this.lo,
    required this.hi,
    required this.grid,
  });

  final NovaChart chart;
  final double lo;
  final double hi;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset.zero, Offset(size.width, 0), gridPaint);
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      gridPaint,
    );
    final range = hi - lo;
    double y(double value) => range == 0
        ? size.height / 2
        : size.height - (value - lo) / range * size.height;
    if (lo < 0 && hi > 0) {
      canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)), gridPaint);
    }
    final count = chart.labels.length;
    double x(int i) => count <= 1 ? 0 : size.width * i / (count - 1);
    for (var s = 0; s < chart.series.length; s++) {
      final color = _novaChartPalette[s % _novaChartPalette.length];
      final line = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final dot = Paint()..color = color;
      final path = Path();
      var drawing = false;
      final values = chart.series[s].values;
      for (var i = 0; i < values.length; i++) {
        final value = values[i];
        if (value == null) {
          drawing = false;
          continue;
        }
        final point = Offset(x(i), y(value));
        if (drawing) {
          path.lineTo(point.dx, point.dy);
        } else {
          path.moveTo(point.dx, point.dy);
          drawing = true;
        }
        if (count <= 16) canvas.drawCircle(point, 2.5, dot);
      }
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(_NovaLinePainter old) =>
      old.chart != chart || old.lo != lo || old.hi != hi || old.grid != grid;
}
