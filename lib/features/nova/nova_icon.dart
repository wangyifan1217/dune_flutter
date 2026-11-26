import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

/// 云枢品牌图标，对齐 WebView `data-nova-icon` / `nova-icon-img`。
abstract final class NovaIcon {
  static const assetPath = 'assets/prototype/nova-icon.png';
  static const tabAssetPath = 'assets/images/tau_tab_icon.png';
}

/// 小饕原版 3D 拟人形象资源（open / wink 静帧切换，画面完全稳定不晃动）。
abstract final class NovaPersonAvatar {
  static const openAsset = 'assets/images/ai_avatar_open.png';
  static const winkAsset = 'assets/images/ai_avatar_wink.png';
  static const blinkAsset = 'assets/images/ai_avatar_blink.gif';
  static const asset = winkAsset;
}

/// 按设备像素把 512 原图解到足够清晰的缓存，避免会话头像发糊。
/// 默认用于列表/消息流静帧；传入 [animate] = true 时仅做轻柔的「眼神眨眼/Wink」切换，
/// 头像整体完全静止不晃动、不旋转、不缩放。
class NovaPersonAvatarImage extends StatelessWidget {
  const NovaPersonAvatarImage({
    super.key,
    this.width,
    this.height,
    this.wink = false,
    this.thinking = false,
    this.animate = false,
    this.fit = BoxFit.cover,
  });

  final double? width;
  final double? height;
  final bool wink;
  final bool thinking;
  final bool animate;
  final BoxFit fit;

  static const nativePx = 512;

  @override
  Widget build(BuildContext context) {
    if (animate) {
      return NovaAnimated3DAvatar(
        width: width,
        height: height,
        thinking: thinking,
        happy: wink,
        fit: fit,
      );
    }
    return Image.asset(
      wink ? NovaPersonAvatar.winkAsset : NovaPersonAvatar.openAsset,
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.medium,
      isAntiAlias: true,
      gaplessPlayback: true,
    );
  }
}

/// 小饕克制灵动头像（沿用原版形象）：
/// - 整体画面 100% 静止锐利（无晃动、无旋转、无呼吸缩放）
/// - 仅在待机偶发（每 5~7 秒轻轻 Wink 一下）、PC 悬停、点击或有未读回复时，
///   自然切到原版 `ai_avatar_wink.png` 眨眼微笑；思考态交由外圈流光环表达。
class NovaAnimated3DAvatar extends StatefulWidget {
  const NovaAnimated3DAvatar({
    super.key,
    this.width,
    this.height,
    this.thinking = false,
    this.happy = false,
    this.enableBlink = true,
    this.enableHoverWink = true,
    this.enableTapWink = true,
    this.fit = BoxFit.cover,
  });

  final double? width;
  final double? height;
  final bool thinking;
  final bool happy;
  final bool enableBlink;
  final bool enableHoverWink;
  final bool enableTapWink;
  final BoxFit fit;

  @override
  State<NovaAnimated3DAvatar> createState() => _NovaAnimated3DAvatarState();
}

class _NovaAnimated3DAvatarState extends State<NovaAnimated3DAvatar> {
  static final math.Random _rng = math.Random();

  Timer? _winkScheduleTimer;
  Timer? _winkHoldTimer;
  Timer? _tapWinkTimer;

  bool _idleWinking = false;
  bool _isHovered = false;
  bool _tapWinking = false;
  bool _precached = false;

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  bool get _tickerEnabled => TickerMode.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      precacheImage(const AssetImage(NovaPersonAvatar.openAsset), context);
      precacheImage(const AssetImage(NovaPersonAvatar.winkAsset), context);
    }
    _syncSchedule();
  }

  @override
  void didUpdateWidget(covariant NovaAnimated3DAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thinking != widget.thinking ||
        oldWidget.happy != widget.happy ||
        oldWidget.enableBlink != widget.enableBlink) {
      _syncSchedule();
    }
  }

  void _syncSchedule() {
    final active = _tickerEnabled &&
        !_reduceMotion &&
        widget.enableBlink &&
        !widget.thinking &&
        !widget.happy;
    if (active) {
      if (_winkScheduleTimer == null || !_winkScheduleTimer!.isActive) {
        _scheduleNextWink();
      }
    } else {
      _winkScheduleTimer?.cancel();
      _winkScheduleTimer = null;
      _winkHoldTimer?.cancel();
      _winkHoldTimer = null;
      if (_idleWinking && mounted) {
        setState(() => _idleWinking = false);
      }
    }
  }

  void _scheduleNextWink() {
    _winkScheduleTimer?.cancel();
    final delayMs = 4800 + _rng.nextInt(2600);
    _winkScheduleTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted ||
          !_tickerEnabled ||
          _reduceMotion ||
          widget.thinking ||
          widget.happy ||
          _isHovered ||
          _tapWinking) {
        return;
      }
      setState(() => _idleWinking = true);
      _winkHoldTimer?.cancel();
      _winkHoldTimer = Timer(const Duration(milliseconds: 240), () {
        if (!mounted) return;
        setState(() => _idleWinking = false);
        _scheduleNextWink();
      });
    });
  }

  void _triggerTapWink() {
    if (!widget.enableTapWink || _reduceMotion || widget.thinking) return;
    _tapWinkTimer?.cancel();
    setState(() => _tapWinking = true);
    _tapWinkTimer = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      setState(() => _tapWinking = false);
    });
  }

  @override
  void dispose() {
    _winkScheduleTimer?.cancel();
    _winkHoldTimer?.cancel();
    _tapWinkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showWink = !widget.thinking &&
        (widget.happy || _isHovered || _tapWinking || _idleWinking);

    Widget content = ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            NovaPersonAvatar.openAsset,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            filterQuality: FilterQuality.medium,
            isAntiAlias: true,
            gaplessPlayback: true,
          ),
          AnimatedOpacity(
            opacity: showWink ? 1.0 : 0.0,
            duration: Duration(
              milliseconds: _reduceMotion ? 0 : (showWink ? 90 : 120),
            ),
            curve: Curves.easeOut,
            child: Image.asset(
              NovaPersonAvatar.winkAsset,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              filterQuality: FilterQuality.medium,
              isAntiAlias: true,
              gaplessPlayback: true,
            ),
          ),
        ],
      ),
    );

    if (widget.enableHoverWink && !_reduceMotion) {
      content = MouseRegion(
        opaque: false,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: content,
      );
    }

    if (widget.enableTapWink && !_reduceMotion) {
      content = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _triggerTapWink(),
        child: content,
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: content,
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
