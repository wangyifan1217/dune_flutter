import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../chat/user_avatar_widget.dart';

String? resolveTaskAvatarUrl(
  AuthSession session, {
  String avatarUrl = '',
  String avatarObjectKey = '',
}) {
  final direct = avatarUrl.trim();
  if (direct.isNotEmpty) return direct;
  final key = avatarObjectKey.trim();
  if (key.isEmpty) return null;
  if (key.startsWith('http://') || key.startsWith('https://')) return key;
  final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
  return '$base/storage/download?bucket=user-avatars&objectKey=${Uri.encodeQueryComponent(key)}&proxy=1';
}

Widget buildTaskUserAvatar({
  required AuthSession session,
  required String name,
  required int userId,
  String avatarPreset = '',
  String avatarObjectKey = '',
  String avatarUrl = '',
  double size = 32,
}) {
  final trimmed = name.trim();
  final initial = trimmed.isEmpty
      ? '?'
      : String.fromCharCode(trimmed.runes.first);
  return ImUserAvatar(
    initial: initial,
    seed: userId,
    size: size,
    avatarPreset: avatarPreset,
    avatarObjectKey: avatarObjectKey,
    avatarUrl: resolveTaskAvatarUrl(
      session,
      avatarUrl: avatarUrl,
      avatarObjectKey: avatarObjectKey,
    ),
  );
}
