import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/xflow/approval_chat_share.dart';
import 'package:dunes_app/features/xflow/proposal_intake_share_card.dart';

void main() {
  testWidgets('generic proposal card title is replaced with the proposal name', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalIntakeShareCard(
            share: const ApprovalChatShare(
              businessType: 'PROPOSAL_INTAKE',
              businessId: 8,
              title: '协作提案',
              submitterName: '李博睿',
            ),
            loadTitle: (_) async => '广西卡品提案',
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('协作提案'), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.text('广西卡品提案'), findsOneWidget);
    expect(find.text('李博睿 提交'), findsOneWidget);
  });
}
