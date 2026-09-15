import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/kpi/kpi_score_summary_card.dart';

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
}
