import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_forecast_model.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_forecast_report.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_forecast_strip.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_hero_metric.dart';

const _captureDirectory = String.fromEnvironment('FORECAST_SNAPSHOT_DIR');

Future<void> _snapshot(WidgetTester tester, String name) async {
  if (_captureDirectory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('forecast-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_captureDirectory).create(recursive: true);
    await File(
      '$_captureDirectory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LighthouseForecastReport report;
  setUpAll(() async {
    for (final font in ['Geist', 'Geist Mono', 'Noto Sans SC']) {
      final asset = switch (font) {
        'Geist' => 'Geist-Regular.ttf',
        'Geist Mono' => 'GeistMono-Regular.ttf',
        _ => 'NotoSansSC-Regular.ttf',
      };
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/$asset'))).load();
    }
    final daily = <DateTime, double>{};
    for (var i = 0; i < 280; i++) {
      final day = DateTime(2026, 1, 1 + i);
      final end = DateTime(day.year, day.month + 1, 0).day;
      daily[day] =
          1e6 *
          (1 + .002 * i) *
          (day.weekday >= 6 ? .6 : 1.1) *
          (day.day > end - 3 ? 2.2 : 1);
    }
    report = lighthouseForecastReport(
      daily: daily,
      today: DateTime(2026, 9, 22),
    )!;
  });

  for (final width in [320.0, 390.0, 940.0]) {
    testWidgets('预测报告 ${width.toInt()}px 含原理且滚动无溢出', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('forecast-capture'),
              child: LighthouseForecastReportSheet(
                report: report,
                metricLabel: '核销规模',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('核销规模 · 月末预测'), findsOneWidget);
      expect(find.text('试行'), findsNothing);
      expect(find.textContaining('近似预测区间'), findsWidgets);
      await _snapshot(tester, 'report-${width.toInt()}');
      await tester.scrollUntilVisible(
        find.text('预测原理'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('月末总额 = 已发生'), findsOneWidget);
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final target =
          scroll.position.pixels + tester.getTopLeft(find.text('预测原理')).dy - 20;
      scroll.position.jumpTo(target.clamp(0, scroll.position.maxScrollExtent));
      await tester.pumpAndSettle();
      await _snapshot(tester, 'principles-${width.toInt()}');
      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.textContaining('Laplace'), findsOneWidget);
    });
  }

  for (final width in [240.0, 300.0, 560.0]) {
    testWidgets('主图预测条 ${width.toInt()}px 同口径且报告可点击', (tester) async {
      tester.view.physicalSize = Size(width, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('forecast-capture'),
              child: Align(
                alignment: Alignment.topCenter,
                child: LighthouseForecastStrip(
                  forecast: lighthousePaceFromModel(
                    report.summary,
                    shownActual: report.summary.actual,
                  ),
                  money: (v) => '${(v / 1e8).toStringAsFixed(2)}亿',
                  accent: const Color(0xFF51418E),
                  onOpenReport: () => opened++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('截至21日'), findsOneWidget);
      expect(find.textContaining('试行'), findsNothing);
      expect(
        tester.getSize(find.byType(LighthouseForecastStrip)).height,
        lessThanOrEqualTo(lighthouseTrendForecastStripHeight),
      );
      await _snapshot(tester, 'strip-${width.toInt()}');
      await tester.tap(find.text('报告 ›'));
      expect(opened, 1);
    });
  }
}
