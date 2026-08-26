import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

const _sndSync = 0x0000;
const _sndNoDefault = 0x0002;
const _sndFilename = 0x00020000;

typedef _PlaySoundW =
    int Function(Pointer<Utf16> pszSound, int hmod, int fdwSound);

_PlaySoundW? _lookupPlaySound() {
  if (!Platform.isWindows) return null;
  return DynamicLibrary.open('winmm.dll').lookupFunction<
    Int32 Function(Pointer<Utf16> pszSound, IntPtr hmod, Uint32 fdwSound),
    _PlaySoundW
  >('PlaySoundW');
}

Future<void> playTauVoiceBytes(
  AudioPlayer player,
  Uint8List bytes,
  String mimeType, {
  bool Function()? isCancelled,
}) async {
  if (isCancelled?.call() == true) return;
  final ext = mimeType.contains('wav')
      ? 'wav'
      : mimeType.contains('ogg')
      ? 'ogg'
      : 'mp3';
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}${Platform.pathSeparator}tau_voice_${DateTime.now().microsecondsSinceEpoch}.$ext',
  );
  await file.writeAsBytes(bytes, flush: true);
  if (isCancelled?.call() == true) return;
  if (Platform.isWindows && ext == 'wav' && await _playWindowsWav(file.path)) {
    return;
  }
  await _playWithJustAudio(player, file.path, bytes, isCancelled);
}

Future<void> stopTauVoicePlayback(AudioPlayer player) async {
  if (Platform.isWindows) {
    _lookupPlaySound()?.call(nullptr, 0, 0);
  }
  try {
    await player.stop();
  } catch (_) {}
}

Future<bool> _playWindowsWav(String path) async {
  if (!Platform.isWindows) return false;
  return Isolate.run(() {
    final playSound = _lookupPlaySound();
    if (playSound == null) return false;
    final encoded = path.toNativeUtf16();
    try {
      return playSound(encoded, 0, _sndSync | _sndNoDefault | _sndFilename) !=
          0;
    } finally {
      malloc.free(encoded);
    }
  });
}

Future<void> _playWithJustAudio(
  AudioPlayer player,
  String path,
  Uint8List bytes,
  bool Function()? isCancelled,
) async {
  if (isCancelled?.call() == true) return;
  final duration = await player.setFilePath(path);
  await player.setVolume(1);
  if (isCancelled?.call() == true) return;
  await player.play();
  if (isCancelled?.call() == true) return;
  final wait = duration ?? _wavDuration(bytes);
  if (wait <= Duration.zero) return;
  if (player.processingState == ProcessingState.completed) return;
  if (!player.playing && player.processingState == ProcessingState.idle) {
    return;
  }
  await player.playerStateStream
      .firstWhere((state) {
        if (state.processingState == ProcessingState.completed) return true;
        return !state.playing && state.processingState == ProcessingState.idle;
      })
      .timeout(
        wait + const Duration(milliseconds: 400),
        onTimeout: () => player.playerState,
      );
}

Duration _wavDuration(Uint8List bytes) {
  if (bytes.length < 44) return Duration.zero;
  if (bytes[0] != 0x52 ||
      bytes[1] != 0x49 ||
      bytes[2] != 0x46 ||
      bytes[3] != 0x46) {
    return Duration.zero;
  }
  final data = ByteData.sublistView(bytes);
  final rate = data.getUint32(24, Endian.little);
  final blockAlign = data.getUint16(32, Endian.little);
  var dataBytes = data.getUint32(40, Endian.little);
  for (var i = 12; i + 8 <= bytes.length; i += 4) {
    if (bytes[i] == 0x64 &&
        bytes[i + 1] == 0x61 &&
        bytes[i + 2] == 0x74 &&
        bytes[i + 3] == 0x61) {
      dataBytes = data.getUint32(i + 4, Endian.little);
      break;
    }
  }
  if (rate <= 0 || blockAlign <= 0 || dataBytes <= 0) return Duration.zero;
  return Duration(
    milliseconds: ((dataBytes / (rate * blockAlign)) * 1000).round(),
  );
}
