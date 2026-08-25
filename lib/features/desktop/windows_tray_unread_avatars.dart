import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/cached_network_image.dart';
import '../auth/auth_session.dart';
import '../chat/group_composite_avatar.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../workbench/native_avatar_presets.dart';
import 'windows_tray_unread_item.dart';

const int _kTrayAvatarPx = 64;
const int _kPngCacheLimit = 80;
const Color _kFallbackBg = DunesColors.brandPurple;
const Color _kGroupBg = Color(0xFFE3E3E3);

final http.Client _http = http.Client();
final Map<String, Uint8List> _pngCache = <String, Uint8List>{};
final Map<String, Future<Uint8List?>> _inflight = <String, Future<Uint8List?>>{};

Uint8List? windowsTrayCachedAvatarPng(NativeConversation conversation) {
  return _pngCache[_sourceKey(conversation)];
}

/// 把未读会话的 IM 头像栅格成 PNG，供托盘原生浮层绘制。
Future<List<WindowsTrayUnreadItem>> windowsTrayHydrateUnreadAvatars({
  required List<WindowsTrayUnreadItem> items,
  required List<NativeConversation> conversations,
  AuthSession? session,
  ConversationService? avatarService,
}) async {
  if (items.isEmpty) return items;
  final byId = <int, NativeConversation>{
    for (final conversation in conversations)
      if (conversation.id > 0) conversation.id: conversation,
  };
  final out = <WindowsTrayUnreadItem>[];
  for (final item in items) {
    final conversation = byId[item.conversationId];
    if (conversation == null) {
      out.add(item);
      continue;
    }
    final png = await _pngForConversation(
      conversation,
      session: session,
      avatarService: avatarService,
    );
    out.add(png == null ? item : item.copyWith(avatarPng: png));
  }
  _trimPngCache(byId.values);
  return out;
}

Future<Uint8List?> _pngForConversation(
  NativeConversation conversation, {
  AuthSession? session,
  ConversationService? avatarService,
}) {
  final key = _sourceKey(conversation);
  if (key == 'none') return Future<Uint8List?>.value(null);
  final cached = _pngCache[key];
  if (cached != null) return Future<Uint8List?>.value(cached);
  return _inflight.putIfAbsent(key, () async {
    try {
      final png = await _renderConversation(
        conversation,
        session: session,
        avatarService: avatarService,
      );
      if (png != null && png.isNotEmpty) {
        _pngCache[key] = png;
      }
      return png;
    } finally {
      _inflight.remove(key);
    }
  });
}

void _trimPngCache(Iterable<NativeConversation> live) {
  if (_pngCache.length <= _kPngCacheLimit) return;
  final keep = <String>{for (final c in live) _sourceKey(c)};
  _pngCache.removeWhere((key, _) => !keep.contains(key));
}

String _sourceKey(NativeConversation conversation) {
  if (_usesComposite(conversation)) {
    if (conversation.avatarMembers.isEmpty) return 'none';
    final parts = conversation.avatarMembers
        .map(
          (m) =>
              '${m.userId}:${m.avatarPreset ?? ''}:${m.avatarObjectKey ?? ''}:${m.avatarUrl ?? ''}',
        )
        .join(';');
    return 'g:${conversation.id}:$parts';
  }
  if (conversation.isPrivate || conversation.isSelfMemo) {
    final preset = (conversation.peerAvatarPreset ?? '').trim();
    final objectKey = (conversation.peerAvatarObjectKey ?? '').trim();
    final url = (conversation.peerAvatarUrl ?? '').trim();
    if (preset.isEmpty && objectKey.isEmpty && url.isEmpty) return 'none';
    return 'p:$preset|$objectKey|$url';
  }
  return 'none';
}

bool _usesComposite(NativeConversation conversation) {
  return conversation.isGroup || conversation.isWorkgroupApproval;
}

