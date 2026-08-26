import 'package:dunes_app/features/nova/voice_call/tau_voice_call_barge_in.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ignores loud peaks during the playback grace period', () {
    final bargeIn = TauVoiceCallBargeIn();
    final started = DateTime(2026, 8, 26, 20, 30);
    bargeIn.onPlaybackStarted(started);

    expect(bargeIn.observePeak(12000, started.add(const Duration(milliseconds: 200))), isFalse);
    expect(bargeIn.observePeak(12000, started.add(const Duration(milliseconds: 400))), isFalse);
  });

  test('requires consecutive loud chunks after the grace period', () {
    final bargeIn = TauVoiceCallBargeIn();
    final started = DateTime(2026, 8, 26, 20, 30);
    bargeIn.onPlaybackStarted(started);
    final afterGrace = started.add(const Duration(milliseconds: 500));

    expect(bargeIn.observePeak(2500, afterGrace), isFalse);
    expect(bargeIn.observePeak(2500, afterGrace.add(const Duration(milliseconds: 80))), isTrue);
  });

  test('quiet chunk resets the consecutive voice count', () {
    final bargeIn = TauVoiceCallBargeIn();
    final started = DateTime(2026, 8, 26, 20, 30);
    bargeIn.onPlaybackStarted(started);
    final afterGrace = started.add(const Duration(milliseconds: 500));

    expect(bargeIn.observePeak(2500, afterGrace), isFalse);
    expect(bargeIn.observePeak(200, afterGrace.add(const Duration(milliseconds: 80))), isFalse);
    expect(bargeIn.observePeak(2500, afterGrace.add(const Duration(milliseconds: 160))), isFalse);
    expect(bargeIn.observePeak(2500, afterGrace.add(const Duration(milliseconds: 240))), isTrue);
  });
}
