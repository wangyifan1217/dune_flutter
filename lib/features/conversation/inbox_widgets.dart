import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/widgets/desktop_feedback_surface.dart';
import '../../core/widgets/desktop_entrance.dart';
import '../ai_summary/ai_summary_sparkle_icon.dart';
import '../chat/group_composite_avatar.dart';
import '../chat/im_ui_kit.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../nova/nova_icon.dart';
import '../nova/presence/nova_presence_host.dart';
import 'im_user_status.dart';
import 'inbox_format.dart';
import '../desktop/desktop_popover_dismissals.dart';
import '../meeting/meeting_live_controller.dart';

class ChatInboxHeader extends StatelessWidget {
  const ChatInboxHeader({
    super.key,
    required this.onOpenContacts,
    this.onNewChat,
    this.onOpenNova,
    this.onOpenAiSummary,
    this.onOpenDailyReport,
    this.onOpenFavorites,
    this.onSelectImStatus,
    this.selfImStatus = ImUserStatusValue.online,
    this.novaThinking = false,
    this.novaUnread = false,
    this.showNovaLeading = true,
    this.onQuickMeeting,
  });

  /// 左上角「快速开会」：点一下直接开始录音；已在会议中则回到会议页。
  final VoidCallback? onQuickMeeting;

  final VoidCallback onOpenContacts;
  final VoidCallback? onNewChat;

  /// 外部用户不开放 Nova，传 null 时左上角入口不展示。
  final VoidCallback? onOpenNova;
  final VoidCallback? onOpenAiSummary;
  final VoidCallback? onOpenDailyReport;
  final VoidCallback? onOpenFavorites;
  final ValueChanged<ImUserStatusValue>? onSelectImStatus;
  final ImUserStatusValue selfImStatus;
  final bool novaThinking;
  final bool novaUnread;
  final bool showNovaLeading;

