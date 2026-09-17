import 'package:flutter/material.dart';

/// 云枢品牌图标，对齐 WebView `data-nova-icon` / `nova-icon-img`。
abstract final class NovaIcon {
  static const assetPath = 'assets/prototype/nova-icon.png';
  static const tabAssetPath = 'assets/images/tau_tab_icon.png';
}

/// 小饕拟人形象资源。会话页 / 电话头像默认用 wink 静帧，不再播 GIF、也不切开眼。
abstract final class NovaPersonAvatar {
  static const openAsset = 'assets/images/ai_avatar_open.png';
  static const winkAsset = 'assets/images/ai_avatar_wink.png';
  static const blinkAsset = 'assets/images/ai_avatar_blink.gif';
  static const asset = winkAsset;
}

/// 按设备像素把 512 原图解到足够清晰的缓存，避免会话头像发糊。
class NovaPersonAvatarImage extends StatelessWidget {
  const NovaPersonAvatarImage({
    super.key,
    this.width,
    this.height,
    this.wink = false,
    this.fit = BoxFit.cover,
  });

  final double? width;
  final double? height;
  final bool wink;
  final BoxFit fit;

  static const nativePx = 512;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final logical = [width ?? 0, height ?? 0].reduce((a, b) => a > b ? a : b);
    final decode = logical <= 0
        ? nativePx
        : (logical * dpr * 2).round().clamp(192, nativePx);
    return Image.asset(
      wink ? NovaPersonAvatar.winkAsset : NovaPersonAvatar.openAsset,
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      gaplessPlayback: true,
      cacheWidth: decode,
      cacheHeight: decode,
    );
  }
}

class NovaIconImage extends StatelessWidget {
  const NovaIconImage({
    super.key,
    required this.size,
    this.borderRadius,
    this.fit = BoxFit.contain,
  });

  final double size;
  final double? borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final radius =
        borderRadius ??
        (size <= 16
            ? 4.0
            : size <= 34
            ? 9.0
            : 12.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        NovaIcon.assetPath,
        width: size,
        height: size,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            _NovaIconSparkleFallback(size: size, borderRadius: radius),
      ),
    );
  }
}

class _NovaIconSparkleFallback extends StatelessWidget {
  const _NovaIconSparkleFallback({
    required this.size,
    required this.borderRadius,
  });

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFA78BD9), Color(0xFF7C62C2), Color(0xFF5A40A0)],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(Icons.auto_awesome, size: size * 0.42, color: Colors.white),
    );
  }
}
