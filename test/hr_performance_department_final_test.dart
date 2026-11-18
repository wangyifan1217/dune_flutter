import 'package:dunes_app/features/hr_performance/hr_performance_department_final.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_detail.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_service.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'hr_performance_workflow_test.dart' as fixtures;

class FinalService extends fixtures.FakeHR {
  FinalService()
    : super(fixtures.testSession(99), [
        {
          ...fixtures.sample(
            id: 1,
            name: '甲',
            stage: 'final',
            draft: true,
            actions: ['approve_final', 'reject_final'],
          ),
          'departmentId': 1,
        },
        {
          ...fixtures.sample(
            id: 2,
            name: '乙',
            stage: 'final',
            draft: true,
            actions: ['approve_final', 'reject_final'],
          ),
          'departmentId': 1,
        },
        {
          ...fixtures.sample(
            id: 3,
            name: '其他部门',
            stage: 'final',
            draft: true,
            actions: ['approve_final'],
          ),
          'departmentId': 2,
        },
        {
          ...fixtures.sample(id: 4, name: '尚未终审', stage: 'hr'),
          'departmentId': 1,
        },
      ]);
  List<int> approved = [];
  @override
  Future<HrPerformanceAccess> access() async =>
      const HrPerformanceAccess(allowed: true, all: true, finalAccess: true);
  @override
  Future<HrPerformanceRecord> detail(int id) async =>
      HrPerformanceRecord.fromJson(rows.firstWhere((r) => r['id'] == id));
  @override
  Future<HrPerformanceRecord> action(
    HrPerformanceRecord record,
    Map<String, dynamic> command,
  ) async {
    lastCommand = command;
    final index = rows.indexWhere((r) => r['id'] == record.id);
    rows[index] = {...rows[index], 'stage': 'review', 'actions': <String>[]};
    return HrPerformanceRecord.fromJson(rows[index]);
  }

  @override
  Future<List<Map<String, dynamic>>> batch(
    List<HrPerformanceRecord> records,
    String action,
    String reason,
  ) async {
    approved = records.map((r) => r.id).toList();
    return [
      for (final r in records) {'id': r.id, 'success': true},
    ];
  }
}

class HistoryService extends FinalService {
  HistoryService() {
    for (var i = 0; i < 2; i++) {
      rows[i] = {
        ...rows[i],
        'snapshot': {
          ...Map<String, dynamic>.from(rows[i]['snapshot'] as Map),
          'total': i == 0 ? 85.0 : 90.0,
        },
      };
    }
  }
  @override
  Future<List<Map<String, dynamic>>> logs(int id) async => [
    {
      'action': 'submit_review',
      'after': {
        'snapshot': {'total': id == 1 ? 85.0 : 80.0},
      },
    },
  ];
}

class ResultPolicyService extends fixtures.FakeHR {
  ResultPolicyService(super.session, super.rows, this.autoConfirm);
  final bool? autoConfirm;
  @override
  Future<Map<String, dynamic>> options(int id) async {
    final data = await super.options(id);
    final config = Map<String, dynamic>.from(data['config'] as Map);
    final rules = Map<String, dynamic>.from(config['rules'] as Map);
    if (autoConfirm != null) rules['autoConfirm'] = autoConfirm;
    return {
      ...data,
      'config': {...config, 'rules': rules},
    };
  }
}

