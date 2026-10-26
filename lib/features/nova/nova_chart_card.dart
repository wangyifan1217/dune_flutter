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
    if (chart.series.length > 1) {
      return _NovaMultiBarChart(chart: chart, ink: ink, muted: muted);
    }
    final values = chart.series.first.values;
    var maxPos = 0.0;
    var maxNeg = 0.0;
    for (final value in values) {
      if (value == null) continue;
      maxPos = math.max(maxPos, value);
      maxNeg = math.max(maxNeg, -value);
    }
    final span = maxPos + maxNeg;
    // 名称常常带同一个前缀（如「河南中石油200元…」）：前缀单独显示一次，每行只留区分部分。
    final prefix = novaChartCommonPrefix(chart.labels);
    final labelStyle = TextStyle(fontSize: 12, height: 1.3, color: ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (prefix.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '以下均为「$prefix」',
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ),
        for (var i = 0; i < chart.labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Tooltip(
              message: chart.labels[i],
              triggerMode: TooltipTriggerMode.longPress,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _novaChartShortLabel(chart.labels[i], prefix),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: labelStyle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        values[i] == null ? '—' : novaChartAmount(values[i]!),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final value = values[i];
                      final width = constraints.maxWidth;
                      if (value == null || span <= 0) {
                        return const SizedBox(height: 8);
                      }
                      final zero = width * maxNeg / span;
                      final length = math.max(2.0, width * value.abs() / span);
                      return SizedBox(
                        height: 8,
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
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 多指标对比：每个对象一组，每个指标一根条。各指标量级不同（销售额和利润差几十倍），
/// 所以每个指标按自己的最大值缩放，条的长短只在同一指标内比较，数值写在右边。
class _NovaMultiBarChart extends StatelessWidget {
  const _NovaMultiBarChart({
    required this.chart,
    required this.ink,
    required this.muted,
  });

  final NovaChart chart;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final series = chart.series;
    final spans = [
      for (final s in series)
        s.values.nonNulls.fold<double>(0, (m, v) => math.max(m, v.abs())),
    ];
    final prefix = novaChartCommonPrefix(chart.labels);
    final valueStyle = TextStyle(
      fontSize: 11.5,
      height: 1.2,
      color: muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Color colorOf(int i) => _novaChartPalette[i % _novaChartPalette.length];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (var i = 0; i < series.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colorOf(i),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      series[i].name,
                      style: TextStyle(fontSize: 11, color: ink),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (prefix.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '以下均为「$prefix」',
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ),
        for (var row = 0; row < chart.labels.length; row++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Tooltip(
              message: chart.labels[row],
              triggerMode: TooltipTriggerMode.longPress,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _novaChartShortLabel(chart.labels[row], prefix),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  for (var i = 0; i < series.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final value = series[i].values[row];
                                if (value == null || spans[i] <= 0) {
                                  return const SizedBox(height: 6);
                                }
                                final length = math.max(
                                  2.0,
                                  constraints.maxWidth * value.abs() / spans[i],
                                );
                                return Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    width: length,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: value < 0
                                          ? _novaChartNegative
                                          : colorOf(i),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 64,
                            child: Text(
                              series[i].values[row] == null
                                  ? '—'
                                  : novaChartAmount(series[i].values[row]!),
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              style: valueStyle,
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
    );
  }
}

String _novaChartShortLabel(String label, String prefix) {
  if (prefix.isEmpty || !label.startsWith(prefix)) return label;
  final rest = label.substring(prefix.length).trim();
  return rest.isEmpty ? label : rest;
}

final _novaChartWordTail = RegExp(r'[0-9A-Za-z.]$');

/// 柱状图各行名称的共同前缀；至少 3 行、前缀至少 3 个字才提取，
/// 且不截断数字或英文（避免「河南中石油2」把「200元」拆成「00元」）。
String novaChartCommonPrefix(List<String> labels) {
  if (labels.length < 3) return '';
  var prefix = labels.first.runes.toList();
  for (final label in labels.skip(1)) {
    final runes = label.runes.toList();
    var n = 0;
    while (n < prefix.length && n < runes.length && prefix[n] == runes[n]) {
      n++;
    }
    prefix = prefix.sublist(0, n);
    if (prefix.isEmpty) return '';
  }
  var text = String.fromCharCodes(prefix);
  while (text.isNotEmpty && _novaChartWordTail.hasMatch(text)) {
    text = text.substring(0, text.length - 1);
  }
  text = text.trimRight();
  if (text.runes.length < 3) return '';
  // 每一行去掉前缀后都要还剩内容，否则前缀就是某一行的全名，不提取。
  for (final label in labels) {
    if (label.substring(text.length).trim().isEmpty) return '';
  }
  return text;
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

/// 回答下面的图默认折叠成一行：点开再看，不把正文挤下去。
class NovaCollapsibleChart extends StatelessWidget {
  const NovaCollapsibleChart({
    super.key,
    required this.chart,
    required this.expanded,
    required this.onToggle,
    this.dark = false,
  });

  final NovaChart chart;
  final bool expanded;
  final VoidCallback onToggle;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? const Color(0xFFF5F2FA) : const Color(0xFF1C1C1E);
    final muted = dark ? const Color(0xFF98989F) : const Color(0xFF8E8E93);
    final title = chart.title.isEmpty
        ? (chart.isLine ? '走势图' : '对比图')
        : chart.title;
    final header = Material(
      color: dark ? const Color(0xFF1F1F22) : const Color(0xFFF8F7FB),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: const ValueKey('nova-chart-toggle'),
        borderRadius: BorderRadius.circular(10),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                chart.isLine
                    ? Icons.show_chart_rounded
                    : Icons.bar_chart_rounded,
                size: 16,
                color: _novaChartPalette.first,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: ink,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                expanded ? '收起' : '展开',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: muted,
              ),
            ],
          ),
        ),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.topLeft,
        child: expanded
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  header,
                  const SizedBox(height: 6),
                  NovaChartCard(chart: chart, dark: dark),
                ],
              )
            : Align(alignment: Alignment.centerLeft, child: header),
      ),
    );
  }
}

/// 回答下面的追问：一行一个，整行可点；最后可以带一个次要操作（如「改用通用问答」）。
class NovaFollowUps extends StatelessWidget {
  const NovaFollowUps({
    super.key,
    required this.suggestions,
    required this.onAsk,
    this.enabled = true,
    this.secondaryLabel,
    this.secondaryKey,
    this.onSecondary,
    this.maxVisible = 3,
  });

  final List<String> suggestions;
  final ValueChanged<String> onAsk;
  final bool enabled;
  final String? secondaryLabel;
  final Key? secondaryKey;
  final VoidCallback? onSecondary;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFE8E4F2) : const Color(0xFF2C2540);
    final muted = dark ? const Color(0xFF98989F) : const Color(0xFF8E8E93);
    final border = dark ? const Color(0xFF34303E) : const Color(0xFFE6E1F2);
    final fill = dark ? const Color(0xFF1F1D25) : Colors.white;
    final accent = _novaChartPalette.first;
    final shown = suggestions.take(maxVisible).toList();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (shown.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 6),
              child: Text(
                '接着问',
                style: TextStyle(fontSize: 11.5, color: muted),
              ),
            ),
          for (final suggestion in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: fill,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: border),
                ),
                child: InkWell(
                  key: ValueKey('nova-suggestion-$suggestion'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: enabled ? () => onAsk(suggestion) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.subdirectory_arrow_right_rounded,
                          size: 15,
                          color: enabled ? accent : muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            suggestion,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: enabled ? ink : muted,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (secondaryLabel != null && onSecondary != null)
            TextButton(
              key: secondaryKey,
              style: TextButton.styleFrom(
                foregroundColor: muted,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12),
              ),
              onPressed: enabled ? onSecondary : null,
              child: Text(secondaryLabel!),
            ),
        ],
      ),
    );
  }
}
