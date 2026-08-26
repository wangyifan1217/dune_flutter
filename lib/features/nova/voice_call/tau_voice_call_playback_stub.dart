import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

Future<void> playTauVoiceBytes(
  AudioPlayer player,
  Uint8List bytes,
  String mimeType, {
  bool Function()? isCancelled,
}) async {
  if (isCancelled?.call() == true) return;
  await player.setAudioSource(
    AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: mimeType)),
  );
  if (isCancelled?.call() == true) return;
  await player.setVolume(1);
  await player.play();
}

Future<void> stopTauVoicePlayback(AudioPlayer player) => player.stop();
