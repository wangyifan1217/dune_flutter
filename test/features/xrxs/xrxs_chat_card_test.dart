import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/xrxs/xrxs_chat_card.dart';

void main() {
  test('XrxsChatCard parses approval payload', () {
    final card = XrxsChatCard.fromPayload({
      'type': 'xrxsApprovalCard',
      'xrxsCard': {
        'sid': 'sid-1',
        'title': '张三的请假',
        'subtitle': '审批待办',
        'statusLabel': '待审批',
        'eventType': 'flow_todo',
        'roleHint': 'approver',
      },
    });
    expect(card, isNotNull);
    expect(card!.sid, 'sid-1');
    expect(card.title, '张三的请假');
    expect(card.canOpenDetail, isTrue);
  });

  test('XrxsChatCard opens attendance confirmation without an approval sid', () {
    final card = XrxsChatCard.fromPayload({
      'type': 'xrxsApprovalCard',
      'xrxsCard': {
        'title': '考勤确认通知',
        'subtitle': '您收到一个新的考勤确认单，去查看',
        'statusLabel': '待确认',
        'eventType': 'attendance_confirm',
        'url':
            'https://e.xinrenxinshi.com/smart-attendance/pages/confirmations/detail/detail?id=106',
      },
    });
    expect(card, isNotNull);
    expect(card!.sid, isEmpty);
    expect(card.opensAttendanceConfirm, isTrue);
    expect(card.canOpenDetail, isTrue);
    expect(card.url, contains('id=106'));
  });

  test('XrxsChatCard rejects unrelated payload', () {
    expect(XrxsChatCard.fromPayload({'type': 'driveEvent'}), isNull);
  });
}
