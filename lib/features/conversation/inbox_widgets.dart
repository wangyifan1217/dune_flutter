import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../ai_summary/ai_summary_sparkle_icon.dart';
import '../chat/group_composite_avatar.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../nova/nova_icon.dart';
import 'inbox_format.dart';

class ChatInboxHeader extends StatelessWidget {
  const ChatInboxHeader({
    super.key,
    required this.onOpenContacts,
    this.onNewChat,
    required this.onOpenNova,
    this.onOpenAiSummary,
    this.onOpenFavorites,
    this.novaThinking = false,
    this.novaUnread = false,
  });

  final VoidCallback onOpenContacts;
  final VoidCallback? onNewChat;
  final VoidCallback onOpenNova;
  final VoidCallback? onOpenAiSummary;
  final VoidCallback? onOpenFavorites;
  final bool novaThinking;
  final bool novaUnread;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 3),
      child: SizedBox(
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '消息',
              style: DunesTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1C1C1C),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _NovaEyesButton(onTap: onOpenNova, unread: novaUnread),
                  if (novaThinking)
                    Text(
                      '正在思考',
                      style: DunesTypography.sans(
                        fontSize: 10.5,
                        color: const Color(0xFF07A957),
                      ),
                    ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _InboxHeaderActions(
                onOpenContacts: onOpenContacts,
                onNewChat: onNewChat,
                onOpenAiSummary: onOpenAiSummary,
                onOpenFavorites: onOpenFavorites,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// PC / 宽屏：右侧收成「···」，点开后在下方浮层展开；手机仍平铺。
class _InboxHeaderActions extends StatefulWidget {
  const _InboxHeaderActions({
    required this.onOpenContacts,
    this.onNewChat,
    this.onOpenAiSummary,
    this.onOpenFavorites,
  });

  final VoidCallback onOpenContacts;
  final VoidCallback? onNewChat;
  final VoidCallback? onOpenAiSummary;
  final VoidCallback? onOpenFavorites;

  @override
  State<_InboxHeaderActions> createState() => _InboxHeaderActionsState();
}

class _InboxHeaderActionsState extends State<_InboxHeaderActions> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlay;
  bool _expanded = false;

  /// APP / PC 统一用「···」下拉，避免手机右上角图标挤在一起。
  bool get _useCluster => true;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _toggle() {
    if (_expanded) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
    if (_expanded && mounted) {
      setState(() => _expanded = false);
    } else {
      _expanded = false;
    }
  }

  void _runAndClose(VoidCallback action) {
    _removeOverlay();
    action();
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    _overlay = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
                child: const SizedBox.expand(),
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 6),
              child: _InboxActionsDropdown(
                showAiSummary: widget.onOpenAiSummary != null,
                showNewChat: widget.onNewChat != null,
                showFavorites: widget.onOpenFavorites != null,
                onAiSummary: widget.onOpenAiSummary == null
                    ? null
                    : () => _runAndClose(widget.onOpenAiSummary!),
                onContacts: () => _runAndClose(widget.onOpenContacts),
                onNewChat: widget.onNewChat == null
                    ? null
                    : () => _runAndClose(widget.onNewChat!),
                onFavorites: widget.onOpenFavorites == null
                    ? null
                    : () => _runAndClose(widget.onOpenFavorites!),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlay!);
    setState(() => _expanded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_useCluster) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onOpenAiSummary != null)
            AiSummarySparkleIcon(onTap: widget.onOpenAiSummary!),
          _IconBtn(
            icon: Icons.people_outline_rounded,
            onTap: widget.onOpenContacts,
          ),
          if (widget.onNewChat != null)
            _IconBtn(icon: Icons.edit_outlined, onTap: widget.onNewChat!),
        ],
      );
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: _IconBtn(
        icon: _expanded ? Icons.close_rounded : Icons.more_horiz_rounded,
        onTap: _toggle,
      ),
    );
  }
}

