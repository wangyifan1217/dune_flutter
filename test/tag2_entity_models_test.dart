import 'package:dunes_app/features/reconciliation/reconciliation_shucai_models.dart';
import 'package:dunes_app/features/reconciliation/tag2_entity_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tag2 snapshot keeps detail confirm and blocks total actions', () {
    final snap = Tag2EntitySnapshot.fromJson({
      'asOfDate': '2026-09-28',
      'rows': [
        {
          'rowKey': '440000||中石油广东',
          'rowType': 'DETAIL',
          'provinceName': '广东',
          'counterpartyName': '中石油广东',
          'ourEntityName': '我方',
          'confirmationStatus': 'WAIT_BUSINESS',
          'canConfirmStage': 'BUSINESS',
          'amounts': [
            {'key': 'transit', 'label': '在途资金', 'display': '3.00', 'drill': true},
            {'key': 'prepayment', 'label': '期末预付款余额', 'display': '1.00', 'drill': true},
          ],
        },
        {
          'rowKey': 'ALL',
          'rowType': 'TOTAL',
          'amounts': [
            {'key': 'transit', 'label': '在途资金', 'display': '3.00', 'drill': false},
          ],
        },
      ],
      'comments': [
        {
          'id': 1,
          'rowKey': '440000||中石油广东',
          'kind': 'COMMENT',
          'body': '已核对',
          'userName': '甲',
        },
      ],
    });
    expect(snap.rows.first.showConfirm, isTrue);
    expect(snap.rows.first.showComment, isTrue);
    expect(snap.rows.first.title, '广东 · 中石油广东 · 我方');
    expect(snap.rows.last.isTotal, isTrue);
    expect(snap.rows.last.showConfirm, isFalse);
    expect(snap.rows.last.showComment, isFalse);
    expect(snap.rows.last.amounts.single.drill, isFalse);
    expect(snap.commentsFor('440000||中石油广东'), hasLength(1));
    expect(isTag2EntityCard('tag2_entity'), isTrue);
    expect(isTag2EntityCard('TAG3_DAILY'), isFalse);
  });

  test('date item reads tag2 progress separately from tag3', () {
    final item = ReconDateItem.fromJson({
      'asOfDate': '2026-09-28',
      'tag3BusinessConfirmRows': 2,
      'tag2BusinessConfirmRows': 1,
      'tag2CommentCount': 3,
      'tag2MyConfirmed': true,
    });
    expect(item.tag3BusinessConfirmRows, 2);
    expect(item.tag2BusinessConfirmRows, 1);
    expect(item.tag2CommentCount, 3);
    expect(item.tag2MyConfirmed, isTrue);
    expect(item.tag3MyConfirmed, isFalse);
  });
}
