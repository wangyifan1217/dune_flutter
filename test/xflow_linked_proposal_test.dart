import 'package:dunes_app/features/xflow/xflow_detail_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseLinkedProposalId reads picker payload', () {
    expect(
      parseLinkedProposalId({
        'proposalId': 18,
        'code': 'PI-18',
        'title': '已完成协作',
        'source': 'proposal_intake',
      }),
      18,
    );
    expect(parseLinkedProposalId(7), 7);
    expect(parseLinkedProposalId(null), 0);
  });

  test('parseLinkedProposalSource prefers intake markers', () {
    expect(
      parseLinkedProposalSource({
        'proposalId': 18,
        'source': 'proposal_intake',
      }),
      linkedProposalSourceIntake,
    );
    expect(
      parseLinkedProposalSource({
        'id': 18,
        'businessType': 'PROPOSAL_INTAKE',
      }),
      linkedProposalSourceIntake,
    );
    expect(
      parseLinkedProposalSource({'proposalId': 3, 'code': 'S-1', 'title': '销售'}),
      '',
    );
  });

  test('linkedProposalIntakePayload stores source for routing', () {
    final payload = linkedProposalIntakePayload(
      id: 22,
      code: 'PI-22',
      title: '协作完成',
    );
    expect(payload['proposalId'], 22);
    expect(payload['source'], linkedProposalSourceIntake);
    expect(payload['businessType'], 'PROPOSAL_INTAKE');
    expect(parseLinkedProposalId(payload), 22);
    expect(linkedProposalOpensIntake(parseLinkedProposalSource(payload)), isTrue);
  });

  test('legacy sales ids still open B10 rather than intake', () {
    expect(linkedProposalOpensIntake(''), isFalse);
    expect(linkedProposalOpensIntake('sales-proposal'), isFalse);
    expect(linkedProposalOpensIntake('proposal_intake'), isTrue);
  });
}
