import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/kpi/kpi_followup.dart';
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

class _FakeFollowupService extends WorkbenchKpiService {
  _FakeFollowupService({this.appeals = const []}) : super(session: _session);

  String? lastMonth;
  final List<KpiAppeal> appeals;
  int closeCount = 0;

  @override
  Future<WorkProfileKpiScore> fetchScore({
    required String month,
    int userId = 0,
  }) async {
    return WorkProfileKpiScore(month: month, prevMonth: '2026-07');
  }

  @override
  Future<KpiFollowupBoard> fetchFollowup({required String month}) async {
    lastMonth = month;
    return const KpiFollowupBoard(
      month: '2026-08',
      summary: KpiFollowupCounts(
        expected: 5,
        scored: 4,
        unscored: 1,
        unpublished: 1,
        publishedUnacked: 1,
        acked: 1,
      ),
      sectors: [
        KpiFollowupSector(
          key: 'telecom',
          name: '运营商',
          summary: KpiFollowupCounts(expected: 1, scored: 1),
          groups: [
            KpiFollowupGroup(
              name: '运营商',
              track: 'lighthouse',
              expected: 1,
              scored: 1,
              projectScore: 88,
            ),
          ],
          leaders: [
            KpiFollowupLeader(
              userName: '王一凡',
              done: true,
              expected: 1,
              scored: 1,
            ),
          ],
        ),
        KpiFollowupSector(
          key: 'rd',
          name: '研发',
          summary: KpiFollowupCounts(
            expected: 2,
            scored: 1,
            unscored: 1,
            unpublished: 1,
          ),
          groups: [
            KpiFollowupGroup(
              name: '研发',
              track: 'rubric',
              expected: 2,
              scored: 1,
              unscored: 1,
              unscoredNames: ['未打分甲'],
            ),
          ],
          leaders: [
            KpiFollowupLeader(
              userId: 10,
              userName: '雷江华',
              expected: 2,
              scored: 1,
              unscored: 1,
              unscoredNames: ['未打分甲'],
            ),
          ],
          members: KpiFollowupMembers(
            unpublished: [
              KpiFollowupPerson(
                userId: 2,
                userName: '已评未发乙',
                departmentName: '出行',
              ),
            ],
          ),
        ),
        KpiFollowupSector(
          key: 'office',
          name: '职能',
          summary: KpiFollowupCounts(
            expected: 2,
            scored: 2,
            publishedUnacked: 1,
            acked: 1,
          ),
          groups: [
            KpiFollowupGroup(
              name: '行政',
              track: 'rubric',
              expected: 2,
              scored: 2,
              projectScore: 1,
            ),
          ],
          leaders: [
            KpiFollowupLeader(
              userId: 11,
              userName: '朱子姝',
              done: true,
              expected: 2,
              scored: 2,
            ),
          ],
          members: KpiFollowupMembers(
            publishedUnacked: [
              KpiFollowupPerson(
                userId: 3,
                userName: '待确认丙',
                supervisorName: '朱子姝',
              ),
            ],
            acked: [KpiFollowupPerson(userId: 4, userName: '已确认丁')],
          ),
        ),
      ],
    );
  }

  @override
  Future<List<KpiAppeal>> listAppeals({
    required String month,
    String status = '',
  }) async {
    return appeals;
  }

  @override
  Future<KpiAppeal> closeAppeal(int id) async {
    closeCount++;
    return KpiAppeal(id: id, status: 'done');
  }
}

void main() {
  testWidgets('月度绩效考评里的催办按运营商能源研发职能分割', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FakeFollowupService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeWorkbenchKpiPage(
            session: _session,
            service: service,
            now: DateTime(2026, 9, 16),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('人事催办台'), findsNothing);
    expect(find.byKey(const Key('kpi-lens-followup')), findsOneWidget);
    await tester.tap(find.byKey(const Key('kpi-lens-followup')));
    await tester.pumpAndSettle();

    expect(service.lastMonth, '2026-08');
    expect(find.text('运营商'), findsWidgets);
    expect(find.text('研发'), findsWidgets);
    expect(find.text('职能'), findsWidgets);
    expect(find.byKey(const Key('kpi-followup-group-运营商')), findsOneWidget);
    expect(find.byKey(const Key('kpi-followup-group-研发')), findsOneWidget);
    expect(find.byKey(const Key('kpi-followup-group-行政')), findsOneWidget);
    expect(find.text('灯塔自动算分，不用催领导打量表'), findsOneWidget);
    expect(find.byKey(const Key('kpi-followup-pipeline')), findsOneWidget);
    expect(find.textContaining('项目绩效系数'), findsNWidgets(2));
    expect(find.byKey(const Key('kpi-followup-leader-雷江华')), findsOneWidget);

    await tester.tap(find.byKey(const Key('kpi-sector-rd')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kpi-followup-group-研发')), findsOneWidget);
    expect(find.byKey(const Key('kpi-followup-group-运营商')), findsNothing);
    expect(find.byKey(const Key('kpi-followup-group-行政')), findsNothing);
    expect(find.byKey(const Key('kpi-followup-member-已评未发乙')), findsOneWidget);

    await tester.tap(find.byKey(const Key('kpi-sector-office')));
    await tester.pumpAndSettle();
    expect(find.textContaining('项目绩效系数 1.0'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kpi-followup-tab-unacked')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kpi-followup-member-待确认丙')), findsOneWidget);
  });

  testWidgets('催办台列出待处理的绩效申诉', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FakeFollowupService(
      appeals: const [
        KpiAppeal(
          id: 8,
          month: '2026-08',
          userId: 2,
          userName: '李四',
          departmentName: '能源',
          kind: 'data',
          comment: '中石油利润不该计入',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeWorkbenchKpiPage(
            session: _session,
            service: service,
            now: DateTime(2026, 9, 16),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kpi-lens-followup')));
    await tester.pumpAndSettle();
    expect(find.text('待处理申诉'), findsOneWidget);
    expect(find.text('中石油利润不该计入'), findsOneWidget);
    expect(find.text('绩效数据'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kpi-followup-appeal-done-8')));
    await tester.pumpAndSettle();
    expect(service.closeCount, 1);
    expect(find.text('待处理申诉'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });
}
