import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import 'tau_voice_call_playback_stub.dart'
    if (dart.library.io) 'tau_voice_call_playback_io.dart'
    as impl;

Future<void> playTauVoiceBytes(
  AudioPlayer player,
  Uint8List bytes,
  String mimeType, {
  bool Function()? isCancelled,
}) => impl.playTauVoiceBytes(
  player,
  bytes,
  mimeType,
  isCancelled: isCancelled,
);

Future<void> stopTauVoicePlayback(AudioPlayer player) =>
    impl.stopTauVoicePlayback(player);
