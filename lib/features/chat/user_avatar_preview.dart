import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../conversation/conversation_service.dart';
import 'user_avatar_widget.dart';

const kUserAvatarPreviewKey = Key('user-avatar-preview');

/// 用户详情点头像：全屏放大查看，点空白或 Esc 关闭。
Future<void> showUserAvatarPreview(
  BuildContext context, {
  required String initial,
  required int seed,
  String? avatarPreset,
  String? avatarObjectKey,
  String? avatarUrl,
  ConversationService? avatarService,
}) {
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: '关闭头像预览',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) {
      return _UserAvatarPreviewDialog(
        initial: initial,
        seed: seed,
        avatarPreset: avatarPreset,
        avatarObjectKey: avatarObjectKey,
        avatarUrl: avatarUrl,
        avatarService: avatarService,
      );
    },
    transitionBuilder: (ctx, animation, _, child) {
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.90, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

class _UserAvatarPreviewDialog extends StatefulWidget {
  const _UserAvatarPreviewDialog({
    required this.initial,
    required this.seed,
    this.avatarPreset,
    this.avatarObjectKey,
    this.avatarUrl,
    this.avatarService,
  });

  final String initial;
  final int seed;
  final String? avatarPreset;
  final String? avatarObjectKey;
  final String? avatarUrl;
  final ConversationService? avatarService;

  @override
  State<_UserAvatarPreviewDialog> createState() =>
      _UserAvatarPreviewDialogState();
}

class _UserAvatarPreviewDialogState extends State<_UserAvatarPreviewDialog> {
  double _dragOffsetY = 0;
  bool _dragging = false;

  void _close(BuildContext context) {
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shortest = size.shortestSide;
    final avatarSize = (shortest * 0.72).clamp(160.0, shortest - 48);
    final progress = (_dragOffsetY.abs() / 240.0).clamp(0.0, 1.0);
    final backdropAlpha = (0.92 * (1.0 - progress * 0.72)).clamp(0.18, 0.92);
    final scale = (1.0 - progress * 0.18).clamp(0.82, 1.0);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () => _close(context),
      },
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          key: kUserAvatarPreviewKey,
          behavior: HitTestBehavior.opaque,
          onTap: () => _close(context),
          onVerticalDragStart: (_) => setState(() => _dragging = true),
          onVerticalDragUpdate: (d) {
            setState(() => _dragOffsetY += d.delta.dy);
          },
          onVerticalDragCancel: () {
            setState(() {
              _dragging = false;
              _dragOffsetY = 0;
            });
          },
          onVerticalDragEnd: (d) {
            final v = (d.primaryVelocity ?? 0).abs();
            if (_dragOffsetY.abs() > 110 || v > 650) {
              _close(context);
              return;
            }
            setState(() {
              _dragging = false;
              _dragOffsetY = 0;
            });
          },
          child: AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            color: Colors.black.withValues(alpha: backdropAlpha),
            child: SafeArea(
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: _dragOffsetY),
                  duration: _dragging
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  builder: (context, offsetY, child) {
                    return Transform.translate(
                      offset: Offset(0, offsetY),
                      child: child,
                    );
                  },
                  child: AnimatedScale(
                    scale: scale,
                    duration: _dragging
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: GestureDetector(
                        onTap: () => _close(context),
                        child: ImUserAvatar(
                          initial: widget.initial,
                          seed: widget.seed,
                          size: avatarSize,
                          avatarPreset: widget.avatarPreset,
                          avatarObjectKey: widget.avatarObjectKey,
                          avatarUrl: widget.avatarUrl,
                          avatarService: widget.avatarService,
                          borderRadius: avatarSize * 0.18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
