import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/widgets/cached_network_image.dart';
import '../../core/theme/dunes_theme.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import '../workbench/native_avatar_presets.dart';

/// 与 WebView `renderListAvatar` 对齐：预设 / 自定义头像 / 首字 fallback。
class ImUserAvatar extends StatelessWidget {
  const ImUserAvatar({
    super.key,
    required this.initial,
    required this.seed,
    this.size = 32,
    this.showOnline = false,
    this.avatarPreset,
    this.avatarObjectKey,
    this.avatarUrl,
    this.avatarService,
  });

  final String initial;
  final int seed;
  final double size;
  final bool showOnline;
  final String? avatarPreset;
  final String? avatarObjectKey;
  final String? avatarUrl;
  final ConversationService? avatarService;

  @override
  Widget build(BuildContext context) {
    final preset = (avatarPreset ?? '').trim();
    final presetSvg = preset.isNotEmpty ? nativeAvatarPresetSvg(preset) : null;
    final rawObjectKey = (avatarObjectKey ?? '').trim();
    final directUrl = (avatarUrl ?? '').trim();
    final objectKey = rawObjectKey;
    final objectKeyAsUrl = _looksLikeUrl(rawObjectKey) ? rawObjectKey : '';
    final effectiveDirectUrl = directUrl.isNotEmpty
        ? directUrl
        : objectKeyAsUrl;

    Widget core;
    // 优先使用后端已解析出的直链，避免 objectKey 滞后时仍展示旧头像。
    if (effectiveDirectUrl.isNotEmpty) {
      final directImageUrl = avatarService != null
          ? avatarService!.mediaProxyUrl(
              effectiveDirectUrl,
              bucket: 'user-avatars',
            )
          : effectiveDirectUrl;
      core = CachedDunesNetworkImage(
        url: directImageUrl,
        width: size,
        height: size,
        borderRadius: BorderRadius.circular(size / 2),
        errorBuilder: _initialAvatar,
      );
    } else if (objectKey.isNotEmpty && avatarService != null) {
      core = FutureBuilder<String>(
        future: resolveCachedAvatarUrl(
          () => avatarService!.resolveMediaUrl(
            objectKey,
            bucket: 'user-avatars',
          ),
          objectKey,
        ),
        builder: (_, snap) {
          if (snap.hasData && snap.data!.isNotEmpty) {
            return CachedDunesNetworkImage(
              url: snap.data!,
              width: size,
              height: size,
              borderRadius: BorderRadius.circular(size / 2),
              errorBuilder: _initialAvatar,
            );
          }
          return _initialAvatar();
        },
      );
    } else if (presetSvg != null) {
      core = ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: SvgPicture.string(
          presetSvg,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    } else {
      core = _initialAvatar();
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(width: size, height: size, child: core),
        if (showOnline) _onlineStatusDot(size),
      ],
    );
  }

  Widget _onlineStatusDot(double avatarSize) {
    final dot = avatarSize >= 40 ? 11.0 : 9.0;
    final border = avatarSize >= 40 ? 2.0 : 1.5;
    final offset = avatarSize >= 40 ? -2.0 : -1.0;
    return Positioned(
      right: offset,
      bottom: offset,
      child: Container(
        width: dot,
        height: dot,
        decoration: BoxDecoration(
          color: DunesColors.green,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: DunesColors.bgApp, width: border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _initialAvatar() {
    final style = InboxFormat.personStyle(seed);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: style.gradient),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Text(
        initial.isEmpty ? '?' : initial,
        style: TextStyle(
          color: style.textColor,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  bool _looksLikeUrl(String value) {
    final v = value.toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }
}
