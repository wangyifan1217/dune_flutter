import 'package:dunes_app/features/conversation/inbox_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 10, 15, 4);

  test('当天消息只显示时分', () {
    expect(
      InboxFormat.msgTimeLabel(DateTime(2026, 9, 10, 9, 8), now: now),
      '09:08',
    );
  });

  test('昨天消息显示昨天加时分', () {
    expect(
      InboxFormat.msgTimeLabel(DateTime(2026, 9, 9, 21, 6), now: now),
      '昨天 21:06',
    );
  });

  test('前天消息显示前天加时分', () {
    expect(
      InboxFormat.msgTimeLabel(DateTime(2026, 9, 8, 14, 32), now: now),
      '前天 14:32',
    );
  });

  test('更早的同年消息在时间前加日期', () {
    expect(
      InboxFormat.msgTimeLabel(DateTime(2026, 8, 1, 8, 0), now: now),
      '8月1日 08:00',
    );
  });

  test('跨年消息在时间前加年月日', () {
    expect(
      InboxFormat.msgTimeLabel(DateTime(2025, 12, 31, 23, 5), now: now),
      '2025年12月31日 23:05',
    );
  });
}
