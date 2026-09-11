import 'package:dunes_app/features/proposal_intake/proposal_intake_unreviewed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unreviewed turnover times can change while reviewed profit stays', () {
    const review = {
      'marketCompleted': true,
      'financeItems': {'profit': true, 'revenue': true, 'margin': true},
    };
    const baseline = {
      'turnoverTimes': 2,
      'profit': 66.2,
      'revenue': 1274.4,
      'margin': 5.2,
      'proposalName': '已复核名称',
      'contractFieldEdits': {'salesName': 'old'},
    };
    final got = proposalIntakeKeepUnreviewedForm(
      baseline: baseline,
      current: {
        'turnoverTimes': 4,
        'profit': 99,
        'revenue': 2000,
        'margin': 9.9,
        'proposalName': '不该改',
        'contractFieldEdits': {'salesName': 'new'},
      },
      review: review,
    );
    expect(got['turnoverTimes'], 4);
    expect(got['profit'], 66.2);
    expect(got['revenue'], 1274.4);
    expect(got['margin'], 5.2);
    expect(got['proposalName'], '已复核名称');
    expect(got['contractFieldEdits'], {'salesName': 'old'});
    expect(
      proposalIntakeFormKeyLocked('turnoverTimes', baseline, review),
      isFalse,
    );
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
      'itemRejectComments': {'financeItem:skuSettle:sku-1:st-b': '请修改结算规则'},
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

  test('rejected child product settlement can change while reviewed rows stay', () {
    const review = {
      'marketCompleted': true,
      'financeCompleted': false,
      'financeItems': {
        'skuSettle:child-1:st-a': true,
        'skuSettle:child-1:st-b': false,
      },
    };
    const baseline = {
      'childProducts': [
        {
          'id': 'child-1',
          'productName': '加油100',
          'settlements': [
            {'id': 'st-a', 'settleRatio': '90'},
            {'id': 'st-b', 'settleRatio': '97.5'},
          ],
        },
      ],
      'childTechnology': {'technologyPlatform': '已复核平台'},
    };
    final got = proposalIntakeKeepUnreviewedForm(
      baseline: baseline,
      current: {
        'childProducts': [
          {
            'id': 'child-1',
            'productName': '被改掉的子产品',
            'settlements': [
              {'id': 'st-a', 'settleRatio': '1'},
              {'id': 'st-b', 'settleRatio': '88'},
            ],
          },
        ],
        'childTechnology': {'technologyPlatform': '不该改'},
      },
      review: review,
    );
    final rows = got['childProducts'] as List;
    final child = rows.single as Map;
    expect(child['productName'], '加油100');
    final settlements = child['settlements'] as List;
    expect(settlements[0]['settleRatio'], '90');
    expect(settlements[1]['settleRatio'], '88');
    expect(got['childTechnology']['technologyPlatform'], '不该改');
    expect(
      proposalIntakeFormKeyLocked('childProducts', baseline, review),
      isFalse,
    );
  });

  test('rejected shared settlement can change while reviewed rows stay', () {
    const review = {
      'financeCompleted': false,
      'financeItems': {
        'sharedSettle:ss-1:ss-1': true,
        'sharedSettle:ss-2:ss-2': false,
      },
      'itemRejectComments': {'financeItem:sharedSettle:ss-2:ss-2': '请改比例'},
    };
    const baseline = {
      'sharedSettlements': [
        {'id': 'ss-1', 'settleRatio': '0.926'},
        {'id': 'ss-2', 'settleRatio': '0.90'},
      ],
    };
    final got = proposalIntakeKeepUnreviewedForm(
      baseline: baseline,
      current: {
        'sharedSettlements': [
          {'id': 'ss-1', 'settleRatio': '0.1'},
          {'id': 'ss-2', 'settleRatio': '0.88'},
        ],
      },
      review: review,
    );
    final rows = got['sharedSettlements'] as List;
    expect(rows[0]['settleRatio'], '0.926');
    expect(rows[1]['settleRatio'], '0.88');
  });

  test('salesScale is not treated as sales contract field', () {
    const review = {'marketCompleted': true, 'salesContractCompleted': true};
    expect(
      proposalIntakeFormKeyLocked('salesScale', const {}, review),
      isFalse,
    );
  });

  test('productFinance stays editable after market review', () {
    const review = {'marketCompleted': true};
    expect(
      proposalIntakeFormKeyLocked('productFinance', const {}, review),
      isFalse,
    );
    expect(
      proposalIntakeFormKeyLocked('productFinance', const {}, {
        'financeCompleted': true,
      }),
      isTrue,
    );
    final got = proposalIntakeKeepUnreviewedForm(
      baseline: {
        'productFinance': {
          'main': {'turnoverTimes': 2},
        },
      },
      current: {
        'productFinance': {
          'main': {'turnoverTimes': 4, 'turnoverCash': 16.67},
        },
      },
      review: review,
    );
    expect(
      (got['productFinance'] as Map)['main']['turnoverTimes'],
      4,
    );
  });

  test(
    'finance interface lock follows technology, not stale interface flag',
    () {
      expect(
        proposalIntakeFormKeyLocked('financeInterfaces', const {}, {
          'technologyCompleted': false,
          'financeInterfaceCompleted': true,
        }),
        isFalse,
      );
      expect(
        proposalIntakeFormKeyLocked('financeInterfaces', const {}, {
          'technologyCompleted': true,
        }),
        isTrue,
      );
      expect(
        proposalIntakeFormKeyLocked('financeInterfaces', const {}, {
          'technologyItems': {'financeInterfaces': true},
        }),
        isTrue,
      );
    },
  );
}
