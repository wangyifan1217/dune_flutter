import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// 聊天内联语音播放（单例）。
class ChatVoicePlayer extends ChangeNotifier {
  ChatVoicePlayer._();

  static final ChatVoicePlayer instance = ChatVoicePlayer._();

  final AudioPlayer _player = AudioPlayer();
  String? playingKey;

  Future<void> toggle(String key, String url) async {
    if (playingKey == key) {
      await stop();
      return;
    }
    await _player.stop();
    playingKey = key;
    notifyListeners();
    try {
      await _player.setUrl(url);
      unawaited(_player.play());
      _player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          playingKey = null;
          notifyListeners();
        }
      });
    } catch (_) {
      playingKey = null;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _player.stop();
    if (playingKey != null) {
      playingKey = null;
      notifyListeners();
    }
  }
}
