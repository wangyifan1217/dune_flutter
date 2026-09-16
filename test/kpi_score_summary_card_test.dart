import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/kpi/kpi_score_summary_card.dart';
import 'package:dunes_app/features/profile/work_profile_kpi.dart';

void main() {
  const legacyMarkdown = '''## 2026年8月 业务绩效汇总

共 **3** 人

| 部门 | 姓名 | 岗位 | 绩效得分 | 绩效等级 | 绩效系数 |
| --- | --- | --- | ---: | --- | ---: |
| 能源板块 | 1. 何佳伟 | 高级售前顾问 | 91.50 | 良（达到预期） | 1.0 |
| 通信板块 | 2. 叶锦成 | 高级售前顾问 | 72.00 | 改（重点改进） | 0.7 |
| 通信板块 | 3. 吕杰 | — | 60.00 | 辅（专项改进） | 0.6 |''';

  group('KpiScoreSummaryData', () {
    test('旧消息没有结构化数据时从 Markdown 表格解析', () {
      final data = KpiScoreSummaryData.fromMessage(
        const {'robotMarkdown': true, 'kpiScoreSummary': true},
        legacyMarkdown,
      );
      expect(data, isNotNull);
      expect(data!.title, '2026年8月 业务绩效汇总');
      expect(data.rows.length, 3);
      expect(data.rows.first.name, '何佳伟');
      expect(data.rows.first.rank, 1);
      expect(data.rows.first.gradeCode, '良');
      expect(data.rows[2].position, '');
      expect(data.rows[1].coefficient, 0.7);
      expect(data.averageScore, closeTo(74.5, 1e-9));
      expect(data.topScore, 91.5);
      expect(data.departmentCoefficient, closeTo((1.0 + 0.7 + 0.6) / 3, 1e-9));
      expect(
        data.byDepartment.map((e) => e.key).toList(),
        ['能源板块', '通信板块'],
      );
      expect(
        data.gradeCounts.map((e) => '${e.key}${e.value}').toList(),
        ['良1', '改1', '辅1'],
      );
    });

    test('非绩效汇总消息不接管', () {
      expect(
        KpiScoreSummaryData.fromMessage(
          const {'robotMarkdown': true},
          legacyMarkdown,
        ),
        isNull,
      );
    });

    test('结构化 payload 优先，未评分的人不拉低均分', () {
      final json = KpiScoreSummaryData(
        title: '2026年8月 月度绩效考评汇总',
        rows: const [
          KpiScoreSummaryRow(rank: 1, name: '甲', score: 90, gradeCode: '良'),
          KpiScoreSummaryRow(rank: 2, name: '乙', pending: true),
        ],
      ).toJson();
      final data = KpiScoreSummaryData.fromMessage({
        'robotMarkdown': true,
        'kpiScoreSummary': true,
        'kpiSummary': json,
      }, 'ignored');
      expect(data!.rows.length, 2);
      expect(data.pendingCount, 1);
      expect(data.averageScore, 90);
    });

    test('已评分人员系数平均为部门绩效系数', () {
      const data = KpiScoreSummaryData(
        title: '测试',
        rows: [
          KpiScoreSummaryRow(rank: 1, name: '甲', score: 90, coefficient: 1),
          KpiScoreSummaryRow(rank: 2, name: '乙', score: 60, coefficient: 0.6),
          KpiScoreSummaryRow(rank: 3, name: '丙', pending: true),
        ],
      );
      expect(data.departmentCoefficient, closeTo(0.8, 1e-9));
    });

    test('研发项目绩效来自整体绩效评价表，职能没有', () {
      const travel = WorkProfileKpiPerson(
        userId: 1,
        userName: '雷江华',
        departmentName: '出行',
        mainScore: 88,
        bonus: 0,
        telecomWeight: 0,
        energyWeight: 0,
        telecomScore: 0,
        energyScore: 0,
        scoreSource: 'rubric',
        categories: [
          WorkProfileKpiCategory(
            category: 'rd',
            categoryLabel: '研发',
            categoryWeight: 1,
            score: 88,
          ),
        ],
      );
      const finance = WorkProfileKpiPerson(
        userId: 2,
        userName: '邓艳丽',
        departmentName: '财务数据中心',
        mainScore: 75,
        bonus: 0,
        telecomWeight: 0,
        energyWeight: 0,
        telecomScore: 0,
        energyScore: 0,
        scoreSource: 'rubric',
        categories: [
          WorkProfileKpiCategory(
            category: 'office',
            categoryLabel: '职能',
            categoryWeight: 1,
            score: 75,
          ),
        ],
      );
      const score = WorkProfileKpiScore(
        month: '2026-08',
        prevMonth: '2026-07',
        people: [travel, finance],
        teams: [
          WorkProfileKpiTeam(
            departmentId: 6,
            departmentName: '出行',
            projectScore: 8.95,
            coefficient: 1,
          ),
        ],
      );
      expect(kpiPersonShareDepartment(travel), '出行');
      expect(
        kpiScoreSummaryData(score, people: [travel]).projectScore,
        closeTo(8.95, 1e-9),
      );
      expect(kpiScoreSummaryData(score, people: [finance]).projectScore, isNull);
    });

    test('行政汇总表第一行项目绩效得分进入转发右上角', () {
      const admin = WorkProfileKpiPerson(
        userId: 3,
        userName: '商羽',
        departmentName: '行政人事部',
        mainScore: 86,
        bonus: 0,
        telecomWeight: 0,
        energyWeight: 0,
        telecomScore: 0,
        energyScore: 0,
        scoreSource: 'rubric',
        categories: [
          WorkProfileKpiCategory(
            category: 'office',
            categoryLabel: '职能',
            categoryWeight: 1,
            score: 86,
          ),
        ],
      );
      const score = WorkProfileKpiScore(
        month: '2026-08',
        prevMonth: '2026-07',
        people: [admin],
        teams: [
          WorkProfileKpiTeam(
            departmentId: 8,
            departmentName: '行政人事部',
            projectScore: 1,
            coefficient: 1,
          ),
        ],
      );
      expect(kpiScoreSummaryData(score, people: [admin]).projectScore, 1);
    });

    test('业务项目绩效按运营商能源整体，不跟研发量表混', () {
      const li = WorkProfileKpiPerson(
        userId: 9,
        userName: '李四',
        departmentName: '能源板块',
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
                bucketLabel: '能源板块',
                weightPct: 100,
                taskTotal: 88,
                curRevenue: 70,
                prevRevenue: 0,
                curProfit: 0,
                prevProfit: 0,
              ),
            ],
          ),
        ],
      );
      const score = WorkProfileKpiScore(
        month: '2026-08',
        prevMonth: '2026-07',
        people: [li],
        teams: [
          WorkProfileKpiTeam(
            departmentId: 0,
            departmentName: '能源',
            projectScore: 81,
            coefficient: 0.9,
          ),
          WorkProfileKpiTeam(
            departmentId: 6,
            departmentName: '出行',
            projectScore: 8.95,
            coefficient: 1,
          ),
        ],
      );
      expect(kpiScoreSummaryData(score, people: [li]).projectScore, 81);
    });

    test('多个研发组项目分不同时右上角不合成一个数', () {
      const travel = WorkProfileKpiPerson(
        userId: 1,
        userName: '雷江华',
        departmentName: '出行',
        mainScore: 88,
        bonus: 0,
        telecomWeight: 0,
        energyWeight: 0,
        telecomScore: 0,
        energyScore: 0,
        scoreSource: 'rubric',
        categories: [
          WorkProfileKpiCategory(
            category: 'rd',
            categoryLabel: '研发',
            categoryWeight: 1,
            score: 88,
          ),
        ],
      );
      const energy = WorkProfileKpiPerson(
        userId: 2,
        userName: '李凡伊',
        departmentName: '产业研发',
        mainScore: 90,
        bonus: 0,
        telecomWeight: 0,
        energyWeight: 0,
        telecomScore: 0,
        energyScore: 0,
        scoreSource: 'rubric',
        categories: [
          WorkProfileKpiCategory(
            category: 'rd',
            categoryLabel: '研发',
            categoryWeight: 1,
            score: 90,
          ),
        ],
      );
      const score = WorkProfileKpiScore(
        month: '2026-08',
        prevMonth: '2026-07',
        people: [travel, energy],
        teams: [
          WorkProfileKpiTeam(
            departmentId: 6,
            departmentName: '出行',
            projectScore: 8.95,
            coefficient: 1,
          ),
          WorkProfileKpiTeam(
            departmentId: 7,
            departmentName: '产业研发',
            projectScore: 8.87,
            coefficient: 1,
          ),
        ],
      );
      expect(kpiScoreSummaryData(score).projectScore, isNull);
    });

    test('全员 0 分标记为疑似未评分', () {
      final data = KpiScoreSummaryData.parseMarkdown(
        legacyMarkdown.replaceAll(RegExp(r'\| \d+\.\d{2} \|'), '| 0.00 |'),
      );
      expect(data!.allScoresZero, isTrue);
    });
  });

  testWidgets('汇总卡超过 8 人时默认收起', (tester) async {
    final rows = [
      for (var i = 0; i < 10; i++)
        KpiScoreSummaryRow(
          rank: i + 1,
          name: '员工$i',
          department: '通信板块',
          score: 90 - i.toDouble(),
          gradeCode: '良',
          coefficient: 1,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: ChatKpiScoreSummaryCard(
                data: KpiScoreSummaryData(title: '测试汇总', rows: rows),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('员工7'), findsOneWidget);
    expect(find.text('员工9'), findsNothing);
    expect(find.text('展开全部 10 人'), findsOneWidget);
    await tester.tap(find.text('展开全部 10 人'));
    await tester.pump();
    expect(find.text('员工9'), findsOneWidget);
  });

  testWidgets('汇总卡顶部显示项目绩效', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChatKpiScoreSummaryCard(
              data: KpiScoreSummaryData(
                title: '测试汇总',
                projectScore: 8.95,
                projectCoefficient: 1,
                rows: [
                  KpiScoreSummaryRow(
                    rank: 1,
                    name: '甲',
                    score: 90,
                    gradeCode: '良',
                    coefficient: 1,
                  ),
                  KpiScoreSummaryRow(
                    rank: 2,
                    name: '乙',
                    score: 60,
                    gradeCode: '辅',
                    coefficient: 0.6,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('项目绩效系数'), findsOneWidget);
    expect(find.text('1.1'), findsWidgets);
    expect(find.text('部门绩效系数'), findsNothing);
    expect(find.text('最高分'), findsNothing);
    expect(find.text('项目得分 8.95'), findsOneWidget);
  });
}
