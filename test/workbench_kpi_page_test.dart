import 'dart:typed_data';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/kpi/native_workbench_kpi_page.dart';
import 'package:dunes_app/features/kpi/workbench_kpi_service.dart';
import 'package:dunes_app/features/profile/work_profile_kpi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = AuthSession(
  phone: '13800000000',
  userId: 1,
  token: '',
  apiBase: '',
  roles: <String>[],
  kpiPerformanceAccess: true,
);

class _FakeKpiService extends WorkbenchKpiService {
  _FakeKpiService() : super(session: _session);

  List<WorkbenchKpiTask> tasks = const [
    WorkbenchKpiTask(
      id: 1,
      userId: 9,
      userName: '李四',
      name: '中石油',
      province: '广东',
    ),
  ];
  int deleteCount = 0;
  int createCount = 0;
  int rerunCount = 0;
  int exportCount = 0;

  @override
  Future<List<WorkbenchKpiTask>> listTasks({
    String q = '',
    bool countedOnly = false,
  }) async {
    return tasks;
  }

  @override
  Future<WorkbenchKpiTask> createTask(WorkbenchKpiTask draft) async {
    createCount++;
    return draft.copyWith(id: 2);
  }

  @override
  Future<void> deleteTask(int id) async {
    deleteCount++;
    tasks = tasks.where((e) => e.id != id).toList();
  }

  @override
  Future<WorkProfileKpiScore> rerunScore(String month) async {
    rerunCount++;
    return WorkProfileKpiScore(
      month: month,
      prevMonth: '2026-07',
      people: const [
        WorkProfileKpiPerson(
          userId: 9,
          userName: '李四',
          mainScore: 88,
          bonus: 0,
          telecomWeight: 1,
          energyWeight: 0,
          telecomScore: 88,
          energyScore: 0,
        ),
      ],
    );
  }

  @override
  Future<Uint8List> exportScore(String month) async {
    exportCount++;
    return Uint8List.fromList([1, 2, 3]);
  }

  int fetchCount = 0;
  int saveCount = 0;
  List<WorkbenchKpiOverrideItem>? lastItems;

  WorkProfileKpiScore _personScore(String month) {
    return WorkProfileKpiScore(
      month: month,
      prevMonth: '2026-07',
      people: const [
        WorkProfileKpiPerson(
          userId: 9,
          userName: '李四',
          mainScore: 88,
          bonus: 0,
          telecomWeight: 0,
          energyWeight: 1,
          telecomScore: 0,
          energyScore: 88,
          categories: [
            WorkProfileKpiCategory(
              category: 'energy',
              categoryLabel: '能源',
              categoryWeight: 1,
              score: 88,
              tasks: [
                WorkProfileKpiTask(
                  taskId: 1,
                  taskName: '中石油',
                  province: '广东',
                  bucketLabel: '能源',
                  weightPct: 70,
                  autoWeightPct: 70,
                  taskTotal: 88,
                  curRevenue: 70,
                  prevRevenue: 60,
                  curProfit: 10,
                  prevProfit: 9,
                ),
                WorkProfileKpiTask(
                  taskId: 2,
                  taskName: '多渠道',
                  province: '广东',
                  bucketLabel: '能源',
                  weightPct: 30,
                  autoWeightPct: 30,
                  taskTotal: 80,
                  curRevenue: 30,
                  prevRevenue: 40,
                  curProfit: 4,
                  prevProfit: 5,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<WorkProfileKpiScore> fetchScore({
    required String month,
    int userId = 0,
  }) async {
    fetchCount++;
    return _personScore(month);
  }

  @override
  Future<WorkProfileKpiScore> saveOverrides({
    required String month,
    required int userId,
    required List<WorkbenchKpiOverrideItem> items,
  }) async {
    saveCount++;
    lastItems = items;
    return _personScore(month);
  }
}

void main() {
  testWidgets('delete requires a second confirmation', (tester) async {
    final service = _FakeKpiService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeWorkbenchKpiPage(
            session: _session,
            service: service,
            now: DateTime(2026, 9, 3),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('中石油'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kpi-delete-1')));
    await tester.pumpAndSettle();
    expect(find.text('确认删除任务？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.deleteCount, 0);
    expect(find.text('中石油'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kpi-delete-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kpi-confirm-ok')));
    await tester.pump();
    expect(service.deleteCount, 1);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('rerun and export require confirmation', (tester) async {
    final service = _FakeKpiService();
    String? savedName;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeWorkbenchKpiPage(
            session: _session,
            service: service,
            now: DateTime(2026, 9, 3),
            saveExport: (bytes, name) async {
              savedName = name;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('kpi-rerun')));
    await tester.pumpAndSettle();
    expect(find.text('确认重跑绩效？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.rerunCount, 0);

    await tester.tap(find.byKey(const Key('kpi-rerun')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kpi-confirm-ok')));
    await tester.pump();
    expect(service.rerunCount, 1);
    expect(find.textContaining('绩效结果'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kpi-export')));
    await tester.pumpAndSettle();
    expect(find.text('确认导出绩效？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kpi-confirm-ok')));
    await tester.pump();
    expect(service.exportCount, 1);
    expect(savedName, '业务绩效-2026-08.xlsx');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('fits a phone-sized APP viewport without overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FakeKpiService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeWorkbenchKpiPage(
            session: _session,
            service: service,
            now: DateTime(2026, 9, 3),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('中石油'), findsOneWidget);
    expect(find.byKey(const Key('kpi-rerun')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('monthly detail save requires a second confirmation', (tester) async {
    final service = _FakeKpiService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeWorkbenchKpiPage(
            session: _session,
            service: service,
            now: DateTime(2026, 9, 3),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('kpi-detail-9')));
    await tester.pumpAndSettle();
    expect(service.fetchCount, 1);
    expect(find.textContaining('李四 · 2026年8月'), findsOneWidget);
    expect(find.byKey(const Key('kpi-detail-save')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('kpi-weight-1')), '80');
    await tester.enterText(find.byKey(const Key('kpi-adj-1')), '5');
    await tester.enterText(find.byKey(const Key('kpi-remark-1')), '下调中石油占比');
    await tester.ensureVisible(find.byKey(const Key('kpi-detail-save')));
    await tester.tap(find.byKey(const Key('kpi-detail-save')));
    await tester.pumpAndSettle();
    expect(find.text('确认变更绩效？'), findsOneWidget);
    expect(find.textContaining('70.00% → 80.00%'), findsOneWidget);
    expect(find.textContaining('加减分 +5'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.saveCount, 0);

    await tester.ensureVisible(find.byKey(const Key('kpi-detail-save')));
    await tester.tap(find.byKey(const Key('kpi-detail-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kpi-confirm-ok')));
    await tester.pump();
    expect(service.saveCount, 1);
    expect(service.lastItems, isNotNull);
    expect(service.lastItems!.single.taskId, 1);
    expect(service.lastItems!.single.weightPct, 80);
    expect(service.lastItems!.single.scoreAdj, 5);
    expect(service.lastItems!.single.remark, '下调中石油占比');
    await tester.pump(const Duration(seconds: 3));
  });
}
