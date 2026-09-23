import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'app_usage_models.dart';

const _themePurple = Color(0xFF7B5CD8);

/// 使用热力「每日使用」：细柱 + 纵轴刻度，手机可点选、天数多时可横滑。
class AppUsageDailyChart extends StatefulWidget {
  const AppUsageDailyChart({
    super.key,
    required this.days,
    required this.maxDay,
  });

  final List<AppUsageDayStay> days;
  final int maxDay;

  @override
  State<AppUsageDailyChart> createState() => _AppUsageDailyChartState();
}

class _AppUsageDailyChartState extends State<AppUsageDailyChart> {
  final ScrollController _scrollController = ScrollController();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.days.isNotEmpty ? widget.days.length - 1 : 0;
    _scrollToLatestDay();
  }

  @override
  void didUpdateWidget(covariant AppUsageDailyChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.days.length != widget.days.length ||
        (widget.days.isNotEmpty &&
            oldWidget.days.isNotEmpty &&
            oldWidget.days.last.date != widget.days.last.date)) {
      _selectedIndex = widget.days.isNotEmpty ? widget.days.length - 1 : 0;
      _scrollToLatestDay();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLatestDay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  void _onSelectDay(int index) {
    if (index < 0 || index >= widget.days.length) return;
    if (_selectedIndex != index) {
      setState(() => _selectedIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.days.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEDE8F5)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '每日使用',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF261D38),
              ),
            ),
            SizedBox(height: 12),
            Center(
              child: Text(
                '暂无每日数据',
                style: TextStyle(fontSize: 13, color: DunesColors.text3),
              ),
            ),
          ],
        ),
      );
    }

    final totalDurationMs = widget.days.fold<int>(
      0,
      (sum, d) => sum + d.durationMs,
    );
    final avgDurationMs = totalDurationMs ~/ widget.days.length;
    final selectedDay = widget.days[
      _selectedIndex.clamp(0, widget.days.length - 1)
    ];
    final scaleMax = _niceDurationMaxMs(
      math.max(widget.maxDay, selectedDay.durationMs),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE8F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B5CD8).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 3.5,
                          height: 14,
                          margin: const EdgeInsets.only(right: 7),
                          decoration: BoxDecoration(
                            color: _themePurple,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const Text(
                          '每日使用',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF261D38),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3EEFA),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${widget.days.length}天',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _themePurple,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      '不含后台挂机时间',
                      style: TextStyle(fontSize: 11, color: DunesColors.text3),
                    ),
                  ],
                ),
              ),
              if (avgDurationMs > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF7FD),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEDE5F7)),
                  ),
                  child: Text(
                    '日均 ${_formatCompactDuration(avgDurationMs)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _themePurple,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _SelectedDayBanner(day: selectedDay),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 480;
              final axisWidth = compact ? 34.0 : 42.0;
              final chartHeight = compact ? 148.0 : 164.0;
              final n = widget.days.length;
              final plotWidth = math.max(0.0, constraints.maxWidth - axisWidth);
              final minSlot = compact ? 36.0 : 42.0;
              final shouldScroll = n * minSlot > plotWidth + 0.5;
              final slotWidth = shouldScroll
                  ? minSlot
                  : (n == 0 ? minSlot : plotWidth / n);
              final chartWidth = shouldScroll ? n * minSlot : plotWidth;

              final plot = Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: axisWidth,
                    child: _YAxis(
                      maxMs: scaleMax,
                      compact: compact,
                    ),
                  ),
                  Expanded(
                    child: shouldScroll
                        ? SingleChildScrollView(
                            controller: _scrollController,
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: SizedBox(
                              width: chartWidth,
                              child: _ChartBody(
                                days: widget.days,
                                maxMs: scaleMax,
                                selectedIndex: _selectedIndex,
                                slotWidth: slotWidth,
                                compact: compact,
                                onSelect: _onSelectDay,
                              ),
                            ),
                          )
                        : _ChartBody(
                            days: widget.days,
                            maxMs: scaleMax,
                            selectedIndex: _selectedIndex,
                            slotWidth: slotWidth,
                            compact: compact,
                            onSelect: _onSelectDay,
                          ),
                  ),
                ],
              );

              return Column(
                children: [
                  SizedBox(height: chartHeight, child: plot),
                  if (shouldScroll) ...[
                    const SizedBox(height: 6),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(
                          Icons.swipe_rounded,
                          size: 12,
                          color: DunesColors.text3,
                        ),
                        SizedBox(width: 3),
                        Text(
                          '左右滑动查看更多日期',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: DunesColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SelectedDayBanner extends StatelessWidget {
  const _SelectedDayBanner({required this.day});

  final AppUsageDayStay day;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F5FD),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _formatDateFullWithWeekday(day.date),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF261D38),
              ),
            ),
          ),
          Text(
            _formatCompactDuration(day.durationMs),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _themePurple,
            ),
          ),
          if (day.pv > 0) ...[
            const SizedBox(width: 8),
            Text(
              '打开 ${day.pv}次',
              style: const TextStyle(fontSize: 11.5, color: DunesColors.text2),
            ),
          ],
        ],
      ),
    );
  }
}

