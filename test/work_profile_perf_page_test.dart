import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/profile/native_work_profile_perf_page.dart';
import 'package:dunes_app/features/profile/work_profile_kpi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkProfileKpiTask _slice({
  String taskName = '',
  String province = '',
  String bucketLabel = '',
  String matchSummary = '',
  String productName = '',
  String productGroup = '',
  String channelName = '',
  String supplyGroup = '',
}) {
  return WorkProfileKpiTask(
    taskId: 1,
    taskName: taskName,
    province: province,
    bucketLabel: bucketLabel,
    weightPct: 0,
    taskTotal: 0,
    curRevenue: 0,
    prevRevenue: 0,
    curProfit: 0,
    prevProfit: 0,
    matchSummary: matchSummary,
    productName: productName,
    productGroup: productGroup,
    channelName: channelName,
    supplyGroup: supplyGroup,
  );
}

void main() {
  test('lighthouse slice title prefers product over old task name', () {
    final fromFields = _slice(
      taskName: '旧任务名',
      province: '广东',
      productName: '中石油',
      productGroup: '能源',
      channelName: '平安',
      bucketLabel: '能源板块',
    );
    expect(kpiLighthouseSliceTitle(fromFields), '中石油');
    expect(kpiLighthouseSliceSubtitle(fromFields), '广东 · 平安');

    final fromSummary = _slice(
      taskName: '小套-加油会员',
      province: '广东',
      bucketLabel: '通信板块',
      matchSummary: '产品=小套-加油会员',
    );
    expect(kpiLighthouseSliceTitle(fromSummary), '小套-加油会员');
    expect(kpiLighthouseSliceSubtitle(fromSummary), '广东');

    final supply = _slice(
      taskName: '中石油',
      province: '中油BP',
      matchSummary: '供给方=中石油',
    );
    expect(kpiLighthouseSliceTitle(supply), '中石油');
    expect(kpiLighthouseSliceSubtitle(supply), '中油BP');

    final channel = _slice(
      taskName: '多渠道',
      province: '全国',
      matchSummary: '渠道L1=多渠道',
    );
    expect(kpiLighthouseSliceTitle(channel), '多渠道');
    expect(kpiLighthouseSliceSubtitle(channel), '全国');
  });

  test('builds markdown summary of final scores and grades', () {
    const score = WorkProfileKpiScore(
      month: '2026-08',
      prevMonth: '2026-07',
      people: [
        WorkProfileKpiPerson(
          userId: 2,
          userName: '何佳伟',
          mainScore: 47.36,
          bonus: 0,
          telecomWeight: 0.5,
          energyWeight: 0.5,
          telecomScore: 40,
          energyScore: 50,
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
    final md = kpiScoreSummaryMarkdown(score);
    expect(md, contains('## 2026年8月 业务绩效汇总'));
    expect(md, contains('共 **2** 人'));
    expect(md, contains('| 姓名 | 最终得分 | 等级 |'));
    expect(md.indexOf('李四'), lessThan(md.indexOf('何佳伟')));
    expect(md, contains('| 李四 | 88.00 | 良（达到预期） |'));
    expect(md, contains('| 何佳伟 | 47.36 | 辅（专项改进） |'));
  });

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
    expect(find.textContaining('中（低于预期）'), findsOneWidget);
    expect(find.byKey(const Key('work-profile-perf-add')), findsNothing);
    expect(find.textContaining('通信（2条规则）'), findsOneWidget);
    expect(find.textContaining('能源（1条规则）'), findsOneWidget);
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

  testWidgets('defaults to previous month and can step to current month', (
    tester,
  ) async {
    final seen = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NativeWorkProfilePerfPage(
          session: session,
          onBack: () {},
          now: DateTime(2026, 9, 3),
          loadScore: (month) async {
            seen.add(month);
            return WorkProfileKpiScore(month: month, prevMonth: '2026-07');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2026年8月'), findsOneWidget);
    expect(seen, ['2026-08']);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('work-profile-perf-month-next'))).onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('work-profile-perf-month-next')));
    await tester.pumpAndSettle();
    expect(find.text('2026年9月'), findsOneWidget);
    expect(seen, ['2026-08', '2026-09']);
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
            expect(month, '2026-08');
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
    expect(find.text('本月暂无对应的灯塔数据规则'), findsOneWidget);
    expect(find.byKey(const Key('work-profile-perf-add')), findsNothing);
  });

  test('maps main score to performance grade', () {
    expect(kpiGradeOf(96).label, '优（优秀）');
    expect(kpiGradeOf(96).coefficient, 1.1);
    expect(kpiGradeOf(88).label, '良（达到预期）');
    expect(kpiGradeOf(82).label, '中（低于预期）');
    expect(kpiGradeOf(76).label, '普（待提升）');
    expect(kpiGradeOf(72).label, '改（重点改进）');
    expect(kpiGradeOf(60).label, '辅（专项改进）');
  });

  testWidgets('does not offer add or edit for counted tasks', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeWorkProfilePerfPage(
          session: session,
          onBack: () {},
          now: DateTime(2026, 9, 3),
          score: const WorkProfileKpiScore(
            month: '2026-08',
            prevMonth: '2026-07',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-profile-perf-add')), findsNothing);
    expect(find.byTooltip('删除'), findsNothing);
    expect(find.text('新增任务'), findsNothing);
  });
}
