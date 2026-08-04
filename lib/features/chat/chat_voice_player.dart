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
      await _playCurrent();
    } catch (e) {
      playingKey = null;
      notifyListeners();
      rethrow;
    }
  }

  /// 播放本地语音文件（如录音草稿回放）。
  Future<void> toggleFile(String key, String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw Exception('语音文件为空');
    }
    if (playingKey == key) {
      await stop();
      return;
    }
    await stop();
    playingKey = key;
    notifyListeners();
    try {
      await _player.setFilePath(trimmed);
      await _playCurrent();
    } catch (e) {
      playingKey = null;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _playCurrent() async {
    await _player.play();
    await _stateSub?.cancel();
    _stateSub = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        playingKey = null;
        notifyListeners();
      }
    });
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
