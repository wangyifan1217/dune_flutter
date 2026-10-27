import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:dunes_app/features/xflow/approval_chat_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('change summary and diff stay readable after redaction', () {
    final summary = ProposalIntakeChangeSummary.tryParse({
      'id': 9,
      'status': 'reviewing',
      'reason': '改规模',
      'myAction': 'change_review_finance',
      'myActionLabel': '待逐条复核变更（财务）',
      'affectedSections': ['finance'],
      'version': 3,
    });
    expect(summary?.id, 9);
    expect(summary?.myAction, 'change_review_finance');
    expect(proposalIntakeChangeStatusLabel('returned'), '已驳回待修改');
    expect(proposalIntakeChangeFieldLabel('projectBackground'), '项目背景');
    expect(proposalIntakeChangeValueText(null, exists: false), '（空）');
    expect(proposalIntakeChangeValueText(['甲', '乙']), '甲、乙');

    final change = ProposalIntakeChange.fromJson({
      'id': 9,
      'proposalId': 4,
      'status': 'reviewing',
      'version': 3,
      'financeItemKeys': ['salesScale', 'skuDetails'],
      'review': {
        'financeItems': {
          'salesScale': {'status': 'approved'},
        },
      },
      'diff': [
        {
          'key': 'salesScale',
          'sections': ['finance'],
          'changes': [
            {
              'path': ['salesScale'],
              'oldValue': '100',
              'newValue': '200',
              'oldExists': true,
              'newExists': true,
            },
          ],
        },
      ],
    });
    expect(change.pendingFinanceItems, ['skuDetails']);
    expect(change.diff.single.changes.single.newValue, '200');
    expect(
      proposalIntakeChangePathLabel(change.diff.single.changes.single.path),
      contains('销售规模'),
    );
  });

  test('approval card keeps the change id for the assistant jump', () {
    final share = ApprovalChatShare.fromPayload({
      'approvalCard': {
        'businessType': 'PROPOSAL_INTAKE',
        'businessId': 4,
        'title': '广西卡品',
        'changeId': 9,
        'tag': '提案变更',
        'actionLabel': '请复核',
      },
    });
    expect(share?.changeId, 9);
    expect(share?.proposalCardLine, '提案变更 · 请复核');
    final again = ApprovalChatShare.fromPayload(share!.toMessagePayload());
    expect(again?.changeId, 9);
    expect(again?.tag, '提案变更');
  });

  test('task banner points a change todo at the change', () {
    expect(proposalIntakeTaskBannerTitle('change_review_market'), contains('市场部'));
    expect(proposalIntakeNavJumpLabel('change_notify_final'), '打开变更');
    expect(proposalIntakeActionLabel('change_revise'), '变更已驳回请修改');
  });
}
