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

  test('XrxsChatCard rejects unrelated payload', () {
    expect(XrxsChatCard.fromPayload({'type': 'driveEvent'}), isNull);
  });
}
