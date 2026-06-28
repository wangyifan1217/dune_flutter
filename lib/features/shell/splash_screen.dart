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

class _AppBootGateState extends State<AppBootGate> {
  /// 启屏最短展示时长，保证呼吸动画完整可见（避免会话校验过快导致一闪而过）。
  static const _minSplash = Duration(milliseconds: 1400);

  bool _minElapsed = false;
  bool _hydrated = false;
  bool _splashGone = false;
  String _version = '';

  /// 同时满足「最短动画时长」与「会话校验完成」才关闭启屏。
  bool get _ready => _minElapsed && _hydrated;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    Future<void>.delayed(_minSplash, () {
      if (mounted) setState(() => _minElapsed = true);
    });
  }

  Future<void> _loadVersion() async {
    var version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      final build = info.buildNumber.trim();
      version = build.isEmpty ? info.version : '${info.version} ($build)';
    } catch (_) {}
    if (mounted) setState(() => _version = version);
  }

  void _onHydrated() {
    if (mounted && !_hydrated) setState(() => _hydrated = true);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 正式应用始终在底层挂载并完成会话校验；启屏覆盖其上，ready 后淡出。
        LoginFlow(onHydrated: _onHydrated),
        if (!_splashGone)
          IgnorePointer(
            ignoring: _ready,
            child: AnimatedOpacity(
              opacity: _ready ? 0 : 1,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOut,
              onEnd: () {
                if (_ready && mounted) setState(() => _splashGone = true);
              },
              child: SplashScreen(version: _version),
            ),
          ),
      ],
    );
  }
}

/// 登录成功后覆屏展示启屏，最短展示 [duration] 后淡出。
class PostLoginSplashOverlay extends StatefulWidget {
  const PostLoginSplashOverlay({
    super.key,
    required this.onDismiss,
    this.duration = const Duration(milliseconds: 1400),
    this.version = '',
  });

  final VoidCallback onDismiss;
  final Duration duration;
  final String version;

  @override
  State<PostLoginSplashOverlay> createState() => _PostLoginSplashOverlayState();
}

class _PostLoginSplashOverlayState extends State<PostLoginSplashOverlay> {
  bool _minElapsed = false;
  bool _fadingOut = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.duration, () {
      if (mounted) setState(() => _minElapsed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: _minElapsed,
      child: AnimatedOpacity(
        opacity: _minElapsed ? 0 : 1,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        onEnd: () {
          if (_minElapsed && !_fadingOut && mounted) {
            _fadingOut = true;
            widget.onDismiss();
          }
        },
        child: SplashScreen(version: widget.version),
      ),
    );
  }
}

/// 启屏页：居中 logo 呼吸动画 + 底部版本号。
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.version = ''});

  final String version;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.92, end: 1.06).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _glow = Tween<double>(begin: 0.16, end: 0.42).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: Stack(
        children: [
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scale.value,
                  child: Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: DunesColors.accent.withValues(alpha: _glow.value),
                          blurRadius: 38,
                          spreadRadius: 4,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: child,
                  ),
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
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 30 + bottomInset,
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
                    widget.version.isEmpty ? '—' : 'v${widget.version}',
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: DunesColors.text.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
