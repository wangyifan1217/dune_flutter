import 'package:dunes_app/features/lighthouse/lighthouse_forecast.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_forecast_strip.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_intraday_hero.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 分时 / 近7天大数卡（原型 docs/lighthouse_7day_trend_prototype.html）。
void main() {
  final today = DateTime(2026, 11, 23);
  final values = [
    128000.0,
    142000.0,
    116000.0,
    168000.0,
    139000.0,
    156500.0,
    73500.0,
  ];
  final days = [
    for (var k = -6; k <= 0; k++)
      LhIntradayDay(
        date: today.add(Duration(days: k)),
        offset: k,
        value: values[k + 6],
      ),
  ];
  final data = LhIntradayData.fromJson({
    'available': true,
    'date': '2026-11-23',
    'today': [
      {'at': '09:00', 'minute': 540, 'profit': 20000, 'verifiedSales': 900000},
      {'at': '15:12', 'minute': 912, 'profit': 73500, 'verifiedSales': 2600000},
    ],
    'prev': [
      {'at': '09:00', 'minute': 540, 'profit': 18000, 'verifiedSales': 800000},
      {'at': '15:00', 'minute': 900, 'profit': 61500, 'verifiedSales': 2300000},
      {
        'at': '23:50',
        'minute': 1430,
        'profit': 156500,
        'verifiedSales': 5100000,
      },
    ],
  });

  Future<List<String>> pump(
    WidgetTester tester, {
    String metric = 'profit',
    String label = '利润',
    bool isRate = false,
    int selected = 0,
    int committed = 0,
    String view = 'min',
    double value = 73500,
    List<int>? taps,
    List<int>? commits,
    List<String>? views,
    bool monthly = false,
    Widget? forecastPanel,
  }) async {
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 380,
              child: LighthouseIntradayHero(
                metricKey: metric,
                metricLabel: label,
                isRate: isRate,
                days: monthly
                    ? [
                        for (var k = -6; k <= 0; k++)
                          LhIntradayDay(
                            date: DateTime(today.year, today.month + k),
                            offset: k,
                            value: values[k + 6],
                          ),
                      ]
                    : days,
                selectedOffset: selected,
                committedOffset: committed,
                value: value,
                data: data,
                todayData: data,
                view: view,
                monthly: monthly,
                monthAsOf: monthly ? today : null,
                forecastPanel: forecastPanel,
                asOfMinute: 912,
                onViewChanged: (v) => views?.add(v),
                onDayTap: (o) => taps?.add(o),
                onDayCommit: (o) => commits?.add(o),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return log;
  }

  testWidgets('今天：今日盈利、截至时间、比昨日同一时刻', (tester) async {
    await pump(tester);
    expect(find.text('今日盈利'), findsOneWidget);
    expect(find.text('截至 15:12 · 进行中'), findsOneWidget);
    // 73500 vs 昨天 15:00 的 61500：+1.20万 +19.5%
    expect(find.textContaining('较昨日同时 +1.20万'), findsOneWidget);
    expect(find.textContaining('+19.5%'), findsOneWidget);
    expect(find.text('选择日期查看分时'), findsOneWidget);
  });

  testWidgets('单击日期 = 预览，同一天连点两下 = 整页切换', (tester) async {
    final taps = <int>[];
    final commits = <int>[];
    await pump(tester, taps: taps, commits: commits);
    await tester.tap(find.text('22'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(taps, [-1]);
    expect(commits, isEmpty);
    await tester.tap(find.text('22'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(commits, [-1]);
    // 隔一会儿再点 = 又是单击。
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('21'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(taps, [-1, -2]);
  });

  testWidgets('预览昨天：标题换成昨日盈利，比的是前一日全天', (tester) async {
    await pump(tester, selected: -1, value: 156500);
    expect(find.text('昨日盈利'), findsOneWidget);
    expect(find.textContaining('全天'), findsWidgets);
    expect(find.text('双击日期看这天明细'), findsOneWidget);
  });

  testWidgets('近7天：日均、最高、今天不计入日均', (tester) async {
    final views = <String>[];
    await pump(tester, view: 'week', views: views);
    expect(find.text('近7天 · 每日盈利'), findsOneWidget);
    expect(find.text('日均盈利'), findsOneWidget);
    expect(find.text('最高 · 11/20'), findsOneWidget);
    expect(find.text('今天不计入日均'), findsOneWidget);
    await tester.tap(find.text('分时'));
    expect(views, ['min']);
  });

  testWidgets(
    'Windows 趋势图双击切换日期时无障碍节点保持稳定',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final commits = <int>[];
        await pump(tester, view: 'week', commits: commits);

        final chart = find.bySemanticsLabel('近7天趋势图');
        final chartNodeId = tester.getSemantics(chart).id;
        final rect = tester.getRect(chart);
        final point = Offset(rect.center.dx, rect.bottom - 20);
        await tester.tapAt(point);
        await tester.pump();
        expect(find.text('看当天分时 →'), findsOneWidget);
        expect(find.bySemanticsLabel('看当天分时 →'), findsNothing);
        expect(tester.getSemantics(chart).id, chartNodeId);
        expect(commits, isEmpty);

        await tester.tapAt(point);
        await tester.pumpAndSettle();
        expect(commits, [-3]);
        expect(find.text('看当天分时 →'), findsNothing);
        expect(tester.getSemantics(chart).id, chartNodeId);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
    variant: TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets('换成核销额：标题、分时都跟着指标走', (tester) async {
    await pump(tester, metric: 'verifiedSales', label: '核销额', value: 2600000);
    expect(find.text('今日核销额'), findsOneWidget);
    expect(find.text('今日累计核销额'), findsOneWidget);
  });

  testWidgets('比率指标没有分时累计', (tester) async {
    await pump(tester, metric: 'rate', label: '净利率', isRate: true, value: 1.46);
    expect(find.textContaining('是比率，没有分时累计'), findsOneWidget);
  });

  testWidgets('月末预测在主数右侧，窄屏换行后报告仍可点', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var opened = 0;
    final forecast = LighthouseForecastCard(
      forecast: LighthousePaceForecast(
        actual: 5076200,
        forecast: 6310000,
        elapsedDays: 23,
        totalDays: 30,
        yearTotal: 53277000,
        beatPrevProb: .01,
        future: [
          LighthouseFutureMonth(month: DateTime(2026, 12), forecast: 6000000),
        ],
      ),
      money: (value) => '${(value / 10000).toStringAsFixed(1)}万',
      onOpenReport: () => opened++,
    );
    final panel = find.byType(LighthouseForecastCard);
    final title = find.text('本月盈利');
    for (final width in [380.0, 275.0]) {
      tester.view.physicalSize = Size(width, 950);
      await pump(
        tester,
        monthly: true,
        value: 5076200,
        forecastPanel: forecast,
      );
      expect(find.text('631.0万'), findsOneWidget);
      expect(find.text('年末 5327.7万 · 超上月 1%'), findsOneWidget);
      if (width == 380) {
        expect(
          tester.getTopLeft(panel).dx,
          greaterThan(tester.getTopRight(title).dx),
        );
      } else {
        expect(
          tester.getTopLeft(panel).dy,
          greaterThan(tester.getBottomLeft(title).dy),
        );
      }
      await tester.tap(find.text('报告'));
      expect(tester.takeException(), isNull);
    }
    expect(opened, 2);
  });
}
