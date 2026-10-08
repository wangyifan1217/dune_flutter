// Pinned just_audio marks in-memory sources experimental; isolate that API here.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LighthouseFeedbackKind {
  select,
  expand,
  collapse,
  navigate,
  share,
  success,
}

/// Short, quiet earcons; repeated chart scrubbing uses haptics only.
class LighthouseFeedback {
  static final instance = LighthouseFeedback._();
  LighthouseFeedback._();
  bool soundEnabled = true;
  bool hapticsEnabled = true;
  AudioPlayer? _player;
  bool _playing = false;
  DateTime? _last;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      soundEnabled = prefs.getBool('lighthouse.feedback.sound') ?? true;
      hapticsEnabled = prefs.getBool('lighthouse.feedback.haptics') ?? true;
    } catch (_) {
      // Preference storage is optional; it must not block the page.
    }
  }

  void play(LighthouseFeedbackKind kind, {bool sound = true}) {
    final now = DateTime.now();
    if (_last != null && now.difference(_last!).inMilliseconds < 65) return;
    _last = now;
    if (hapticsEnabled) unawaited(_haptic(kind));
    if (soundEnabled && sound && !_playing) unawaited(_tone(kind));
  }

  /// 每次只震一下（原来收起 / 转发 / 成功是连震两下，太吵）。
  Future<void> _haptic(LighthouseFeedbackKind kind) async {
    try {
      switch (kind) {
        case LighthouseFeedbackKind.select:
        case LighthouseFeedbackKind.collapse:
          await HapticFeedback.selectionClick();
        case LighthouseFeedbackKind.expand:
        case LighthouseFeedbackKind.share:
          await HapticFeedback.lightImpact();
        case LighthouseFeedbackKind.navigate:
        case LighthouseFeedbackKind.success:
          await HapticFeedback.mediumImpact();
      }
    } catch (_) {
      // Unsupported hardware must never prevent a business action.
    }
  }

  Future<void> _tone(LighthouseFeedbackKind kind) async {
    _playing = true;
    try {
      final player = _player ??= AudioPlayer(
        handleAudioSessionActivation: false,
      );
      await player.setVolume(0.18);
      await player.setAudioSource(
        _FeedbackAudioSource(lighthouseFeedbackWav(kind)),
      );
      await player.play();
    } catch (_) {
      // Browser autoplay restrictions / unsupported output: keep the action usable.
    } finally {
      _playing = false;
    }
  }

  Future<void> showSettings(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          Future<void> save() async {
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('lighthouse.feedback.sound', soundEnabled);
              await prefs.setBool(
                'lighthouse.feedback.haptics',
                hapticsEnabled,
              );
            } catch (_) {
              // The in-memory choice remains active if persistence is unavailable.
            }
          }

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('灯塔 · 触感与声音'),
                  subtitle: Text('每次轻点只响一声、震一下'),
                ),
                SwitchListTile(
                  title: const Text('轻提示音'),
                  value: soundEnabled,
                  onChanged: (value) {
                    update(() => soundEnabled = value);
                    unawaited(save());
                    if (value) play(LighthouseFeedbackKind.expand);
                  },
                ),
                SwitchListTile(
                  title: const Text('触感反馈'),
                  subtitle: const Text('震动效果取决于设备；浏览器和电脑可能不支持'),
                  value: hapticsEnabled,
                  onChanged: (value) {
                    update(() => hapticsEnabled = value);
                    unawaited(save());
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// PCM WAV avoids network assets. 每个动作只响一声（不再两个音连着响），
/// 用音高区分：展开偏高、收起偏低。
Uint8List lighthouseFeedbackWav(LighthouseFeedbackKind kind) {
  final notes = switch (kind) {
    LighthouseFeedbackKind.select => [760.0],
    LighthouseFeedbackKind.expand => [880.0],
    LighthouseFeedbackKind.collapse => [560.0],
    LighthouseFeedbackKind.navigate => [700.0],
    LighthouseFeedbackKind.share => [960.0],
    LighthouseFeedbackKind.success => [1040.0],
  };
  const sampleRate = 22050;
  const noteSamples = 1102; // 50 ms per note, including a soft attack/release.
  final count = notes.length * noteSamples;
  final bytes = Uint8List(44 + count * 2);
  final data = ByteData.sublistView(bytes);
  void ascii(int offset, String value) =>
      bytes.setRange(offset, offset + value.length, value.codeUnits);
  ascii(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, count * 2, Endian.little);
  for (var i = 0; i < count; i++) {
    final n = i % noteSamples;
    final envelope = math
        .pow(math.sin(math.pi * n / noteSamples), 2)
        .toDouble();
    final sample =
        (6500 *
                envelope *
                math.sin(
                  2 * math.pi * notes[i ~/ noteSamples] * n / sampleRate,
                ))
            .round();
    data.setInt16(44 + i * 2, sample, Endian.little);
  }
  return bytes;
}

class _FeedbackAudioSource extends StreamAudioSource {
  _FeedbackAudioSource(this.bytes);
  final Uint8List bytes;
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final to = end ?? bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: to - from,
      offset: from,
      stream: Stream.value(bytes.sublist(from, to)),
      contentType: 'audio/wav',
    );
  }
}
