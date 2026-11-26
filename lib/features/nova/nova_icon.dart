import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

/// 云枢品牌图标，对齐 WebView `data-nova-icon` / `nova-icon-img`。
abstract final class NovaIcon {
  static const assetPath = 'assets/prototype/nova-icon.png';
  static const tabAssetPath = 'assets/images/tau_tab_icon.png';
}

/// 小饕 3D 拟人形象资源（状态驱动 4 表情帧：open / blink / thinking / wink）。
abstract final class NovaPersonAvatar {
  static const openAsset = 'assets/images/ai_avatar_open.png';
  static const winkAsset = 'assets/images/ai_avatar_wink.png';
  static const blinkPngAsset = 'assets/images/ai_avatar_blink.png';
  static const thinkingAsset = 'assets/images/ai_avatar_thinking.png';
  static const blinkAsset = 'assets/images/ai_avatar_blink.gif';
  static const asset = winkAsset;
}

/// 按设备像素把 512 原图解到足够清晰的缓存，避免会话头像发糊。
/// 默认用于列表/消息流静帧；传入 [animate] = true 或 [thinking] = true 时
/// 自动启用轻量状态驱动 3D 动效（眨眼 / 呼吸 / 思考歪头 / 点击 Wink / PC 3D 悬停视差）。
class NovaPersonAvatarImage extends StatelessWidget {
  const NovaPersonAvatarImage({
    super.key,
    this.width,
    this.height,
    this.wink = false,
    this.thinking = false,
    this.animate = false,
    this.enableBlink = true,
    this.enableBreath = true,
    this.enableHoverTilt = true,
    this.enableTapReaction = true,
    this.fit = BoxFit.cover,
  });

  final double? width;
  final double? height;
  final bool wink;
  final bool thinking;
  final bool animate;
  final bool enableBlink;
  final bool enableBreath;
  final bool enableHoverTilt;
  final bool enableTapReaction;
  final BoxFit fit;

  static const nativePx = 512;