  @override
  Widget build(BuildContext context) {
    if (isDesktopCommOnly) {
      return Container(
        constraints: BoxConstraints(
          minHeight:
              68 +
              (MediaQuery.textScalerOf(context).scale(16) - 16).clamp(0, 24),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        child: Row(
          children: [
            if (showNovaLeading && onOpenNova != null) ...[
              Tooltip(
                message: novaThinking ? '小饕正在思考' : '打开小饕',
                child: _NovaEyesButton(onTap: onOpenNova!, unread: novaUnread),
              ),
              const SizedBox(width: 8),
            ] else if (onQuickMeeting != null) ...[
              _QuickMeetingButton(onTap: onQuickMeeting!),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '消息',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.resolve(context, DunesColors.text),
                      context: context,
                    ),
                  ),
                  if (novaThinking)
                    Text(
                      '小饕正在思考',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DunesTypography.sans(
                        fontSize: 10.5,
                        color: DunesColors.resolve(
                          context,
                          const Color(0xFF07A957),
                        ),
                        context: context,
                      ),
                    ),
                ],
              ),
            ),
            _InboxHeaderActions(
              onOpenContacts: onOpenContacts,
              onNewChat: onNewChat,
              onOpenAiSummary: onOpenAiSummary,
              onOpenDailyReport: onOpenDailyReport,
              onOpenFavorites: onOpenFavorites,
              onSelectImStatus: onSelectImStatus,
              selfImStatus: selfImStatus,
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
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
                color: DunesColors.resolve(
                  context,
                  const Color(0xFF1C1C1C),
                ),
                context: context,
              ),
            ),
            if (showNovaLeading && onOpenNova != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NovaEyesButton(onTap: onOpenNova!, unread: novaUnread),
                    if (novaThinking)
                      Text(
                        '正在思考',
                        style: DunesTypography.sans(
                          fontSize: 10.5,
                          color: DunesColors.resolve(
                            context,
                            const Color(0xFF07A957),
                          ),
                          context: context,
                        ),
                      ),
                  ],
                ),
              )
            else if (onQuickMeeting != null)
              Align(
                alignment: Alignment.centerLeft,
                child: _QuickMeetingButton(onTap: onQuickMeeting!),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: _InboxHeaderActions(
                onOpenContacts: onOpenContacts,
                onNewChat: onNewChat,
                onOpenAiSummary: onOpenAiSummary,
                onOpenDailyReport: onOpenDailyReport,
                onOpenFavorites: onOpenFavorites,
                onSelectImStatus: onSelectImStatus,
                selfImStatus: selfImStatus,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 消息页左上角的「快速开会 / 会议纪要」入口。
/// APP 端为纯图标圆钮，录音中带声纹律动与脉冲光环，暂停时带琥珀呼吸环；PC 端保留原胶囊。
class _QuickMeetingButton extends StatelessWidget {
  const _QuickMeetingButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final controller = MeetingLiveController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.active,
        controller.paused,
        controller.recovering,
        controller.saveFailed,
      ]),
      builder: (context, _) {
        final live = controller.active.value;
        final paused = controller.paused.value;
        final failed = controller.saveFailed.value;
        final recovering = controller.recovering.value;

        if (!isDesktopCommOnly) {
          final isRecording = live && !paused && !failed;
          final isPaused = live && (paused || failed);
          final semanticsLabel = isRecording
              ? '会议录音中，点击回到会议'
              : isPaused
              ? '会议录音已暂停，点击处理'
              : '会议纪要';
          final gradientColors = isRecording
              ? const [Color(0xFFFF6B6B), Color(0xFFE04848)]
              : isPaused
              ? const [Color(0xFFFFC25C), Color(0xFFE08E26)]
              : const [Color(0xFF9D84EC), Color(0xFF6E52CC)];
          final ringColor = isRecording
              ? const Color(0xFFFF5B61)
              : isPaused
              ? const Color(0xFFFFB340)
              : const Color(0xFF7B5CD8);

          return Semantics(
            button: true,
            label: semanticsLabel,
            child: Tooltip(
              message: semanticsLabel,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('inbox-quick-meeting'),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        if (live)
                          _MeetingIconPulseRing(
                            color: ringColor,
                            paused: isPaused,
                          ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: gradientColors,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: ringColor.withValues(
                                  alpha: live ? 0.36 : 0.24,
                                ),
                                blurRadius: live ? 10 : 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: recovering
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: Colors.white,
                                  ),
                                )
                              : isRecording
                              ? const _MiniMeetingWaveIcon()
                              : Icon(
                                  isPaused
                                      ? Icons.pause_rounded
                                      : Icons.mic_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                        ),
                        if (live)
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isPaused
                                    ? const Color(0xFFFFB340)
                                    : const Color(0xFFFF3B30),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? const Color(0xFF1A1924)
                                      : Colors.white,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final fg = live
            ? DunesColors.resolve(context, const Color(0xFFBC5C40))
            : DunesColors.resolve(context, const Color(0xFF7B5CD8));
        return Semantics(
          button: true,
          label: live ? '回到进行中的会议' : '快速开会',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('inbox-quick-meeting'),
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              borderRadius: BorderRadius.circular(999),
              child: Ink(
                height: 30,
                padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: live
                              ? [
                                  DunesColors.resolve(
                                    context,
                                    Color(0xFFE07A5F),
                                    role: DunesColorRole.surface,
                                  ),
                                  DunesColors.resolve(
                                    context,
                                    Color(0xFFBC5C40),
                                    role: DunesColorRole.surface,
                                  ),
                                ]
                              : [
                                  DunesColors.resolve(
                                    context,
                                    Color(0xFF9D84EC),
                                    role: DunesColorRole.surface,
                                  ),
                                  DunesColors.resolve(
                                    context,
                                    Color(0xFF6E52CC),
                                    role: DunesColorRole.surface,
                                  ),
                                ],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        live ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                        size: 13,
                        color: DunesColors.resolve(context, Colors.white),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      live ? '会议中' : '快速开会',
                      style: DunesTypography.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fg,
                        context: context,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 录音中向外扩散的柔和脉冲光环；暂停时变为缓慢呼吸光圈（仅在录音活跃时挂载）。
class _MeetingIconPulseRing extends StatefulWidget {
  const _MeetingIconPulseRing({required this.color, required this.paused});

  final Color color;
  final bool paused;

  @override
  State<_MeetingIconPulseRing> createState() => _MeetingIconPulseRingState();
}

class _MeetingIconPulseRingState extends State<_MeetingIconPulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.paused ? 1800 : 1250),
  )..repeat(reverse: widget.paused);

  @override
  void didUpdateWidget(covariant _MeetingIconPulseRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paused != widget.paused) {
      _ctrl.duration = Duration(milliseconds: widget.paused ? 1800 : 1250);
      _ctrl
        ..reset()
        ..repeat(reverse: widget.paused);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.color.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_ctrl.value);
        if (widget.paused) {
          return Container(
            width: 34 + t * 4,
            height: 34 + t * 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.color.withValues(alpha: 0.28 + t * 0.34),
                width: 1.6,
              ),
            ),
          );
        }
        return Opacity(
          opacity: (1.0 - t).clamp(0.0, 1.0) * 0.65,
          child: Transform.scale(
            scale: 0.92 + t * 0.46,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: widget.color, width: 2.0),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 录音图标内部 3 柱迷你声纹律动（仅录音活跃时挂载，暂停/结束自动销毁）。
class _MiniMeetingWaveIcon extends StatefulWidget {
  const _MiniMeetingWaveIcon();

  @override
  State<_MiniMeetingWaveIcon> createState() => _MiniMeetingWaveIconState();
}

class _MiniMeetingWaveIconState extends State<_MiniMeetingWaveIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const Icon(Icons.graphic_eq_rounded, size: 16, color: Colors.white);
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final h1 = 5.5 + 7.5 * ((t + 0.15) % 1.0);
        final h2 = 7.0 + 8.5 * (1.0 - t);
        final h3 = 5.5 + 7.0 * ((t + 0.55) % 1.0);
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final h in [h1, h2, h3])
              Container(
                width: 2.4,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 1.1),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// PC / 宽屏：右侧收成「···」，点开后在下方浮层展开；手机仍平铺。
class _InboxHeaderActions extends StatefulWidget {
  const _InboxHeaderActions({
    required this.onOpenContacts,
    this.onNewChat,
    this.onOpenAiSummary,
    this.onOpenDailyReport,
    this.onOpenFavorites,
    this.onSelectImStatus,
    this.selfImStatus = ImUserStatusValue.online,
  });

  final VoidCallback onOpenContacts;
  final VoidCallback? onNewChat;
  final VoidCallback? onOpenAiSummary;
  final VoidCallback? onOpenDailyReport;
  final VoidCallback? onOpenFavorites;
  final ValueChanged<ImUserStatusValue>? onSelectImStatus;
  final ImUserStatusValue selfImStatus;

  @override
  State<_InboxHeaderActions> createState() => _InboxHeaderActionsState();
}

class _InboxHeaderActionsState extends State<_InboxHeaderActions> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlay;
  bool _expanded = false;
  final _triggerFocus = FocusNode(debugLabel: 'Inbox menu trigger');
  final _menuFocus = FocusScopeNode(debugLabel: 'Inbox menu');

  /// APP / PC 统一用「···」下拉，避免手机右上角图标挤在一起。
  bool get _useCluster => true;

  @override
  void dispose() {
    _removeOverlay(restoreFocus: false, updateState: false);
    _menuFocus.dispose();
    _triggerFocus.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_expanded) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _removeOverlay({bool restoreFocus = true, bool updateState = true}) {
    DesktopPopoverDismissals.remove(_dismissWithEscape);
    _overlay?.remove();
    _overlay = null;
    if (_expanded && mounted && updateState) {
      setState(() => _expanded = false);
    } else {
      _expanded = false;
    }
    if (restoreFocus && isDesktopCommOnly && _triggerFocus.context != null) {
      _triggerFocus.requestFocus();
    }
  }

  void _dismissWithEscape() => _removeOverlay();

  Widget _focusMenu(Widget child) => isDesktopCommOnly
      ? FocusScope(node: _menuFocus, autofocus: true, child: child)
      : child;

  void _runAndClose(VoidCallback action) {
    _removeOverlay(restoreFocus: false);
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
              child: _focusMenu(
                _InboxActionsDropdown(
                  showAiSummary: widget.onOpenAiSummary != null,
                  showDailyReport: widget.onOpenDailyReport != null,
                  showNewChat: widget.onNewChat != null,
                  showFavorites: widget.onOpenFavorites != null,
                  showSetStatus: widget.onSelectImStatus != null,
                  selfImStatus: widget.selfImStatus,
                  onAiSummary: widget.onOpenAiSummary == null
                      ? null
                      : () => _runAndClose(widget.onOpenAiSummary!),
                  onDailyReport: widget.onOpenDailyReport == null
                      ? null
                      : () => _runAndClose(widget.onOpenDailyReport!),
                  onContacts: () => _runAndClose(widget.onOpenContacts),
                  onNewChat: widget.onNewChat == null
                      ? null
                      : () => _runAndClose(widget.onNewChat!),
                  onFavorites: widget.onOpenFavorites == null
                      ? null
                      : () => _runAndClose(widget.onOpenFavorites!),
                  onSetStatus: widget.onSelectImStatus == null
                      ? null
                      : _openStatusPicker,
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlay!);
    if (isDesktopCommOnly) DesktopPopoverDismissals.add(_dismissWithEscape);
    setState(() => _expanded = true);
  }

  void _openStatusPicker() {
    _removeOverlay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showStatusOverlay();
    });
  }

  void _showStatusOverlay() {
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
              child: _focusMenu(
                _InboxStatusPicker(
                  currentStatus: widget.selfImStatus,
                  onSelect: (status) {
                    _removeOverlay();
                    widget.onSelectImStatus?.call(status);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlay!);
    if (isDesktopCommOnly) DesktopPopoverDismissals.add(_dismissWithEscape);
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
            tooltip: '联系人',
            onTap: widget.onOpenContacts,
          ),
          if (widget.onNewChat != null)
            _IconBtn(
              icon: Icons.edit_outlined,
              tooltip: '新建会话',
              onTap: widget.onNewChat!,
            ),
        ],
      );
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: _IconBtn(
        icon: _expanded ? Icons.close_rounded : Icons.more_horiz_rounded,
        tooltip: _expanded ? '关闭菜单' : '更多操作',
        focusNode: isDesktopCommOnly ? _triggerFocus : null,
        onTap: _toggle,
      ),
    );
  }
}

class _InboxActionsDropdown extends StatelessWidget {
  const _InboxActionsDropdown({
    required this.showAiSummary,
    required this.showDailyReport,
    required this.showNewChat,
    required this.showFavorites,
    required this.onContacts,
    this.showSetStatus = false,
    this.selfImStatus = ImUserStatusValue.online,
    this.onAiSummary,
    this.onDailyReport,
    this.onNewChat,
    this.onFavorites,
    this.onSetStatus,
  });

  final bool showAiSummary;
  final bool showDailyReport;
  final bool showNewChat;
  final bool showFavorites;
  final bool showSetStatus;
  final ImUserStatusValue selfImStatus;
  final VoidCallback? onAiSummary;
  final VoidCallback? onDailyReport;
  final VoidCallback onContacts;
  final VoidCallback? onNewChat;
  final VoidCallback? onFavorites;
  final VoidCallback? onSetStatus;

