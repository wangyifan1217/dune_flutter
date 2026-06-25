import 'package:flutter/material.dart';

import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_service.dart';
import '../../core/theme/dunes_theme.dart';
import '../nova/nova_icon.dart';
import 'inbox_format.dart';

class ChatInboxHeader extends StatelessWidget {
  const ChatInboxHeader({
    super.key,
    required this.visibleCount,
    required this.onOpenContacts,
    required this.onNewChat,
    required this.onScan,
  });

  final int visibleCount;
  final VoidCallback onOpenContacts;
  final VoidCallback onNewChat;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 11),
      child: Row(
        children: [
          RichText(
            text: TextSpan(
              style: DunesTypography.sans(
                fontSize: 21,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.025 * 21,
                color: DunesColors.text,
              ),
              children: [
                const TextSpan(text: '消息'),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'CHAT · $visibleCount',
                      style: DunesTypography.mono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.06 * 9.5,
                        color: DunesColors.text3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          _IconBtn(icon: Icons.people_outline_rounded, onTap: onOpenContacts),
          _IconBtn(icon: Icons.edit_outlined, onTap: onNewChat),
          _IconBtn(icon: Icons.qr_code_scanner_outlined, onTap: onScan),
        ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: DunesColors.bgSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 15, color: DunesColors.text3),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: DunesTypography.sans(fontSize: 13, color: DunesColors.text),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '搜索人 / 群 / 消息内容 / 审批号',
                  hintStyle: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            const Icon(Icons.mic_none_rounded, size: 15, color: DunesColors.text3),
          ],
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
  });

  final String label;
  final int count;
  final bool pinned;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
        ],
      ),
    );
  }
}

enum ChatInboxRowKind {
  aiAssistant,
  systemNotification,
  broadcast,
  workgroupApproval,
  group,
  private,
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
    this.showAiMark = false,
    this.showOnlineDot = false,
    this.avatarInitial,
    this.avatarSeed = 0,
    this.avatarPreset,
    this.avatarObjectKey,
    this.avatarService,
    this.sysTag,
    this.showDivider = true,
    this.previewGenerating = false,
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
  final bool showAiMark;
  final bool showOnlineDot;
  final String? avatarInitial;
  final int avatarSeed;
  final String? avatarPreset;
  final String? avatarObjectKey;
  final ConversationService? avatarService;
  final String? sysTag;
  final bool showDivider;
  final bool previewGenerating;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: DunesColors.bgApp,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: OverflowBox(
                      alignment: Alignment.center,
                      maxWidth: 50,
                      maxHeight: 50,
                      child: _Avatar(
                        kind: kind,
                        initial: avatarInitial,
                        seed: avatarSeed,
                        showOnlineDot: showOnlineDot,
                        avatarPreset: avatarPreset,
                        avatarObjectKey: avatarObjectKey,
                        avatarService: avatarService,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
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
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: -0.01 * 13.5,
                                        color: DunesColors.text,
                                      ),
                                    ),
                                  ),
                                  if (showAiMark) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
                                  if (memberCount != null && memberCount! > 0) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      '($memberCount)',
                                      style: DunesTypography.sans(
                                        fontSize: 11,
                                        color: DunesColors.text3,
                                      ),
                                    ),
                                  ],
                                  if (subtitle != null && subtitle!.isNotEmpty) ...[
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
                  if (unreadCount > 0 || muted)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (muted)
                            const Icon(Icons.notifications_off_outlined, size: 14, color: DunesColors.text3),
                          if (unreadCount > 0)
                            _UnreadBadge(
                              text: unreadCount > 99 ? '99+' : '$unreadCount',
                              color: kind == ChatInboxRowKind.private ||
                                      kind == ChatInboxRowKind.aiAssistant
                                  ? const Color(0xFF7B5CD8)
                                  : DunesColors.coral,
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
          const Padding(
            padding: EdgeInsets.only(left: 71, right: 16),
            child: Divider(height: 1, thickness: 1, color: DunesColors.borderSoft),
          ),
      ],
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isSingle = text.length == 1;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: BoxConstraints(
        minWidth: isSingle ? 24 : 26,
        minHeight: 24,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isSingle ? 0 : 8,
        vertical: 0,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.22),
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: DunesTypography.sans(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.02 * 11,
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
              style: DunesTypography.sans(fontSize: 12.5, color: DunesColors.text3),
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
            style: DunesTypography.sans(fontSize: 12.5, color: DunesColors.text3),
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
    this.avatarService,
  });

  final ChatInboxRowKind kind;
  final String? initial;
  final int seed;
  final bool showOnlineDot;
  final String? avatarPreset;
  final String? avatarObjectKey;
  final ConversationService? avatarService;

  @override
  Widget build(BuildContext context) {
    final borderRadius = kind == ChatInboxRowKind.private
        ? BorderRadius.circular(22)
        : BorderRadius.circular(12);

    BoxDecoration decoration;
    Widget child;

    switch (kind) {
      case ChatInboxRowKind.aiAssistant:
        return const NovaIconImage(size: 44, borderRadius: 12);
      case ChatInboxRowKind.systemNotification:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: const LinearGradient(
            colors: [Color(0xFFC2AEE7), Color(0xFF9C82CE)],
          ),
        );
        child = const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 17);
      case ChatInboxRowKind.broadcast:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: const LinearGradient(
            colors: [Color(0xFFD9C9F0), Color(0xFFB89FE2)],
          ),
        );
        child = const Icon(Icons.campaign_outlined, color: Colors.white, size: 17);
      case ChatInboxRowKind.workgroupApproval:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: const LinearGradient(
            colors: [Color(0xFF9079C2), Color(0xFF6A4FA0)],
          ),
        );
        child = const Icon(Icons.assignment_outlined, color: Colors.white, size: 17);
      case ChatInboxRowKind.group:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: const LinearGradient(
            colors: [Color(0xFFCABCEB), Color(0xFFA88CD8)],
          ),
        );
        child = const Icon(Icons.groups_outlined, color: Colors.white, size: 17);
      case ChatInboxRowKind.private:
        final letter = (initial == null || initial!.isEmpty) ? '?' : initial!;
        if (avatarService != null ||
            (avatarPreset != null && avatarPreset!.isNotEmpty) ||
            (avatarObjectKey != null && avatarObjectKey!.isNotEmpty)) {
          return ImUserAvatar(
            initial: letter,
            seed: seed,
            size: 44,
            showOnline: showOnlineDot,
            avatarPreset: avatarPreset,
            avatarObjectKey: avatarObjectKey,
            avatarService: avatarService,
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
          width: 44,
          height: 44,
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
  const _IconBtn({required this.icon, required this.onTap});

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
          width: 34,
          height: 34,
          child: Icon(icon, size: 16, color: DunesColors.text2),
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
