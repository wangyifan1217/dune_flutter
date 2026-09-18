import 'package:dunes_app/features/reconciliation/reconciliation_shucai_models.dart';
import 'package:dunes_app/features/reconciliation/tag3_daily_models.dart';
import 'package:dunes_app/features/reconciliation/tag3_daily_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconCardTitle names tag3 daily', () {
    expect(reconCardTitle('TAG3_DAILY'), '业财一体-日清月结');
    expect(isTag3DailyCard('tag3_daily'), isTrue);
  });

  test('Tag3DailySnapshot parses confirm flags and sorts periods', () {
    final snap = Tag3DailySnapshot.fromJson({
      'asOfDate': '2026-09-15',
      'rows': [
        {
          'rowKey': '多渠道|亿科景信',
          'channelCategoryL1Name': '多渠道',
          'projectName': '亿科景信',
          'period': 'MONTH',
          'periodLabel': '本月累计',
          'salesAmount': 14830,
          'confirmationStatus': 'WAIT_BUSINESS',
          'confirmationStatusLabel': '待业务确认',
          'canConfirm': true,
          'canConfirmStage': 'BUSINESS',
        },
        {
          'rowKey': '多渠道|亿科景信',
          'channelCategoryL1Name': '多渠道',
          'projectName': '亿科景信',
          'period': 'DAY',
          'periodLabel': '2026-09-14',
          'statDate': '2026-09-14 00:00:00',
          'salesAmount': 800,
          'confirmationStatus': 'WAIT_BUSINESS',
          'canConfirm': true,
          'canConfirmStage': 'BUSINESS',
        },
        {
          'rowKey': '多渠道|亿科景信',
          'channelCategoryL1Name': '多渠道',
          'projectName': '亿科景信',
          'period': 'DAY',
          'periodLabel': '2026-09-15',
          'statDate': '2026-09-15 00:00:00',
          'salesAmount': 720,
          'confirmationStatus': 'WAIT_BUSINESS',
          'canConfirm': true,
          'canConfirmStage': 'BUSINESS',
        },
      ],
      'assignees': [
        {
          'rowKey': '多渠道|亿科景信',
          'businessUsers': [
            {'userId': 12, 'name': '张三', 'phone': '13800001111'},
          ],
          'operationUsers': [
            {'userId': 15, 'name': '李四', 'phone': '13900002222'},
          ],
        },
      ],
      'comments': [
        {
          'id': 1,
          'rowKey': '多渠道|亿科景信',
          'period': 'DAY',
          'statDate': '2026-09-14',
          'userId': 12,
          'userName': '张三',
          'kind': 'COMMENT',
          'body': '核销偏少，先记一笔',
          'createdAt': '2026-09-15T02:00:00Z',
        },
      ],
    });
    expect(snap.rows.length, 3);
    expect(snap.confirmableRows.length, 2);
    expect(snap.rows.where((r) => r.isMonthCumulative).first.showConfirmAction, isFalse);
    expect(snap.rows.where((r) => r.isMonthCumulative).first.showCommentAction, isFalse);
    expect(snap.confirmableRows.every((r) => r.period == 'DAY'), isTrue);
    expect(snap.rows.where((r) => r.period == 'DAY').every((r) => r.showCommentAction), isTrue);
    expect(snap.commentsFor(snap.rows.firstWhere((r) => r.periodLabel == '2026-09-14')).single.userName, '张三');
    expect(snap.commentsFor(snap.rows.firstWhere((r) => r.periodLabel == '2026-09-15')), isEmpty);
    final sorted = sortTag3DailyRows(snap.rows);
    expect(sorted.first.period, 'DAY');
    expect(sorted.last.period, 'MONTH');
    expect(tag3DailyPercent(0.0051), '0.51%');
    expect(tag3DailyMoney(15), '15.00');
    expect(tag3DailyConfirmButtonLabel('BUSINESS'), '确认');
    expect(tag3DailyConfirmButtonLabel('OPERATION'), '确认');
    final empty = tag3DailyAuditLanes(
      assignee: snap.assigneeFor('多渠道|亿科景信'),
    );
    expect(empty[0].done, isFalse);
    expect(empty[0].names, '张三');
    expect(empty[1].done, isFalse);
    expect(empty[1].names, '李四');
    expect(empty[0].statusLabel, '未确认');
    final withBiz = tag3DailyAuditLanes(
      assignee: snap.assigneeFor('多渠道|亿科景信'),
      comments: snap.commentsFor(snap.rows.firstWhere((r) => r.periodLabel == '2026-09-14')),
    );
    expect(withBiz[0].done, isFalse);
    final confirmed = tag3DailyAuditLanes(
      assignee: snap.assigneeFor('多渠道|亿科景信'),
      comments: [
        Tag3DailyComment(
          id: 2,
          rowKey: '多渠道|亿科景信',
          period: 'DAY',
          statDate: '2026-09-14',
          periodLabel: '2026-09-14',
          projectName: '亿科景信',
          userId: 12,
          userName: '张三',
          kind: 'CONFIRM',
          stage: 'BUSINESS',
          body: '',
          createdAt: '2026-09-15T02:00:00Z',
        ),
      ],
    );
    expect(confirmed[0].done, isTrue);
    expect(confirmed[1].done, isFalse);
  });

  test('today preview injects TAG3_DAILY card with 日清 and 月结 rows', () {
    final asOf = tag3DailyPreviewAsOfDate(DateTime(2026, 9, 17));
    expect(asOf, '2026-09-17');
    final snap = tag3DailyPreviewSnapshot(asOfDate: asOf);
    expect(snap.asOfDate, '2026-09-17');
    expect(snap.rows.where((r) => r.period == 'DAY'), hasLength(4));
    expect(snap.rows.where((r) => r.isMonthCumulative), hasLength(2));
    expect(snap.rows.where((r) => r.isMonthCumulative).every((r) => !r.showConfirmAction), isTrue);
    final injected = withTag3DailyPreview(const [], asOfDate: asOf);
    if (kTag3DailyStaticPreview) {
      expect(injected, hasLength(1));
      expect(injected.single.payload?['cardType'], 'TAG3_DAILY');
      expect(injected.single.payload?['asOfDate'], '2026-09-17');
    } else {
      expect(injected, isEmpty);
    }
  });

  test('date list shows daily dispatch copy and confirm status', () {
    expect(
      tag3DailyDispatchBody('2026-09-06'),
      '2026-09-06 业财一体-日清月结已生成，业务/运营请各自核对并确认',
    );
    expect(
      tag3DailyDateStatusPill(myConfirmed: true, confirmRows: 0),
      '你已确认',
    );
    expect(
      tag3DailyDateStatusPill(myConfirmed: false, confirmRows: 2),
      '已有确认',
    );
    expect(
      tag3DailyDateStatusPill(myConfirmed: false, confirmRows: 0),
      '待确认',
    );
    expect(
      tag3DailyDateProgressLine(
        businessConfirmRows: 2,
        operationConfirmRows: 1,
        commentCount: 3,
      ),
      '业务已确认 2 条 · 运营已确认 1 条 · 意见 3 条',
    );
    expect(
      tag3DailySnapshotStatusLine([
        Tag3DailyRow.fromJson({
          'rowKey': 'a',
          'period': 'DAY',
          'confirmationStatus': 'WAIT_BUSINESS',
        }),
        Tag3DailyRow.fromJson({
          'rowKey': 'a',
          'period': 'DAY',
          'confirmationStatus': 'WAIT_OPERATION',
        }),
        Tag3DailyRow.fromJson({
          'rowKey': 'a',
          'period': 'DAY',
          'confirmationStatus': 'ALL_CONFIRMED',
        }),
        Tag3DailyRow.fromJson({
          'rowKey': 'a',
          'period': 'MONTH',
          'confirmationStatus': 'WAIT_BUSINESS',
        }),
      ]),
      '3 条日行 · 待业务确认 1 · 待运营确认 1 · 已完成 1',
    );
    expect(
      ReconDateItem.fromJson({
        'asOfDate': '2026-09-06',
        'tag3ConfirmRows': 2,
        'tag3BusinessConfirmRows': 2,
        'tag3OperationConfirmRows': 1,
        'tag3CommentCount': 4,
        'tag3MyConfirmed': true,
      }).tag3MyConfirmed,
      isTrue,
    );
  });

  test('date list pads through yesterday when snapshots stopped', () {
    final padded = padTag3DailyDateItems(
      const [
        ReconDateItem(asOfDate: '2026-09-06'),
        ReconDateItem(asOfDate: '2026-09-05'),
      ],
      now: DateTime(2026, 9, 18, 9, 44),
    );
    expect(padded.first.asOfDate, '2026-09-17');
    expect(
      padded.map((e) => e.asOfDate),
      containsAll(['2026-09-17', '2026-09-07', '2026-09-06', '2026-09-05']),
    );
  });
}
