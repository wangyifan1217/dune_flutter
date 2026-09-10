import 'package:dunes_app/features/proposal_intake/proposal_intake_unreviewed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('write-off amount can change while reviewed profit stays', () {
    const review = {
      'marketCompleted': true,
      'financeItems': {
        'profit': true,
        'revenue': true,
        'margin': true,
      },
    };
    const baseline = {
      'writeOffAmount': 2000,
      'profit': 66.2,
      'revenue': 1274.4,
      'margin': 5.2,
      'proposalName': '已复核名称',
      'contractFieldEdits': {'salesName': 'old'},
    };
    final got = proposalIntakeKeepUnreviewedForm(
      baseline: baseline,
      current: {
        'writeOffAmount': 2787.5,
        'profit': 99,
        'revenue': 2000,
        'margin': 9.9,
        'proposalName': '不该改',
        'contractFieldEdits': {'salesName': 'new'},
      },
      review: review,
    );
    expect(got['writeOffAmount'], 2787.5);
    expect(got['profit'], 66.2);
    expect(got['revenue'], 1274.4);
    expect(got['margin'], 5.2);
    expect(got['proposalName'], '已复核名称');
    expect(got['contractFieldEdits'], {'salesName': 'old'});
    expect(proposalIntakeFormKeyLocked('writeOffAmount', baseline, review), isFalse);
    expect(proposalIntakeFormKeyLocked('profit', baseline, review), isTrue);
  });

  test('rejected sku settlement can change while reviewed rows stay', () {
    const review = {
      'marketCompleted': true,
      'financeCompleted': false,
      'financeItems': {
        'skuSettle:sku-1:st-a': true,
        'skuSettle:sku-1:st-b': false,
      },
      'itemRejectComments': {
        'financeItem:skuSettle:sku-1:st-b': '请修改结算规则',
      },
    };
    const baseline = {
      'proposalName': '已复核名称',
      'skuDetails': [
        {
          'id': 'sku-1',
          'productName': '江苏中石油400元电子券',
          'settlements': [
            {'id': 'st-a', 'settleRatio': '90'},
            {'id': 'st-b', 'settleRatio': '97.5'},
          ],
        },
      ],
    };
    final got = proposalIntakeKeepUnreviewedForm(
      baseline: baseline,
      current: {
        'proposalName': '不该改',
        'skuDetails': [
          {
            'id': 'sku-1',
            'productName': '被改掉的品名',
            'settlements': [
              {'id': 'st-a', 'settleRatio': '1'},
              {'id': 'st-b', 'settleRatio': '88'},
            ],
          },
        ],
      },
      review: review,
    );
    expect(got['proposalName'], '已复核名称');
    final rows = got['skuDetails'] as List;
    final sku = rows.single as Map;
    expect(sku['productName'], '江苏中石油400元电子券');
    final settlements = sku['settlements'] as List;
    expect(settlements[0]['settleRatio'], '90');
    expect(settlements[1]['settleRatio'], '88');
    expect(
      proposalIntakeFormKeyLocked('skuDetails', baseline, review),
      isFalse,
    );
  });

  test('salesScale is not treated as sales contract field', () {
    const review = {'marketCompleted': true, 'salesContractCompleted': true};
    expect(
      proposalIntakeFormKeyLocked('salesScale', const {}, review),
      isFalse,
    );
  });
}
