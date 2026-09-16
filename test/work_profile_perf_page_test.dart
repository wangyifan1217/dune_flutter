import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/kpi/kpi_score_summary_card.dart';
import 'package:dunes_app/features/profile/native_work_profile_perf_page.dart';
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
      bucketLabel: '运营商',
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

  test('量表明细用考核目标，不写成全国', () {
    const task = WorkProfileKpiTask(
      taskId: -11,
      taskName: '目标完成度',
      province: '',
      bucketLabel: '业绩产出',
      weightPct: 40,
      taskTotal: 34,
      curRevenue: 0,
      prevRevenue: 0,
      curProfit: 0,
      prevProfit: 0,
      matchSummary: '所负责产品/项目的核心业务指标（OKR/KPI）达成情况',
      metrics: [
        WorkProfileKpiMetric(
          key: 'goal',
          label: '目标完成度',
          status: 'ok',
          kind: 'rubric',
          maxPoints: 40,
          points: 34,
          note: '所负责产品/项目的核心业务指标（OKR/KPI）达成情况',
        ),
      ],
    );
    expect(task.isRubric, isTrue);
    expect(
      kpiLighthouseSliceSubtitle(task),
      '所负责产品/项目的核心业务指标（OKR/KPI）达成情况',
    );
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
    expect(md, contains('## 2026年8月 月度绩效考评汇总'));
    expect(md, contains('共 **2** 人'));
    expect(md, contains('| 部门 | 姓名 | 岗位 | 绩效得分 | 绩效等级 | 绩效系数 |'));
    expect(md.indexOf('李四'), lessThan(md.indexOf('何佳伟')));
    expect(md, contains('| — | 1. 李四 | — | 88.00 | 良（达到预期） | 1.0 |'));
    expect(md, contains('| — | 2. 何佳伟 | — | 47.36 | 辅（专项改进） | 0.6 |'));

    final filtered = kpiScoreSummaryMarkdown(
      score,
      people: score.people.where((p) => p.userName == '李四').toList(),
    );
    expect(filtered, contains('共 **1** 人'));
    expect(filtered, contains('1. 李四'));
    expect(filtered, isNot(contains('何佳伟')));
  });

  test('summary marks skipped people without a fake zero score', () {
    const ding = WorkProfileKpiPerson(
      userId: 11,
      userName: '丁涛',
      departmentName: '出行组',
      position: 'Java工程师',
      mainScore: 0,
      bonus: 0,
      telecomWeight: 0,
      energyWeight: 0,
      telecomScore: 0,
      energyScore: 0,
      scoreSource: 'rubric',
      scoreStatus: 'skipped',
      skipReason: 'probation',
      gradeLabel: '试用期',
    );
    const scored = WorkProfileKpiPerson(
      userId: 1,
      userName: '胡浩',
      departmentName: '出行组',
      position: 'Java工程师',
      mainScore: 86,
      bonus: 0,
      telecomWeight: 0,
      energyWeight: 0,
      telecomScore: 0,
      energyScore: 0,
      scoreSource: 'rubric',
      scoreStatus: 'scored',
    );
    const score = WorkProfileKpiScore(
      month: '2026-08',
      prevMonth: '2026-07',
      people: [ding, scored],
    );
    final md = kpiScoreSummaryMarkdown(score);
    expect(md, contains('| 出行组 | 1. 胡浩 | Java工程师 | 86.00 |'));
    expect(md, contains('| 出行组 | 2. 丁涛 | Java工程师 | — | 试用期 | — |'));
    expect(md, isNot(contains('| 0.00 | 试用期 |')));
    expect(kpiPersonShareDepartment(ding), '出行组');
    final data = kpiScoreSummaryData(score);
    expect(data.skippedCount, 1);
    expect(data.pendingCount, 0);
    expect(data.averageScore, 86);
  });

  test('summary groups by scored sector, not roster department', () {
    const he = WorkProfileKpiPerson(
      userId: 40,
      userName: '何佳伟',
      departmentName: '能源板块',
      position: '高级售前顾问',
      mainScore: 49.51,
      bonus: 0,
      telecomWeight: 1,
      energyWeight: 0,
      telecomScore: 49.51,
      energyScore: 0,
      categories: [
        WorkProfileKpiCategory(
          category: 'telecom',
          categoryLabel: '运营商',
          categoryWeight: 1,
          score: 49.51,
          tasks: [
            WorkProfileKpiTask(
              taskId: 1,
              taskName: '会员套餐订阅',
              province: '广东',
              bucketLabel: '运营商',
              weightPct: 100,
              taskTotal: 49.51,
              curRevenue: 1,
              prevRevenue: 1,
              curProfit: 1,
              prevProfit: 1,
            ),
          ],
        ),
      ],
    );
    const score = WorkProfileKpiScore(
      month: '2026-08',
      prevMonth: '2026-07',
      people: [he],
    );
    final md = kpiScoreSummaryMarkdown(score);
    expect(md, contains('| 运营商 | 1. 何佳伟 | 高级售前顾问 |'));
    expect(md, isNot(contains('| 能源 | 1. 何佳伟 |')));
    expect(kpiPersonShareDepartment(he), '运营商');
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
              'categoryLabel': '运营商',
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
    final telecom = score.me!.categories.firstWhere(
      (c) => c.category == 'telecom',
    );
    final energy = score.me!.categories.firstWhere(
      (c) => c.category == 'energy',
    );
    expect(telecom.tasks.map((t) => t.weightPct).toList(), [70, 30]);
    expect(energy.tasks.single.weightPct, 100);
    expect(energy.tasks.single.curRevenue, 200);
  });

  testWidgets('shows telecom and energy lists with auto weights', (
    tester,
  ) async {
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
              'categoryLabel': '运营商',
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
    expect(find.textContaining('运营商（2条规则）'), findsOneWidget);
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
    expect(find.textContaining('任务分 75.0（自动 70.0）'), findsOneWidget);
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
      tester
          .widget<IconButton>(
            find.byKey(const Key('work-profile-perf-month-next')),
          )
          .onPressed,
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
    expect(find.textContaining('运营商（2）'), findsNothing);
    expect(find.text('页面预览 · 样例数据，非正式成绩'), findsNothing);
  });

  testWidgets('empty month shows a quiet empty state', (tester) async {
    const score = WorkProfileKpiScore(month: '2026-08', prevMonth: '2026-07');
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

  testWidgets('subject confirms rubric score on 绩效发展', (tester) async {
    var ackCount = 0;
    const scored = WorkProfileKpiPerson(
      userId: 1,
      userName: '王奕凡',
      departmentName: 'AI研发',
      mainScore: 95,
      bonus: 0,
      telecomWeight: 0,
      energyWeight: 0,
      telecomScore: 0,
      energyScore: 0,
      grade: '优',
      gradeLabel: '优（优秀）',
      coefficient: 1.1,
      scoreSource: 'rubric',
      scoreStatus: 'scored',
      canAck: true,
      categories: [
        WorkProfileKpiCategory(
          category: 'rd',
          categoryLabel: 'AI研发',
          categoryWeight: 1,
          score: 95,
          tasks: [
            WorkProfileKpiTask(
              taskId: -11,
              taskName: '目标完成度',
              province: '',
              bucketLabel: '业绩产出',
              weightPct: 30,
              taskTotal: 30,
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
        home: NativeWorkProfilePerfPage(
          session: session,
          onBack: () {},
          now: DateTime(2026, 9, 3),
          score: const WorkProfileKpiScore(
            month: '2026-08',
            prevMonth: '2026-07',
            people: [scored],
          ),
          ackScore: (month) async {
            ackCount++;
            return WorkProfileKpiScore(
              month: month,
              prevMonth: '2026-07',
              people: [
                WorkProfileKpiPerson(
                  userId: 1,
                  userName: '王奕凡',
                  departmentName: 'AI研发',
                  mainScore: 95,
                  bonus: 0,
                  telecomWeight: 0,
                  energyWeight: 0,
                  telecomScore: 0,
                  energyScore: 0,
                  grade: '优',
                  gradeLabel: '优（优秀）',
                  coefficient: 1.1,
                  scoreSource: 'rubric',
                  scoreStatus: 'scored',
                  ackedAt: '2026-09-15T03:00:00Z',
                  categories: scored.categories,
                ),
              ],
            );
          },
        ),
      ),
    );
    expect(find.byKey(const Key('work-profile-perf-ack')), findsOneWidget);
    await tester.tap(find.byKey(const Key('work-profile-perf-ack')));
    await tester.pumpAndSettle();
    expect(find.text('确认本月绩效？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('work-profile-perf-ack-ok')));
    await tester.pumpAndSettle();
    expect(ackCount, 1);
    expect(find.byKey(const Key('work-profile-perf-acked')), findsOneWidget);
    expect(find.byKey(const Key('work-profile-perf-ack')), findsNothing);
  });

  testWidgets('绩效发展量表明细用考核目标和评分标准，不画进度条', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const person = WorkProfileKpiPerson(
      userId: 1,
      userName: '朱子姝',
      departmentName: 'AI研发',
      mainScore: 90,
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
      ackedAt: '2026-09-15T03:00:00Z',
      categories: [
        WorkProfileKpiCategory(
          category: 'rd',
          categoryLabel: 'AI研发',
          categoryWeight: 1,
          score: 90,
          tasks: [
            WorkProfileKpiTask(
              taskId: -11,
              taskName: '目标完成度',
              province: '',
              bucketLabel: '业绩产出',
              weightPct: 40,
              taskTotal: 34,
              curRevenue: 0,
              prevRevenue: 0,
              curProfit: 0,
              prevProfit: 0,
              matchSummary: '所负责产品/项目的核心业务指标（OKR/KPI）达成情况',
              metrics: [
                WorkProfileKpiMetric(
                  key: 'goal',
                  label: '目标完成度',
                  status: 'ok',
                  kind: 'rubric',
                  maxPoints: 40,
                  points: 34,
                  note: '所负责产品/项目的核心业务指标（OKR/KPI）达成情况',
                ),
                WorkProfileKpiMetric(
                  key: 'goal_32_35',
                  label: '32–35分',
                  status: 'ok',
                  kind: 'rubric',
                  base: 32,
                  maxPoints: 35,
                  note: '100%达成所有目标，成果符合预期。',
                ),
                WorkProfileKpiMetric(
                  key: 'goal_0_20',
                  label: '0–20分',
                  status: 'none',
                  kind: 'rubric',
                  base: 0,
                  maxPoints: 20,
                  note: '任务完成率低于70%，或有任务未完成严重影响项目。',
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
          now: DateTime(2026, 9, 16),
          score: const WorkProfileKpiScore(
            month: '2026-08',
            prevMonth: '2026-07',
            people: [person],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('量表 90.00'), findsOneWidget);
    expect(find.textContaining('运营商权重'), findsNothing);
    expect(find.textContaining('本月营收'), findsNothing);
    expect(find.textContaining('上期为 0'), findsNothing);
    expect(find.textContaining('全国'), findsNothing);
    expect(
      find.text('所负责产品/项目的核心业务指标（OKR/KPI）达成情况'),
      findsWidgets,
    );
    expect(find.text('100%达成所有目标，成果符合预期。'), findsOneWidget);
    expect(find.textContaining('34.0 / 40'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('lighthouse detail can send a data appeal to HR', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var sent = '';
    const score = WorkProfileKpiScore(
      month: '2026-08',
      prevMonth: '2026-07',
      people: [
        WorkProfileKpiPerson(
          userId: 1,
          userName: '李四',
          mainScore: 80,
          bonus: 0,
          telecomWeight: 1,
          energyWeight: 0,
          telecomScore: 80,
          energyScore: 0,
          categories: [
            WorkProfileKpiCategory(
              category: 'telecom',
              categoryLabel: '运营商',
              categoryWeight: 1,
              score: 80,
              tasks: [
                WorkProfileKpiTask(
                  taskId: 1,
                  taskName: '小套-出行会员',
                  province: '广东',
                  bucketLabel: '运营商',
                  weightPct: 100,
                  taskTotal: 80,
                  curRevenue: 100,
                  prevRevenue: 90,
                  curProfit: 10,
                  prevProfit: 9,
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
          submitAppeal: (month, comment) async {
            sent = '$month|$comment';
            return KpiAppeal(
              id: 9,
              month: month,
              userId: 1,
              kind: 'data',
              comment: comment,
            );
          },
        ),
      ),
    );
    expect(find.byKey(const Key('work-profile-perf-appeal')), findsOneWidget);
    await tester.tap(find.byKey(const Key('work-profile-perf-appeal')));
    await tester.pumpAndSettle();
    expect(find.text('申诉绩效数据'), findsOneWidget);
    expect(find.textContaining('收入、利润、项目归属'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('work-profile-perf-appeal-comment')),
      '出行会员利润不该计入',
    );
    await tester.tap(find.byKey(const Key('work-profile-perf-appeal-ok')));
    await tester.pumpAndSettle();
    expect(sent, '2026-08|出行会员利润不该计入');
    expect(find.text('已申诉'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('rubric detail appeals evaluation not lighthouse numbers', (
    tester,
  ) async {
    const scored = WorkProfileKpiPerson(
      userId: 1,
      userName: '王奕凡',
      departmentName: 'AI研发',
      mainScore: 95,
      bonus: 0,
      telecomWeight: 0,
      energyWeight: 0,
      telecomScore: 0,
      energyScore: 0,
      scoreSource: 'rubric',
      scoreStatus: 'scored',
      categories: [
        WorkProfileKpiCategory(
          category: 'rd',
          categoryLabel: 'AI研发',
          categoryWeight: 1,
          score: 95,
          tasks: [
            WorkProfileKpiTask(
              taskId: -11,
              taskName: '目标完成度',
              province: '',
              bucketLabel: '业绩产出',
              weightPct: 30,
              taskTotal: 30,
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
        home: NativeWorkProfilePerfPage(
          session: session,
          onBack: () {},
          score: const WorkProfileKpiScore(
            month: '2026-08',
            prevMonth: '2026-07',
            people: [scored],
          ),
          submitAppeal: (month, comment) async {
            return KpiAppeal(
              id: 3,
              month: month,
              userId: 1,
              kind: 'rubric',
              comment: comment,
            );
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('work-profile-perf-appeal')));
    await tester.pumpAndSettle();
    expect(find.text('申诉评价结果'), findsOneWidget);
    expect(find.textContaining('某档打错、等级不服'), findsNothing);
    expect(find.textContaining('不改灯塔流水'), findsNothing);
  });
}
