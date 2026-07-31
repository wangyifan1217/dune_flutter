import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/login_flow.dart';

/// 启动门控：进程冷启动（被杀死后重新打开 / 首次安装）时先展示启屏，
/// 启屏加载完毕后切换到正式应用。App 仅在后台被唤醒（进程未被杀死）时
/// 不会重建该组件，因此不会重复展示启屏。
class AppBootGate extends StatefulWidget {
  const AppBootGate({super.key});

  @override
  State<AppBootGate> createState() => _AppBootGateState();
}

class _AppBootGateState extends State<AppBootGate>
    with SingleTickerProviderStateMixin {
  /// 启屏最短展示时长，保证呼吸动画至少完整一轮可见。
  static const _minSplash = Duration(milliseconds: 1800);

  /// 退出动效时长：Logo 放大消散 + 整页淡出。
  static const _exitDuration = Duration(milliseconds: 720);

  bool _minElapsed = false;
  bool _hydrated = false;
  bool _splashGone = false;
  bool _exitStarted = false;
  String _version = '';

  late final AnimationController _exit;

  /// 同时满足「最短动画时长」与「会话校验完成」才开始退出启屏。
  bool get _ready => _minElapsed && _hydrated;

  @override
  void initState() {
    super.initState();
    _exit = AnimationController(vsync: this, duration: _exitDuration);
    _loadVersion();
    Future<void>.delayed(_minSplash, () {
      if (mounted) {
        setState(() => _minElapsed = true);
        _tryStartExit();
      }
    });
  }

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    var version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version.trim();
    } catch (_) {}
    if (mounted) setState(() => _version = version);
  }

  void _onHydrated() {
    if (mounted && !_hydrated) {
      setState(() => _hydrated = true);
      _tryStartExit();
    }
  }

  void _tryStartExit() {
    if (!_ready || _exitStarted || !mounted) return;
    _exitStarted = true;
    _exit.forward().whenComplete(() {
      if (mounted) setState(() => _splashGone = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 始终铺同色底，避免启屏淡出瞬间透出空栈黑屏。
        const ColoredBox(color: DunesColors.bgApp),
        // 预挂载正式内容（不 Offstage），启屏盖在上面；退出时底下已就绪可交叉淡入。
        IgnorePointer(
          ignoring: !_splashGone,
          child: LoginFlow(onHydrated: _onHydrated),
        ),
        if (!_splashGone)
          IgnorePointer(
            child: FadeTransition(
              opacity: Tween<double>(begin: 1, end: 0).animate(
                CurvedAnimation(
                  parent: _exit,
                  curve: const Interval(0.15, 1, curve: Curves.easeInOutCubic),
                ),
              ),
              child: SplashScreen(
                version: _version,
                exitAnimation: _exit,
              ),
            ),
          ),
      ],
    );
  }
}

/// 登录成功后覆屏展示启屏，最短展示 [duration] 后以同样动效淡出。
class PostLoginSplashOverlay extends StatefulWidget {
  const PostLoginSplashOverlay({
    super.key,
    required this.onDismiss,
    this.duration = const Duration(milliseconds: 1800),
    this.version = '',
  });

  final VoidCallback onDismiss;
  final Duration duration;
  final String version;

  @override
  State<PostLoginSplashOverlay> createState() => _PostLoginSplashOverlayState();
}

class _PostLoginSplashOverlayState extends State<PostLoginSplashOverlay>
    with SingleTickerProviderStateMixin {
  static const _exitDuration = Duration(milliseconds: 720);

  bool _dismissed = false;
  late final AnimationController _exit;

  @override
  void initState() {
    super.initState();
    _exit = AnimationController(vsync: this, duration: _exitDuration);
    Future<void>.delayed(widget.duration, () {
      if (!mounted) return;
      _exit.forward().whenComplete(() {
        if (!_dismissed && mounted) {
          _dismissed = true;
          widget.onDismiss();
        }
      });
    });
  }

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0).animate(
          CurvedAnimation(
            parent: _exit,
            curve: const Interval(0.15, 1, curve: Curves.easeInOutCubic),
          ),
        ),
        child: SplashScreen(
          version: widget.version,
          exitAnimation: _exit,
        ),
      ),
    );
  }
}

