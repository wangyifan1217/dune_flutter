import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'weekly_summary_models.dart';

const _ink = Color(0xFF1D1D1F);
const _inkSub = Color(0xFF3A3A3C);
const _secondary = Color(0xFF8E8E93);
const _dot = Color(0xFFAEAEB2);

class WeeklySummaryPoster extends StatelessWidget {
  const WeeklySummaryPoster({
    super.key,
    required this.data,
    this.showShareHint = false,
    this.onShare,
  });

  final WeeklySummaryShare data;
  final bool showShareHint;
  final VoidCallback? onShare;

  static const double cardWidth = 272.0;

  @override
  Widget build(BuildContext context) {
    final sheetRows = _sheetRows(context);
    final border = DunesColors.resolve(
      context,
      const Color(0xFFE0E8E5),
      role: DunesColorRole.border,
    );
    return SizedBox(
      width: cardWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.surface,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x09000000),
              blurRadius: 16,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _metrics(context),
                  if (sheetRows.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    for (var i = 0; i < sheetRows.length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      sheetRows[i],
                    ],
                  ],
                  if (data.latestLabel.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Divider(height: 1, color: border),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: DunesColors.resolve(context, _secondary),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _latestText(data.latestLabel),
                            style: _sans(
                              context,
                              size: 11,
                              weight: FontWeight.w400,
                              color: _secondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              DunesColors.accentSoft,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.insert_chart_outlined_rounded,
            size: 19,
            color: DunesColors.resolve(context, DunesColors.accent),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '一周小结',
                style: _sans(
                  context,
                  size: 16,
                  weight: FontWeight.w600,
                  color: _ink,
                  height: 1.3,
                ),
              ),
              if (data.rangeLabel.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  data.rangeLabel.trim(),
                  style:
                      _sans(
                        context,
                        size: 11,
                        weight: FontWeight.w400,
                        color: _secondary,
                        height: 1.4,
                      ).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ],
          ),
        ),
        if (showShareHint)
          IconButton(
            tooltip: '分享一周小结',
            onPressed: onShare,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(
              Icons.ios_share_rounded,
              size: 18,
              color: DunesColors.resolve(context, DunesColors.accent),
            ),
          ),
      ],
    ),
  );

  Widget _metrics(BuildContext context) {
    // Keep equal values as separate metrics (e.g. an empty week).
    final values = [
      _grouped(data.sessionCount),
      _grouped(data.messageCount),
      _grouped(data.minutes),
    ];
    const labels = ['会话', '消息', '分钟'];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          const Color(0xFFF1F6F4),
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final maxDigits = values
              .map((v) => v.length)
              .reduce((a, b) => a > b ? a : b);
          final columns =
              scale <= 1.3 &&
              maxDigits * 20 * .62 * scale <= constraints.maxWidth / 3 - 4;
          if (!columns) {
            return Column(
              children: [
                for (var i = 0; i < values.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(values[i], style: _numberStyle(context)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        labels[i],
                        style: _sans(
                          context,
                          size: 11,
                          weight: FontWeight.w400,
                          color: _secondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(values[i], style: _numberStyle(context)),
                      const SizedBox(height: 5),
                      Text(
                        labels[i],
                        style: _sans(
                          context,
                          size: 11,
                          weight: FontWeight.w400,
                          color: _secondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  TextStyle _numberStyle(BuildContext context) => _sans(
    context,
    size: 20,
    weight: FontWeight.w600,
    color: _ink,
    height: 1.2,
    letterSpacing: -.5,
  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  List<Widget> _sheetRows(BuildContext context) {
    final rows = <Widget>[];
    final meeting = _meetingLine(context);
    if (meeting != null) rows.add(_factRow(context, '会议', meeting));
    final week = _weekLine(context);
    if (week != null) rows.add(_factRow(context, '本周', week));
    final travel = _travelLine(context);
    final travelCaption = _travelCaption();
    if (travel != null || travelCaption.isNotEmpty) {
      rows.add(
        _factRow(
          context,
          '差旅',
          travel ?? const TextSpan(text: ''),
          caption: travelCaption,
        ),
      );
    }
    return rows;
  }

  Widget _factRow(
    BuildContext context,
    String label,
    InlineSpan line, {
    String caption = '',
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28 * MediaQuery.textScalerOf(context).scale(1),
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                label,
                style: _sans(
                  context,
                  size: 11,
                  weight: FontWeight.w500,
                  color: _secondary,
                  height: 1.35,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [line]),
                  style: _lineStyle(context),
                ),
                if (caption.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      caption,
                      style: _sans(
                        context,
                        size: 11,
                        weight: FontWeight.w500,
                        color: _secondary,
                        height: 1.3,
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

  InlineSpan? _meetingLine(BuildContext context) {
    final parts = <InlineSpan>[];
    if (data.meetingCount > 0) {
      parts.addAll(_numUnit(context, '${data.meetingCount}', '场'));
    }
    if (data.attendeeCount > 0) {
      if (parts.isNotEmpty) parts.add(_sep(context));
      parts.addAll(_numUnit(context, '${data.attendeeCount}', '人'));
    }
    if (parts.isEmpty) return null;
    return TextSpan(children: parts);
  }

  InlineSpan? _weekLine(BuildContext context) {
    final parts = <InlineSpan>[];
    void add(int value, String unit) {
      if (value <= 0) return;
      if (parts.isNotEmpty) parts.add(_sep(context));
      parts.addAll(_numUnit(context, '$value', unit));
    }

    add(data.completedTasks, '项任务');
    add(data.proposals, '提案');
    add(data.minutesCount, '纪要');
    if (parts.isEmpty) return null;
    return TextSpan(children: parts);
  }

  InlineSpan? _travelLine(BuildContext context) {
    final route = data.route.trim();
    final parts = <InlineSpan>[];
    if (data.travelDays > 0) {
      parts.addAll(_numUnit(context, '${data.travelDays}', '天'));
    }
    if (route.isNotEmpty) {
      if (parts.isNotEmpty) parts.add(_sep(context));
      parts.add(TextSpan(text: route, style: _unitStyle(context)));
    }
    if (parts.isEmpty) return null;
    return TextSpan(children: parts);
  }

  String _travelCaption() {
    final parts = <String>[];
    if (data.flightKm > 0) parts.add('飞行约 ${_grouped(data.flightKm)} 公里');
    if (data.trainKm > 0) parts.add('高铁约 ${_grouped(data.trainKm)} 公里');
    return parts.join(' · ');
  }

  List<InlineSpan> _numUnit(BuildContext context, String value, String unit) {
    return [
      TextSpan(text: value, style: _valueStyle(context)),
      TextSpan(text: ' $unit', style: _unitStyle(context)),
    ];
  }

  InlineSpan _sep(BuildContext context) {
    return TextSpan(text: ' · ', style: _dotStyle(context));
  }

  TextStyle _lineStyle(BuildContext context) {
    return _sans(
      context,
      size: 12,
      weight: FontWeight.w500,
      color: _inkSub,
      height: 1.35,
    );
  }

  TextStyle _valueStyle(BuildContext context) {
    return _sans(
      context,
      size: 12,
      weight: FontWeight.w600,
      color: _ink,
      letterSpacing: -0.2,
      height: 1.35,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  }

  TextStyle _unitStyle(BuildContext context) {
    return _sans(
      context,
      size: 12,
      weight: FontWeight.w500,
      color: _inkSub,
      height: 1.35,
    );
  }

  TextStyle _dotStyle(BuildContext context) {
    return _sans(
      context,
      size: 12,
      weight: FontWeight.w500,
      color: _dot,
      height: 1.35,
    );
  }

  TextStyle _sans(
    BuildContext context, {
    required double size,
    required FontWeight weight,
    required Color color,
    double? letterSpacing,
    double? height,
  }) {
    return DunesTypography.sans(
      context: context,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
      height: height,
    );
  }

  static String _latestText(String label) {
    final text = label.trim();
    if (text.startsWith('最晚')) return text;
    return '最晚$text';
  }

  static String _grouped(int value) {
    final text = '$value';
    final buf = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final left = text.length - i;
      if (i > 0 && left % 3 == 0) buf.write(',');
      buf.write(text[i]);
    }
    return buf.toString();
  }
}
