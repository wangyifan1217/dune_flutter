import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// 聊天内联语音播放（单例）。
class ChatVoicePlayer extends ChangeNotifier {
  ChatVoicePlayer._();

  static final ChatVoicePlayer instance = ChatVoicePlayer._();

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<ProcessingState>? _stateSub;
  String? playingKey;

  Future<void> toggle(String key, String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw Exception('语音地址为空');
    }
    if (playingKey == key) {
      await stop();
      return;
    }
    await stop();
    playingKey = key;
    notifyListeners();
    try {
      await _player.setUrl(trimmed);
      await _player.play();
      await _stateSub?.cancel();
      _stateSub = _player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          playingKey = null;
          notifyListeners();
        }
      });
    } catch (e) {
      playingKey = null;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stop() async {
    await _stateSub?.cancel();
    _stateSub = null;
    try {
      await _player.stop();
    } catch (_) {}
    if (playingKey != null) {
      playingKey = null;
      notifyListeners();
    }
  }
}