/// 启屏页：居中 Logo 呼吸 → 退出时放大消散 + 底部文案淡出。
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.version = '',
    this.exitAnimation,
  });

  final String version;

  /// 0→1 退出进度；为空则仅呼吸、不退出。
  final Animation<double>? exitAnimation;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    widget.exitAnimation?.addStatusListener(_onExitStatus);
  }

  @override
  void didUpdateWidget(covariant SplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exitAnimation != widget.exitAnimation) {
      oldWidget.exitAnimation?.removeStatusListener(_onExitStatus);
      widget.exitAnimation?.addStatusListener(_onExitStatus);
      if (widget.exitAnimation?.isAnimating == true ||
          widget.exitAnimation?.isCompleted == true) {
        _stopBreathForExit();
      }
    }
  }

  void _onExitStatus(AnimationStatus status) {
    if (status == AnimationStatus.forward ||
        status == AnimationStatus.completed) {
      _stopBreathForExit();
    }
  }

  void _stopBreathForExit() {
    if (!_breath.isAnimating && _breath.value == 0.5) return;
    // 退出前把呼吸收在中位，避免和放大消散抢戏。
    _breath.stop();
    _breath.value = 0.5;
  }

  @override
  void dispose() {
    widget.exitAnimation?.removeStatusListener(_onExitStatus);
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final exit = widget.exitAnimation;

    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _breath,
          if (exit != null) exit,
        ]),
        builder: (context, child) {
          final breathT = Curves.easeInOut.transform(_breath.value);
          final exitT = exit == null
              ? 0.0
              : Curves.easeInOutCubic.transform(exit.value);

          // 呼吸：0.92↔1.06；退出：从当前尺度放大到约 1.28 并淡出。
          final breathScale = 0.92 + 0.14 * breathT;
          final exitScale = 1.0 + 0.22 * exitT;
          final scale = breathScale * exitScale;

          final breathGlow = 0.14 + 0.18 * breathT;
          // 退出前半段光晕略增强，后半段收掉，形成「消散」感。
          final exitGlowBoost = exitT < 0.45
              ? exitT / 0.45
              : (1.0 - (exitT - 0.45) / 0.55);
          final glowAlpha =
              (breathGlow + 0.16 * exitGlowBoost).clamp(0.0, 0.42);
          final blur = 28.0 + 18.0 * breathT + 24.0 * exitT;
          final spread = 2.0 + 4.0 * breathT + 6.0 * exitT;

          final logoOpacity = (1.0 - Curves.easeIn.transform(
            (exitT / 0.75).clamp(0.0, 1.0),
          ));
          final textOpacity = (1.0 - Curves.easeIn.transform(
            (exitT / 0.55).clamp(0.0, 1.0),
          ));

          return Stack(
            children: [
              Center(
                child: Opacity(
                  opacity: logoOpacity,
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: DunesColors.accent
                                .withValues(alpha: glowAlpha),
                            blurRadius: blur,
                            spreadRadius: spread,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: child,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 30 + bottomInset,
                child: Opacity(
                  opacity: textOpacity,
                  child: Transform.translate(
                    offset: Offset(0, 10 * exitT),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '沙丘',
                          style: DunesTypography.sans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.text,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        AnimatedOpacity(
                          opacity: widget.version.isEmpty ? 0 : 1,
                          duration: const Duration(milliseconds: 240),
                          child: Text(
                            widget.version.isEmpty
                                ? '—'
                                : 'v${widget.version}',
                            style: DunesTypography.sans(
                              fontSize: 12,
                              color: DunesColors.text.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: Image.asset(
          'assets/images/app_logo.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: DunesColors.accentSoft,
            alignment: Alignment.center,
            child: const Icon(
              Icons.terrain_rounded,
              size: 48,
              color: DunesColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}
