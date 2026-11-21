import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_detail.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_service.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_sheets.dart';
import 'hr_performance_workflow_test.dart' as fixtures;

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('HR_CAPTURE_UI')) {
      for (final family in [
        'HrReviewFont',
        'Geist',
        'Noto Sans SC',
        'Microsoft YaHei',
      ]) {
        final loader = FontLoader(family);
        loader.addFont(
          Future.value(
            ByteData.sublistView(
              await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
            ),
          ),
        );
        await loader.load();
      }
    }
  });
  for (final width in [360.0, 800.0, 1200.0]) {
    testWidgets(
      'detail handles long text, evidence and actions at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final raw = fixtures.sample(
          stage: 'hr',
          actions: ['approve_hr'],
          draft: true,
        );
        final snapshot = Map<String, dynamic>.from(raw['snapshot'] as Map);
        raw['snapshot'] = snapshot;
        snapshot.addAll({
          'name': '朱子姝',
          'departmentName': '人工智能研发与产品工程中心',
          'positionName': 'AI应用架构师（平台与交付质量负责人）',
          'selfTotal': 90,
          'total': 90,
          'grade': '良',
          'coefficient': 1,
          'directSupervisorName': '许正阳',
          'divisionSupervisorName': '许正阳',
          'workflow': {'dueAt': '2026-11-25T23:59:00+08:00'},
          'lines': [
            {
              'indicatorId': 'target',
              'name': '任务交付质量与业务价值',
              'project': '工作业绩',
              'weight': 100,
              'score': 90,
              'taskIds': [9],
              'bands': [
                {
                  'min': 90,
                  'max': 100,
                  'description': '按计划交付并通过验收，交付内容包含完整说明与可复核的业务结果。',
                },
                {'min': 0, 'max': 89, 'description': '未完全达到预定标准，根据实际交付质量评分。'},
              ],
            },
          ],
          'evidence': [
            {
              'id': 9,
              'title': '完成人工智能应用平台上线及验收',
              'status': 'completed',
              'dueAt': '2026-10-20T18:00:00+08:00',
              'completedAt': '2026-10-20T17:30:00+08:00',
            },
          ],
        });
        final service = fixtures.FakeHR(fixtures.testSession(4), [
          raw,
        ], hr: true);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('capture'),
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'HrReviewFont'),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(width == 800 ? 1.3 : 1),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: HrPerformanceDetail(
                  session: fixtures.testSession(4),
                  record: HrPerformanceRecord.fromJson(raw),
                  service: service,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('hr-detail-name')))
              .style!
              .fontSize,
          lessThanOrEqualTo(16),
        );
        expect(
          find.byKey(const ValueKey('hr-action-approve_hr')).hitTestable(),
          findsOneWidget,
        );
        if (const bool.fromEnvironment('HR_CAPTURE_UI')) {
          await capture(tester, 'summary-$width');
        }
        await tester.ensureVisible(find.byKey(const ValueKey('hr-evidence-1')));
        await tester.pumpAndSettle();
        expect(find.text('#9'), findsNothing);
        await tester.tap(find.text('任务证据（1）'));
        await tester.pumpAndSettle();
        expect(find.text('#9'), findsOneWidget);
        expect(find.text('负责人 朱子姝'), findsOneWidget);
        expect(find.text('截止 2026-10-20 18:00'), findsOneWidget);
        expect(find.text('完成 2026-10-20 17:30'), findsOneWidget);
        expect(find.text('按期完成'), findsOneWidget);
        expect(find.text('关联指标：任务交付质量与业务价值'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('HR_CAPTURE_UI')) {
          await capture(tester, 'evidence-$width');
        }
        if (width == 360) {
          await tester.ensureVisible(find.text('完整表格'));
          await tester.tap(find.text('完整表格'));
          await tester.pumpAndSettle();
          expect(find.byType(Table), findsWidgets);
          final bars = tester
              .widgetList<Scrollbar>(find.byType(Scrollbar))
              .where(
                (bar) =>
                    bar.controller != null &&
                    bar.controller!.hasClients &&
                    bar.controller!.position.axis == Axis.horizontal,
              );
          expect(
            bars.single.controller!.position.maxScrollExtent,
            greaterThan(0),
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets(
    'desktop select is centered, searchable and preserves choice on cancel',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHrReasonSheet(
                  context,
                  title: '回退考核',
                  targets: ['self', 'review', 'hr'],
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.byIcon(Icons.expand_more_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNWidgets(2));
      await tester.enterText(find.byType(TextField).last, '初评');
      await tester.pumpAndSettle();
      expect(find.text('主管初评').hitTestable(), findsOneWidget);
      await tester.tap(find.text('主管初评'));
      await tester.pumpAndSettle();
      expect(find.text('主管初评'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.expand_more_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭处理方式'));
      await tester.pumpAndSettle();
      expect(find.text('主管初评'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('build/hr_ui_review');
    await folder.create(recursive: true);
    await File(
      '${folder.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
