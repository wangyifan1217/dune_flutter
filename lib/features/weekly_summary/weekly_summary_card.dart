import 'dart:ui';

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

    return SizedBox(
      width: cardWidth,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DunesColors.resolve(
                context,
                Colors.white,
                role: DunesColorRole.surface,
              ).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: DunesColors.resolve(
                  context,
                  Colors.white,
                  role: DunesColorRole.border,
                ).withValues(alpha: 0.95),
                width: 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context),
                  const SizedBox(height: 9),
                  _metrics(context),
                  if (data.latestLabel.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      _latestText(data.latestLabel),
                      style: _sans(
                        context,
                        size: 11,
                        weight: FontWeight.w500,
                        color: _secondary,
                        height: 1.2,
                      ),
                    ),
                  ],
                  if (sheetRows.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0x14FFFFFF)
                            : const Color(0x09000000),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: sheetRows,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            '一周小结',
            style: _sans(
              context,
              size: 15,
              weight: FontWeight.w600,
              color: _ink,
              letterSpacing: -0.2,
              height: 1.15,
            ),
          ),
        ),
        if (data.rangeLabel.trim().isNotEmpty)
          Text(
            data.rangeLabel.trim(),
            style: _sans(
              context,
              size: 11,
              weight: FontWeight.w500,
              color: _secondary,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        if (showShareHint) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onShare,
            child: Icon(
              Icons.ios_share_rounded,
              size: 15,
              color: DunesColors.resolveNullable(context, _secondary),
            ),
          ),
        ],
      ],
    );
  }

  Widget _metrics(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _metric(context, '${data.sessionCount}', '会话')),
        Expanded(child: _metric(context, '${data.messageCount}', '消息')),
        Expanded(child: _metric(context, '${data.minutes}', '分钟')),
      ],
    );
  }

  Widget _metric(BuildContext context, String value, String unit) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: _sans(
            context,
            size: 18,
            weight: FontWeight.w600,
            color: _ink,
            letterSpacing: -0.4,
            height: 1,
          ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        const SizedBox(width: 3),
        Text(
          unit,
          style: _sans(
            context,
            size: 11,
            weight: FontWeight.w500,
            color: _secondary,
            height: 1,
          ),
        ),
      ],
    );
  }

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
            width: 28,
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
                Text.rich(TextSpan(children: [line]), style: _lineStyle(context)),
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
