import 'package:dunes_app/features/proposal_intake/proposal_list_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tag group merges proposals under one 标签一 and folds the rest', (tester) async {
    tester.view.physicalSize = const Size(460, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <int>[];
    final entries = [
      for (var i = 0; i < 5; i++)
        ProposalTagGroupEntry(
          id: i + 1,
          data: ProposalListCardData(
            index: i,
            tag1: '中石油普惠现金券（交易）',
            name: '提案 ${i + 1}',
            chips: const ['能源', '新增'],
            scale: '1,000',
            steps: const [
              ProposalListStep('提交', ProposalListStepState.done),
              ProposalListStep('市场部', ProposalListStepState.now),
            ],
            nowText: '市场部 · 待王一凡复核',
          ),
          onTap: () => opened.add(i + 1),
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProposalTagGroupCard(
              data: ProposalTagGroupData(
                index: 0,
                tag1: '中石油普惠现金券（交易）',
                header: const ProposalListCardData(
                  index: 0,
                  tag1: '中石油普惠现金券（交易）',
                  nameLabel: '提案 5 份',
                  name: '5 进行中 · 0 已完成',
                  chips: ['能源'],
                  mid: [
                    ProposalListCardMetric(label: '产品', value: '5', unit: '个'),
                    ProposalListCardMetric(label: '年化规模合计', value: '5,000', unit: '万'),
                  ],
                  right: [
                    ProposalListCardMetric(label: '标签二', value: '中石油 / 北京', wrap: true),
                    ProposalListCardMetric(label: '标签三', value: '平安 / 优惠买单', wrap: true),
                  ],
                ),
                entries: entries,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // 上半部分是灯塔那六格，合计数在里面。
    expect(find.text('提案 5 份'), findsOneWidget);
    expect(find.text('年化规模合计'), findsOneWidget);
    // 只剩四个框：产品、年化规模合计、标签二、标签三。
    expect(find.text('标签二'), findsOneWidget);
    expect(find.text('周转资金合计'), findsNothing);
    expect(find.text('提案 1'), findsOneWidget);
    expect(find.text('提案 4'), findsNothing);
    expect(find.text('展开其余 2 份提案'), findsOneWidget);
    await tester.tap(find.text('展开其余 2 份提案'));
    await tester.pump();
    expect(find.text('提案 5'), findsOneWidget);
    await tester.tap(find.text('提案 2'));
    expect(opened, [2]);
    // 提案名称前有序号；标签一右边的按钮把下面的提案整组收起。
    expect(find.text('1.'), findsOneWidget);
    await tester.tap(find.text('收起').first);
    await tester.pump();
    expect(find.text('提案 1'), findsNothing);
    expect(find.text('展开 5 份'), findsOneWidget);
  });
}
