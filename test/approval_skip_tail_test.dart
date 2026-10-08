import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:dunes_app/features/xflow/approval_pending_nav.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter_test/flutter_test.dart';

XflowProposalItem _approval(int id) => XflowProposalItem(
  id: id,
  businessType: 'PROPOSAL',
  code: 'P-$id',
  title: '审批$id',
  status: 'OPEN',
  createdByName: '测试',
  createdAt: DateTime(2026, 10, 8),
);

ProposalIntakeRow _proposal(int id) => ProposalIntakeRow.fromJson({
  'id': id,
  'code': 'TA-$id',
  'status': 'pending_president',
});

void main() {
  setUp(() {
    ApprovalSkipTail.reset();
    ProposalSkipTail.reset();
  });

  test('skipped approval stays behind the rest in skip order', () {
    final queue = [_approval(1), _approval(2), _approval(3)];

    final afterSkip = ApprovalSkipTail.pick(
      items: queue,
      businessType: 'PROPOSAL',
      businessId: 1,
      afterDecision: false,
    );
    expect(afterSkip?.id, 2);

    final afterNextApproved = ApprovalSkipTail.pick(
      items: [_approval(1), _approval(3)],
      businessType: 'PROPOSAL',
      businessId: 2,
      afterDecision: true,
    );
    expect(afterNextApproved?.id, 3);

    final skippedLast = ApprovalSkipTail.pick(
      items: [_approval(1)],
      businessType: 'PROPOSAL',
      businessId: 3,
      afterDecision: true,
    );
    expect(skippedLast?.id, 1);
  });

  test('several skips keep their order at the tail', () {
    final queue = [_approval(1), _approval(2), _approval(3)];
    expect(
      ApprovalSkipTail.pick(
        items: queue,
        businessType: 'PROPOSAL',
        businessId: 1,
        afterDecision: false,
      )?.id,
      2,
    );
    expect(
      ApprovalSkipTail.pick(
        items: queue,
        businessType: 'PROPOSAL',
        businessId: 2,
        afterDecision: false,
      )?.id,
      3,
    );

    final afterThirdApproved = ApprovalSkipTail.pick(
      items: [_approval(1), _approval(2)],
      businessType: 'PROPOSAL',
      businessId: 3,
      afterDecision: true,
    );
    expect(afterThirdApproved?.id, 1);

    final secondSkip = ApprovalSkipTail.pick(
      items: [_approval(2)],
      businessType: 'PROPOSAL',
      businessId: 1,
      afterDecision: true,
    );
    expect(secondSkip?.id, 2);
  });

  test('skipping the last open approval does not wrap', () {
    expect(
      ApprovalSkipTail.pick(
        items: [_approval(1)],
        businessType: 'PROPOSAL',
        businessId: 1,
        afterDecision: false,
      ),
      isNull,
    );
    final stillFirst = ApprovalSkipTail.pick(
      items: [_approval(1), _approval(2)],
      businessType: 'PROPOSAL',
      businessId: 9,
      afterDecision: true,
    );
    expect(stillFirst?.id, 1);
  });

  test('skipped proposal stays behind later approvals', () {
    final queue = [_proposal(1), _proposal(2), _proposal(3)];
    expect(
      ProposalSkipTail.pick(
        items: queue,
        currentId: 1,
        afterDecision: false,
      )?.id,
      2,
    );
    expect(
      ProposalSkipTail.pick(
        items: [_proposal(1), _proposal(3)],
        currentId: 2,
        afterDecision: true,
      )?.id,
      3,
    );
    expect(
      ProposalSkipTail.pick(
        items: [_proposal(1)],
        currentId: 3,
        afterDecision: true,
      )?.id,
      1,
    );
  });
}
