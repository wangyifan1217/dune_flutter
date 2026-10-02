import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'weekly_summary_models.dart';

const _ink = Color(0xFF1D1D1F);
const _inkSub = Color(0xFF3A3A3C);
const _secondary = Color(0xFF8E8E93);
const _line = Color(0x10000000);
const _tileBg = Color(0x07000000);

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

  static const double cardWidth = 258.0;

  @override
  Widget build(BuildContext context) {
    final view = _WeeklySummaryView.fromShare(data);

    return SizedBox(
      width: cardWidth,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
                width: 1.0,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0C000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
                BoxShadow(
                  color: Color(0x04000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(view),
                  const SizedBox(height: 10),
                  _communicationSection(view),
                  if (view.meetings.isNotEmpty) ...[
                    _divider(),
                    _meetingsSection(view),
                  ],
                  if (view.portrait.isNotEmpty) ...[
                    _divider(),
                    _portraitSection(view),
                  ],
                  if (view.travel.isNotEmpty || view.route.isNotEmpty) ...[
                    _divider(),
                    _travelSection(view),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(_WeeklySummaryView view) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            '一周小结',
            style: DunesTypography.sans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: _ink,
              height: 1.15,
            ),
          ),
        ),
        if (view.rangeLabel.isNotEmpty)
          Text(
            view.rangeLabel,
            style: DunesTypography.sans(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: _secondary,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        if (showShareHint) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onShare,
            child: const Icon(
              Icons.ios_share_rounded,
              size: 15,
              color: _secondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 9),
      child: SizedBox(
        height: 0.5,
        width: double.infinity,
        child: DecoratedBox(decoration: BoxDecoration(color: _line)),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        title,
        style: DunesTypography.sans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _secondary,
        ),
      ),
    );
  }

  Widget _communicationSection(_WeeklySummaryView view) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('沟通'),
        Row(
          children: [
            for (final item in view.communication)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.value,
                      style:
                          DunesTypography.sans(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: _ink,
                            height: 1.05,
                          ).copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.label,
                      style: DunesTypography.sans(
                        fontSize: 10.5,
                        color: _secondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (view.latestLabel.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '最晚在${view.latestLabel}',
            style: DunesTypography.sans(
              fontSize: 11,
              color: _secondary,
              height: 1.25,
            ),
          ),
        ],
      ],
    );
  }

  Widget _meetingsSection(_WeeklySummaryView view) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('会议'),
        Row(
          children: [
            for (final item in view.meetings)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.value,
                      style:
                          DunesTypography.sans(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: _ink,
                            height: 1.05,
                          ).copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.label,
                      style: DunesTypography.sans(
                        fontSize: 10.5,
                        color: _secondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _portraitSection(_WeeklySummaryView view) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('画像'),
        DecoratedBox(
          decoration: BoxDecoration(
            color: _tileBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Column(
              children: [
                for (var i = 0; i < view.portrait.length; i++) ...[
                  if (i > 0) const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          view.portrait[i].label,
                          style: DunesTypography.sans(
                            fontSize: 11.5,
                            color: _inkSub,
                          ),
                        ),
                      ),
                      Text(
                        view.portrait[i].value,
                        style:
                            DunesTypography.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _ink,
                            ).copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _travelSection(_WeeklySummaryView view) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('差旅'),
        if (view.travel.isNotEmpty)
          Row(
            children: [
              for (final item in view.travel)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.value,
                        style:
                            DunesTypography.sans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: _ink,
                              height: 1.05,
                            ).copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        style: DunesTypography.sans(
                          fontSize: 10,
                          color: _secondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        if (view.route.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            view.route,
            style: DunesTypography.sans(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: _inkSub,
              height: 1.25,
            ),
          ),
        ],
      ],
    );
  }
}

class _Metric {
  const _Metric(this.value, this.label);
  final String value;
  final String label;
}

class _WeeklySummaryView {
  const _WeeklySummaryView({
    required this.rangeLabel,
    required this.sessionCount,
    required this.messageCount,
    required this.minutes,
    this.latestLabel = '',
    this.meetingCount = 0,
    this.attendeeCount = 0,
    this.completedTasks = 0,
    this.proposals = 0,
    this.minutesCount = 0,
    this.travelDays = 0,
    this.flightKm = 0,
    this.trainKm = 0,
    this.route = '',
  });

  final String rangeLabel;
  final int sessionCount;
  final int messageCount;
  final int minutes;
  final String latestLabel;
  final int meetingCount;
  final int attendeeCount;
  final int completedTasks;
  final int proposals;
  final int minutesCount;
  final int travelDays;
  final int flightKm;
  final int trainKm;
  final String route;

  factory _WeeklySummaryView.fromShare(WeeklySummaryShare data) {
    return _WeeklySummaryView(
      rangeLabel: data.rangeLabel,
      sessionCount: data.sessionCount,
      messageCount: data.messageCount,
      minutes: data.minutes,
      latestLabel: data.latestLabel,
      meetingCount: 0,
      attendeeCount: 0,
      completedTasks: 0,
      proposals: 0,
      minutesCount: 0,
      travelDays: 0,
      flightKm: 0,
      trainKm: 0,
      route: '',
    );
  }

  List<_Metric> get communication => [
    _Metric('$sessionCount', '工作会话'),
    _Metric('$messageCount', '消息'),
    _Metric('$minutes', '分钟'),
  ];

  List<_Metric> get meetings {
    if (meetingCount <= 0 && attendeeCount <= 0) return const [];
    return [
      if (meetingCount > 0) _Metric('$meetingCount', '场次'),
      if (attendeeCount > 0) _Metric('$attendeeCount', '参会人数'),
    ];
  }

  List<_Metric> get portrait {
    return [
      if (completedTasks > 0) _Metric('$completedTasks', '已完成任务'),
      if (proposals > 0) _Metric('$proposals', '发起提案'),
      if (minutesCount > 0) _Metric('$minutesCount', '会议纪要'),
    ];
  }

  List<_Metric> get travel {
    if (travelDays <= 0 && flightKm <= 0 && trainKm <= 0) return const [];
    return [
      if (travelDays > 0) _Metric('$travelDays', '天'),
      if (flightKm > 0) _Metric(_km(flightKm), '飞行约公里'),
      if (trainKm > 0) _Metric(_km(trainKm), '高铁约公里'),
    ];
  }

  static String _km(int km) {
    final text = '$km';
    final buf = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final left = text.length - i;
      if (i > 0 && left % 3 == 0) buf.write(',');
      buf.write(text[i]);
    }
    return buf.toString();
  }
}