  @override
  Widget build(BuildContext context) {
    final statusDef = selfImStatus.def;
    return _InboxMenuCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showSetStatus && onSetStatus != null)
            _DropdownItem(
              leading: Icon(
                statusDef.icon,
                size: 20,
                color: DunesColors.resolveNullable(context, statusDef.color),
              ),
              label: '设置状态',
              trailing: selfImStatus.showsBadge
                  ? Text(
                      statusDef.label,
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: DunesColors.resolve(
                          context,
                          const Color(0xFF9CA3AF),
                        ),
                        context: context,
                      ),
                    )
                  : null,
              onTap: onSetStatus!,
            ),
          if (showNewChat && onNewChat != null)
            _DropdownItem(
              leading: Icon(
                Icons.group_add_outlined,
                size: 20,
                color: DunesColors.resolveNullable(context, Color(0xFF4B5563)),
              ),
              label: '发起群聊',
              onTap: onNewChat!,
            ),
          _DropdownItem(
            leading: Icon(
              Icons.people_outline_rounded,
              size: 20,
              color: DunesColors.resolveNullable(context, Color(0xFF4B5563)),
            ),
            label: '通讯录',
            onTap: onContacts,
          ),
          if (showDailyReport && onDailyReport != null)
            _DropdownItem(
              leading: Icon(
                Icons.edit_note_outlined,
                size: 20,
                color: DunesColors.resolveNullable(context, Color(0xFF4B5563)),
              ),
              label: '填写日报',
              onTap: onDailyReport!,
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
              leading: Icon(
                Icons.bookmark_border_rounded,
                size: 20,
                color: DunesColors.resolveNullable(context, Color(0xFF4B5563)),
              ),
              label: '我的收藏',
              onTap: onFavorites!,
            ),
        ],
      ),
    );
  }
}

class _InboxStatusPicker extends StatefulWidget {
  const _InboxStatusPicker({
    required this.currentStatus,
    required this.onSelect,
  });

  final ImUserStatusValue currentStatus;
  final ValueChanged<ImUserStatusValue> onSelect;

  @override
  State<_InboxStatusPicker> createState() => _InboxStatusPickerState();
}

class _InboxStatusPickerState extends State<_InboxStatusPicker> {
  bool _customizing = false;
  late String _customIcon;
  late String _customColor;
  late final TextEditingController _textCtrl;

  @override
  void initState() {
    super.initState();
    final current = widget.currentStatus;
    _customIcon = current.icon.isNotEmpty
        ? current.icon
        : ImUserStatusCatalog.customIcons.first;
    _customColor = ImUserStatusCatalog.normalizeColor(current.color).isNotEmpty
        ? ImUserStatusCatalog.normalizeColor(current.color)
        : ImUserStatusCatalog.customColors[4];
    _textCtrl = TextEditingController(
      text: current.key == ImUserStatusCatalog.custom ? current.text : '',
    );
    _textCtrl.addListener(_onCustomTextChanged);
  }

  void _onCustomTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _textCtrl.removeListener(_onCustomTextChanged);
    _textCtrl.dispose();
    super.dispose();
  }

  String _committedCustomText() {
    final value = _textCtrl.value;
    var text = value.text;
    if (value.composing.isValid && !value.composing.isCollapsed) {
      text = text.replaceRange(value.composing.start, value.composing.end, '');
    }
    return text.replaceAll('\n', '');
  }

  bool get _isComposing {
    final composing = _textCtrl.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  void _submitCustom() {
    final text = ImUserStatusCatalog.clampText(_committedCustomText());
    final icon = ImUserStatusCatalog.normalizeIcon(_customIcon);
    final color = ImUserStatusCatalog.normalizeColor(_customColor);
    if (text.isEmpty || icon.isEmpty) return;
    widget.onSelect(
      ImUserStatusValue(
        key: ImUserStatusCatalog.custom,
        text: text,
        icon: icon,
        color: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _InboxMenuCard(
      child: SizedBox(
        width: 260,
        child: _customizing ? _buildCustomEditor() : _buildPresetList(),
      ),
    );
  }

  Widget _buildPresetList() {
    final current = widget.currentStatus;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (current.showsBadge)
          _DropdownItem(
            leading: Icon(
              Icons.remove_circle_outline,
              size: 20,
              color: DunesColors.resolveNullable(context, Color(0xFF6B7280)),
            ),
            label: '取消状态',
            onTap: () => widget.onSelect(ImUserStatusValue.online),
          ),
        for (final item in ImUserStatusCatalog.all)
          _DropdownItem(
            leading: Icon(
              item.icon,
              size: 20,
              color: DunesColors.resolveNullable(context, item.color),
            ),
            label: item.label,
            trailing: item.key == current.key
                ? Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: DunesColors.resolveNullable(
                      context,
                      Color(0xFF07A957),
                    ),
                  )
                : null,
            onTap: () => widget.onSelect(ImUserStatusValue(key: item.key)),
          ),
        _DropdownItem(
          leading: Icon(
            current.key == ImUserStatusCatalog.custom
                ? current.def.icon
                : Icons.edit_outlined,
            size: 20,
            color: current.key == ImUserStatusCatalog.custom
                ? current.def.color
                : DunesColors.resolve(context, DunesColors.brandPurple),
          ),
          label: current.key == ImUserStatusCatalog.custom
              ? current.def.label
              : '自定义',
          trailing: current.key == ImUserStatusCatalog.custom
              ? Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: DunesColors.resolveNullable(
                    context,
                    Color(0xFF07A957),
                  ),
                )
              : Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: DunesColors.resolveNullable(
                    context,
                    Color(0xFF9CA3AF),
                  ),
                ),
          onTap: () => setState(() => _customizing = true),
        ),
      ],
    );
  }

  Widget _buildCustomEditor() {
    final committed = _committedCustomText();
    final committedCount = committed.characters.length;
    final canSubmit =
        !_isComposing &&
        ImUserStatusCatalog.clampText(committed).isNotEmpty &&
        _customIcon.isNotEmpty;
    final iconColor =
        ImUserStatusCatalog.colorOf(_customColor) ??
        DunesColors.resolve(context, DunesColors.brandPurple);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _customizing = false),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: DunesColors.resolveNullable(
                      context,
                      Color(0xFF4B5563),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '自定义状态',
                    style: DunesTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.resolve(
                        context,
                        const Color(0xFF1C1C1C),
                      ),
                      context: context,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final key in ImUserStatusCatalog.customIcons)
                _StatusIconChip(
                  iconKey: key,
                  selected: _customIcon == key,
                  color: iconColor,
                  onTap: () => setState(() => _customIcon = key),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final hex in ImUserStatusCatalog.customColors)
                _StatusColorChip(
                  color: ImUserStatusCatalog.colorOf(hex)!,
                  selected: _customColor == hex,
                  onTap: () => setState(() => _customColor = hex),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _textCtrl,
            autofocus: true,
            maxLength: ImUserStatusCatalog.textMaxChars,
            maxLengthEnforcement:
                MaxLengthEnforcement.truncateAfterCompositionEnds,
            decoration: InputDecoration(
              hintText: '最多${ImUserStatusCatalog.textMaxChars}个字',
              isDense: true,
              counterText:
                  '$committedCount/${ImUserStatusCatalog.textMaxChars}',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: DunesColors.resolve(
                    context,
                    Color(0xFFE5E7EB),
                    role: DunesColorRole.border,
                  ),
                ),
              ),
            ),
            style: DunesTypography.sans(
              fontSize: 14,
              color: DunesColors.resolve(context, DunesColors.text),
              context: context,
            ),
            onSubmitted: (_) {
              if (canSubmit) _submitCustom();
            },
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: canSubmit ? _submitCustom : null,
            style: FilledButton.styleFrom(
              backgroundColor: DunesColors.resolve(
                context,
                DunesColors.brandPurple,
                role: DunesColorRole.surface,
              ),
              disabledBackgroundColor: DunesColors.resolve(
                context,
                const Color(0xFFE5E7EB),
                role: DunesColorRole.surface,
              ),
              minimumSize: const Size.fromHeight(36),
            ),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}