class _InboxActionsDropdown extends StatelessWidget {
  const _InboxActionsDropdown({
    required this.showAiSummary,
    required this.showNewChat,
    required this.showFavorites,
    required this.onContacts,
    this.onAiSummary,
    this.onNewChat,
    this.onFavorites,
  });

  final bool showAiSummary;
  final bool showNewChat;
  final bool showFavorites;
  final VoidCallback? onAiSummary;
  final VoidCallback onContacts;
  final VoidCallback? onNewChat;
  final VoidCallback? onFavorites;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x28000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
          border: Border.all(color: const Color(0xFFECECEC)),
        ),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showNewChat && onNewChat != null)
                _DropdownItem(
                  leading: const Icon(
                    Icons.group_add_outlined,
                    size: 20,
                    color: Color(0xFF4B5563),
                  ),
                  label: '发起群聊',
                  onTap: onNewChat!,
                ),
              _DropdownItem(
                leading: const Icon(
                  Icons.people_outline_rounded,
                  size: 20,
                  color: Color(0xFF4B5563),
                ),
                label: '通讯录',
                onTap: onContacts,
              ),
              if (showAiSummary && onAiSummary != null)
                _DropdownItem(
                  leading: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CustomPaint(
                      painter: GeminiSparklePainter(
                        colors: kAiSummaryPurpleGradient,
                        showCompanion: true,
                        pulse: 1,
                      ),
                    ),
                  ),
                  label: '智能总结',
                  onTap: onAiSummary!,
                ),
              if (showFavorites && onFavorites != null)
                _DropdownItem(
                  leading: const Icon(
                    Icons.bookmark_border_rounded,
                    size: 20,
                    color: Color(0xFF4B5563),
                  ),
                  label: '我的收藏',
                  onTap: onFavorites!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropdownItem extends StatelessWidget {
  const _DropdownItem({
    required this.leading,
    required this.label,
    required this.onTap,
  });

  final Widget leading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: DunesTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1C1C1C),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatInboxSearchBar extends StatelessWidget {
  const ChatInboxSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // 与顶栏动画隔离，避免 Web 合成层把搜索栏一起带动。
    return RepaintBoundary(
      child: Container(
        color: const Color(0xFFF5F5F5),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 17, color: Color(0xFFB2B2B2)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: DunesColors.text,
                  ),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '搜索会话或联系人',
                    hintStyle: DunesTypography.sans(
                      fontSize: 13,
                      color: const Color(0xFFB2B2B2),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  if (controller.text.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return IconButton(
                    tooltip: '清除',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                    icon: const Icon(
                      Icons.close,
                      color: Color(0xFFB2B2B2),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatInboxSectionHeader extends StatelessWidget {
  const ChatInboxSectionHeader({
    super.key,
    required this.label,
    required this.count,
    this.pinned = false,
    this.leading,
    this.collapsed = false,
    this.onTap,
  });

  final String label;
  final int count;
  final bool pinned;
  final Widget? leading;
  final bool collapsed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 5),
              ] else
                Icon(
                  pinned ? Icons.push_pin_outlined : Icons.more_horiz,
                  size: 11,
                  color: pinned ? DunesColors.accent : DunesColors.text3,
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: DunesTypography.mono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.08 * 9.5,
                    color: DunesColors.text3,
                  ),
                ),
              ),
              Text(
                '$count',
                style: DunesTypography.mono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.04 * 9.5,
                  color: DunesColors.text3,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  collapsed
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                  size: 16,
                  color: DunesColors.text3,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum ChatInboxRowKind {
  aiAssistant,
  aiSummary,
  approvalAssistant,
  taskAssistant,
  driveAssistant,
  weeklySummary,
  reconciliationAssistant,
  administrativeNotice,
  duneAnnouncement,
  selfMemo,
  systemNotification,
  broadcast,
  workgroupApproval,
  group,
  private,
  robot,
}

class ChatInboxRow extends StatelessWidget {
  const ChatInboxRow({
    super.key,
    required this.kind,
    required this.title,
    required this.preview,
    required this.timeLabel,
    required this.onTap,
    this.subtitle,
    this.memberCount,
    this.unreadCount = 0,
    this.muted = false,
    this.pinned = false,
    this.showAiMark = false,
    this.showOnlineDot = false,
    this.avatarInitial,
    this.avatarSeed = 0,
    this.avatarPreset,
    this.avatarObjectKey,
    this.avatarUrl,
    this.avatarService,
    this.groupAvatarMembers = const <ConversationAvatarMember>[],
    this.sysTag,
    this.showDivider = true,
    this.previewGenerating = false,
    this.selected = false,
    this.robotAvatar,
  });

  final ChatInboxRowKind kind;
  final String title;
  final String preview;
  final String timeLabel;
  final VoidCallback onTap;
  final String? subtitle;
  final int? memberCount;
  final int unreadCount;
  final bool muted;
  final bool pinned;
  final bool showAiMark;
  final bool showOnlineDot;
  final String? avatarInitial;
  final int avatarSeed;
  final String? avatarPreset;
  final String? avatarObjectKey;
  final String? avatarUrl;
  final ConversationService? avatarService;
  final List<ConversationAvatarMember> groupAvatarMembers;
  final String? sysTag;
  final bool showDivider;
  final bool previewGenerating;
  final bool selected;
  final Widget? robotAvatar;

  Color get _rowBg {
    if (selected) return DunesColors.accentSoft;
    if (pinned) return DunesColors.bgSoft;
    return DunesColors.bgApp;
  }

  @override
  Widget build(BuildContext context) {
    final unreadText = unreadCount > 99 ? '99+' : '$unreadCount';
    final unreadColor =
        kind == ChatInboxRowKind.private ||
            kind == ChatInboxRowKind.aiAssistant ||
            kind == ChatInboxRowKind.aiSummary ||
            kind == ChatInboxRowKind.approvalAssistant ||
            kind == ChatInboxRowKind.taskAssistant ||
            kind == ChatInboxRowKind.driveAssistant ||
            kind == ChatInboxRowKind.weeklySummary ||
            kind == ChatInboxRowKind.reconciliationAssistant ||
            kind == ChatInboxRowKind.administrativeNotice ||
            kind == ChatInboxRowKind.duneAnnouncement ||
            kind == ChatInboxRowKind.selfMemo ||
            kind == ChatInboxRowKind.robot
        ? const Color(0xFF7B5CD8)
        : DunesColors.coral;
    return Column(
      children: [
        Material(
          color: _rowBg,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        RepaintBoundary(
                          child: OverflowBox(
                            alignment: Alignment.center,
                            maxWidth: 56,
                            maxHeight: 56,
                            child:
                                robotAvatar ??
                                _Avatar(
                                  kind: kind,
                                  initial: avatarInitial,
                                  seed: avatarSeed,
                                  showOnlineDot: showOnlineDot,
                                  avatarPreset: avatarPreset,
                                  avatarObjectKey: avatarObjectKey,
                                  avatarUrl: avatarUrl,
                                  avatarService: avatarService,
                                  groupAvatarMembers: groupAvatarMembers,
                                ),
                          ),
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            right: -4,
                            top: -5,
                            child: _UnreadBadge(
                              text: unreadText,
                              color: unreadColor,
                              mini: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: DunesTypography.sans(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: -0.01 * 15,
                                        color: DunesColors.text,
                                      ),
                                    ),
                                  ),
                                  if (showAiMark) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: DunesColors.accent,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        'AI',
                                        style: DunesTypography.mono(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                          letterSpacing: 0.04 * 8.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (memberCount != null &&
                                      memberCount! > 0) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      '($memberCount)',
                                      style: DunesTypography.sans(
                                        fontSize: 11,
                                        color: DunesColors.text3,
                                      ),
                                    ),
                                  ],
                                  if (subtitle != null &&
                                      subtitle!.isNotEmpty) ...[
                                    Text(
                                      ' · ${subtitle!.toUpperCase()}',
                                      style: DunesTypography.mono(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.06 * 8.5,
                                        color: DunesColors.text3,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (timeLabel.isNotEmpty)
                              Text(
                                timeLabel,
                                style: DunesTypography.sans(
                                  fontSize: 11,
                                  color: DunesColors.text3,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        _PreviewLine(
                          preview: preview,
                          sysTag: sysTag,
                          generating: previewGenerating,
                        ),
                      ],
                    ),
                  ),
                  if (muted)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Icon(
                            Icons.notifications_off_outlined,
                            size: 14,
                            color: DunesColors.text3,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          ColoredBox(
            color: _rowBg,
            child: const Padding(
              padding: EdgeInsets.only(left: 80, right: 16),
              child: Divider(
                height: 1,
                thickness: 1,
                color: DunesColors.borderSoft,
              ),
            ),
          ),
      ],
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({
    required this.text,
    required this.color,
    this.mini = false,
  });

  final String text;
  final Color color;
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final isSingle = text.length == 1;
    return Container(
      margin: mini ? EdgeInsets.zero : const EdgeInsets.only(top: 4),
      constraints: BoxConstraints(
        minWidth: mini ? (isSingle ? 16 : 20) : (isSingle ? 24 : 26),
        minHeight: mini ? 16 : 24,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: mini ? (isSingle ? 0 : 5) : (isSingle ? 0 : 8),
        vertical: 0,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: mini ? 1.0 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.22),
            blurRadius: mini ? 8 : 12,
            spreadRadius: 0,
            offset: Offset(0, mini ? 2 : 3),
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: DunesTypography.sans(
          fontSize: mini ? 9 : 11,
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: mini ? 0 : -0.02 * 11,
          height: 1,
        ),
      ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({
    required this.preview,
    this.sysTag,
    this.generating = false,
  });

  final String preview;
  final String? sysTag;
  final bool generating;

  @override
  Widget build(BuildContext context) {
    if (generating) {
      return Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              preview.isEmpty ? '正在生成…' : preview,
              style: DunesTypography.sans(
                fontSize: 12.5,
                color: DunesColors.text3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          if (sysTag != null && sysTag!.isNotEmpty)
            TextSpan(
              text: '$sysTag ',
              style: DunesTypography.mono(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: DunesColors.accent,
              ),
            ),
          TextSpan(
            text: preview.isEmpty ? '暂无消息' : preview,
            style: DunesTypography.sans(
              fontSize: 12.5,
              color: DunesColors.text3,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.kind,
    this.initial,
    this.seed = 0,
    this.showOnlineDot = false,
    this.avatarPreset,
    this.avatarObjectKey,
    this.avatarUrl,
    this.avatarService,
    this.groupAvatarMembers = const <ConversationAvatarMember>[],
  });

  final ChatInboxRowKind kind;
  final String? initial;
  final int seed;
  final bool showOnlineDot;
  final String? avatarPreset;
  final String? avatarObjectKey;
  final String? avatarUrl;
  final ConversationService? avatarService;
  final List<ConversationAvatarMember> groupAvatarMembers;

  static const _inboxAvatarSize = kImListAvatarSize;
  static const _inboxAvatarRadius = _inboxAvatarSize * 0.18;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(_inboxAvatarRadius);

    BoxDecoration decoration;
    Widget child;

    switch (kind) {
      case ChatInboxRowKind.aiAssistant:
        return const NovaIconImage(size: _inboxAvatarSize, borderRadius: 12);
      case ChatInboxRowKind.approvalAssistant:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [DunesColors.brandPurple, DunesColors.brandPurpleDeep],
          ),
        );
        child = const Icon(
          Icons.fact_check_outlined,
          color: Colors.white,
          size: 20,
        );
      case ChatInboxRowKind.taskAssistant:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2F8F7E), Color(0xFF5EAEDE)],
          ),
        );
        child = const Icon(
          Icons.assignment_turned_in_outlined,
          color: Colors.white,
          size: 20,
        );
      case ChatInboxRowKind.driveAssistant:
        decoration = BoxDecoration(
          color: const Color(0xFF3B82F6),
          borderRadius: borderRadius,
        );
        child = const Icon(Icons.cloud_outlined, color: Colors.white, size: 21);
      case ChatInboxRowKind.weeklySummary:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFC4A574), Color(0xFF8B6A3F)],
          ),
        );
        child = const Icon(
          Icons.auto_stories_outlined,
          color: Colors.white,
          size: 20,
        );
      case ChatInboxRowKind.reconciliationAssistant:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5B6FC4), Color(0xFF7652B8)],
          ),
        );
        child = const Icon(
          Icons.sync_alt_rounded,
          color: Colors.white,
          size: 20,
        );
      case ChatInboxRowKind.administrativeNotice:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3D7A8C), Color(0xFF5DA7A2)],
          ),
        );
        child = const Icon(
          Icons.campaign_outlined,
          color: Colors.white,
          size: 20,
        );
      case ChatInboxRowKind.duneAnnouncement:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: const LinearGradient(
            colors: [Color(0xFFC2AEE7), Color(0xFF9C82CE)],
          ),
        );
        child = const Icon(
          Icons.campaign_outlined,
          color: Colors.white,
          size: 20,
        );
      case ChatInboxRowKind.selfMemo:
        decoration = BoxDecoration(
          color: const Color(0xFF7B5CD8),
          borderRadius: borderRadius,
        );
        child = const Icon(
          Icons.folder_copy_outlined,
          color: Colors.white,
          size: 21,
        );
      case ChatInboxRowKind.robot:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: const LinearGradient(
            colors: [Color(0xFFB8A4E8), Color(0xFF7B5CD8)],
          ),
        );
        child = const Icon(
          Icons.smart_toy_outlined,
          color: Colors.white,
          size: 20,
        );
      case ChatInboxRowKind.aiSummary:
        return const AiSummaryAvatarMark(size: _inboxAvatarSize);
      case ChatInboxRowKind.systemNotification:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: const LinearGradient(
            colors: [Color(0xFFC2AEE7), Color(0xFF9C82CE)],
          ),
        );
        child = const Icon(
          Icons.notifications_none_rounded,
          color: Colors.white,
          size: 17,
        );
      case ChatInboxRowKind.broadcast:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: const LinearGradient(
            colors: [Color(0xFFD9C9F0), Color(0xFFB89FE2)],
          ),
        );
        child = const Icon(
          Icons.campaign_outlined,
          color: Colors.white,
          size: 17,
        );
      case ChatInboxRowKind.group:
      case ChatInboxRowKind.workgroupApproval:
        if (groupAvatarMembers.isNotEmpty) {
          return GroupCompositeAvatar(
            members: groupAvatarMembers,
            size: _inboxAvatarSize,
            avatarService: avatarService,
          );
        }
        if (kind == ChatInboxRowKind.workgroupApproval) {
          decoration = BoxDecoration(
            borderRadius: borderRadius,
            gradient: const LinearGradient(
              colors: [Color(0xFF9079C2), Color(0xFF6A4FA0)],
            ),
          );
          child = const Icon(
            Icons.assignment_outlined,
            color: Colors.white,
            size: 17,
          );
        } else {
          decoration = BoxDecoration(
            borderRadius: borderRadius,
            gradient: const LinearGradient(
              colors: [Color(0xFFCABCEB), Color(0xFFA88CD8)],
            ),
          );
          child = const Icon(
            Icons.groups_outlined,
            color: Colors.white,
            size: 17,
          );
        }
      case ChatInboxRowKind.private:
        final letter = (initial == null || initial!.isEmpty) ? '?' : initial!;
        if (avatarService != null ||
            (avatarPreset != null && avatarPreset!.isNotEmpty) ||
            (avatarObjectKey != null && avatarObjectKey!.isNotEmpty) ||
            (avatarUrl != null && avatarUrl!.isNotEmpty)) {
          return ImUserAvatar(
            initial: letter,
            seed: seed,
            size: _inboxAvatarSize,
            showOnline: showOnlineDot,
            avatarPreset: avatarPreset,
            avatarObjectKey: avatarObjectKey,
            avatarUrl: avatarUrl,
            avatarService: avatarService,
            borderRadius: _inboxAvatarRadius,
          );
        }
        final style = InboxFormat.personStyle(seed);
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(colors: style.gradient),
        );
        child = Text(
          (initial == null || initial!.isEmpty) ? '?' : initial!,
          style: TextStyle(
            color: style.textColor,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: _inboxAvatarSize,
          height: _inboxAvatarSize,
          decoration: decoration,
          alignment: Alignment.center,
          child: child,
        ),
        if (showOnlineDot && kind == ChatInboxRowKind.private)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: DunesColors.green,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: DunesColors.bgApp, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: DunesColors.text2),
        ),
      ),
    );
  }
}

