import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_service.dart';
import 'package:dunes_app/features/hr_performance/native_hr_performance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = AuthSession(
  phone: '13800138000',
  userId: 1,
  token: 'test',
  apiBase: 'https://example.com/api/v1',
  roles: [],
);

class _Service extends HrPerformanceService {
  _Service() : super(_session);
  @override
  Future<HrPerformanceAccess> access() async =>
      const HrPerformanceAccess(team: true);
  @override
  Future<List<HrPerformanceRecord>> records(
    String month,
    String scope,
  ) async => [
    HrPerformanceRecord.fromJson({
      'id': 1,
      'userId': 1,
      'month': month,
      'stage': 'indicators',
      'adjustmentDueAt': '2026-11-04T23:59:59+08:00',
      'snapshot': {
        'name': '测试员工', 'departmentName': '研发部', 'positionName': '工程师',
        'templateName': '技术模板', 'probation': true, 'blockers': <String>[],
        // Even an incorrectly populated response must not render draft scores.
        'total': 88.8, 'grade': '草稿等级', 'coefficient': 9.9,
        'lines': [
          {
            'indicatorId': 'target',
            'name': '目标完成度',
            'weight': 100,
            'score': 88.8,
          },
        ],
        'evidence': [
          {'id': 9, 'title': '已完成任务证据', 'completedAt': '2026-10-20T08:00:00Z'},
        ],
      },
    }),
  ];
  @override
  Future<List<Map<String, dynamic>>> logs(int id) async => [];
  @override
  Future<List<Map<String, dynamic>>> alerts() async => [];
  @override
  Future<Map<String, dynamic>> options(int id) async => {
    'config': {
      'rules': {},
      'indicators': [],
      'templates': [],
      'adjustmentItems': [],
      'exemptionReasons': ['其他'],
    },
    'tasks': [],
    'missingTaskIds': [],
  };
}

class _HrStartService extends _Service {
  List<int>? startedRecords;

  @override
  Future<HrPerformanceAccess> access() async =>
      const HrPerformanceAccess(allowed: true, hr: true, all: true);

  @override
  Future<({bool started, bool canStart, bool supportsBatch})> monthStatus(
    String month,
  ) async => (started: true, canStart: true, supportsBatch: true);

  @override
  Future<List<HrPerformanceRecord>> records(String month, String scope) async =>
      [
        HrPerformanceRecord.fromJson({
          'id': 42,
          'userId': 2,
          'month': month,
          'stage': 'indicators',
          'startedAt': null,
          'snapshot': {'name': '待发起员工', 'departmentName': '研发部'},
        }),
      ];

  @override
  Future<int> startMonth(
    String month, {
    List<int> recordIds = const [],
    List<int> departmentIds = const [],
  }) async {
    startedRecords = recordIds;
    return recordIds.length;
  }
}

void main() {
  test('数字化解决方案中心及其下级不纳入考核', () {
    const parents = <int, int?>{2: 1, 3: 1, 5: 4};
    const names = <int, String>{1: '数字化解决方案中心', 2: '能源板块', 3: '通信板块', 4: '研发部'};
    expect(
      hrPerformanceDepartmentExcluded(
        departmentId: 3,
        departmentName: '通信板块',
        parents: parents,
        names: names,
      ),
      isTrue,
    );
    expect(
      hrPerformanceDepartmentExcluded(
        departmentId: 1,
        departmentName: '数字化解决方案中心',
        parents: parents,
        names: names,
      ),
      isTrue,
    );
    expect(
      hrPerformanceDepartmentExcluded(
        departmentId: 4,
        departmentName: '研发部',
        parents: parents,
        names: names,
      ),
      isFalse,
    );
  });
  test('new access flags preserve old defaults and session round trip', () {
    expect(_session.hrPerformanceHrAccess, isFalse);
    final session = _session.copyWith(
      hrPerformanceHrAccess: true,
      hrPerformanceFinalAccess: true,
      hrPerformanceFollowupAccess: true,
    );
    final restored = AuthSession.fromJson(session.toJson());
    expect(restored.hrPerformanceHrAccess, isTrue);
    expect(restored.hrPerformanceFinalAccess, isTrue);
    expect(restored.hrPerformanceFollowupAccess, isTrue);
    expect(restored.kpiPerformanceAccess, isFalse);
    expect(restored.kpiFollowupAccess, isFalse);
  });

  testWidgets('首批发起后 HR 仍可发起勾选的人员', (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _HrStartService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeHrPerformancePage(session: _session, service: service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('全员'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始考核'));
    await tester.pumpAndSettle();
    expect(find.text('发起全员考核'), findsOneWidget);
    await tester.tap(find.text('发起已勾选的 1 人'));
    await tester.pumpAndSettle();
    expect(service.startedRecords, isNull);
    await tester.tap(find.text('确认发起'));
    await tester.pumpAndSettle();
    expect(service.startedRecords, [42]);
    await tester.pump(const Duration(seconds: 3));
  });

  for (final width in [360.0, 900.0]) {
    testWidgets(
      'progress and evidence render at width $width without draft scores',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NativeHrPerformancePage(
                session: _session,
                service: _Service(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('我的'), findsOneWidget);
        expect(find.text('团队'), findsOneWidget);
        expect(find.text('全员'), findsNothing);
        if (width < 640) {
          await tester.tap(find.text('测试员工'));
          await tester.pumpAndSettle();
        }
        expect(find.text('已完成任务证据'), findsNothing);
        await tester.ensureVisible(find.text('任务证据（1）'));
        await tester.tap(find.text('任务证据（1）'));
        await tester.pumpAndSettle();
        expect(find.text('已完成任务证据'), findsOneWidget);
        await tester.tap(find.text('任务证据（1）'));
        await tester.pumpAndSettle();
        expect(find.text('已完成任务证据'), findsNothing);
        expect(find.textContaining('88.8'), findsNothing);
        expect(find.textContaining('草稿等级'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
