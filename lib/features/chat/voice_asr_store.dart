import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// IM 语音转文字本地缓存。
///
/// 实际转写请求由后端代理 SiliconFlow（Key 不落客户端）。
class VoiceAsrStore extends ChangeNotifier {
  VoiceAsrStore._();

  static final VoiceAsrStore instance = VoiceAsrStore._();

  static const _prefsKey = 'dunes_im_voice_asr_v1';

  final Map<String, String> _texts = <String, String>{};
  final Set<String> _loading = <String>{};
  Future<void>? _loadFuture;
  bool _loaded = false;

  String? textFor(String key) {
    final k = key.trim();
    if (k.isEmpty) return null;
    final text = _texts[k]?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  bool isLoading(String key) => _loading.contains(key.trim());

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            final key = k.toString().trim();
            final text = v.toString().trim();
            if (key.isNotEmpty && text.isNotEmpty) {
              _texts[key] = text;
            }
          });
        }
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_texts));
  }

  /// [request] 负责下载音频并调用后端转写接口，返回识别文本。
  Future<String> transcribe({
    required String key,
    required Future<String> Function() request,
  }) async {
    await ensureLoaded();
    final k = key.trim();
    if (k.isEmpty) throw Exception('语音标识无效');

    final existing = textFor(k);
    if (existing != null) return existing;

    if (_loading.contains(k)) {
      while (_loading.contains(k)) {
        await Future<void>.delayed(const Duration(milliseconds: 160));
      }
      final waited = textFor(k);
      if (waited != null) return waited;
      throw Exception('转写失败，请重试');
    }

    _loading.add(k);
    notifyListeners();
    try {
      final text = (await request()).trim();
      if (text.isEmpty) throw Exception('未识别到文字');
      _texts[k] = text;
      await _persist();
      notifyListeners();
      return text;
    } finally {
      _loading.remove(k);
      notifyListeners();
    }
  }
}
