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
    barrierColor: Colors.black.withValues(alpha: 0.92),
    transitionDuration: const Duration(milliseconds: 200),
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
          scale: Tween<double>(begin: 0.94, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

class _UserAvatarPreviewDialog extends StatelessWidget {
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

  void _close(BuildContext context) {
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shortest = size.shortestSide;
    final avatarSize = (shortest * 0.72).clamp(160.0, shortest - 48);
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
          child: SafeArea(
            child: Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: GestureDetector(
                  onTap: () => _close(context),
                  child: ImUserAvatar(
                    initial: initial,
                    seed: seed,
                    size: avatarSize,
                    avatarPreset: avatarPreset,
                    avatarObjectKey: avatarObjectKey,
                    avatarUrl: avatarUrl,
                    avatarService: avatarService,
                    borderRadius: avatarSize * 0.18,
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
