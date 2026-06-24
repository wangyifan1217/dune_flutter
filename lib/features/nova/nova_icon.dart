import 'package:flutter/material.dart';

/// 云枢品牌图标，对齐 WebView `data-nova-icon` / `nova-icon-img`。
abstract final class NovaIcon {
  static const assetPath = 'assets/prototype/nova-icon.png';
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
    final radius = borderRadius ?? (size <= 16 ? 4.0 : size <= 34 ? 9.0 : 12.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        NovaIcon.assetPath,
        width: size,
        height: size,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _NovaIconSparkleFallback(size: size, borderRadius: radius),
      ),
    );
  }
}

class _NovaIconSparkleFallback extends StatelessWidget {
  const _NovaIconSparkleFallback({required this.size, required this.borderRadius});

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
