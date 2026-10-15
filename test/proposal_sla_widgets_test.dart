import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:dunes_app/features/proposal_intake/proposal_list_card.dart';
import 'package:dunes_app/features/proposal_intake/proposal_sla_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProposalSlaSummary _sla(String status) => ProposalSlaSummary.tryParse({
  'instanceId': 1,
  'status': status,
  'statusLabel': switch (status) {
    'warning' => '卡点',
    'overdue' => '已超时',
    _ => '正常',
  },
  'round': 2,
  'totalLimitMinutes': 4320,
  'totalElapsedMinutes': 3000,
  'totalRemainingMinutes': 1320,
  'remindCount': 3,
  'overdueCount': 1,
  'paused': true,
  'currentStageLabel': '财务复核',
  'current': [
    {
      'id': 5,
      'round': 2,
      'stageLabel': '财务复核',
      'label': '合同与条款复核',
      'assigneeName': '刘雨滴',
      'effectiveMinutes': status == 'overdue' ? 800 : 640,
      'limitMinutes': 720,
      'remainingMinutes': status == 'overdue' ? 0 : 80,
      'overdueMinutes': status == 'overdue' ? 80 : 0,
      'state': status,
      'remindCount': 2,
    },
  ],
})!;

void main() {
  for (final width in [360.0, 1100.0]) {
    testWidgets('list card with sla chip fits at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(children: [
            for (final status in ['normal', 'warning', 'overdue'])
              ProposalListCard(
                data: ProposalListCardData(
                  index: 0,
                  tag1: '加油券',
                  name: '一个名字比较长的销售提案用来测试底栏是否溢出',
                  steps: const [
                    ProposalListStep('提交', ProposalListStepState.done),
                    ProposalListStep('市场部', ProposalListStepState.done),
                    ProposalListStep('科技部', ProposalListStepState.done),
                    ProposalListStep('财务部', ProposalListStepState.now),
                    ProposalListStep('最终确认', ProposalListStepState.todo),
                  ],
                  nowText: '财务部 · 待刘雨滴复核',
                  days: '停 4 天',
                  sla: _sla(status),
                ),
                more: const Icon(Icons.more_horiz),
              ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('proposal-sla-chip')), findsNWidgets(3));
      expect(find.text('停 4 天'), findsNothing);
    });

    testWidgets('sla overview fits at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: ProposalSlaOverview(sla: _sla('overdue'), onOpenRecords: () => opened++),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('时限 · 已超时'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('proposal-sla-records')));
      expect(opened, 1);
    });
  }

  testWidgets('card without sla keeps the days capsule', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ProposalListCard(
          data: ProposalListCardData(index: 0, tag1: '加油券', name: '提案', days: '停 4 天'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('停 4 天'), findsOneWidget);
    expect(find.byKey(const ValueKey('proposal-sla-chip')), findsNothing);
  });
}
