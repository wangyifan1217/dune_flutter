import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/attendance/attendance_models.dart';

void main() {
  test('parses optional schedule and preserves it when recording a punch', () {
    final today = AttendanceToday.fromJson({
      'date': '2026-11-07',
      'sites': [],
      'schedule': {'startTime': '09:00', 'endTime': '18:00'},
    });
    final punch = AttendancePunch.fromJson({
      'id': 1,
      'type': 'check_in',
      'punchedAt': '2026-11-07T01:00:00Z',
    });
    final updated = today.withPunch(punch);
    expect(updated.startTime, '09:00');
    expect(updated.endTime, '18:00');
    expect(updated.checkIn, punch);
    expect(updated.nextPunchType, 'check_out');
    expect(AttendanceToday.fromJson({'sites': []}).startTime, isEmpty);
  });
}
