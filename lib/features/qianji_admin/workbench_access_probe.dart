/// Each independent access check can update the UI without waiting for others.
Future<void> publishWorkbenchAccessProbe<T>(
  Future<T> request, {
  required bool Function() isCurrent,
  required void Function(T) onResult,
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    final value = await request.timeout(timeout);
    if (isCurrent()) onResult(value);
  } catch (_) {
    // Keep the previous state on timeout or failure.
  }
}
