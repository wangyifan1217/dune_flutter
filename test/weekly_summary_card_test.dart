import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/weekly_summary/weekly_summary_card.dart';
import 'package:dunes_app/features/weekly_summary/weekly_summary_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const sample = WeeklySummaryShare(
  rangeLabel: '10.05 — 10.11',
  sessionCount: 28,
  messageCount: 1260,
  minutes: 185,
  meetingCount: 3,
  attendeeCount: 12,
  completedTasks: 8,
  proposals: 2,
  minutesCount: 3,
  travelDays: 2,
  route: '上海 → 杭州',
  flightKm: 1200,
  trainKm: 340,
  latestLabel: '工作至 22:40',
);
Future<void> pumpPoster(
  WidgetTester tester,
  WeeklySummaryShare data, {
  double width = 320,
  double scale = 1,
  bool dark = false,
  bool share = false,
  VoidCallback? onShare,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? DunesTheme.dark() : DunesTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: width,
                child: Align(
                  child: WeeklySummaryPoster(
                    data: data,
                    showShareHint: share,
                    onShare: onShare,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'poster preserves weekly metrics, meetings, work and travel facts',
    (tester) async {
      await pumpPoster(tester, sample);
      for (final text in [
        '一周小结',
        '10.05 — 10.11',
        '28',
        '1,260',
        '185',
        '会话',
        '消息',
        '分钟',
        '会议',
        '本周',
        '差旅',
        '最晚工作至 22:40',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(
        find.textContaining('上海 → 杭州', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('8 项任务', findRichText: true), findsOneWidget);
      expect(find.text('飞行约 1,200 公里 · 高铁约 340 公里'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'poster fits long dates, routes and large numbers at enlarged text dark=$dark',
      (tester) async {
        const data = WeeklySummaryShare(
          rangeLabel: '2026.10.05 — 2026.10.11',
          sessionCount: 123456789,
          messageCount: 987654321,
          minutes: 123456,
          meetingCount: 12345,
          travelDays: 12,
          route: '上海 → 杭州 → 南京 → 苏州 → 深圳 → 北京',
        );
        await pumpPoster(tester, data, width: 230, scale: 1.8, dark: dark);
        expect(find.text('123,456,789'), findsOneWidget);
        expect(find.text('987,654,321'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'empty week keeps all three zero metrics and share remains interactive',
    (tester) async {
      var shares = 0;
      await pumpPoster(
        tester,
        const WeeklySummaryShare(rangeLabel: '', sessionCount: 0, minutes: 0),
        share: true,
        onShare: () => shares++,
      );
      expect(find.text('0'), findsNWidgets(3));
      expect(find.text('会议'), findsNothing);
      expect(find.text('差旅'), findsNothing);
      final button = find.byTooltip('分享一周小结');
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      await tester.tap(button);
      expect(shares, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
