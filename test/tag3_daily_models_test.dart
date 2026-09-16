import 'package:dunes_app/features/reconciliation/reconciliation_shucai_models.dart';
import 'package:dunes_app/features/reconciliation/tag3_daily_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconCardTitle names tag3 daily', () {
    expect(reconCardTitle('TAG3_DAILY'), '业财一体-日清');
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
    expect(tag3DailyConfirmButtonLabel('BUSINESS'), '业务确认');
    expect(tag3DailyConfirmButtonLabel('OPERATION'), '运营确认');
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
}
