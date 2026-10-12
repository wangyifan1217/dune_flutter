import 'package:dunes_app/features/xflow/xflow_detail_logic.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stored proposal stays visible when disabled template lacks the field', () {
    const detail = XflowProposalDetail(id: 1, code: 'PAY-1', title: '预付款',
      status: 'pending', summary: '', beaconId: '', ownerName: '', amountText: '',
      formValues: {}, products: [], slots: [], createdById: 7, raw: {});
    final fields = [XflowField.fromJson({'key': 'memo', 'type': 'text', 'label': '用途'})];
    final sections = buildFieldSections(fields, {
      'memo': '采购',
      'linkedProposal': linkedProposalIntakePayload(id: 22, code: 'PI-22', title: '原提案'),
    }, detail);
    final links = sections.expand((s) => s.items).where((f) => f.key == 'linkedProposal');
    expect(links, hasLength(1));
    expect(links.single.value, contains('原提案'));
    expect(links.single.field.readonly, isTrue);
    expect(fields, hasLength(1));
  });

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

  test('approval linked intake is treated as collaboration proposal', () {
    final payload = linkedProposalIntakePayload(
      id: 37,
      code: 'TA-20260824-000037',
      title: '抖音渠道中石油产品上线提案',
    );
    expect(linkedProposalOpensIntake(parseLinkedProposalSource(payload)), isTrue);
    expect(parseLinkedProposalId(payload), 37);
  });
}