Future<Uint8List?> _renderConversation(
  NativeConversation conversation, {
  AuthSession? session,
  ConversationService? avatarService,
}) async {
  try {
    if (_usesComposite(conversation)) {
      return _encodeImage(
        await _renderGroup(
          conversation.avatarMembers,
          session: session,
          avatarService: avatarService,
        ),
      );
    }
    if (conversation.isPrivate || conversation.isSelfMemo) {
      return _encodeImage(
        await _renderUser(
          initial: _initialOf(
            conversation.displayTitle,
            fallback: conversation.isSelfMemo ? '备' : '?',
          ),
          preset: conversation.peerAvatarPreset,
          objectKey: conversation.peerAvatarObjectKey,
          url: conversation.peerAvatarUrl,
          session: session,
          avatarService: avatarService,
        ),
      );
    }
  } catch (_) {}
  return null;
}

Future<ui.Image> _renderGroup(
  List<ConversationAvatarMember> members, {
  AuthSession? session,
  ConversationService? avatarService,
}) async {
  final shown = _stableMembers(members);
  if (shown.isEmpty) {
    return _drawInitial('群', _kTrayAvatarPx);
  }
  if (shown.length == 1) {
    final m = shown.first;
    return _renderUser(
      initial: _initialOf(m.displayName),
      preset: m.avatarPreset,
      objectKey: m.avatarObjectKey,
      url: m.avatarUrl,
      session: session,
      avatarService: avatarService,
    );
  }

  const size = _kTrayAvatarPx * 1.0;
  const gap = 1.0;
  final cell = groupCompositeAvatarCellSize(size, shown.length);
  final rows = groupCompositeAvatarRowPattern(shown.length);
  final images = await Future.wait([
    for (final m in shown)
      _renderUser(
        initial: _initialOf(m.displayName),
        preset: m.avatarPreset,
        objectKey: m.avatarObjectKey,
        url: m.avatarUrl,
        session: session,
        avatarService: avatarService,
        clipRadius: 1,
      ),
  ]);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final outer = RRect.fromRectAndRadius(
    Rect.fromLTWH(0, 0, size, size),
    Radius.circular(size * 0.18),
  );
  canvas.clipRRect(outer);
  canvas.drawColor(_kGroupBg, BlendMode.src);

  var y = gap;
  for (var r = 0; r < rows.length; r++) {
    if (r > 0) y += gap;
    final indexes = rows[r];
    final rowWidth = indexes.length * cell + gap * (indexes.length - 1);
    var x = (size - rowWidth) / 2;
    for (final index in indexes) {
      _drawCover(
        canvas,
        images[index],
        Rect.fromLTWH(x, y, cell, cell),
        radius: 1,
      );
      x += cell + gap;
    }
    y += cell;
  }

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(_kTrayAvatarPx, _kTrayAvatarPx);
  } finally {
    picture.dispose();
    for (final image in images) {
      image.dispose();
    }
  }
}

Future<ui.Image> _renderUser({
  required String initial,
  String? preset,
  String? objectKey,
  String? url,
  AuthSession? session,
  ConversationService? avatarService,
  double? clipRadius,
}) async {
  final photoUrl = _resolvedPhotoUrl(
    url: url,
    objectKey: objectKey,
    session: session,
    avatarService: avatarService,
  );
  ui.Image? photo;
  if (photoUrl != null && photoUrl.isNotEmpty) {
    photo = await _decodeUrl(photoUrl, session);
  }
  if (photo == null) {
    final svg = (preset ?? '').trim();
    if (svg.isNotEmpty) {
      final source = nativeAvatarPresetSvg(svg);
      if (source != null) {
        photo = await _rasterizeSvg(source);
      }
    }
  }
  if (photo == null) {
    return _drawInitial(initial, _kTrayAvatarPx);
  }
  final radius = clipRadius ?? _kTrayAvatarPx * 0.18;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final dst = Rect.fromLTWH(
    0,
    0,
    _kTrayAvatarPx.toDouble(),
    _kTrayAvatarPx.toDouble(),
  );
  canvas.clipRRect(RRect.fromRectAndRadius(dst, Radius.circular(radius)));
  _drawCover(canvas, photo, dst);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(_kTrayAvatarPx, _kTrayAvatarPx);
  } finally {
    picture.dispose();
    photo.dispose();
  }
}