class _NovaEyesButton extends StatefulWidget {
  const _NovaEyesButton({required this.onTap, required this.unread});

  final VoidCallback onTap;
  final bool unread;

  @override
  State<_NovaEyesButton> createState() => _NovaEyesButtonState();
}

class _NovaEyesButtonState extends State<_NovaEyesButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'NOVA',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onTap,
          child: SizedBox(
            width: 44,
            height: 40,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final t = _controller.value;
                      final lookOffset = math.sin(t * math.pi * 2) * 3;
                      final blinkDistance = (t - 0.72).abs();
                      final eyeScaleY = blinkDistance < 0.055
                          ? blinkDistance / 0.055
                          : 1.0;
                      return Transform.translate(
                        offset: Offset(lookOffset, 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _NovaEye(verticalScale: eyeScaleY),
                            const SizedBox(width: 4),
                            _NovaEye(verticalScale: eyeScaleY),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (widget.unread)
                  Positioned(
                    top: 1,
                    right: 1,
                    child: Container(
                      width: 16,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF5B61),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '1',
                        style: DunesTypography.sans(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NovaEye extends StatelessWidget {
  const _NovaEye({required this.verticalScale});

  final double verticalScale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleY: verticalScale,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: const Color(0xFF7E64BD),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class NovaSectionIcon extends StatelessWidget {
  const NovaSectionIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const NovaIconImage(size: 15, borderRadius: 4);
  }
}

/// 与 WebView C1 左滑删除对齐（本地隐藏，非服务端删除）。
class SwipeableChatInboxRow extends StatefulWidget {
  const SwipeableChatInboxRow({
    super.key,
    required this.child,
    required this.onDelete,
  });

  final Widget child;
  final VoidCallback onDelete;

  @override
  State<SwipeableChatInboxRow> createState() => _SwipeableChatInboxRowState();
}

class _SwipeableChatInboxRowState extends State<SwipeableChatInboxRow> {
  static const _actionWidth = 72.0;
  double _offset = 0;

  void _close() {
    if (_offset == 0) return;
    setState(() => _offset = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        if (_offset != 0)
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: _actionWidth,
                child: Material(
                  color: DunesColors.coral,
                  child: InkWell(
                    onTap: () {
                      _close();
                      widget.onDelete();
                    },
                    child: Center(
                      child: Text(
                        '删除',
                        style: DunesTypography.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _offset = (_offset + details.delta.dx).clamp(-_actionWidth, 0);
            });
          },
          onHorizontalDragEnd: (_) {
            setState(() {
              _offset = _offset < -_actionWidth / 2 ? -_actionWidth : 0;
            });
          },
          onTap: _offset == 0 ? null : _close,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_offset, 0, 0),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
