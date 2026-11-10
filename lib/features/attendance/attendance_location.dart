import 'package:geolocator/geolocator.dart';

/// A satellite or Wi-Fi fix tight enough to stop waiting.
const attendancePreciseAccuracyMeters = 50.0;

/// An indoor fix that is usable once it has had a few seconds to settle.
const attendanceSettledAccuracyMeters = 120.0;

/// Samples newer than this can end the wait as soon as they are accurate.
const attendanceLiveSampleAge = Duration(seconds: 15);

/// A cached fix inside this window is shown when no newer point arrives.
const attendanceCachedSampleAge = Duration(minutes: 2);

/// How long to keep listening after a precise cached point, in case a live
/// fix arrives immediately after.
const attendanceCachedPreciseGrace = Duration(seconds: 3);

bool _accuracyIsValid(double accuracy) {
  return !accuracy.isNaN && !accuracy.isInfinite && accuracy > 0;
}

bool _ageInWindow(Position position, DateTime now, Duration maxAge) {
  if (!_accuracyIsValid(position.accuracy)) return false;
  final age = now.difference(position.timestamp);
  return age >= const Duration(seconds: -5) && age <= maxAge;
}

/// A point from the current satellite or network fix.
bool attendanceSampleIsLive(Position position, DateTime now) {
  return _ageInWindow(position, now, attendanceLiveSampleAge);
}

/// The last fix the phone already has. Old enough to be a cache, new enough
/// that the person is unlikely to have left the office.
bool attendanceSampleIsRecent(Position position, DateTime now) {
  return _ageInWindow(position, now, attendanceCachedSampleAge);
}

/// Prefers a tight fix. Two tight fixes follow the newer sample so a person
/// can move. Two coarse fixes keep the smaller error radius.
Position? betterAttendancePosition(
  Position? current,
  Position next,
  DateTime now,
) {
  if (!attendanceSampleIsRecent(next, now)) return current;
  if (current == null || !_accuracyIsValid(current.accuracy)) return next;
  final nextIsPrecise = next.accuracy <= attendancePreciseAccuracyMeters;
  final currentIsPrecise = current.accuracy <= attendancePreciseAccuracyMeters;
  if (nextIsPrecise && currentIsPrecise) {
    return next.timestamp.isAfter(current.timestamp) ? next : current;
  }
  if (nextIsPrecise) return next;
  if (currentIsPrecise) return current;
  final nextIsSettled = next.accuracy <= attendanceSettledAccuracyMeters;
  final currentIsSettled = current.accuracy <= attendanceSettledAccuracyMeters;
  if (nextIsSettled && currentIsSettled) {
    return next.timestamp.isAfter(current.timestamp) ? next : current;
  }
  if (nextIsSettled) return next;
  if (currentIsSettled) return current;
  return next.accuracy < current.accuracy ? next : current;
}

/// The first iOS sample is often a cell fix of one or two kilometres.
/// Keep listening until the error radius tightens, or until a moderate
/// indoor fix has had time to replace that first sample.
bool attendanceFixIsReady(Position position, Duration waited) {
  if (position.accuracy <= attendancePreciseAccuracyMeters) return true;
  return position.accuracy <= attendanceSettledAccuracyMeters &&
      waited >= const Duration(seconds: 6);
}

/// Text for the accuracy row. A cached point is labeled so it is not mistaken
/// for a brand-new satellite fix.
String? attendanceAccuracyLabel(
  Position? position,
  double? accuracy,
  DateTime now,
) {
  if (accuracy == null || accuracy.isNaN || accuracy <= 0) return null;
  final rounded = accuracy.round();
  final cached =
      position != null &&
      attendanceSampleIsRecent(position, now) &&
      !attendanceSampleIsLive(position, now);
  if (accuracy > attendanceSettledAccuracyMeters) {
    return cached
        ? '约 $rounded 米，仍是粗定位（刚才的缓存）'
        : '约 $rounded 米，仍是粗定位';
  }
  if (cached) return '约 $rounded 米，使用刚才的缓存位置';
  return '约 $rounded 米（仅供参考）';
}

/// A live precise fix stops the wait immediately. A precise cached fix stops
/// after a short grace. A coarse point never stops the wait by itself.
bool attendanceShouldStopWaiting({
  required Position position,
  required DateTime now,
  required Duration waited,
}) {
  if (!attendanceSampleIsRecent(position, now)) return false;
  if (attendanceSampleIsLive(position, now)) {
    return attendanceFixIsReady(position, waited);
  }
  return position.accuracy <= attendancePreciseAccuracyMeters &&
      waited >= attendanceCachedPreciseGrace;
}
