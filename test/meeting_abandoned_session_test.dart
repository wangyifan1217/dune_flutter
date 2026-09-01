import 'package:dunes_app/features/meeting/meeting_abandoned_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatAbandonedDuration uses minutes for typical meetings', () {
    expect(formatAbandonedDuration(const Duration(seconds: 12)), '12 秒');
    expect(formatAbandonedDuration(const Duration(minutes: 8)), '8 分钟');
    expect(
      formatAbandonedDuration(const Duration(minutes: 8, seconds: 20)),
      '8 分 20 秒',
    );
    expect(formatAbandonedDuration(const Duration(hours: 1, minutes: 5)), '1 小时 5 分钟');
  });

  test('prompt tells user the file can be restored as draft', () {
    const rec = AbandonedMeetingRecording(
      title: '周会',
      durationMs: 12 * 60 * 1000,
      segmentCount: 3,
    );
    final text = abandonedMeetingPrompt(rec);
    expect(text, contains('周会'));
    expect(text, contains('12 分钟'));
    expect(text, contains('草稿'));
  });
}
