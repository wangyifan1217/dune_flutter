import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/profile/native_work_profile_perf_page.dart';
import 'package:dunes_app/features/profile/work_profile_kpi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const session = AuthSession(
    phone: '13800000000',
    userId: 1,
    token: '',
    apiBase: '',
    roles: <String>[],
  );

  test('parses 70/30 telecom weights and keeps energy separate', () {
    final score = WorkProfileKpiScore.fromJson({
      'month': '2026-08',
      'prevMonth': '2026-07',
      'people': [
        {
          'userId': 1,
          'userName': '李四',
          'mainScore': 80.5,
          'bonus': 0,
          'telecomWeight': 0.33,
          'energyWeight': 0.67,
          'telecomScore': 90,
          'energyScore': 75,
          'categories': [
            {
              'category': 'telecom',
              'categoryLabel': '通信',
              'categoryWeight': 0.33,
              'score': 90,
              'tasks': [
                {
                  'taskId': 1,
                  'taskName': 'A',
                  'province': '贵州',
                  'weightPct': 70,
                  'taskTotal': 90,
                  'curRevenue': 70,
                  'prevRevenue': 70,
                  'curProfit': 7,
                  'prevProfit': 7,
                  'metrics': [
                    {
                      'key': 'revenue',
                      'label': '营收环比',
                      'status': 'ok',
                      'points': 25,
                      'momPct': 0,
                    },
                  ],
                },
                {
                  'taskId': 2,
                  'taskName': 'B',
                  'province': '',
                  'weightPct': 30,
                  'taskTotal': 90,
                  'curRevenue': 30,
                  'prevRevenue': 30,
                  'curProfit': 3,
                  'prevProfit': 3,
                  'metrics': [],
                },
              ],
            },
            {
              'category': 'energy',
              'categoryLabel': '能源',
              'categoryWeight': 0.67,
              'score': 75,
              'tasks': [
                {
                  'taskId': 3,
                  'taskName': 'C',
                  'province': '广东',
                  'weightPct': 100,
                  'taskTotal': 75,
                  'curRevenue': 200,
                  'prevRevenue': 200,
                  'curProfit': 20,
                  'prevProfit': 20,
                  'metrics': [],
                },
              ],
            },
          ],
        },
      ],
    });
    final telecom = score.me!.categories.firstWhere((c) => c.category == 'telecom');
    final energy = score.me!.categories.firstWhere((c) => c.category == 'energy');
    expect(telecom.tasks.map((t) => t.weightPct).toList(), [70, 30]);
    expect(energy.tasks.single.weightPct, 100);
    expect(energy.tasks.single.curRevenue, 200);
  });

  testWidgets('shows telecom and energy lists with auto weights', (tester) async {
    final score = WorkProfileKpiScore.fromJson({
      'month': '2026-08',
      'prevMonth': '2026-07',
      'people': [
        {
          'userId': 1,
          'userName': '李四',
          'mainScore': 80.5,
          'bonus': 0,
          'telecomWeight': 0.33,
          'energyWeight': 0.67,
          'telecomScore': 90,
          'energyScore': 75,
          'categories': [
            {
              'category': 'telecom',
              'categoryLabel': '通信',
              'categoryWeight': 0.33,
              'score': 90,
              'tasks': [
                {
                  'taskId': 1,
                  'taskName': '小套-出行会员',
                  'province': '贵州',
                  'weightPct': 70,
                  'taskTotal': 88,
                  'curRevenue': 70,
                  'prevRevenue': 80,
                  'curProfit': 7,
                  'prevProfit': 8,
                  'metrics': [
                    {
                      'key': 'revenue',
                      'label': '营收环比',
                      'status': 'ok',
                      'points': 20,
                      'momPct': -12.5,
                    },
                  ],
                },
                {
                  'taskId': 2,
                  'taskName': '小套-加油会员',
                  'province': '全国',
                  'weightPct': 30,
                  'taskTotal': 90,
                  'curRevenue': 30,
                  'prevRevenue': 30,
                  'curProfit': 3,
                  'prevProfit': 3,
                  'metrics': [],
                },
              ],
            },
            {
              'category': 'energy',
              'categoryLabel': '能源',
              'categoryWeight': 0.67,
              'score': 75,
              'tasks': [
                {
                  'taskId': 3,
                  'taskName': '中石油',
                  'province': '广东',
                  'weightPct': 100,
                  'taskTotal': 75,
                  'curRevenue': 200,
                  'prevRevenue': 180,
                  'curProfit': 20,
                  'prevProfit': 18,
                  'metrics': [],
                },
              ],
            },
          ],
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: NativeWorkProfilePerfPage(
          session: session,
          onBack: () {},
          score: score,
        ),
      ),
    );

    expect(find.text('绩效发展'), findsOneWidget);
    expect(find.textContaining('主营 80.50'), findsOneWidget);
    expect(find.textContaining('通信（2）'), findsOneWidget);
    expect(find.textContaining('能源（1）'), findsOneWidget);
    expect(find.text('权重 70.00%'), findsOneWidget);
    expect(find.text('权重 30.00%'), findsOneWidget);
    expect(find.text('权重 100.00%'), findsOneWidget);
    expect(find.textContaining('小套-出行会员'), findsOneWidget);
    expect(find.textContaining('中石油'), findsOneWidget);
    expect(find.textContaining('营收环比'), findsOneWidget);
  });

  testWidgets('shows manual weight badge and remark', (tester) async {
    const score = WorkProfileKpiScore(
      month: '2026-08',
      prevMonth: '2026-07',
      people: [
        WorkProfileKpiPerson(
          userId: 1,
          userName: '李四',
          mainScore: 80,
          bonus: 0,
          telecomWeight: 0,
          energyWeight: 1,
          telecomScore: 0,
          energyScore: 80,
          categories: [
            WorkProfileKpiCategory(
              category: 'energy',
              categoryLabel: '能源',
              categoryWeight: 1,
              score: 80,
              tasks: [
                WorkProfileKpiTask(
                  taskId: 3,
                  taskName: '中石油',
                  province: '广东',
                  bucketLabel: '能源',
                  weightPct: 80,
                  autoWeightPct: 100,
                  taskTotal: 75,
                  curRevenue: 200,
                  prevRevenue: 180,
                  curProfit: 20,
                  prevProfit: 18,
                  weightOverridden: true,
                  scoreAdj: 5,
                  scoreAdjusted: true,
                  autoTaskTotal: 70,
                  remark: '下调中石油占比',
                ),
              ],
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NativeWorkProfilePerfPage(
          session: session,
          onBack: () {},
          score: score,
        ),
      ),
    );
    expect(find.text('手工'), findsOneWidget);
    expect(find.text('权重 80.00%'), findsOneWidget);
    expect(find.text('自动权重 100.00%'), findsOneWidget);
    expect(find.text('备注 下调中石油占比'), findsOneWidget);
    expect(find.text('加减分 +5'), findsOneWidget);
    expect(find.textContaining('得分 75.0（自动 70.0）'), findsOneWidget);
  });

  testWidgets('defaults to current month and can step to previous month', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeWorkProfilePerfPage(
          session: session,
          onBack: () {},
          now: DateTime(2026, 9, 3),
          score: const WorkProfileKpiScore(
            month: '2026-09',
            prevMonth: '2026-08',
          ),
        ),
      ),
    );
    expect(find.text('2026年9月'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('work-profile-perf-month-next'))).onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('work-profile-perf-month-prev')));
    await tester.pump();
    expect(find.text('2026年8月'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('work-profile-perf-month-next'))).onPressed,
      isNotNull,
    );
  });

  testWidgets('failed live load shows error instead of sample data', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeWorkProfilePerfPage(
          session: session,
          onBack: () {},
          now: DateTime(2026, 9, 3),
          loadScore: (month) async {
            expect(month, '2026-09');
            throw Exception('kpi down');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-profile-perf-error')), findsOneWidget);
    expect(find.text('加载失败，请稍后重试'), findsOneWidget);
    expect(find.textContaining('通信（2）'), findsNothing);
    expect(find.text('页面预览 · 样例数据，非正式成绩'), findsNothing);
  });

  testWidgets('empty month shows a quiet empty state', (tester) async {
    const score = WorkProfileKpiScore(
      month: '2026-08',
      prevMonth: '2026-07',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NativeWorkProfilePerfPage(
          session: session,
          onBack: () {},
          score: score,
        ),
      ),
    );
    expect(find.byKey(const Key('work-profile-perf-empty')), findsOneWidget);
    expect(find.text('本月暂无计入任务'), findsOneWidget);
  });
}
