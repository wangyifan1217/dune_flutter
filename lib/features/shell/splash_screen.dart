import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/login_flow.dart';

/// 启动门控：冷启动直接进入正式应用（已屏蔽启屏动画，秒开 IM 列表）。
/// App 仅在后台被唤醒（进程未被杀死）时不会重建该组件。
class AppBootGate extends StatelessWidget {
  const AppBootGate({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: DunesColors.bgApp,
      child: LoginFlow(),
    );
  }
}

/// 登录成功后启屏覆层；当前产品已屏蔽，挂载后立刻关闭。
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

class _PostLoginSplashOverlayState extends State<PostLoginSplashOverlay> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 启屏视觉（保留供以后恢复使用）。
class SplashScreen extends StatelessWidget {
  const SplashScreen({
    super.key,
    this.version = '',
    this.exitAnimation,
  });

  final String version;
  final Animation<double>? exitAnimation;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.bgApp,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '沙丘',
              style: DunesTypography.sans(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                color: DunesColors.text,
              ),
            ),
            if (version.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'v$version',
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.text3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
