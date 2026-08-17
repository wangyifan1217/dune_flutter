import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../chat/group_composite_avatar.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';

OverlayEntry? _activeInAppMessageBanner;
int _activeBannerConversationId = 0;

/// 当前应用内 IM 横幅对应的会话；没有横幅时为 0。
int get inAppMessageBannerConversationId => _activeBannerConversationId;

/// APP 前台微信式 IM 横幅（组件保留，当前未接入）。
/// 暂时恢复为仅 TPNS / 桌面通知。
void showInAppMessageBanner({
  required BuildContext context,
  required int conversationId,
  required String title,
  required String body,
  NativeConversation? conversation,
  AuthSession? session,
  required VoidCallback onTap,
  Duration duration = const Duration(milliseconds: 4500),
}) {
  if (conversationId <= 0) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _activeInAppMessageBanner?.remove();
  _activeInAppMessageBanner = null;
  _activeBannerConversationId = conversationId;

  late OverlayEntry entry;
  void removeEntry() {
    if (_activeInAppMessageBanner == entry) {
      _activeInAppMessageBanner = null;
      _activeBannerConversationId = 0;
      entry.remove();
    }
  }

  entry = OverlayEntry(
    builder: (ctx) => _InAppMessageBannerOverlay(
      title: title,
      body: body,
      conversation: conversation,
      session: session,
      autoDismiss: duration,
      onAction: onTap,
      onRemove: removeEntry,
    ),
  );

  _activeInAppMessageBanner = entry;
  overlay.insert(entry);
}

void dismissInAppMessageBanner() {
  _activeInAppMessageBanner?.remove();
  _activeInAppMessageBanner = null;
  _activeBannerConversationId = 0;
}

class _InAppMessageBannerOverlay extends StatefulWidget {
  const _InAppMessageBannerOverlay({
    required this.title,
    required this.body,
    required this.onAction,
    required this.onRemove,
    this.conversation,
    this.session,
    this.autoDismiss,
  });

  final String title;
  final String body;
  final NativeConversation? conversation;
  final AuthSession? session;
  final VoidCallback onAction;
  final VoidCallback onRemove;
  final Duration? autoDismiss;

  @override
  State<_InAppMessageBannerOverlay> createState() =>
      _InAppMessageBannerOverlayState();
}

class _InAppMessageBannerOverlayState extends State<_InAppMessageBannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -0.18),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  ConversationService? _avatarService;
  Timer? _autoTimer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final session = widget.session;
    if (session != null) {
      _avatarService = ConversationService(session: session);
    }
    final auto = widget.autoDismiss;
    if (auto != null) {
      _autoTimer = Timer(auto, () => _close(act: false));
    }
  }

  Future<void> _close({required bool act}) async {
    if (_closing) return;
    _closing = true;
    _autoTimer?.cancel();
    try {
      if (mounted) await _controller.reverse();
    } catch (_) {}
    if (act) widget.onAction();
    widget.onRemove();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _controller.dispose();
    _avatarService?.close();
    super.dispose();
  }

  String _initial(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return String.fromCharCode(t.runes.first);
  }

  Widget _buildAvatar() {
    const size = 40.0;
    final conv = widget.conversation;
    final title = widget.title.trim();
    final initial = _initial(
      conv?.title.trim().isNotEmpty == true ? conv!.title : title,
    );
    if (conv != null &&
        (conv.isGroup || conv.isWorkgroupApproval) &&
        conv.avatarMembers.isNotEmpty) {
      return GroupCompositeAvatar(
        members: conv.avatarMembers,
        size: size,
        avatarService: _avatarService,
      );
    }
    return ImUserAvatar(
      initial: initial,
      seed: conv?.peerUserId ?? conv?.id ?? title.hashCode,
      size: size,
      avatarPreset: conv?.peerAvatarPreset,
      avatarObjectKey: conv?.peerAvatarObjectKey,
      avatarUrl: conv?.peerAvatarUrl,
      avatarService: _avatarService,
      borderRadius: size * 0.18,
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: topInset + 8,
      left: 10,
      right: 10,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Dismissible(
            key: const ValueKey<String>('in-app-im-banner'),
            direction: DismissDirection.up,
            dismissThresholds: const {DismissDirection.up: 0.18},
            onDismissed: (_) {
              if (_closing) return;
              _closing = true;
              _autoTimer?.cancel();
              widget.onRemove();
            },
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _close(act: true),
                child: Ink(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                    child: Row(
                      children: [
                        _buildAvatar(),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title.trim().isEmpty
                                    ? '沙丘'
                                    : widget.title.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DunesTypography.sans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: DunesColors.text,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.body.trim().isEmpty
                                    ? '您有新消息'
                                    : widget.body.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DunesTypography.sans(
                                  fontSize: 13,
                                  color: DunesColors.text2,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