class _StatusIconChip extends StatelessWidget {
  const _StatusIconChip({
    required this.iconKey,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String iconKey;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = ImUserStatusCatalog.iconData[iconKey];
    if (icon == null) return const SizedBox.shrink();
    return Material(
      color: selected
          ? color.withValues(alpha: 0.14)
          : DunesColors.resolve(
              context,
              DunesColors.bgSoft,
              role: DunesColorRole.surface,
            ),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            icon,
            size: 18,
            color: DunesColors.resolveNullable(
              context,
              selected ? color : color.withValues(alpha: 0.72),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusColorChip extends StatelessWidget {
  const _StatusColorChip({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: DunesColors.resolveNullable(
              context,
              color,
              role: DunesColorRole.surface,
            ),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? DunesColors.resolve(
                      context,
                      const Color(0xFF111827),
                      role: DunesColorRole.border,
                    )
                  : DunesColors.resolve(
                      context,
                      Colors.white,
                      role: DunesColorRole.border,
                    ),
              width: selected ? 2 : 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxMenuCard extends StatelessWidget {
  const _InboxMenuCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DesktopEntrance(
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              Colors.white,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x28000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: DunesColors.resolve(
                context,
                const Color(0xFFECECEC),
                role: DunesColorRole.border,
              ),
            ),
          ),
          child: IntrinsicWidth(child: child),
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
    this.trailing,
  });

  final Widget leading;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

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
                  color: DunesColors.resolve(context, const Color(0xFF1C1C1C)),
                  context: context,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

class ChatInboxSearchBar extends StatefulWidget {
  const ChatInboxSearchBar({
    super.key,
    this.controller,
    this.onChanged,
    this.onTap,
    this.hintText,
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final String? hintText;

  @override
  State<ChatInboxSearchBar> createState() => _ChatInboxSearchBarState();
}

class _ChatInboxSearchBarState extends State<ChatInboxSearchBar> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'InboxSearchBar');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!mounted) return;
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hint =
        widget.hintText ?? (widget.onTap != null ? '搜索' : '搜索会话或联系人');
    final accent = ImVisualTokens.accent(context);
    final mutedIconColor = DunesColors.resolve(
      context,
      isDesktopCommOnly ? const Color(0xFF8A8894) : const Color(0xFFA8A4B3),
    );
    // 与顶栏动画隔离，避免 Web 合成层把搜索栏一起带动。
    return RepaintBoundary(
      child: Container(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        padding: isDesktopCommOnly
            ? const EdgeInsets.fromLTRB(12, 4, 12, 10)
            : const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: _InboxSearchChrome(
          focused: _focused,
          child: widget.onTap != null
              ? _InboxSearchTapTarget(hint: hint, onTap: widget.onTap!)
              : Row(
                  children: [
                    AnimatedScale(
                      scale: _focused ? 1.06 : 1.0,
                      duration: ImVisualTokens.fastAnim,
                      curve: ImVisualTokens.iosCurve,
                      child: Icon(
                        Icons.search_rounded,
                        size: 17,
                        color: _focused ? accent : mutedIconColor,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _focusNode,
                        onChanged: widget.onChanged,
                        style: DunesTypography.sans(
                          fontSize: 13.5,
                          color: DunesColors.resolve(context, DunesColors.text),
                          context: context,
                        ),
                        textInputAction: TextInputAction.search,
                        cursorColor: accent,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          filled: false,
                          hintText: hint,
                          hintStyle: DunesTypography.sans(
                            fontSize: 13,
                            color: mutedIconColor,
                            context: context,
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (widget.controller != null)
                      ListenableBuilder(
                        listenable: widget.controller!,
                        builder: (context, _) {
                          final empty = widget.controller!.text.isEmpty;
                          return AnimatedSwitcher(
                            duration: ImVisualTokens.fastAnim,
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: ScaleTransition(scale: anim, child: child),
                            ),
                            child: empty
                                ? const SizedBox.shrink(
                                    key: ValueKey('clear-empty'),
                                  )
                                : IconButton(
                                    key: const ValueKey('clear-btn'),
                                    tooltip: '清除',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    iconSize: 15,
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      widget.controller!.clear();
                                      widget.onChanged?.call('');
                                    },
                                    icon: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: ImVisualTokens.isDark(context)
                                            ? Colors.white.withValues(
                                                alpha: 0.14,
                                              )
                                            : const Color(0xFFDAD6E4),
                                      ),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 12,
                                        color: ImVisualTokens.isDark(context)
                                            ? Colors.white70
                                            : Colors.white,
                                      ),
                                    ),
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

class _InboxSearchChrome extends StatefulWidget {
  const _InboxSearchChrome({required this.child, this.focused = false});
  final Widget child;
  final bool focused;
  @override
  State<_InboxSearchChrome> createState() => _InboxSearchChromeState();
}

class _InboxSearchChromeState extends State<_InboxSearchChrome> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final dark = ImVisualTokens.isDark(context);
    final activeFocus = widget.focused || _focused;
    final accent = ImVisualTokens.accent(context);
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    if (!isDesktopCommOnly) {
      return AnimatedContainer(
        duration: disableAnim ? Duration.zero : ImVisualTokens.fastAnim,
        curve: ImVisualTokens.iosCurve,
        alignment: Alignment.center,
        height:
            38 +
            (MediaQuery.textScalerOf(context).scale(13) - 13).clamp(0.0, 18.0),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: activeFocus
              ? (dark ? const Color(0xFF282538) : Colors.white)
              : (dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFF3F1F8)),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: activeFocus
                ? accent.withValues(alpha: 0.52)
                : (dark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFEAE6F3)),
            width: activeFocus ? 1.1 : 0.7,
          ),
          boxShadow: activeFocus
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.12),
                    blurRadius: 12,
                    spreadRadius: -2,
                    offset: const Offset(0, 3),
                  ),
                ]
              : const [],
        ),
        child: widget.child,
      );
    }
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: disableAnim ? Duration.zero : ImVisualTokens.fastAnim,
          curve: ImVisualTokens.iosCurve,
          alignment: Alignment.center,
          height:
              36 +
              (MediaQuery.textScalerOf(context).scale(13) - 13).clamp(
                0.0,
                20.0,
              ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: activeFocus
                ? (dark ? const Color(0xFF2A273B) : Colors.white)
                : _hovered
                ? (dark
                      ? Colors.white.withValues(alpha: 0.11)
                      : const Color(0xFFECEAF4))
                : (dark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFF3F2F7)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: activeFocus
                  ? accent.withValues(alpha: .58)
                  : (_hovered
                        ? accent.withValues(alpha: .20)
                        : Colors.transparent),
            ),
            boxShadow: activeFocus
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: .12),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _InboxSearchTapTarget extends StatelessWidget {
  const _InboxSearchTapTarget({required this.hint, required this.onTap});

  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mutedColor = DunesColors.resolve(
      context,
      isDesktopCommOnly ? const Color(0xFF8A8894) : const Color(0xFFA8A4B3),
    );
    return ImTapScale(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(18),
      pressedScale: 0.985,
      enableHoverTint: false,
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.search_rounded,
              size: isDesktopCommOnly ? 16 : 17,
              color: mutedColor,
            ),
            SizedBox(width: isDesktopCommOnly ? 8 : 7),
            Expanded(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 13.5,
                  height: 1.2,
                  color: mutedColor,
                  context: context,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum ChatInboxFilter { all, unread, mention, group }

/// 移动端 IM 列表顶部分段筛选条（样式 1 · iOS 分段滑块）。
class ChatInboxSegmentedFilter extends StatelessWidget {
  const ChatInboxSegmentedFilter({
    super.key,
    required this.selected,
    required this.onSelected,
    this.unreadCount = 0,
    this.mentionCount = 0,
  });

  final ChatInboxFilter selected;
  final ValueChanged<ChatInboxFilter> onSelected;
  final int unreadCount;
  final int mentionCount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final extraHeight = (MediaQuery.textScalerOf(context).scale(12) - 12)
        .clamp(0.0, 14.0);
    final selectedIndex = ChatInboxFilter.values.indexOf(selected);
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : const Color(0xFFF2F1F6);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.055);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        border: Border(
          bottom: BorderSide(
            color: dividerColor,
            width: (1 / MediaQuery.devicePixelRatioOf(context)).clamp(0.33, 0.5),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Container(
          height: 32 + extraHeight,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segmentWidth =
                  constraints.maxWidth / ChatInboxFilter.values.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    left: segmentWidth * selectedIndex,
                    top: 0,
                    bottom: 0,
                    width: segmentWidth,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFFB69BFF).withValues(alpha: 0.22)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(7.5),
                          border: isDark
                              ? Border.all(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  width: 0.6,
                                )
                              : null,
                          boxShadow: isDark
                              ? const []
                              : const [
                                  BoxShadow(
                                    color: Color(0x14000000),
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      _segmentButton(
                        context,
                        filter: ChatInboxFilter.all,
                        label: '全部',
                        isDark: isDark,
                      ),
                      _segmentButton(
                        context,
                        filter: ChatInboxFilter.unread,
                        label: '未读',
                        count: unreadCount,
                        isDark: isDark,
                      ),
                      _segmentButton(
                        context,
                        filter: ChatInboxFilter.mention,
                        label: '@我',
                        count: mentionCount,
                        isDark: isDark,
                      ),
                      _segmentButton(
                        context,
                        filter: ChatInboxFilter.group,
                        label: '群聊',
                        isDark: isDark,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _segmentButton(
    BuildContext context, {
    required ChatInboxFilter filter,
    required String label,
    int count = 0,
    required bool isDark,
  }) {
    final active = selected == filter;
    final textColor = active
        ? (isDark ? const Color(0xFFDFD4FF) : DunesColors.text)
        : (isDark
              ? const Color(0xFFF1EFF8).withValues(alpha: 0.62)
              : DunesColors.text3);
    final badgeColor = active
        ? (isDark ? const Color(0xFFC5B0FF) : DunesColors.brandPurple)
        : (isDark
              ? const Color(0xFFF1EFF8).withValues(alpha: 0.50)
              : DunesColors.text3);
    final countText = count > 99 ? '99+' : '$count';

    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (!active) HapticFeedback.selectionClick();
            onSelected(filter);
          },
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: textColor,
                      context: context,
                    ),
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 3),
                  Text(
                    countText,
                    maxLines: 1,
                    style: DunesTypography.sans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: badgeColor,
                      context: context,
                    ),
                  ),
                ],
              ],
            ),
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
                  color: pinned
                      ? DunesColors.resolve(context, DunesColors.accent)
                      : DunesColors.resolve(context, DunesColors.text3),
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: DunesTypography.mono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.08 * 9.5,
                    color: DunesColors.resolve(context, DunesColors.text3),
                    context: context,
                  ),
                ),
              ),
              Text(
                '$count',
                style: DunesTypography.mono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.04 * 9.5,
                  color: DunesColors.resolve(context, DunesColors.text3),
                  context: context,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  collapsed
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                  size: 16,
                  color: DunesColors.resolve(context, DunesColors.text3),
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
  kpiAssistant,
  driveAssistant,
  xrxsAssistant,
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

/// 手动标为未读时显示小红点；已有未读条数时仍用数字角标。
bool chatInboxMarkedUnreadDot({
  required int unreadCount,
  required bool markedUnread,
}) => markedUnread && unreadCount <= 0;

const _desktopInboxAvatarSize = 42.0;

class ChatInboxRow extends StatelessWidget {
  const ChatInboxRow({
    super.key,
    required this.kind,
    required this.title,
    required this.preview,
    required this.timeLabel,
    required this.onTap,
    this.subtitle,
    this.unreadCount = 0,
    this.markedUnread = false,
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
    this.workgroupTag = false,
    this.robotAvatar,
    this.mentionLabel,
    this.imStatus,
    this.imStatusText,
    this.imStatusIcon,
    this.imStatusColor,
    this.onLongPress,
  });

  final ChatInboxRowKind kind;
  final String title;
  final String preview;
  final String timeLabel;
  final VoidCallback onTap;
  final String? subtitle;
  final int unreadCount;
  final bool markedUnread;
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

  /// 已读不回工作群（reply_sla）：标题旁石绿色「工作群」文字标签，不显示人数。
  final bool workgroupTag;
  final Widget? robotAvatar;

  /// 群聊未读 @ 提示，如 `[@了你]`，不受后续消息预览覆盖。
  final String? mentionLabel;

  /// 私聊对端自定义状态；空/在线不展示。
  final String? imStatus;
  final String? imStatusText;
  final String? imStatusIcon;
  final String? imStatusColor;
  final VoidCallback? onLongPress;

  Color _resolveRowBg(BuildContext context, {required bool desktop}) {
    if (desktop) {
      final light = selected
          ? DunesColors.accentSoft
          : pinned
          ? DunesColors.bgSoft
          : Colors.white;
      return DunesColors.resolve(context, light, role: DunesColorRole.surface);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (selected) {
      return DunesColors.resolve(
        context,
        DunesColors.accentSoft,
        role: DunesColorRole.surface,
      );
    }
    if (pinned) {
      // 不透明极浅紫底：既体现置顶层级，又不会透出底层左滑按钮。
      return isDark ? const Color(0xFF252437) : const Color(0xFFF6F4FC);
    }
    return DunesColors.resolve(
      context,
      Colors.white,
      role: DunesColorRole.surface,
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopCommOnly;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rowBg = _resolveRowBg(context, desktop: desktop);
    final avatarSlot = desktop ? _desktopInboxAvatarSize : 48.0;
    final avatarLimit = desktop ? avatarSlot : 48.0;
    final unreadText = unreadCount > 99 ? '99+' : '$unreadCount';
    final unreadColor =
        desktop ||
            kind == ChatInboxRowKind.private ||
            kind == ChatInboxRowKind.aiAssistant ||
            kind == ChatInboxRowKind.aiSummary ||
            kind == ChatInboxRowKind.approvalAssistant ||
            kind == ChatInboxRowKind.taskAssistant ||
            kind == ChatInboxRowKind.kpiAssistant ||
            kind == ChatInboxRowKind.driveAssistant ||
            kind == ChatInboxRowKind.xrxsAssistant ||
            kind == ChatInboxRowKind.weeklySummary ||
            kind == ChatInboxRowKind.reconciliationAssistant ||
            kind == ChatInboxRowKind.administrativeNotice ||
            kind == ChatInboxRowKind.duneAnnouncement ||
            kind == ChatInboxRowKind.selfMemo ||
            kind == ChatInboxRowKind.robot
        ? DunesColors.resolve(context, const Color(0xFF7B5CD8))
        : DunesColors.resolve(context, DunesColors.coral);
    final previewLine = _PreviewLine(
      preview: preview,
      sysTag: sysTag,
      generating: previewGenerating,
      mentionLabel: mentionLabel,
    );
    final hasUnread = unreadCount > 0 || markedUnread;
    final rowSurface = DesktopFeedbackSurface(
      onTap: onTap,
      selected: selected,
      showSelectionIndicator: false,
      visualInset: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      backgroundColor: rowBg,
      child: Padding(
        padding: desktop
            ? const EdgeInsets.fromLTRB(14, 9, 14, 9)
            : const EdgeInsets.fromLTRB(16, 11, 16, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: avatarSlot,
              height: avatarSlot,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  RepaintBoundary(
                    child: Center(
                      child: desktop
                          ? OverflowBox(
                              alignment: Alignment.center,
                              maxWidth: avatarLimit,
                              maxHeight: avatarLimit,
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
                            )
                          : (robotAvatar ??
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
                                )),
                    ),
                  ),
                  if (!desktop && unreadCount > 0)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: _UnreadBadge(
                        text: unreadText,
                        color: unreadColor,
                        mini: true,
                      ),
                    )
                  else if (chatInboxMarkedUnreadDot(
                    unreadCount: unreadCount,
                    markedUnread: markedUnread,
                  ))
                    const Positioned(
                      right: -1,
                      top: -1,
                      child: _MarkedUnreadDot(),
                    ),
                ],
              ),
            ),
            SizedBox(width: desktop ? 11 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, titleBox) => Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DunesTypography.sans(
                                    fontSize: desktop ? 14 : 15,
                                    fontWeight: desktop && (selected || hasUnread)
                                        ? FontWeight.w700
                                        : !desktop && hasUnread
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    letterSpacing: -0.01 * 15,
                                    color: DunesColors.resolve(
                                      context,
                                      DunesColors.text,
                                    ),
                                    context: context,
                                  ),
                                ),
                              ),
                              if (!desktop && pinned) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 11.5,
                                  color: DunesColors.resolve(
                                    context,
                                    DunesColors.brandPurple,
                                  ).withValues(alpha: 0.72),
                                ),
                              ],
                              if (workgroupTag) ...[
                                const SizedBox(width: 6),
                                const WorkgroupTag(),
                              ],
                              // 列表拖窄时名字优先：状态最多占近六成，再窄只留图标。
                              if (ImUserStatusCatalog.showsBadge(imStatus)) ...[
                                const SizedBox(width: 6),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: titleBox.maxWidth * 0.58,
                                  ),
                                  child: ImStatusBadge(
                                    status: imStatus!,
                                    text: imStatusText ?? '',
                                    iconKey: imStatusIcon ?? '',
                                    color: imStatusColor ?? '',
                                    iconOnly: titleBox.maxWidth < 150,
                                  ),
                                ),
                              ],
                              if (showAiMark) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: DunesColors.resolve(
                                      context,
                                      DunesColors.accent,
                                      role: DunesColorRole.surface,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    'AI',
                                    style: DunesTypography.mono(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w700,
                                      color: DunesColors.resolve(
                                        context,
                                        Colors.white,
                                      ),
                                      letterSpacing: 0.04 * 8.5,
                                      context: context,
                                    ),
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
                                    color: DunesColors.resolve(
                                      context,
                                      DunesColors.text3,
                                    ),
                                    context: context,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (timeLabel.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          timeLabel,
                          style: DunesTypography.sans(
                            fontSize: 11,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text3,
                            ),
                            context: context,
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: desktop ? 3 : 3.5),
                  if (desktop && unreadCount > 0)
                    Row(
                      children: [
                        Expanded(child: previewLine),
                        const SizedBox(width: 6),
                        _UnreadBadge(
                          text: unreadText,
                          color: unreadColor,
                          mini: true,
                        ),
                      ],
                    )
                  else if (!desktop && muted)
                    Row(
                      children: [
                        Expanded(child: previewLine),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 13.5,
                          color: DunesColors.resolve(
                            context,
                            DunesColors.text3,
                          ).withValues(alpha: 0.78),
                        ),
                      ],
                    )
                  else
                    previewLine,
                ],
              ),
            ),
            if (desktop && muted)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.notifications_off_outlined,
                      size: 14,
                      color: DunesColors.resolve(context, DunesColors.text3),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    return Column(
      children: [
        if (!desktop && onLongPress != null)
          GestureDetector(onLongPress: onLongPress, child: rowSurface)
        else
          rowSurface,
        if (showDivider)
          ColoredBox(
            color: desktop
                ? DunesColors.resolve(
                    context,
                    DunesColors.bgApp,
                    role: DunesColorRole.surface,
                  )
                : rowBg,
            child: Padding(
              padding: EdgeInsets.only(
                left: desktop ? 67 : 76,
                right: desktop ? 16 : 0,
              ),
              child: SizedBox(
                height: (1 / MediaQuery.devicePixelRatioOf(context))
                    .clamp(0.33, 0.5),
                width: double.infinity,
                child: ColoredBox(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: desktop ? 0.042 : 0.048),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MarkedUnreadDot extends StatelessWidget {
  const _MarkedUnreadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          const Color(0xFFFA5151),
          role: DunesColorRole.surface,
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.border,
          ),
          width: 1.5,
        ),
      ),
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
    final appMini = mini && !isDesktopCommOnly;
    return Container(
      margin: mini ? EdgeInsets.zero : const EdgeInsets.only(top: 4),
      constraints: BoxConstraints(
        minWidth: appMini
            ? (isSingle ? 18 : 22)
            : mini
            ? (isSingle ? 16 : 20)
            : (isSingle ? 24 : 26),
        minHeight: appMini ? 18 : (mini ? 16 : 24),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: mini ? (isSingle ? 0 : 5) : (isSingle ? 0 : 8),
        vertical: 0,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DunesColors.resolveNullable(
          context,
          color,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.border,
          ).withValues(alpha: 0.9),
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
          fontSize: appMini ? 10.5 : (mini ? 9 : 11),
          color: DunesColors.resolve(context, Colors.white),
          fontWeight: FontWeight.w700,
          letterSpacing: mini ? 0 : -0.02 * 11,
          height: 1,
          context: context,
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
    this.mentionLabel,
  });

  final String preview;
  final String? sysTag;
  final bool generating;
  final String? mentionLabel;

  @override
  Widget build(BuildContext context) {
    final previewSize = isDesktopCommOnly ? 12.5 : 13.5;
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
                fontSize: previewSize,
                color: DunesColors.resolve(context, DunesColors.text3),
                context: context,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    final mention = (mentionLabel ?? '').trim();
    final tag = (sysTag ?? '').trim();
    // 机器人会话的 businessType 存的是 robotKey（r_xxx）：给人看「机器人」，key 放悬停提示。
    final robotTag = tag.startsWith('r_');
    return Row(
      children: [
        if (mention.isNotEmpty) ...[
          Text(
            mention,
            style: DunesTypography.sans(
              fontSize: previewSize,
              fontWeight: FontWeight.w600,
              color: DunesColors.resolve(
                context,
                isDesktopCommOnly
                    ? DunesColors.brandPurpleDeep
                    : const Color(0xFFE4554D),
              ),
              context: context,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                if (robotTag)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Tooltip(
                      message: tag,
                      child: Container(
                        margin: const EdgeInsets.only(right: 5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: DunesColors.resolve(
                            context,
                            DunesColors.accentSoft,
                            role: DunesColorRole.surface,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '机器人',
                          style: DunesTypography.sans(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.accent,
                            ),
                            context: context,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (tag.isNotEmpty)
                  TextSpan(
                    text: '$tag ',
                    style: DunesTypography.mono(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.resolve(context, DunesColors.accent),
                      context: context,
                    ),
                  ),
                TextSpan(
                  text: preview.isEmpty ? '暂无消息' : preview,
                  style: DunesTypography.sans(
                    fontSize: previewSize,
                    color: DunesColors.resolve(context, DunesColors.text3),
                    context: context,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    final inboxAvatarSize = isDesktopCommOnly
        ? _desktopInboxAvatarSize
        : kImListAvatarSize;
    final inboxAvatarRadius = inboxAvatarSize * 0.18;
    final borderRadius = BorderRadius.circular(inboxAvatarRadius);

    BoxDecoration decoration;
    Widget child;

    switch (kind) {
      case ChatInboxRowKind.aiAssistant:
        return Container(
          width: inboxAvatarSize,
          height: inboxAvatarSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: DunesColors.resolve(
                context,
                const Color(0xFFEBF0FA),
                role: DunesColorRole.border,
              ),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1E7B5CD8),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipOval(
            child: NovaPersonAvatarImage(
              width: inboxAvatarSize,
              height: inboxAvatarSize,
            ),
          ),
        );
      case ChatInboxRowKind.approvalAssistant:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              DunesColors.resolve(
                context,
                DunesColors.brandPurple,
                role: DunesColorRole.surface,
              ),
              DunesColors.resolve(
                context,
                DunesColors.brandPurpleDeep,
                role: DunesColorRole.surface,
              ),
            ],
          ),
        );
        child = Icon(
          Icons.fact_check_outlined,
          color: DunesColors.resolve(context, Colors.white),
          size: 20,
        );
      case ChatInboxRowKind.taskAssistant:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              DunesColors.resolve(
                context,
                Color(0xFF2F8F7E),
                role: DunesColorRole.surface,
              ),
              DunesColors.resolve(
                context,
                Color(0xFF5EAEDE),
                role: DunesColorRole.surface,
              ),
            ],
          ),
        );
        child = Icon(
          Icons.assignment_turned_in_outlined,
          color: DunesColors.resolve(context, Colors.white),
          size: 20,
        );
      case ChatInboxRowKind.kpiAssistant:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              DunesColors.resolve(
                context,
                Color(0xFF8C5A91),
                role: DunesColorRole.surface,
              ),
              DunesColors.resolve(
                context,
                Color(0xFFC17B7B),
                role: DunesColorRole.surface,
              ),
            ],
          ),
        );
        child = Icon(
          Icons.insights_outlined,
          color: DunesColors.resolve(context, Colors.white),
          size: 20,
        );
      case ChatInboxRowKind.driveAssistant:
        decoration = BoxDecoration(
          color: DunesColors.resolve(
            context,
            const Color(0xFF3B82F6),
            role: DunesColorRole.surface,
          ),
          borderRadius: borderRadius,
        );
        child = Icon(
          Icons.cloud_outlined,
          color: DunesColors.resolve(context, Colors.white),
          size: 21,
        );
      case ChatInboxRowKind.xrxsAssistant:
        decoration = BoxDecoration(
          color: DunesColors.resolve(
            context,
            const Color(0xFF0F766E),
            role: DunesColorRole.surface,
          ),
          borderRadius: borderRadius,
        );
        child = Icon(
          Icons.badge_outlined,
          color: DunesColors.resolve(context, Colors.white),
          size: 21,
        );
      case ChatInboxRowKind.weeklySummary:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              DunesColors.resolve(
                context,
                Color(0xFFC4A574),
                role: DunesColorRole.surface,
              ),
              DunesColors.resolve(
                context,
                Color(0xFF8B6A3F),
                role: DunesColorRole.surface,
              ),
            ],
          ),
        );
        child = Icon(
          Icons.auto_stories_outlined,
          color: DunesColors.resolve(context, Colors.white),
          size: 20,
        );
      case ChatInboxRowKind.reconciliationAssistant:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              DunesColors.resolve(
                context,
                Color(0xFF5B6FC4),
                role: DunesColorRole.surface,
              ),
              DunesColors.resolve(
                context,
                Color(0xFF7652B8),
                role: DunesColorRole.surface,
              ),
            ],
          ),
        );
        child = Icon(
          Icons.sync_alt_rounded,
          color: DunesColors.resolve(context, Colors.white),
          size: 20,
        );
      case ChatInboxRowKind.administrativeNotice:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              DunesColors.resolve(
                context,
                Color(0xFF3D7A8C),
                role: DunesColorRole.surface,
              ),
              DunesColors.resolve(
                context,
                Color(0xFF5DA7A2),
                role: DunesColorRole.surface,
              ),
            ],
          ),
        );
        child = Icon(
          Icons.campaign_outlined,
          color: DunesColors.resolve(context, Colors.white),
          size: 20,
        );
      case ChatInboxRowKind.duneAnnouncement:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            colors: [
              DunesColors.resolve(
                context,
                Color(0xFFC2AEE7),
                role: DunesColorRole.surface,
              ),
              DunesColors.resolve(
                context,
                Color(0xFF9C82CE),
                role: DunesColorRole.surface,
              ),
            ],
          ),
        );
        child = Icon(
          Icons.campaign_outlined,
          color: DunesColors.resolve(context, Colors.white),
          size: 20,
        );
      case ChatInboxRowKind.selfMemo:
        decoration = BoxDecoration(
          color: DunesColors.resolve(
            context,
            const Color(0xFF7B5CD8),
            role: DunesColorRole.surface,
          ),
          borderRadius: borderRadius,
        );
        child = Icon(
          Icons.folder_copy_outlined,
          color: DunesColors.resolve(context, Colors.white),
          size: 21,
        );
      case ChatInboxRowKind.robot:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            colors: [
              DunesColors.resolve(
                context,
                Color(0xFFB8A4E8),
                role: DunesColorRole.surface,
              ),
              DunesColors.resolve(
                context,
                Color(0xFF7B5CD8),
                role: DunesColorRole.surface,
              ),
            ],
          ),
        );
        child = Icon(
          Icons.smart_toy_outlined,
          color: DunesColors.resolve(context, Colors.white),
          size: 20,
        );
      case ChatInboxRowKind.aiSummary:
        return AiSummaryAvatarMark(size: inboxAvatarSize);
      case ChatInboxRowKind.systemNotification:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            colors: [
              DunesColors.resolve(
                context,
                Color(0xFFC2AEE7),
                role: DunesColorRole.surface,
              ),
              DunesColors.resolve(
                context,
                Color(0xFF9C82CE),
                role: DunesColorRole.surface,
              ),
            ],
          ),
        );
        child = Icon(
          Icons.notifications_none_rounded,
          color: DunesColors.resolve(context, Colors.white),
          size: 17,
        );
      case ChatInboxRowKind.broadcast:
        decoration = BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            colors: [
              DunesColors.resolve(
                context,
                Color(0xFFD9C9F0),
                role: DunesColorRole.surface,
              ),
              DunesColors.resolve(
                context,
                Color(0xFFB89FE2),
                role: DunesColorRole.surface,
              ),
            ],
          ),
        );
        child = Icon(
          Icons.campaign_outlined,
          color: DunesColors.resolve(context, Colors.white),
          size: 17,
        );
      case ChatInboxRowKind.group:
      case ChatInboxRowKind.workgroupApproval:
        if (groupAvatarMembers.isNotEmpty) {
          return GroupCompositeAvatar(
            members: groupAvatarMembers,
            size: inboxAvatarSize,
            avatarService: avatarService,
          );
        }
        if (kind == ChatInboxRowKind.workgroupApproval) {
          decoration = BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              colors: [
                DunesColors.resolve(
                  context,
                  Color(0xFF9079C2),
                  role: DunesColorRole.surface,
                ),
                DunesColors.resolve(
                  context,
                  Color(0xFF6A4FA0),
                  role: DunesColorRole.surface,
                ),
              ],
            ),
          );
          child = Icon(
            Icons.assignment_outlined,
            color: DunesColors.resolve(context, Colors.white),
            size: 17,
          );
        } else {
          decoration = BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              colors: [
                DunesColors.resolve(
                  context,
                  Color(0xFFCABCEB),
                  role: DunesColorRole.surface,
                ),
                DunesColors.resolve(
                  context,
                  Color(0xFFA88CD8),
                  role: DunesColorRole.surface,
                ),
              ],
            ),
          );
          child = Icon(
            Icons.groups_outlined,
            color: DunesColors.resolve(context, Colors.white),
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
            size: inboxAvatarSize,
            showOnline: showOnlineDot,
            avatarPreset: avatarPreset,
            avatarObjectKey: avatarObjectKey,
            avatarUrl: avatarUrl,
            avatarService: avatarService,
            borderRadius: inboxAvatarRadius,
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
            color: DunesColors.resolveNullable(context, style.textColor),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: inboxAvatarSize,
          height: inboxAvatarSize,
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
                color: DunesColors.resolve(
                  context,
                  DunesColors.green,
                  role: DunesColorRole.surface,
                ),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: DunesColors.resolve(
                    context,
                    DunesColors.bgApp,
                    role: DunesColorRole.border,
                  ),
                  width: 2,
                ),
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
    required this.tooltip,
    this.focusNode,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final button = DesktopFeedbackSurface(
      onTap: onTap,
      focusNode: focusNode,
      mobileBorder: const CircleBorder(),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          icon,
          size: 20,
          color: DunesColors.resolve(context, DunesColors.text2),
        ),
      ),
    );
    return isDesktopCommOnly
        ? Tooltip(message: tooltip, child: button)
        : button;
  }
}

