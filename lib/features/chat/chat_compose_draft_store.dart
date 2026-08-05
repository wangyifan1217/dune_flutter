import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// IM 输入框未发送草稿：按会话 / 私聊 peer 本地持久化。
class ChatComposeDraftStore {
  ChatComposeDraftStore._();

  static final ChatComposeDraftStore instance = ChatComposeDraftStore._();

  static const _prefsKey = 'dunes_im_compose_draft_v1';

  final Map<String, String> _texts = <String, String>{};
  Future<void>? _loadFuture;
  bool _loaded = false;
  Timer? _persistDebounce;

  static String? keyFor({int conversationId = 0, int peerUserId = 0}) {
    if (conversationId > 0) return 'c:$conversationId';
    if (peerUserId > 0) return 'p:$peerUserId';
    return null;
  }

  String? textFor(String? key) {
    final k = (key ?? '').trim();
    if (k.isEmpty) return null;
    final text = _texts[k] ?? '';
    return text.isEmpty ? null : text;
  }

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
            final text = v.toString();
            if (key.isNotEmpty && text.isNotEmpty) {
              _texts[key] = text;
            }
          });
        }
      }
    } catch (_) {}
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_texts));
  }

  void save(String? key, String text, {bool flush = false}) {
    final k = (key ?? '').trim();
    if (k.isEmpty) return;
    final value = text;
    if (value.isEmpty) {
      if (_texts.remove(k) == null) return;
    } else {
      _texts[k] = value;
    }
    _persistDebounce?.cancel();
    if (flush) {
      unawaited(_persist());
      return;
    }
    _persistDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_persist());
    });
  }

  void clear(String? key, {bool flush = true}) {
    final k = (key ?? '').trim();
    if (k.isEmpty) return;
    if (_texts.remove(k) == null) return;
    _persistDebounce?.cancel();
    if (flush) {
      unawaited(_persist());
    }
  }

  /// 私聊首次建会话后，把 peer 草稿迁到会话 id。
  void migratePeerToConversation(int peerUserId, int conversationId) {
    if (peerUserId <= 0 || conversationId <= 0) return;
    final from = keyFor(peerUserId: peerUserId);
    final to = keyFor(conversationId: conversationId);
    if (from == null || to == null) return;
    final text = _texts.remove(from);
    if (text == null || text.isEmpty) return;
    _texts[to] = text;
    _persistDebounce?.cancel();
    unawaited(_persist());
  }
}
