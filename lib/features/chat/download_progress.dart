/// Emits at most five intermediate updates per second, without pending timers.
class DownloadProgressReporter {
  DownloadProgressReporter(this.onProgress) : _clock = Stopwatch()..start();
  final void Function(double)? onProgress;
  final Stopwatch _clock;
  int _lastUpdate = -200;

  void received(int bytes, int? total) {
    if (total == null || total <= 0) return;
    final now = _clock.elapsedMilliseconds;
    if (now - _lastUpdate < 200) return;
    _lastUpdate = now;
    // 100% means the file was committed, not merely received from the socket.
    onProgress?.call((bytes / total).clamp(0.0, 0.99));
  }

  void complete() => onProgress?.call(1.0);
}
