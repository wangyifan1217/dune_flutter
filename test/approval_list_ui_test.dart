import 'package:dunes_app/features/xflow/approval_list_ui.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:dunes_app/features/xflow/xflow_shared_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wide draft keeps copy and delete in a compact row', (tester) async {
    tester.view.physicalSize = const Size(1270, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var copies = 0, deletes = 0, opens = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [
      XflowProposalListCard(mode: XflowListCardMode.b14,
        item: XflowProposalItem(id: 13, businessType: 'REIMBURSEMENT', code: '#13',
          title: '王奕凡 - 电子报销审批', status: 'DRAFT', createdByName: '王奕凡',
          createdAt: DateTime(2026,10,13), documentKind: '非业务审批', proposalType: '电子报销审批'),
        onTap: () => opens++, onCopy: () => copies++, onDeleteDraft: () => deletes++)]))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(XflowProposalListCard)).height, lessThan(100));
    await tester.tap(find.text('复制'));
    await tester.tap(find.text('删除草稿'));
    expect(copies, 1);
    expect(deletes, 1);
    expect(opens, 0);
  });

  for (final width in [360.0, 1100.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'approval list width=$width theme=$brightness preserves content and actions',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var opened = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 900),
                    textScaler: const TextScaler.linear(1.2),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      const ApprovalListSummary(
                        kicker: '我的审批 · 12 项',
                        badgeText: '3 待处理',
                        badgeUrge: true,
                        footItems: [
                          ('待审批', '3', 'urge'),
                          ('审批中', '4', null),
                          ('已通过', '5', 'pos'),
                          ('已驳回', '0', null),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ApprovalListFilterChip(
                        label: '待我审批 3',
                        active: true,
                        onTap: () {},
                      ),
                      const SizedBox(height: 10),
                      XflowProposalListCard(
                        item: XflowProposalItem(
                          id: 1,
                          businessType: 'PAYMENT',
                          code: 'PAY-20261013-001',
                          title: '设备采购合同付款申请',
                          status: 'PENDING',
                          createdByName: '张三',
                          createdAt: DateTime(2026, 10, 13),
                          documentKind: '业务审批',
                          proposalType: '合同付款',
                        ),
                        onTap: () => opened = true,
                      ),
                      const ApprovalListEmpty(filtered: true),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('PAY-20261013-001'), findsOneWidget);
          expect(find.text('发起人 张三'), findsOneWidget);
          await tester.tap(find.text('PAY-20261013-001'));
          expect(opened, isTrue);
        },
      );
    }
  }
}