void main() {
  testWidgets('self review uses self review submit label', (tester) async {
    final record = HrPerformanceRecord.fromJson(
      fixtures.sample(stage: 'self', actions: ['submit_self']),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showHrScoreSheet(
                context,
                record,
                {
                  'rules': {'decimalPlaces': 1},
                },
                title: '提交自评',
                initial: true,
                self: true,
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
      find.descendant(
        of: find.byKey(const ValueKey('hr-sheet-submit')),
        matching: find.text('提交自评'),
      ),
      findsOneWidget,
    );
    expect(find.text('提交初评'), findsNothing);
  });

  for (final auto in [true, false, null]) {
    testWidgets('result confirmation uses period rule $auto', (tester) async {
      final data = fixtures.sample(
        stage: 'result',
        actions: ['confirm_result'],
      );
      final snapshot = Map<String, dynamic>.from(data['snapshot'] as Map);
      data['snapshot'] = {
        ...snapshot,
        'total': 88,
        'grade': 'A',
        'coefficient': 1.1,
        'workflow': {
          'dueAt': '2026-11-20T10:00:00Z',
          'requests': [],
          'bonuses': [],
        },
      };
      final service = ResultPolicyService(fixtures.testSession(1), [
        data,
      ], auto);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HrPerformanceDetail(
              session: service.session,
              service: service,
              record: HrPerformanceRecord.fromJson(data),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final hint = tester
          .widget<Text>(
            find.byKey(const ValueKey('hr-result-confirmation-policy')),
          )
          .data!;
      expect(hint, contains('2026-11-20 18:00（北京时间）'));
      expect(
        hint,
        contains(
          auto == true
              ? '系统会自动确认结果'
              : auto == false
              ? '到期后不会自动确认'
              : '逾期处理规则暂不可用',
        ),
      );
    });
  }

  testWidgets('pending appeal pauses automatic confirmation', (tester) async {
    final data = fixtures.sample(stage: 'result');
    final snapshot = Map<String, dynamic>.from(data['snapshot'] as Map);
    data['snapshot'] = {
      ...snapshot,
      'total': 88,
      'workflow': {
        'dueAt': '2026-11-20T10:00:00Z',
        'requests': [
          {'kind': 'appeal', 'status': 'pending', 'id': 'a1', 'reason': '核对'},
        ],
        'bonuses': [],
      },
    };
    final service = ResultPolicyService(fixtures.testSession(1), [data], true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HrPerformanceDetail(
            session: service.session,
            service: service,
            record: HrPerformanceRecord.fromJson(data),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('当前申诉处理中，自动确认暂缓'), findsOneWidget);
  });

  testWidgets(
    'department counts all stages and separates people outside permission',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FinalService();
      service.rows.addAll([
        {
          ...fixtures.sample(id: 5, userId: 5, name: '免考核', stage: 'exempt'),
          'departmentId': 1,
        },
        {
          ...fixtures.sample(id: 6, userId: 6, name: '已下发', stage: 'result'),
          'departmentId': 1,
        },
        {
          ...fixtures.sample(id: 7, userId: 99, name: '本人', stage: 'final'),
          'departmentId': 1,
        },
        {
          ...fixtures.sample(id: 8, userId: 8, name: '离职', stage: 'archived'),
          'departmentId': 1,
          'snapshot': {
            ...(fixtures.sample()['snapshot'] as Map),
            'workflow': {
              'archiveReason': '离职未确认',
              'requests': [],
              'bonuses': [],
            },
          },
        },
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHrDepartmentFinal(context, service, 1),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.textContaining('本部门考核记录 7 人'), findsOneWidget);
      for (final label in [
        '前序环节 1',
        '待终审（可办理） 2',
        '待终审（其他） 1',
        '已下发 1',
        '免考核 1',
        '其他归档 1',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'score entry immediately explains invalid scores and required remarks',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final row = fixtures.sample(stage: 'review', draft: true);
      final record = HrPerformanceRecord.fromJson(row);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHrScoreSheet(
                  context,
                  record,
                  {
                    'rules': {'decimalPlaces': 1, 'remarkBelow': 60},
                  },
                  title: '主管初评',
                  initial: true,
                ),
                child: const Text('评分'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('评分'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('hr-score-target')),
        '101',
      );
      await tester.pump();
      expect(find.text('请输入 0–100.0 的得分'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('hr-score-target')),
        '50',
      );
      await tester.pump();
      expect(find.text('评分备注（必填）'), findsOneWidget);
      expect(find.textContaining('0 项已填写完整'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changed initial score is shown first in department preview', (
    tester,
  ) async {
    final service = HistoryService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showHrDepartmentFinal(context, service, 1),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.textContaining('初评 80.0 分 · +10.0 分'), findsOneWidget);
    expect(find.textContaining('与初评一致'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('乙')).dy,
      lessThan(tester.getTopLeft(find.text('甲')).dy),
    );
  });

  testWidgets(
    'individual final approval confirms without resubmitting scores',
    (tester) async {
      final row = fixtures.sample(
        stage: 'final',
        actions: ['approve_final'],
        draft: true,
      );
      final service = fixtures.FakeHR(fixtures.testSession(99), [
        row,
      ], hr: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HrPerformanceDetail(
              session: service.session,
              service: service,
              record: HrPerformanceRecord.fromJson(row),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('终审通过并下发'));
      await tester.pumpAndSettle();
      expect(find.text('确认终审通过'), findsOneWidget);
      expect(find.byKey(const ValueKey('hr-score-target')), findsNothing);
      await tester.tap(find.text('确认通过并下发'));
      await tester.pumpAndSettle();
      expect(service.lastCommand?['action'], 'approve_final');
      expect(service.lastCommand?.containsKey('lines'), isFalse);
      await tester.pump(const Duration(seconds: 3));
    },
  );
  testWidgets(
    'department preview rejects one person and approves remaining people',
    (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FinalService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHrDepartmentFinal(context, service, 1),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('甲'), findsOneWidget);
      expect(find.text('乙'), findsOneWidget);
      expect(find.text('其他部门'), findsNothing);
      expect(find.text('尚未终审'), findsNothing);
      await tester.tap(find.text('驳回').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '需要重新评分');
      await tester.tap(find.byKey(const ValueKey('hr-sheet-submit')));
      await tester.pumpAndSettle();
      expect(service.lastCommand?['action'], 'reject_final');
      expect(service.lastCommand?['reason'], '需要重新评分');
      expect(find.text('甲'), findsNothing);
      await tester.tap(find.text('部门通过并下发'));
      await tester.pumpAndSettle();
      expect(find.textContaining('当前列表中的 1 人'), findsOneWidget);
      await tester.tap(find.text('确认通过并下发'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(service.approved, [2]);
      expect(find.text('已通过并下发 1 人'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
