import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_sheets.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_detail.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_service.dart';
import 'hr_performance_workflow_test.dart' as fixtures;

class AuditService extends fixtures.FakeHR {
  AuditService(super.session, super.rows) : super(hr: true);
  @override
  Future<List<Map<String, dynamic>>> logs(int id) async => [
    {
      'actor': 'system:hr-performance',
      'action': 'initialize',
      'reason': '系统记录',
      'createdAt': '2026-11-20T08:00:00Z',
    },
    {
      'actor': 'admin:1',
      'action': 'assign',
      'reason': '后台记录',
      'createdAt': '2026-11-20T08:00:00Z',
    },
    {
      'actor': 'user:5:AdMiN',
      'action': 'assign',
      'reason': '管理员记录',
      'createdAt': '2026-11-20T08:00:00Z',
    },
    {
      'actor': 'user:33:李小伊',
      'action': 'submit_review',
      'reason': '完成审批',
      'createdAt': '2026-11-20T08:00:00Z',
    },
  ];
}

void main() {
  for (final width in [360.0, 1200.0]) {
    testWidgets('short form fits content at width $width and confirms', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
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
                  title: '退回自评',
                  message: '将退回本人自评。',
                  minLength: 1,
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final panel = tester.getRect(
        find.byKey(const ValueKey('hr-sheet-submit')),
      );
      final title = tester.getRect(find.text('退回自评'));
      expect(panel.bottom - title.top, lessThan(380));
      if (width > 640) {
        expect(
          tester.getSize(find.byKey(const ValueKey('hr-reason'))).width,
          lessThanOrEqualTo(520),
        );
      }
      await tester.enterText(find.byKey(const ValueKey('hr-reason')), '需要补充');
      if (width == 360) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(
          tester
              .getBottomLeft(find.byKey(const ValueKey('hr-sheet-submit')))
              .dy,
          lessThanOrEqualTo(520),
        );
      }
      await tester.tap(find.byKey(const ValueKey('hr-sheet-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hr-confirm-action')), findsOneWidget);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect(find.text('需要补充'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('large form scrolls and keeps submit accessible', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => hrFormSheet(
                context,
                title: '多项评分',
                values: {},
                maxWidth: 760,
                fields: (_, update) => [
                  for (var i = 0; i < 30; i++)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('指标 $i'),
                    ),
                ],
                submit: (v) => v,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('hr-sheet-submit')).hitTestable(),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('指标 29'));
    await tester.pumpAndSettle();
    expect(find.text('指标 29').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('hr-sheet-submit')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'audit hides system and admin records but retains human records',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final raw = fixtures.sample();
      final service = AuditService(fixtures.testSession(4), [raw]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HrPerformanceDetail(
              session: fixtures.testSession(4),
              record: HrPerformanceRecord.fromJson(raw),
              service: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('修改记录'));
      await tester.tap(find.text('修改记录'));
      await tester.pumpAndSettle();
      expect(find.textContaining('系统记录'), findsNothing);
      expect(find.textContaining('后台记录'), findsNothing);
      expect(find.textContaining('管理员记录'), findsNothing);
      expect(find.textContaining('完成审批'), findsOneWidget);
      expect(find.textContaining('李小伊'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
