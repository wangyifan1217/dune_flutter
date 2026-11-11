import 'package:dunes_app/features/attendance/attendance_location.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

Position _position({
  required double accuracy,
  required DateTime timestamp,
  double latitude = 30.473298,
}) {
  return Position(
    longitude: 114.409767,
    latitude: latitude,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  final now = DateTime.utc(2026, 11, 10, 1, 30);

  test('a fresh coarse sample does not replace a tight fix', () {
    final tight = _position(accuracy: 18, timestamp: now);
    final coarse = _position(
      accuracy: 2814,
      timestamp: now.add(const Duration(seconds: 2)),
      latitude: 30.559622,
    );

    expect(betterAttendancePosition(tight, coarse, now), same(tight));
  });

  test('a cell fix yields to the later satellite fix', () {
    final cell = _position(
      accuracy: 2814,
      timestamp: now,
      latitude: 30.559622,
    );
    final satellite = _position(
      accuracy: 22,
      timestamp: now.add(const Duration(seconds: 4)),
    );

    expect(betterAttendancePosition(cell, satellite, now), same(satellite));
  });

  test('an older precise point stays when the new sample is only a cell fix', () {
    final shown = _position(
      accuracy: 20,
      timestamp: now.subtract(const Duration(minutes: 2)),
    );
    final cell = _position(
      accuracy: 2814,
      timestamp: now,
      latitude: 30.559622,
    );

    expect(betterAttendancePosition(shown, cell, now), same(shown));
  });

  test('a satellite fix is not replaced by a later indoor estimate', () {
    final satellite = _position(accuracy: 20, timestamp: now);
    final indoor = _position(
      accuracy: 90,
      timestamp: now.add(const Duration(seconds: 8)),
    );

    expect(
      betterAttendancePosition(
        satellite,
        indoor,
        now.add(const Duration(seconds: 8)),
      ),
      same(satellite),
    );
  });

  test('stale and invalid samples are ignored', () {
    final current = _position(accuracy: 40, timestamp: now);
    final stale = _position(
      accuracy: 8,
      timestamp: now.subtract(const Duration(minutes: 30)),
      latitude: 31,
    );
    final invalid = _position(accuracy: -1, timestamp: now);

    expect(betterAttendancePosition(current, stale, now), same(current));
    expect(betterAttendancePosition(current, invalid, now), same(current));
    expect(betterAttendancePosition(null, stale, now), isNull);
  });

  test('a recent cached point is kept when no newer sample exists', () {
    final cached = _position(
      accuracy: 35,
      timestamp: now.subtract(const Duration(seconds: 45)),
    );

    expect(betterAttendancePosition(null, cached, now), same(cached));
    expect(attendanceSampleIsLive(cached, now), isFalse);
    expect(attendanceSampleIsRecent(cached, now), isTrue);
  });

  test('a cache from half an hour ago is not reused', () {
    final cached = _position(
      accuracy: 12,
      timestamp: now.subtract(const Duration(minutes: 30)),
    );

    expect(betterAttendancePosition(null, cached, now), isNull);
    expect(attendanceSampleIsRecent(cached, now), isFalse);
  });

  test('waiting stops for a live precise fix and a short-lived precise cache', () {
    final live = _position(accuracy: 28, timestamp: now);
    final cache = _position(
      accuracy: 20,
      timestamp: now.subtract(const Duration(seconds: 40)),
    );
    final coarseCache = _position(
      accuracy: 2814,
      timestamp: now.subtract(const Duration(seconds: 40)),
      latitude: 30.559622,
    );

    expect(
      attendanceShouldStopWaiting(
        position: live,
        now: now,
        waited: const Duration(seconds: 1),
      ),
      isTrue,
    );
    expect(
      attendanceShouldStopWaiting(
        position: cache,
        now: now,
        waited: const Duration(seconds: 2),
      ),
      isFalse,
    );
    expect(
      attendanceShouldStopWaiting(
        position: cache,
        now: now,
        waited: attendanceCachedPreciseGrace,
      ),
      isTrue,
    );
    expect(
      attendanceShouldStopWaiting(
        position: coarseCache,
        now: now,
        waited: const Duration(seconds: 18),
      ),
      isFalse,
    );
    final indoorCache = _position(
      accuracy: 90,
      timestamp: now.subtract(const Duration(seconds: 40)),
    );
    expect(
      attendanceShouldStopWaiting(
        position: indoorCache,
        now: now,
        waited: const Duration(seconds: 2),
      ),
      isFalse,
    );
    expect(
      attendanceShouldStopWaiting(
        position: indoorCache,
        now: now,
        waited: attendanceCachedPreciseGrace,
      ),
      isTrue,
    );
  });

  test('the first kilometre-scale sample is not ready to use', () {
    final cell = _position(accuracy: 2814, timestamp: now);

    expect(attendanceFixIsReady(cell, Duration.zero), isFalse);
    expect(attendanceFixIsReady(cell, const Duration(seconds: 18)), isFalse);
    expect(
      attendanceFixIsReady(
        _position(accuracy: 28, timestamp: now),
        const Duration(seconds: 1),
      ),
      isTrue,
    );
    expect(
      attendanceFixIsReady(
        _position(accuracy: 90, timestamp: now),
        const Duration(seconds: 3),
      ),
      isTrue,
    );
    expect(
      attendanceFixIsReady(
        _position(accuracy: 90, timestamp: now),
        const Duration(seconds: 2),
      ),
      isFalse,
    );
  });
}