  static int resolveDecodePx(BuildContext context, double? width, double? height) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final logical = math.max(width ?? 0, height ?? 0);
    return logical <= 0
        ? nativePx
        : (logical * dpr * 2).round().clamp(192, nativePx);
  }

  @override
  Widget build(BuildContext context) {
    if (animate || thinking) {
      return NovaAnimated3DAvatar(
        width: width,
        height: height,
        thinking: thinking,
        happy: wink,
        enableBlink: enableBlink,
        enableBreath: enableBreath,
        enableHoverTilt: enableHoverTilt,
        enableTapReaction: enableTapReaction,
        fit: fit,
      );
    }
    final decode = resolveDecodePx(context, width, height);
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

/// 小饕状态驱动 3D 动态头像（零死循环 GIF，页面隐藏 / 减弱动态时自动停帧）。
class NovaAnimated3DAvatar extends StatefulWidget {
  const NovaAnimated3DAvatar({
    super.key,
    this.width,
    this.height,
    this.thinking = false,
    this.happy = false,
    this.enableBlink = true,
    this.enableBreath = true,
    this.enableHoverTilt = true,
    this.enableTapReaction = true,
    this.fit = BoxFit.cover,
  });

  final double? width;
  final double? height;
  final bool thinking;
  final bool happy;
  final bool enableBlink;
  final bool enableBreath;
  final bool enableHoverTilt;
  final bool enableTapReaction;
  final BoxFit fit;

  @override
  State<NovaAnimated3DAvatar> createState() => _NovaAnimated3DAvatarState();
}

class _NovaAnimated3DAvatarState extends State<NovaAnimated3DAvatar>
    with TickerProviderStateMixin {
  static final math.Random _rng = math.Random();

  late final AnimationController _breathController;
  late final AnimationController _tapController;
  Timer? _blinkTimer;
  Timer? _blinkCloseTimer;
  Timer? _tapWinkTimer;

  bool _isBlinking = false;
  bool _tapWinkActive = false;
  bool _isHovered = false;
  Offset _hoverNormalized = Offset.zero;
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );
    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimations();
    if (!_precached) {
      _precached = true;
      final decode = NovaPersonAvatarImage.resolveDecodePx(
        context,
        widget.width,
        widget.height,
      );
      for (final asset in const [
        NovaPersonAvatar.openAsset,
        NovaPersonAvatar.blinkPngAsset,
        NovaPersonAvatar.thinkingAsset,
        NovaPersonAvatar.winkAsset,
      ]) {
        precacheImage(
          ResizeImage(AssetImage(asset), width: decode, height: decode),
          context,
        );
      }
    }
  }

  @override
  void didUpdateWidget(covariant NovaAnimated3DAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thinking != widget.thinking ||
        oldWidget.happy != widget.happy ||
        oldWidget.enableBlink != widget.enableBlink ||
        oldWidget.enableBreath != widget.enableBreath) {
      _syncAnimations();
    }
  }

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  bool get _tickerEnabled => TickerMode.of(context);

  void _syncAnimations() {
    final active = _tickerEnabled && !_reduceMotion;

    if (active && (widget.enableBreath || widget.thinking)) {
      if (!_breathController.isAnimating) {
        _breathController.repeat(reverse: true);
      }
    } else {
      _breathController.stop();
    }

    if (active && widget.enableBlink && !widget.thinking && !widget.happy) {
      if (_blinkTimer == null || !_blinkTimer!.isActive) {
        _scheduleNextBlink();
      }
    } else {
      _cancelBlinkTimers();
      if (_isBlinking && mounted) {
        setState(() => _isBlinking = false);
      }
    }
  }

  void _cancelBlinkTimers() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    _blinkCloseTimer?.cancel();
    _blinkCloseTimer = null;
  }

  void _scheduleNextBlink() {
    _blinkTimer?.cancel();
    final delayMs = 3600 + _rng.nextInt(2400);
    _blinkTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted ||
          !_tickerEnabled ||
          _reduceMotion ||
          widget.thinking ||
          widget.happy ||
          _tapWinkActive) {
        return;
      }
      _performBlink(doubleBlink: _rng.nextInt(5) == 0);
    });
  }

  void _performBlink({required bool doubleBlink}) {
    if (!mounted) return;
    setState(() => _isBlinking = true);
    _blinkCloseTimer?.cancel();
    _blinkCloseTimer = Timer(const Duration(milliseconds: 145), () {
      if (!mounted) return;
      setState(() => _isBlinking = false);
      if (doubleBlink) {
        _blinkCloseTimer = Timer(const Duration(milliseconds: 110), () {
          if (!mounted || widget.thinking || widget.happy || _tapWinkActive) {
            return;
          }
          setState(() => _isBlinking = true);
          _blinkCloseTimer = Timer(const Duration(milliseconds: 130), () {
            if (!mounted) return;
            setState(() => _isBlinking = false);
            _scheduleNextBlink();
          });
        });
      } else {
        _scheduleNextBlink();
      }
    });
  }

  void _triggerTapReaction() {
    if (!widget.enableTapReaction || _reduceMotion) return;
    _tapController.forward(from: 0);
    _tapWinkTimer?.cancel();
    if (!widget.thinking) {
      setState(() {
        _tapWinkActive = true;
        _isBlinking = false;
      });
      _tapWinkTimer = Timer(const Duration(milliseconds: 560), () {
        if (!mounted) return;
        setState(() => _tapWinkActive = false);
      });
    }
  }

  String _currentAsset() {
    if (widget.thinking) return NovaPersonAvatar.thinkingAsset;
    if (widget.happy || _tapWinkActive) return NovaPersonAvatar.winkAsset;
    if (_isBlinking) return NovaPersonAvatar.blinkPngAsset;
    return NovaPersonAvatar.openAsset;
  }

  @override
  void dispose() {
    _cancelBlinkTimers();
    _tapWinkTimer?.cancel();
    _breathController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final decode = NovaPersonAvatarImage.resolveDecodePx(
      context,
      widget.width,
      widget.height,
    );
    final reduceMotion = _reduceMotion;
    final asset = _currentAsset();

    final image = Image.asset(
      asset,
      key: ValueKey<String>(asset),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      gaplessPlayback: true,
      cacheWidth: decode,
      cacheHeight: decode,
    );

    Widget content = reduceMotion
        ? image
        : AnimatedSwitcher(
            duration: Duration(milliseconds: _isBlinking ? 55 : 135),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: image,
          );

    if (!reduceMotion) {
      content = AnimatedBuilder(
        animation: Listenable.merge([_breathController, _tapController]),
        builder: (context, child) {
          final breathT = Curves.easeInOutSine.transform(_breathController.value);
          // 柔和呼吸微浮（~2.6% 缩放 + 0.9px 上下浮动）
          final breathScale = widget.enableBreath ? 1.0 + breathT * 0.026 : 1.0;
          final breathDy = widget.enableBreath ? (0.5 - breathT) * 1.4 : 0.0;

          // 思考时轻缓 3D 歪头摆动
          final thinkingTiltZ = widget.thinking
              ? (breathT - 0.5) * 0.11
              : 0.0;

          // 点击弹性微弹
          final tapT = _tapController.value;
          final tapBump = tapT > 0 && tapT < 1
              ? math.sin(tapT * math.pi) * 0.085
              : 0.0;

          // PC 鼠标悬停微幅 3D 倾斜视差
          final hoverScale = _isHovered ? 1.045 : 1.0;
          final tiltX = _isHovered ? -_hoverNormalized.dy * 0.16 : 0.0;
          final tiltY = _isHovered ? _hoverNormalized.dx * 0.18 : 0.0;

          final matrix = Matrix4.identity()
            ..setEntry(3, 2, 0.0018)
            ..translate(0.0, breathDy)
            ..rotateX(tiltX)
            ..rotateY(tiltY)
            ..rotateZ(thinkingTiltZ)
            ..scale(breathScale * hoverScale + tapBump);

          return Transform(
            alignment: Alignment.center,
            transform: matrix,
            child: child,
          );
        },
        child: content,
      );
    }

    if (widget.enableHoverTilt && !reduceMotion) {
      content = MouseRegion(
        opaque: false,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() {
          _isHovered = false;
          _hoverNormalized = Offset.zero;
        }),
        onHover: (event) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) return;
          final size = box.size;
          if (size.width <= 0 || size.height <= 0) return;
          final nx = ((event.localPosition.dx / size.width) * 2 - 1)
              .clamp(-1.0, 1.0);
          final ny = ((event.localPosition.dy / size.height) * 2 - 1)
              .clamp(-1.0, 1.0);
          setState(() => _hoverNormalized = Offset(nx, ny));
        },
        child: content,
      );
    }

    if (widget.enableTapReaction && !reduceMotion) {
      content = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _triggerTapReaction(),
        child: content,
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: content,
      ),
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            DunesColors.resolve(
              context,
              Color(0xFFA78BD9),
              role: DunesColorRole.surface,
            ),
            DunesColors.resolve(
              context,
              Color(0xFF7C62C2),
              role: DunesColorRole.surface,
            ),
            DunesColors.resolve(
              context,
              Color(0xFF5A40A0),
              role: DunesColorRole.surface,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        Icons.auto_awesome,
        size: size * 0.42,
        color: DunesColors.resolve(context, Colors.white),
      ),
    );
  }
}
