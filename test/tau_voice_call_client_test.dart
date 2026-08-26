import 'package:dunes_app/features/nova/voice_call/tau_voice_call_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefers WAV audioBase64 over legacy PCM', () {
    final reply = TauVoiceCallReply.fromData({
      'audioBase64': 'wav-data',
      'audioPcmBase64': 'pcm-data',
      'audioFormat': 'wav',
      'mimeType': 'audio/wav',
      'sampleRate': 24000,
      'channels': 1,
      'bitsPerSample': 16,
    });

    expect(reply.audioBase64, 'wav-data');
    expect(reply.isRawPcm, isFalse);
    expect(reply.sampleRate, 24000);
    expect(reply.channels, 1);
    expect(reply.bitsPerSample, 16);
  });

  test('uses legacy audioPcmBase64 only when WAV is absent', () {
    final reply = TauVoiceCallReply.fromData({
      'audioPcmBase64': 'pcm-data',
      'sampleRate': 24000,
    });

    expect(reply.audioBase64, 'pcm-data');
    expect(reply.isRawPcm, isTrue);
  });
}
