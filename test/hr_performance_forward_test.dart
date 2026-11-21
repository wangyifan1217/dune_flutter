import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_chat_card.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_detail.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_management_ui.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_service.dart';
import 'hr_performance_workflow_test.dart' as fixtures;

class StrictLegacyService extends fixtures.FakeHR {
  StrictLegacyService(super.session, super.rows) : super(hr: true);
  @override
  Future<Map<String, dynamic>> summary(
    String month,
    List<int> ids, {
    bool confirmScores = false,
    bool includeDraftScores = false,
  }) async {
    throw StateError('Forwarding must not depend on the summary endpoint');
  }
}

void main() {
  testWidgets(
    'forward card uses final review layout without any approval actions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HrPerformanceChatCard(
              session: fixtures.testSession(4),
              payload: {
                'hrPerformanceSummary': true,
                'hrPerformanceReadOnlySummary': true,
                'month': '2026-10',
                'department': '研发部',
                'averageCoefficient': 1.0,
                'hasScores': true,
                'rows': [
                  {
                    'id': 1,
                    'name': '员工甲',
                    'department': '研发部',
                    'stage': 'hr',
                    'total': 90,
                    'grade': '良',
                    'coefficient': 1.0,
                  },
                ],
              },
            ),
          ),
        ),
      );
      expect(find.text('绩效考核汇总'), findsOneWidget);
      expect(find.text('已评分人员平均系数'), findsOneWidget);
      await tester.tap(find.text('展开人员（1）'));
      await tester.pumpAndSettle();
      expect(find.textContaining('员工甲'), findsOneWidget);
      expect(find.textContaining('90 分 · 良 · 系数 1.0 · HR 审核'), findsOneWidget);
      expect(find.text('部门确认'), findsNothing);
      expect(find.text('驳回'), findsNothing);
      expect(find.text('查看'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'forward range selects department including children and returns explicit people',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final a = fixtures.sample(id: 1, name: '员工甲');
      a['departmentId'] = 7;
      final b = fixtures.sample(id: 2, name: '员工乙');
      b['departmentId'] = 8;
      final c = fixtures.sample(id: 3, name: '员工丙');
      c['departmentId'] = 9;
      Map<String, dynamic>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('打开'),
                onPressed: () async {
                  result = await showHrExportSheet(
                    context,
                    month: '2026-10',
                    forForward: true,
                    selectedIds: {},
                    records: [
                      for (final item in [a, b, c])
                        HrPerformanceRecord.fromJson(item),
                    ],
                    departments: [
                      {'id': 7, 'name': '研发部', 'parentId': null},
                      {'id': 8, 'name': '研发子组', 'parentId': 7},
                      {'id': 9, 'name': '财务部', 'parentId': null},
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('按部门'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('研发部'));
      await tester.pumpAndSettle();
      expect(find.textContaining('将转发 2 人'), findsOneWidget);
      await tester.tap(find.text('选择会话'));
      await tester.pumpAndSettle();
      expect(result!['ids'], [1, 2]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'legacy department approval is hidden even if returned by server',
    (tester) async {
      final record = fixtures.sample(
        stage: 'hr',
        actions: ['approve_hr', 'approve_department_hr'],
      );
      final service = fixtures.FakeHR(fixtures.testSession(4), [
        record,
      ], hr: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HrPerformanceDetail(
              session: fixtures.testSession(4),
              record: HrPerformanceRecord.fromJson(record),
              service: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('HR 通过'), findsOneWidget);
      expect(find.text('本部门全部通过'), findsNothing);
    },
  );
  testWidgets(
    'forward sends selected people only after explicit confirmation',
    (tester) async {
      final a = fixtures.sample(id: 1, name: '员工甲', stage: 'hr', draft: true);
      (a['snapshot'] as Map)['total'] = 90;
      final b = fixtures.sample(id: 2, name: '员工乙', stage: 'hr', draft: true);
      (b['snapshot'] as Map)['total'] = 90;
      final service = StrictLegacyService(fixtures.testSession(4), [a, b]);
      final conversations = fixtures.FakeConversations();
      await fixtures.mount(tester, 1200, service, conversations: conversations);
      await tester.tap(find.text('转发'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('员工甲').last);
      await tester.tap(find.text('员工乙').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('人事测试会话'));
      await tester.pumpAndSettle();
      expect(conversations.sentPayload, isNull);
      expect(find.textContaining('包含分数、等级和系数'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hr-confirm-action')));
      await tester.pumpAndSettle();
      expect((conversations.sentPayload?['rows'] as List).first['total'], 90);
      expect(conversations.sentTo, 77);
      expect(
        conversations.sentPayload?['hrPerformanceReadOnlySummary'],
        isTrue,
      );
      expect((conversations.sentPayload?['rows'] as List).length, 2);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'forwards from an empty stage filter while omitting scores the viewer cannot see',
    (tester) async {
      final raw = fixtures.sample(
        id: 1,
        name: '员工甲',
        stage: 'opening',
        draft: false,
      );
      (raw['snapshot'] as Map)['total'] = 90;
      final service = StrictLegacyService(fixtures.testSession(4), [raw]);
      final conversations = fixtures.FakeConversations();
      await fixtures.mount(tester, 1200, service, conversations: conversations);
      for (final stage in [
        'opening',
        'indicators',
        'self',
        'review',
        'calibration',
        'hr',
        'ready_final',
        'final',
        'result',
        'interview',
        'archived',
        'exempt',
      ]) {
        expect(find.byKey(ValueKey('hr-stage-$stage')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('hr-stage-final')));
      await tester.pumpAndSettle();
      expect(find.text('员工甲'), findsNothing);
      await tester.tap(find.text('转发'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('员工甲').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('人事测试会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hr-confirm-action')));
      await tester.pumpAndSettle();
      final sent = (conversations.sentPayload?['rows'] as List).single as Map;
      expect(sent['stage'], 'opening');
      expect(sent.containsKey('total'), isFalse);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