class _NovaEyesButton extends StatelessWidget {
  const _NovaEyesButton({required this.onTap, required this.unread});

  final VoidCallback onTap;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '小饕',
      child: GestureDetector(
        onSecondaryTapDown: (details) => unawaited(
          showNovaPresenceFloatMenu(context, details.globalPosition),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: DunesColors.resolve(
                              context,
                              Colors.white,
                              role: DunesColorRole.border,
                            ),
                            width: 1.5,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x247B5CD8),
                              blurRadius: 5,
                              offset: Offset(0, 1.5),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: NovaPersonAvatarImage(width: 34, height: 34),
                        ),
                      ),
                    ),
                  ),
                  if (unread)
                    Positioned(
                      top: 1,
                      right: 1,
                      child: Container(
                        width: 16,
                        height: 16,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: DunesColors.resolveNullable(
                            context,
                            Color(0xFFFF5B61),
                            role: DunesColorRole.surface,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '1',
                          style: DunesTypography.sans(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.resolve(context, Colors.white),
                            context: context,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
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

/// 协调列表中同时只展开一行的左滑操作区。
class InboxSwipeGroupController extends ChangeNotifier {
  Object? _openRowKey;

  Object? get openRowKey => _openRowKey;

  void open(Object? rowKey) {
    if (_openRowKey == rowKey) return;
    _openRowKey = rowKey;
    notifyListeners();
  }

  void closeIf(Object? rowKey) {
    if (_openRowKey == null || _openRowKey != rowKey) return;
    _openRowKey = null;
    notifyListeners();
  }

  void closeAll() {
    if (_openRowKey == null) return;
    _openRowKey = null;
    notifyListeners();
  }
}

/// 列表行左滑快捷操作：跟手拖动、松手回弹、支持多行互斥收起。
class SwipeableChatInboxRow extends StatefulWidget {
  const SwipeableChatInboxRow({
    super.key,
    required this.child,
    this.rowKey,
    this.swipeGroup,
    this.onTogglePin,
    this.pinLabel = '置顶',
    this.onMarkUnread,
    this.markUnreadLabel = '标为未读',
    this.onToggleMute,
    this.muteLabel = '免打扰',
    this.onDelete,
  });

  final Widget child;
  final Object? rowKey;
  final InboxSwipeGroupController? swipeGroup;
  final VoidCallback? onTogglePin;
  final String pinLabel;
  final VoidCallback? onMarkUnread;
  final String markUnreadLabel;
  final VoidCallback? onToggleMute;
  final String muteLabel;
  final VoidCallback? onDelete;

  @override
  State<SwipeableChatInboxRow> createState() => _SwipeableChatInboxRowState();
}

class _SwipeableChatInboxRowState extends State<SwipeableChatInboxRow> {
  double _offset = 0;
  bool _dragging = false;

  int get _actionCount =>
      (widget.onTogglePin == null ? 0 : 1) +
      (widget.onMarkUnread == null ? 0 : 1) +
      (widget.onToggleMute == null ? 0 : 1) +
      (widget.onDelete == null ? 0 : 1);

  double get _actionWidth => _actionCount >= 3 ? 68.0 : 76.0;

  double get _openWidth => _actionWidth * _actionCount;

  @override
  void initState() {
    super.initState();
    widget.swipeGroup?.addListener(_onSwipeGroupChanged);
  }

  @override
  void didUpdateWidget(covariant SwipeableChatInboxRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.swipeGroup != widget.swipeGroup) {
      oldWidget.swipeGroup?.removeListener(_onSwipeGroupChanged);
      widget.swipeGroup?.addListener(_onSwipeGroupChanged);
    }
    final maxWidth = _openWidth;
    if (_offset < -maxWidth) {
      _offset = -maxWidth;
    }
  }

  @override
  void dispose() {
    widget.swipeGroup?.removeListener(_onSwipeGroupChanged);
    super.dispose();
  }

  void _onSwipeGroupChanged() {
    final group = widget.swipeGroup;
    if (group == null || !mounted) return;
    final key = widget.rowKey ?? this;
    if (group.openRowKey != key && _offset != 0) {
      setState(() {
        _dragging = false;
        _offset = 0;
      });
    }
  }

  void _close() {
    if (_offset == 0) return;
    setState(() {
      _dragging = false;
      _offset = 0;
    });
    widget.swipeGroup?.closeIf(widget.rowKey ?? this);
  }

  Widget _swipeAction({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: _actionWidth,
      child: Material(
        color: DunesColors.resolveNullable(
          context,
          color,
          role: DunesColorRole.surface,
        ),
        child: InkWell(
          onTap: () {
            _close();
            onTap();
          },
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.resolve(context, Colors.white),
                  context: context,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        if (_offset != 0 && _actionCount > 0)
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: _openWidth,
                child: Row(
                  children: [
                    if (widget.onTogglePin != null)
                      _swipeAction(
                        label: widget.pinLabel,
                        color: DunesColors.brandPurple,
                        onTap: widget.onTogglePin!,
                      ),
                    if (widget.onMarkUnread != null)
                      _swipeAction(
                        label: widget.markUnreadLabel,
                        color: DunesColors.brandPurple,
                        onTap: widget.onMarkUnread!,
                      ),
                    if (widget.onToggleMute != null)
                      _swipeAction(
                        label: widget.muteLabel,
                        color: isDark
                            ? const Color(0xFF5A586B)
                            : const Color(0xFF8E8E93),
                        onTap: widget.onToggleMute!,
                      ),
                    if (widget.onDelete != null)
                      _swipeAction(
                        label: '删除',
                        color: DunesColors.coral,
                        onTap: widget.onDelete!,
                      ),
                  ],
                ),
              ),
            ),
          ),
        GestureDetector(
          onHorizontalDragStart: _actionCount == 0
              ? null
              : (_) {
                  widget.swipeGroup?.open(widget.rowKey ?? this);
                  setState(() => _dragging = true);
                },
          onHorizontalDragUpdate: _actionCount == 0
              ? null
              : (details) {
                  if (details.delta.dx.abs() < details.delta.dy.abs()) return;
                  setState(() {
                    _offset = (_offset + details.delta.dx).clamp(
                      -_openWidth,
                      0,
                    );
                  });
                },
          onHorizontalDragEnd: _actionCount == 0
              ? null
              : (details) {
                  final vx = details.primaryVelocity ?? 0;
                  final shouldOpen =
                      vx < -320 || (vx <= 180 && _offset < -_openWidth * 0.42);
                  final target = shouldOpen ? -_openWidth : 0.0;
                  if (shouldOpen) {
                    if (_offset > -_openWidth + 2) {
                      HapticFeedback.selectionClick();
                    }
                    widget.swipeGroup?.open(widget.rowKey ?? this);
                  } else {
                    widget.swipeGroup?.closeIf(widget.rowKey ?? this);
                  }
                  setState(() {
                    _dragging = false;
                    _offset = target;
                  });
                },
          onHorizontalDragCancel: _actionCount == 0 ? null : _close,
          onTap: _offset == 0 ? null : _close,
          child: AnimatedContainer(
            duration: _dragging || reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_offset, 0, 0),
            child: AbsorbPointer(absorbing: _offset != 0, child: widget.child),
          ),
        ),
      ],
    );
  }
}

/// 已读不回工作群的文字标识。只给 reply_sla 新工作群用。
class WorkgroupTag extends StatelessWidget {
  const WorkgroupTag({super.key, this.fontSize = 9.5});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final accent = ImVisualTokens.accent(context);
    final textColor = ImVisualTokens.accentText(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: ImVisualTokens.accentSoftSurface(context),
        border: Border.all(
          color: accent.withValues(alpha: 0.24),
          width: 0.6,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4.5,
            height: 4.5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent,
            ),
          ),
          const SizedBox(width: 3.5),
          Text(
            '工作群',
            style: DunesTypography.sans(
              fontSize: fontSize,
              height: 1.1,
              fontWeight: FontWeight.w600,
              color: textColor,
              context: context,
            ),
          ),
        ],
      ),
    );
  }
}