class _YAxis extends StatelessWidget {
  const _YAxis({required this.maxMs, required this.compact});

  final int maxMs;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const labelH = 22.0;
    final ticks = <int>[maxMs, maxMs ~/ 2, 0];
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 22),
      child: Column(
        children: [
          for (var i = 0; i < ticks.length; i++) ...[
            if (i > 0) const Spacer(),
            SizedBox(
              height: i == ticks.length - 1 ? labelH : 14,
              child: Align(
                alignment: i == ticks.length - 1
                    ? Alignment.bottomRight
                    : Alignment.topRight,
                child: Text(
                  _formatAxisTick(ticks[i]),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: compact ? 9 : 10,
                    height: 1,
                    color: DunesColors.text3,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartBody extends StatelessWidget {
  const _ChartBody({
    required this.days,
    required this.maxMs,
    required this.selectedIndex,
    required this.slotWidth,
    required this.compact,
    required this.onSelect,
  });

  final List<AppUsageDayStay> days;
  final int maxMs;
  final int selectedIndex;
  final double slotWidth;
  final bool compact;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    const labelH = 22.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        if (slotWidth <= 0) return;
        onSelect((details.localPosition.dx / slotWidth).floor());
      },
      child: Column(
        children: [
        Expanded(
          child: CustomPaint(
            painter: _DailyBarPainter(
              days: days,
              maxMs: maxMs,
              selectedIndex: selectedIndex,
              slotWidth: slotWidth,
              compact: compact,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        SizedBox(
          height: labelH,
          child: Row(
            children: [
              for (var i = 0; i < days.length; i++)
                SizedBox(
                  width: slotWidth,
                  child: _DateLabel(
                    date: days[i].date,
                    selected: selectedIndex == i,
                    compact: compact,
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

class _DateLabel extends StatelessWidget {
  const _DateLabel({
    required this.date,
    required this.selected,
    required this.compact,
  });

  final String date;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final today = _isToday(date);
    return Center(
      child: Text(
        compact ? _formatDateTiny(date) : _formatDateShort(date),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(
          fontSize: compact ? 9.5 : 10.5,
          height: 1,
          fontWeight: selected || today ? FontWeight.w700 : FontWeight.w500,
          color: selected || today ? _themePurple : DunesColors.text3,
        ),
      ),
    );
  }
}

class _DailyBarPainter extends CustomPainter {
  _DailyBarPainter({
    required this.days,
    required this.maxMs,
    required this.selectedIndex,
    required this.slotWidth,
    required this.compact,
  });

  final List<AppUsageDayStay> days;
  final int maxMs;
  final int selectedIndex;
  final double slotWidth;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty || size.width <= 0 || size.height <= 0) return;
    final plotH = size.height;
    final gridPaint = Paint()
      ..color = const Color(0xFFEDE7F6)
      ..strokeWidth = 1;
    for (final t in [0.0, 0.5, 1.0]) {
      final y = plotH * t;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final barW = compact
        ? math.min(8.0, slotWidth * 0.34)
        : math.min(12.0, slotWidth * 0.28);
    final radius = Radius.circular(barW / 2);
    final usable = plotH * 0.88;

    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final cx = slotWidth * i + slotWidth / 2;
      final selected = i == selectedIndex;
      if (selected) {
        final highlight = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, plotH / 2),
            width: math.min(slotWidth - 2, compact ? 28 : 36),
            height: plotH,
          ),
          const Radius.circular(8),
        );
        canvas.drawRRect(
          highlight,
          Paint()..color = const Color(0xFFF4EEFC),
        );
      }

      final ratio = maxMs <= 0 ? 0.0 : (day.durationMs / maxMs).clamp(0.0, 1.0);
      final minH = day.durationMs > 0 ? 4.0 : 0.0;
      final h = day.durationMs <= 0 ? 2.0 : math.max(minH, usable * ratio);
      final top = plotH - h;
      final rect = RRect.fromLTRBR(
        cx - barW / 2,
        top,
        cx + barW / 2,
        plotH,
        radius,
      );
      if (day.durationMs <= 0) {
        canvas.drawRRect(
          rect,
          Paint()..color = const Color(0xFFD9CDEA),
        );
        continue;
      }
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: selected
              ? const [Color(0xFF9B7DE8), Color(0xFF6743D1)]
              : const [Color(0xFFC9B7F0), Color(0xFFA48AD9)],
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DailyBarPainter oldDelegate) {
    return oldDelegate.days != days ||
        oldDelegate.maxMs != maxMs ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.slotWidth != slotWidth ||
        oldDelegate.compact != compact;
  }
}

int _niceDurationMaxMs(int maxMs) {
  final minutes = maxMs <= 0 ? 30 : math.max(1, (maxMs / 60000).ceil());
  const steps = <int>[
    15,
    30,
    45,
    60,
    90,
    120,
    150,
    180,
    240,
    300,
    360,
    480,
    600,
    720,
    960,
    1200,
    1440,
  ];
  for (final step in steps) {
    if (step >= minutes) return step * 60000;
  }
  return ((minutes + 59) ~/ 60) * 60 * 60000;
}

DateTime? _tryParseDate(String raw) {
  try {
    final direct = DateTime.tryParse(raw);
    if (direct != null) return direct;
    if (raw.length == 5 && raw.contains('-')) {
      final now = DateTime.now();
      return DateTime.tryParse('${now.year}-$raw');
    }
  } catch (_) {}
  return null;
}

String _formatDateShort(String raw) {
  final dt = _tryParseDate(raw);
  if (dt != null) {
    return '${dt.month}/${dt.day}';
  }
  if (raw.length >= 10) return raw.substring(5);
  return raw;
}

String _formatDateTiny(String raw) {
  final dt = _tryParseDate(raw);
  if (dt != null) return '${dt.month}/${dt.day}';
  return _formatDateShort(raw);
}

String _formatDateFullWithWeekday(String raw) {
  final dt = _tryParseDate(raw);
  if (dt != null) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final weekday = weekdays[dt.weekday - 1];
    return '${dt.month}月${dt.day}日 $weekday';
  }
  return raw;
}

bool _isToday(String raw) {
  final dt = _tryParseDate(raw);
  if (dt == null) return false;
  final now = DateTime.now();
  return dt.year == now.year && dt.month == now.month && dt.day == now.day;
}

String _formatCompactDuration(int durationMs) {
  if (durationMs <= 0) return '0分';
  final minutes = (durationMs / 60000).round();
  if (minutes <= 0) return '<1分';
  if (minutes < 60) return '$minutes分';
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  if (rem == 0) return '$hours小时';
  return '$hours小时$rem分';
}

String _formatAxisTick(int durationMs) {
  if (durationMs <= 0) return '0';
  final minutes = (durationMs / 60000).round();
  if (minutes < 60) return '$minutes分';
  final hours = minutes / 60;
  if (hours == hours.roundToDouble()) return '${hours.toInt()}时';
  final h = minutes ~/ 60;
  final rem = minutes % 60;
  return '$h:${rem.toString().padLeft(2, '0')}';
}
