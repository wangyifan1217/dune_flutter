import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/kpi/kpi_summary_person_sheet.dart';
import 'package:dunes_app/features/profile/work_profile_kpi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = AuthSession(
  phone: '13800000000',
  userId: 1,
  token: '',
  apiBase: '',
  roles: <String>[],
);

WorkProfileKpiScore _yeRuiScore() {
  return const WorkProfileKpiScore(
    month: '2026-08',
    prevMonth: '2026-07',
    people: [
      WorkProfileKpiPerson(
        userId: 11,
        userName: '叶睿',
        departmentName: '行政人事部',
        position: '行政经理',
        mainScore: 86,
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
            score: 86,
            tasks: [
              WorkProfileKpiTask(
                taskId: -1,
                taskName: '工作质量',
                province: '',
                bucketLabel: '职能',
                weightPct: 40,
                taskTotal: 34,
                curRevenue: 0,
                prevRevenue: 0,
                curProfit: 0,
                prevProfit: 0,
                metrics: [
                  WorkProfileKpiMetric(
                    key: 'quality',
                    label: '工作质量',
                    status: 'ok',
                    kind: 'rubric',
                    maxPoints: 40,
                    points: 34,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

void main() {
  testWidgets('点开转发名单后能看到这个人的量表明细，不能改分', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showKpiSummaryPersonSheet(
                    context: context,
                    session: _session,
                    name: '叶睿',
                    month: '2026-08',
                    userId: 11,
                    fetchScore: (month, userId) async {
                      expect(month, '2026-08');
                      expect(userId, 11);
                      return _yeRuiScore();
                    },
                  );
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('叶睿'), findsWidgets);
    expect(find.textContaining('工作质量'), findsWidgets);
    expect(find.text('86.00'), findsWidgets);
    expect(find.byKey(const Key('kpi-detail-save')), findsNothing);
  });

  testWidgets('没有绩效权限时展示失败原因', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showKpiSummaryPersonSheet(
                    context: context,
                    session: _session,
                    name: '叶睿',
                    month: '2026-08',
                    userId: 11,
                    fetchScore: (month, userId) async {
                      throw Exception('需要月度绩效考评权限');
                    },
                  );
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('需要月度绩效考评权限'), findsOneWidget);
  });

  testWidgets('旧转发没有 userId 时按姓名从当月名单里对上', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const other = WorkProfileKpiPerson(
      userId: 99,
      userName: '别人',
      departmentName: '行政人事部',
      mainScore: 70,
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
          score: 70,
          tasks: [
            WorkProfileKpiTask(
              taskId: -2,
              taskName: '别人的指标',
              province: '',
              bucketLabel: '职能',
              weightPct: 40,
              taskTotal: 28,
              curRevenue: 0,
              prevRevenue: 0,
              curProfit: 0,
              prevProfit: 0,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showKpiSummaryPersonSheet(
                    context: context,
                    session: _session,
                    name: '叶睿',
                    month: '2026-08',
                    userId: 0,
                    fetchScore: (month, userId) async {
                      expect(userId, 0);
                      final ye = _yeRuiScore().people.single;
                      return WorkProfileKpiScore(
                        month: '2026-08',
                        prevMonth: '2026-07',
                        people: [other, ye],
                      );
                    },
                  );
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('工作质量'), findsWidgets);
    expect(find.textContaining('别人的指标'), findsNothing);
  });
}
