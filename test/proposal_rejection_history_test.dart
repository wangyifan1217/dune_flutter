import 'package:flutter_test/flutter_test.dart';
import '../lib/features/proposal_intake/proposal_intake_models.dart';

void main() {
  test('only final rejection history counts, independently of proposal version', () {
    final row = ProposalIntakeRow.fromJson({
      'version': 100,
      'review': {'reviewRejected': true, 'techRevisionRound': 8},
    });
    expect(row.restartCount, 0);
    final resubmitted = row.copyWith(review: {
      'presidentRejected': false,
      'finalRejectionHistory': [
        {'round': 1, 'comment': '补充资料'},
        {'round': 2, 'comment': '重新核算'},
      ],
    });
    expect(resubmitted.restartCount, 2);
    expect(resubmitted.finalRejectionHistory.last['comment'], '重新核算');
  });

  test('legacy final rejection shown once, authoritative history takes precedence', () {
    final row = ProposalIntakeRow.fromJson({
      'review': {
        'presidentRejected': true,
        'presidentComment': '旧意见',
        'presidentRejectUserId': 12,
      },
    });
    expect(row.restartCount, 1);
    expect(row.finalRejectionHistory.single['legacy'], true);
    expect(row.copyWith(review: {
      ...row.review,
      'finalRejectionHistory': [{'round': 1, 'comment': '完整记录'}],
    }).restartCount, 1);
  });
}