Future<ui.Image> _drawInitial(String initial, int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(size * 0.18)),
    Paint()..color = _kFallbackBg,
  );
  final letter = initial.isEmpty ? '?' : initial;
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            textAlign: TextAlign.center,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w500,
            maxLines: 1,
          ),
        )
        ..pushStyle(
          ui.TextStyle(
            color: Colors.white,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w500,
          ),
        )
        ..addText(letter);
  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: size.toDouble()));
  canvas.drawParagraph(
    paragraph,
    Offset(0, (size - paragraph.height) / 2),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size, size);
  } finally {
    picture.dispose();
  }
}

void _drawCover(
  Canvas canvas,
  ui.Image image,
  Rect dst, {
  double radius = 0,
}) {
  if (radius > 0) {
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(dst, Radius.circular(radius)));
  }
  final src = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  final scale = dst.width / src.width > dst.height / src.height
      ? dst.width / src.width
      : dst.height / src.height;
  final w = src.width * scale;
  final h = src.height * scale;
  final fitted = Rect.fromLTWH(
    dst.left + (dst.width - w) / 2,
    dst.top + (dst.height - h) / 2,
    w,
    h,
  );
  canvas.drawImageRect(
    image,
    src,
    fitted,
    Paint()..filterQuality = FilterQuality.medium,
  );
  if (radius > 0) canvas.restore();
}

Future<Uint8List?> _encodeImage(ui.Image image) async {
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

String? _resolvedPhotoUrl({
  String? url,
  String? objectKey,
  AuthSession? session,
  ConversationService? avatarService,
}) {
  final direct = (url ?? '').trim();
  if (_looksLikeUrl(direct)) return direct;
  final key = (objectKey ?? '').trim();
  if (_looksLikeUrl(key)) return key;
  final source = key.isNotEmpty ? key : direct;
  if (source.isEmpty) return null;
  final cached = dunesAvatarResolvedUrlCache[source];
  if (cached != null && cached.isNotEmpty) return cached;
  final resolved = avatarService != null
      ? avatarService.mediaProxyUrl(source, bucket: 'user-avatars')
      : _sessionProxyUrl(session, source);
  if (resolved.isEmpty) return null;
  dunesAvatarResolvedUrlCache[source] = resolved;
  return resolved;
}

String _sessionProxyUrl(AuthSession? session, String objectKey) {
  final base = (session?.apiBase ?? '').trim().replaceAll(RegExp(r'/$'), '');
  if (base.isEmpty) return '';
  return '$base/storage/download?bucket=user-avatars'
      '&objectKey=${Uri.encodeQueryComponent(objectKey)}&proxy=1';
}

bool _looksLikeUrl(String value) {
  final v = value.toLowerCase();
  return v.startsWith('http://') || v.startsWith('https://');
}

Future<ui.Image?> _decodeUrl(String url, AuthSession? session) async {
  try {
    final headers = <String, String>{};
    final token = session?.token.trim() ?? '';
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final resp = await _http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
    if (resp.bodyBytes.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(
      resp.bodyBytes,
      targetWidth: _kTrayAvatarPx,
      targetHeight: _kTrayAvatarPx,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (_) {
    return null;
  }
}

Future<ui.Image?> _rasterizeSvg(String svg) async {
  try {
    final info = await vg.loadPicture(SvgStringLoader(svg), null);
    try {
      return await info.picture.toImage(_kTrayAvatarPx, _kTrayAvatarPx);
    } finally {
      info.picture.dispose();
    }
  } catch (_) {
    return null;
  }
}

List<ConversationAvatarMember> _stableMembers(
  List<ConversationAvatarMember> source,
) {
  final list = source.where((m) => m.userId > 0).toList(growable: true);
  list.sort((a, b) => a.userId.compareTo(b.userId));
  if (list.length <= 9) return list;
  return list.take(9).toList(growable: false);
}

String _initialOf(String name, {String fallback = '?'}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return fallback;
  return String.fromCharCodes(trimmed.runes.take(1));
}
