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

  test('salesScale is not treated as sales contract field', () {
    const review = {'marketCompleted': true, 'salesContractCompleted': true};
    expect(
      proposalIntakeFormKeyLocked('salesScale', const {}, review),
      isFalse,
    );
  });
}
