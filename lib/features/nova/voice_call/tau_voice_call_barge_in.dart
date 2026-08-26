/// Detects user barge-in while τ is playing a reply.
///
/// Playback echo is ignored for a short grace period, then a louder and
/// sustained peak is required before the current reply is cut off.
class TauVoiceCallBargeIn {
  TauVoiceCallBargeIn({
    this.ignorePlayback = const Duration(milliseconds: 480),
    this.peakThreshold = 2200,
    this.requiredVoicedChunks = 2,
  });

  final Duration ignorePlayback;
  final int peakThreshold;
  final int requiredVoicedChunks;

  DateTime? _startedAt;
  int _voicedChunks = 0;

  void onPlaybackStarted([DateTime? now]) {
    _startedAt = now ?? DateTime.now();
    _voicedChunks = 0;
  }

  void reset() {
    _startedAt = null;
    _voicedChunks = 0;
  }

  bool observePeak(int peak, [DateTime? now]) {
    final startedAt = _startedAt;
    if (startedAt == null) return false;
    final at = now ?? DateTime.now();
    if (at.difference(startedAt) < ignorePlayback) return false;
    if (peak < peakThreshold) {
      _voicedChunks = 0;
      return false;
    }
    _voicedChunks += 1;
    return _voicedChunks >= requiredVoicedChunks;
  }
}
