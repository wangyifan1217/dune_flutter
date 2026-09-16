import 'dart:typed_data';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/kpi/native_workbench_kpi_page.dart';
import 'package:dunes_app/features/kpi/kpi_followup.dart';
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
    WorkbenchKpiTask(
      id: 3,
      userId: 9,
      userName: '李四',
      name: '不计项目',
      province: '广东',
      isCounted: false,
    ),
  ];
  bool lastCountedOnly = false;
  int deleteCount = 0;
  int createCount = 0;
  int rerunCount = 0;
  int exportCount = 0;

  @override
  Future<List<WorkbenchKpiTask>> listTasks({
    String q = '',
    bool countedOnly = false,
  }) async {
    lastCountedOnly = countedOnly;
    if (countedOnly) {
      return tasks.where((task) => task.isCounted).toList(growable: false);
    }
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
                  productName: '中石油',
                  productGroup: '能源',
                  channelName: '平安',
                  bucketLabel: '能源板块',
                  weightPct: 70,
                  autoWeightPct: 70,
                  taskTotal: 88,
                  curRevenue: 70,
                  prevRevenue: 60,
                  curProfit: 10,
                  prevProfit: 9,
                  matchSummary: '产品=中石油；渠道L1=平安',
                ),
                WorkProfileKpiTask(
                  taskId: 2,
                  taskName: '多渠道',
                  province: '广东',
                  channelName: '多渠道',
                  bucketLabel: '能源',
                  weightPct: 30,
                  autoWeightPct: 30,
                  taskTotal: 80,
                  curRevenue: 30,
                  prevRevenue: 40,
                  curProfit: 4,
                  prevProfit: 5,
                  matchSummary: '渠道L1=多渠道',
                ),
              ],
            ),
          ],
        ),
      ],
      teams: const [
        WorkProfileKpiTeam(
          departmentId: 0,
          departmentName: '能源',
          projectScore: 81,
          coefficient: 0.9,
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
  Future<KpiFollowupBoard> fetchFollowup({required String month}) async {
    return KpiFollowupBoard(month: month);
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

  List<WorkbenchKpiRubricItem>? lastRubricItems;
  int saveRubricCount = 0;

  @override
  Future<WorkProfileKpiScore> saveRubricScore({
    required String month,
    required int userId,
    required List<WorkbenchKpiRubricItem> items,
  }) async {
    saveRubricCount++;
    lastRubricItems = items;
    return _personScore(month);
  }

  int importCount = 0;

  @override
  Future<WorkbenchKpiRubricImportResult> importRubricScore({
    required String month,
    required List<int> bytes,
    required String fileName,
  }) async {
    importCount++;
    return WorkbenchKpiRubricImportResult(
      month: month,
      imported: 2,
      people: const ['朱子姝 已导入', '王奕凡 已导入'],
      teamHint: 'AI研发 项目绩效系数 1.0（项目得分 9）',
    );
  }

  @override
  Future<WorkProfileKpiScore> ackRubricScore({required String month}) async {
    return fetchScore(month: month);
  }

  int publishCount = 0;
  List<int>? lastPublishIds;

  @override
  Future<WorkbenchKpiRubricPublishResult> publishRubricScore({
    required String month,
    required List<int> userIds,
  }) async {
    publishCount++;
    lastPublishIds = userIds;
    return WorkbenchKpiRubricPublishResult(
      month: month,
      notified: userIds.length,
    );
  }
}

void main() {
  testWidgets(
    'opens person detail from the roster table without listing rules below',
    (tester) async {
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
      expect(find.text('中石油'), findsNothing);
      expect(find.textContaining('条规则'), findsNothing);
      expect(find.byKey(const Key('kpi-person-9')), findsOneWidget);
      await tester.tap(find.byKey(const Key('kpi-person-9')));
      await tester.pumpAndSettle();
      expect(find.text('中石油'), findsOneWidget);
      expect(find.text('广东 · 平安'), findsOneWidget);
      expect(find.text('多渠道'), findsOneWidget);
      expect(find.textContaining('1. 李四 · 2026年8月'), findsOneWidget);
      expect(find.textContaining('良（达到预期）'), findsAtLeastNWidgets(1));
      expect(find.text('产品=中石油；渠道L1=平安'), findsNothing);
      expect(find.text('渠道L1=多渠道'), findsNothing);
      expect(find.text('仅计入'), findsNothing);
      expect(find.byKey(const Key('kpi-add')), findsNothing);
      expect(find.byTooltip('删除'), findsNothing);
      expect(find.byTooltip('编辑'), findsNothing);
    },
  );

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
    expect(find.textContaining('良（达到预期）'), findsAtLeastNWidgets(1));

    await tester.tap(find.byKey(const Key('kpi-export')));
    await tester.pumpAndSettle();
    expect(find.text('确认导出绩效？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kpi-confirm-ok')));
    await tester.pump();
    expect(service.exportCount, 1);
    expect(savedName, '月度绩效考评-2026-08.xlsx');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('fits a phone-sized APP viewport without overflow', (
    tester,
  ) async {
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
    expect(find.byKey(const Key('kpi-person-9')), findsOneWidget);
    expect(find.byKey(const Key('kpi-rerun')), findsOneWidget);
    expect(find.byKey(const Key('kpi-summary')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('kpi-person-9')));
    await tester.tap(find.byKey(const Key('kpi-person-9')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1. 李四 · 2026年8月'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('monthly detail save requires a second confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
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

    await tester.tap(find.byKey(const Key('kpi-person-9')));
    await tester.pumpAndSettle();
    expect(service.fetchCount, 2);
    expect(find.textContaining('1. 李四 · 2026年8月'), findsOneWidget);
    expect(find.byKey(const Key('kpi-detail-save')), findsOneWidget);

    // 权重/加减分/备注默认收起，点「调整」才展开。
    expect(find.byKey(const Key('kpi-weight-1')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('kpi-edit-1')));
    await tester.tap(find.byKey(const Key('kpi-edit-1')));
    await tester.pumpAndSettle();
    expect(find.text('权重'), findsOneWidget);
    expect(find.text('加减分'), findsWidgets);

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

  testWidgets('shows markdown summary and forwards it to IM', (tester) async {
    final service = _FakeKpiService();
    var picked = 0;
    var sentId = 0;
    var sentMd = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeWorkbenchKpiPage(
            session: _session,
            service: service,
            now: DateTime(2026, 9, 3),
            pickConversation: () async {
              picked++;
              return 42;
            },
            sendMarkdown: (id, markdown) async {
              sentId = id;
              sentMd = markdown;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kpi-summary')), findsOneWidget);
    expect(find.textContaining('全部板块 · 共'), findsOneWidget);
    expect(find.text('转发到 IM'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kpi-summary-forward')));
    await tester.pump();
    expect(picked, 1);
    expect(sentId, 42);
    expect(sentMd, contains('| 能源 | 1. 李四 | — | 88.00 | 良（达到预期） | 1.0 |'));
    expect(find.text('已转发到会话'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('people list defaults to score high to low', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _RankedKpiService();
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
    expect(find.byKey(const Key('kpi-section-none')), findsOneWidget);
    final zhang = tester.getTopLeft(find.text('张三'));
    final li = tester.getTopLeft(find.text('李四'));
    final he = tester.getTopLeft(find.text('何佳伟'));
    expect(zhang.dy, lessThan(li.dy));
    expect(li.dy, lessThan(he.dy));
  });

  testWidgets('sector chips filter the people list', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
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
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(const Key('kpi-lens-sector')), findsNothing);
    expect(find.byKey(const Key('kpi-lens-dept')), findsNothing);
    expect(find.byKey(const Key('kpi-lens-roster')), findsOneWidget);
    expect(find.byKey(const Key('kpi-lens-followup')), findsOneWidget);
    expect(find.byKey(const Key('kpi-sector-telecom')), findsOneWidget);
    expect(find.byKey(const Key('kpi-sector-energy')), findsOneWidget);
    expect(find.byKey(const Key('kpi-sector-office')), findsOneWidget);
    expect(find.text('导出 Excel'), findsOneWidget);
    expect(find.text('导入量表'), findsOneWidget);

    // 李四只有能源板块的任务，切到运营商后不该出现在表里。
    expect(find.byKey(const Key('kpi-person-9')), findsOneWidget);
    await tester.tap(find.byKey(const Key('kpi-sector-telecom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kpi-person-9')), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('kpi-scope-hint'))).data,
      contains('运营商 · 共'),
    );

    await tester.tap(find.byKey(const Key('kpi-sector-energy')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kpi-person-9')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('kpi-scope-hint'))).data,
      contains('能源 · 共'),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('kpi-scope-hint'))).data,
      contains('项目绩效系数 0.9'),
    );
    expect(find.byKey(const Key('kpi-group-filter')), findsNothing);
    expect(find.byKey(const Key('kpi-section-energy')), findsNothing);
    expect(find.byKey(const Key('kpi-project-energy')), findsOneWidget);
    expect(find.text('项目绩效系数'), findsOneWidget);
    expect(find.byKey(const Key('kpi-person-9')), findsOneWidget);
  });

  testWidgets('职能月度绩效分组能看到行政项目分数', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _OfficeKpiService();
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
    await tester.tap(find.byKey(const Key('kpi-sector-office')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kpi-section-行政')), findsOneWidget);
    expect(find.byKey(const Key('kpi-project-行政')), findsOneWidget);
    expect(find.byKey(const Key('kpi-section-财务')), findsOneWidget);
    expect(find.byKey(const Key('kpi-project-财务')), findsOneWidget);
    expect(find.text('项目绩效系数'), findsWidgets);
  });

  testWidgets('mixes AI research rubric people with energy and opens bands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _MixedKpiService();
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
    expect(find.byKey(const Key('kpi-sector-rd')), findsOneWidget);
    expect(find.byKey(const Key('kpi-person-9')), findsOneWidget);
    expect(find.byKey(const Key('kpi-person-2')), findsOneWidget);
    expect(find.textContaining('共 3 人'), findsOneWidget);
    expect(find.byKey(const Key('kpi-section-energy')), findsOneWidget);
    expect(find.byKey(const Key('kpi-section-rd')), findsOneWidget);

    await tester.tap(find.byKey(const Key('kpi-sector-rd')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kpi-person-9')), findsNothing);
    expect(find.byKey(const Key('kpi-person-2')), findsOneWidget);
    expect(find.textContaining('共 2 人'), findsOneWidget);
    expect(find.textContaining('研发 · 共 2 人'), findsOneWidget);
    expect(find.byKey(const Key('kpi-section-rd')), findsNothing);
    expect(find.byKey(const Key('kpi-group-filter')), findsOneWidget);
    expect(find.byKey(const Key('kpi-group-AI研发')), findsOneWidget);
    expect(find.byKey(const Key('kpi-group-出行')), findsOneWidget);
    expect(find.byKey(const Key('kpi-section-AI研发')), findsOneWidget);
    expect(find.byKey(const Key('kpi-section-出行')), findsOneWidget);
    expect(find.byKey(const Key('kpi-project-AI研发')), findsOneWidget);
    expect(find.byKey(const Key('kpi-project-出行')), findsOneWidget);
    expect(find.text('待确认'), findsWidgets);
    expect(find.byKey(const Key('kpi-dept-filter')), findsNothing);

    await tester.tap(find.byKey(const Key('kpi-person-2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('目标完成度'), findsWidgets);
    expect(find.text('目标完成度 · 业绩产出'), findsOneWidget);
    expect(find.textContaining('本月营收'), findsNothing);
    expect(find.text('考核人 朱子姝'), findsOneWidget);
    expect(find.byKey(const Key('kpi-scored-by')), findsOneWidget);
    expect(find.text('27–30分'), findsOneWidget);
    expect(find.textContaining('超额完成所有任务'), findsOneWidget);
    expect(find.textContaining('本月营收'), findsNothing);
    expect(find.byKey(const Key('kpi-rubric-goal')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('kpi-rubric-goal')), '29');
    await tester.tap(find.byKey(const Key('kpi-detail-save')));
    await tester.pumpAndSettle();
    expect(find.text('确认录入量表分？'), findsOneWidget);
    expect(find.textContaining('只写入工作台'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kpi-confirm-ok')));
    await tester.pumpAndSettle();
    expect(service.saveRubricCount, 1);
    expect(service.lastRubricItems, isNotNull);
    expect(service.lastRubricItems!.single.key, 'goal');
    expect(service.lastRubricItems!.single.points, 29);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('imports personal rubric sheets from excel', (tester) async {
    final service = _FakeKpiService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeWorkbenchKpiPage(
            session: _session,
            service: service,
            now: DateTime(2026, 9, 3),
            pickImportFile: () async =>
                (bytes: Uint8List.fromList([1, 2, 3]), name: 'M8.xlsx'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kpi-import')));
    await tester.pumpAndSettle();
    expect(find.text('确认导入量表？'), findsOneWidget);
    expect(find.textContaining('项目绩效得分'), findsOneWidget);
    expect(find.textContaining('不会自动通知员工'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kpi-confirm-ok')));
    await tester.pumpAndSettle();
    expect(service.importCount, 1);
    expect(find.textContaining('已导入 2 人'), findsOneWidget);
    expect(find.textContaining('AI研发 项目绩效系数'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('rubric person confirms own monthly score', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _SelfAckKpiService();
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
    expect(find.byKey(const Key('kpi-ack-status-2')), findsOneWidget);
    expect(find.text('待确认'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kpi-person-2')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('kpi-ack')));
    await tester.tap(find.byKey(const Key('kpi-ack')));
    await tester.pumpAndSettle();
    expect(find.text('确认本月绩效？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kpi-confirm-ok')));
    await tester.pumpAndSettle();
    expect(service.ackCount, 1);
    expect(find.byKey(const Key('kpi-acked')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('publish sends scored rubric people to assistant', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _MixedKpiService();
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
    expect(find.text('发布结果'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kpi-publish')));
    await tester.pumpAndSettle();
    expect(find.text('按项目组发布'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kpi-publish-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kpi-confirm-ok')));
    await tester.pumpAndSettle();
    expect(service.publishCount, 1);
    expect(service.lastPublishIds, [2, 3]);
    expect(find.textContaining('新发布 2 人'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('publish warns when some rubric people are still pending', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _PendingPublishKpiService();
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
    expect(find.text('未发布'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kpi-publish')));
    await tester.pumpAndSettle();
    expect(find.text('按项目组发布'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kpi-publish-group-AI研发')));
    await tester.pumpAndSettle();
    expect(find.textContaining('未评完，这次不发他们'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kpi-confirm-ok')));
    await tester.pumpAndSettle();
    expect(service.lastPublishIds, [2]);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('filters project groups and pins leaders in sector lists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _ProjectGroupKpiService();
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
    expect(find.byKey(const Key('kpi-group-filter')), findsNothing);

    await tester.tap(find.byKey(const Key('kpi-sector-telecom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kpi-group-filter')), findsNothing);
    var shi = tester.getTopLeft(find.text('石淼'));
    var wan = tester.getTopLeft(find.text('万青'));
    expect(shi.dy, lessThan(wan.dy));
    expect(find.text('徐峥'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kpi-sector-energy')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kpi-group-filter')), findsNothing);
    final wang = tester.getTopLeft(find.text('王一凡'));
    final xuan = tester.getTopLeft(find.text('王轩'));
    expect(wang.dy, lessThan(xuan.dy));

    await tester.tap(find.byKey(const Key('kpi-sector-rd')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kpi-group-filter')), findsOneWidget);
    expect(find.byKey(const Key('kpi-group-AI研发')), findsOneWidget);
    expect(find.byKey(const Key('kpi-group-出行')), findsOneWidget);
    expect(find.byKey(const Key('kpi-project-AI研发')), findsOneWidget);
    expect(find.byKey(const Key('kpi-project-出行')), findsOneWidget);
    var zhu = tester.getTopLeft(find.text('朱子姝'));
    var yi = tester.getTopLeft(find.text('王奕凡'));
    expect(zhu.dy, lessThan(yi.dy));
    expect(find.text('雷江华'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kpi-group-出行')));
    await tester.pumpAndSettle();
    expect(find.text('朱子姝'), findsNothing);
    expect(find.text('王奕凡'), findsNothing);
    expect(find.text('雷江华'), findsOneWidget);
    expect(find.byKey(const Key('kpi-project-出行')), findsOneWidget);
    expect(find.byKey(const Key('kpi-project-AI研发')), findsNothing);

    await tester.tap(find.byKey(const Key('kpi-group-AI研发')));
    await tester.pumpAndSettle();
    expect(find.text('雷江华'), findsNothing);
    zhu = tester.getTopLeft(find.text('朱子姝'));
    yi = tester.getTopLeft(find.text('王奕凡'));
    expect(zhu.dy, lessThan(yi.dy));
    expect(find.byKey(const Key('kpi-project-AI研发')), findsOneWidget);
    expect(find.byKey(const Key('kpi-project-出行')), findsNothing);
  });
}

class _RankedKpiService extends _FakeKpiService {
  @override
  Future<WorkProfileKpiScore> fetchScore({
    required String month,
    int userId = 0,
  }) async {
    return WorkProfileKpiScore(
      month: month,
      prevMonth: '2026-07',
      people: const [
        WorkProfileKpiPerson(
          userId: 2,
          userName: '何佳伟',
          mainScore: 47.36,
          bonus: 0,
          telecomWeight: 0,
          energyWeight: 1,
          telecomScore: 0,
          energyScore: 47.36,
        ),
        WorkProfileKpiPerson(
          userId: 3,
          userName: '张三',
          mainScore: 91,
          bonus: 0,
          telecomWeight: 1,
          energyWeight: 0,
          telecomScore: 91,
          energyScore: 0,
        ),
        WorkProfileKpiPerson(
          userId: 1,
          userName: '李四',
          mainScore: 88,
          bonus: 0,
          telecomWeight: 0,
          energyWeight: 1,
          telecomScore: 0,
          energyScore: 88,
        ),
      ],
    );
  }
}

WorkProfileKpiPerson _rubricWang({
  int userId = 2,
  String userName = '王奕凡',
  String departmentName = 'AI研发',
  String position = 'PHP工程师',
  bool pending = false,
  bool canWrite = true,
  bool canAck = false,
  String ackedAt = '',
  bool needsPublish = false,
}) {
  return WorkProfileKpiPerson(
    userId: userId,
    userName: userName,
    departmentName: departmentName,
    position: position,
    mainScore: pending ? 0 : 95,
    bonus: 0,
    telecomWeight: 0,
    energyWeight: 0,
    telecomScore: 0,
    energyScore: 0,
    grade: pending ? '' : '优',
    gradeLabel: pending ? '未评分' : '优（优秀）',
    coefficient: pending ? 0 : 1.1,
    scoreSource: 'rubric',
    scoreStatus: pending ? 'pending' : 'scored',
    canWrite: canWrite,
    scoredByName: pending ? '' : '朱子姝',
    canAck: canAck,
    ackedAt: ackedAt,
    needsPublish: needsPublish,
    categories: [
      WorkProfileKpiCategory(
        category: 'rd',
        categoryLabel: 'AI研发',
        categoryWeight: 1,
        score: pending ? 0 : 95,
        tasks: [
          WorkProfileKpiTask(
            taskId: -11,
            taskName: '目标完成度',
            province: '',
            bucket: 'goal',
            bucketLabel: '业绩产出',
            weightPct: 30,
            taskTotal: pending ? 0 : 30,
            curRevenue: 0,
            prevRevenue: 0,
            curProfit: 0,
            prevProfit: 0,
            metrics: [
              WorkProfileKpiMetric(
                key: 'goal',
                label: '目标完成度',
                status: pending ? 'none' : 'ok',
                kind: 'rubric',
                maxPoints: 30,
                points: pending ? null : 30,
              ),
              const WorkProfileKpiMetric(
                key: 'goal_27_30',
                label: '27–30分',
                status: 'ok',
                kind: 'rubric',
                base: 27,
                maxPoints: 30,
                note: '超额完成所有任务，或主动承担额外工作并出色完成。',
              ),
              const WorkProfileKpiMetric(
                key: 'goal_24_26',
                label: '24–26分',
                status: 'none',
                kind: 'rubric',
                base: 24,
                maxPoints: 26,
                note: '100%按时按量完成所有任务，完成质量高。',
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

WorkProfileKpiPerson _rubricLei() {
  return const WorkProfileKpiPerson(
    userId: 3,
    userName: '雷江华',
    departmentName: '出行',
    position: '产品经理',
    mainScore: 88,
    bonus: 0,
    telecomWeight: 0,
    energyWeight: 0,
    telecomScore: 0,
    energyScore: 0,
    grade: '良',
    gradeLabel: '良（达到预期）',
    coefficient: 1,
    scoreSource: 'rubric',
    scoreStatus: 'scored',
    canWrite: true,
    categories: [
      WorkProfileKpiCategory(
        category: 'rd',
        categoryLabel: '出行',
        categoryWeight: 1,
        score: 88,
        tasks: [
          WorkProfileKpiTask(
            taskId: -21,
            taskName: '目标完成度',
            province: '',
            bucket: 'goal',
            bucketLabel: '业绩产出',
            weightPct: 40,
            taskTotal: 35,
            curRevenue: 0,
            prevRevenue: 0,
            curProfit: 0,
            prevProfit: 0,
          ),
        ],
      ),
    ],
  );
}

class _MixedKpiService extends _FakeKpiService {
  @override
  WorkProfileKpiScore _personScore(String month) {
    return WorkProfileKpiScore(
      month: month,
      prevMonth: '2026-07',
      people: [
        ...super._personScore(month).people,
        _rubricWang(),
        _rubricLei(),
      ],
      teams: [
        ...super._personScore(month).teams,
        const WorkProfileKpiTeam(
          departmentId: 2,
          departmentName: 'AI研发',
          projectScore: 9,
          coefficient: 1,
          memberAvg: 95,
          deptScore: 95,
        ),
        const WorkProfileKpiTeam(
          departmentId: 3,
          departmentName: '出行',
          projectScore: 8.95,
          coefficient: 1,
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
    final all = _personScore(month);
    if (userId <= 0) return all;
    return WorkProfileKpiScore(
      month: all.month,
      prevMonth: all.prevMonth,
      people: all.people.where((p) => p.userId == userId).toList(),
    );
  }

  @override
  Future<WorkProfileKpiScore> saveRubricScore({
    required String month,
    required int userId,
    required List<WorkbenchKpiRubricItem> items,
  }) async {
    saveRubricCount++;
    lastRubricItems = items;
    return fetchScore(month: month, userId: userId);
  }
}

class _SelfAckKpiService extends _FakeKpiService {
  int ackCount = 0;
  bool acked = false;

  @override
  WorkProfileKpiScore _personScore(String month) {
    return WorkProfileKpiScore(
      month: month,
      prevMonth: '2026-07',
      people: [
        _rubricWang(
          canAck: !acked,
          ackedAt: acked ? '2026-09-15T03:00:00Z' : '',
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
  Future<WorkProfileKpiScore> ackRubricScore({required String month}) async {
    ackCount++;
    acked = true;
    return _personScore(month);
  }
}

class _PendingPublishKpiService extends _FakeKpiService {
  @override
  WorkProfileKpiScore _personScore(String month) {
    return WorkProfileKpiScore(
      month: month,
      prevMonth: '2026-07',
      people: [
        _rubricWang(needsPublish: true),
        _rubricWang(userId: 4, userName: '待评', pending: true),
      ],
    );
  }
}

class _OfficeKpiService extends _FakeKpiService {
  @override
  WorkProfileKpiScore _personScore(String month) {
    return WorkProfileKpiScore(
      month: month,
      prevMonth: '2026-07',
      people: [
        _officePerson(
          userId: 33,
          userName: '商羽',
          departmentName: '行政人事部',
          score: 86,
        ),
        _officePerson(
          userId: 34,
          userName: '邓艳丽',
          departmentName: '财务数据中心',
          score: 75,
        ),
      ],
      teams: const [
        WorkProfileKpiTeam(
          departmentId: 8,
          departmentName: '行政人事部',
          projectScore: 1,
          coefficient: 1,
        ),
        WorkProfileKpiTeam(
          departmentId: 9,
          departmentName: '财务数据中心',
          projectScore: 0.7,
          coefficient: 0.7,
        ),
      ],
    );
  }
}

WorkProfileKpiPerson _officePerson({
  required int userId,
  required String userName,
  required String departmentName,
  required double score,
}) {
  return WorkProfileKpiPerson(
    userId: userId,
    userName: userName,
    departmentName: departmentName,
    mainScore: score,
    bonus: 0,
    telecomWeight: 0,
    energyWeight: 0,
    telecomScore: 0,
    energyScore: 0,
    scoreSource: 'rubric',
    scoreStatus: 'scored',
    categories: [
      WorkProfileKpiCategory(
        category: 'office',
        categoryLabel: '职能',
        categoryWeight: 1,
        score: score,
        tasks: [
          WorkProfileKpiTask(
            taskId: -userId,
            taskName: '综合得分',
            province: '',
            bucketLabel: '月度绩效',
            weightPct: 100,
            taskTotal: score,
            curRevenue: 0,
            prevRevenue: 0,
            curProfit: 0,
            prevProfit: 0,
          ),
        ],
      ),
    ],
  );
}

WorkProfileKpiPerson _marketPerson({
  required int id,
  required String name,
  required String sector,
  required String product,
  String channel = '',
  double score = 80,
}) {
  return WorkProfileKpiPerson(
    userId: id,
    userName: name,
    departmentName: sector == 'telecom' ? '通信板块' : '能源板块',
    mainScore: score,
    bonus: 0,
    telecomWeight: sector == 'telecom' ? 1 : 0,
    energyWeight: sector == 'energy' ? 1 : 0,
    telecomScore: sector == 'telecom' ? score : 0,
    energyScore: sector == 'energy' ? score : 0,
    categories: [
      WorkProfileKpiCategory(
        category: sector,
        categoryLabel: sector == 'telecom' ? '运营商' : '能源',
        categoryWeight: 1,
        score: score,
        tasks: [
          WorkProfileKpiTask(
            taskId: id,
            taskName: product,
            province: '全国',
            productName: product,
            productGroup: sector == 'telecom' ? '运营商' : '能源',
            channelName: channel,
            bucketLabel: sector == 'telecom' ? '运营商' : '能源',
            weightPct: 100,
            taskTotal: score,
            curRevenue: 0,
            prevRevenue: 0,
            curProfit: 0,
            prevProfit: 0,
          ),
        ],
      ),
    ],
  );
}

class _ProjectGroupKpiService extends _FakeKpiService {
  @override
  Future<WorkProfileKpiScore> fetchScore({
    required String month,
    int userId = 0,
  }) async {
    return WorkProfileKpiScore(
      month: month,
      prevMonth: '2026-07',
      people: [
        _marketPerson(
          id: 11,
          name: '万青',
          sector: 'telecom',
          product: '小套-出行会员',
          score: 96,
        ),
        _marketPerson(
          id: 12,
          name: '石淼',
          sector: 'telecom',
          product: '小套-出行会员',
          score: 70,
        ),
        _marketPerson(
          id: 13,
          name: '徐峥',
          sector: 'telecom',
          product: '小套-加油会员',
          score: 60,
        ),
        _marketPerson(
          id: 21,
          name: '王轩',
          sector: 'energy',
          product: '中石油现金券',
          score: 99,
        ),
        _marketPerson(
          id: 22,
          name: '王一凡',
          sector: 'energy',
          product: '中石油现金券',
          score: 50,
        ),
        _marketPerson(
          id: 23,
          name: '吕宙',
          sector: 'energy',
          product: '中石油现金券',
          channel: '平安',
          score: 40,
        ),
        _rubricWang(),
        _rubricWang(userId: 31, userName: '朱子姝', position: 'AI应用架构师'),
        _rubricLei(),
      ],
      teams: const [
        WorkProfileKpiTeam(
          departmentId: 2,
          departmentName: 'AI研发',
          projectScore: 9,
          coefficient: 1,
        ),
        WorkProfileKpiTeam(
          departmentId: 3,
          departmentName: '出行',
          projectScore: 8.95,
          coefficient: 1,
        ),
      ],
    );
  }
}
