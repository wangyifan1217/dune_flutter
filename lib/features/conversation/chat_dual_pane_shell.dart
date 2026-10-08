import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/widgets/desktop_section_transition.dart';
import '../shell/dunes_main_tab_bar.dart';

import '../../core/theme/dunes_theme.dart';

/// Windows / macOS / 宽屏下的「侧栏导航 + 会话列表 + 聊天窗口」壳。
///
/// 左侧竖栏导航；列表与聊天分栏渲染，窄屏不应使用本组件。
class ChatDualPaneShell extends StatefulWidget {
  const ChatDualPaneShell({
    super.key,
    required this.listPane,
    required this.chatPane,
    required this.sideRail,
    this.listPaneWidth = 320,
    this.transitionToken = 0,
  });

  final Widget listPane;
  final Widget chatPane;
  final Widget sideRail;
  final double listPaneWidth;
  final int transitionToken;

  @override
  State<ChatDualPaneShell> createState() => _ChatDualPaneShellState();
}

class _ChatDualPaneShellState extends State<ChatDualPaneShell> {
  static const _widthKey = 'dunes_desktop_conversation_width_v1';
  static const _minListWidth = 260.0;
  static const _maxListWidth = 440.0;
  static const _minChatWidth = 400.0;
  final _dividerFocus = FocusNode(debugLabel: 'Conversation divider');
  late double _preferredWidth;
  bool _changed = false;
  bool _hovered = false;
  bool _dragging = false;
  Future<void> _writes = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _preferredWidth = widget.listPaneWidth;
    if (isDesktopCommOnly) unawaited(_restoreWidth());
  }

  Future<void> _restoreWidth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_widthKey);
      if (!mounted || _changed || widget.listPaneWidth != 320) return;
      if (saved != null && saved.isFinite) {
        setState(
          () => _preferredWidth = saved.clamp(_minListWidth, _maxListWidth),
        );
      }
    } catch (_) {
      // Local preferences must never prevent opening the conversation pane.
    }
  }

  @override
  void didUpdateWidget(ChatDualPaneShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listPaneWidth != widget.listPaneWidth) {
      _changed = true;
      _preferredWidth = widget.listPaneWidth;
    }
  }

  void _saveWidth() {
    final width = _preferredWidth;
    _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(_widthKey, width);
      } catch (_) {}
    });
  }

  void _resize(double value, double minWidth, double maxWidth) {
    _changed = true;
    setState(() => _preferredWidth = value.clamp(minWidth, maxWidth));
  }

  void _reset() {
    _changed = true;
    setState(() => _preferredWidth = widget.listPaneWidth);
    _saveWidth();
  }

  @override
  void dispose() {
    _dividerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = isDesktopCommOnly;
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1024.0;
        final maxWidth = math.min(
          _maxListWidth,
          math.max(
            0.0,
            available - kDunesMainSideRailWidth - 1 - _minChatWidth,
          ),
        );
        final minWidth = math.min(_minListWidth, maxWidth);
        final width = desktop
            ? _preferredWidth.clamp(minWidth, maxWidth)
            : widget.listPaneWidth;
        final active = _hovered || _dragging || _dividerFocus.hasFocus;
        return ColoredBox(
          color: DunesColors.resolve(
            context,
            DunesColors.bgApp,
            role: DunesColorRole.surface,
          ),
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  widget.sideRail,
                  SizedBox(
                    width: width,
                    child: DesktopSectionTransition(
                      token: widget.transitionToken,
                      child: widget.listPane,
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: DunesColors.resolve(
                      context,
                      DunesColors.borderSoft,
                      role: DunesColorRole.border,
                    ),
                  ),
                  Expanded(
                    child: DesktopSectionTransition(
                      token: widget.transitionToken,
                      child: widget.chatPane,
                    ),
                  ),
                ],
              ),
              if (desktop)
                Positioned(
                  left: kDunesMainSideRailWidth + width - 6,
                  top: 0,
                  bottom: 0,
                  width: 13,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    onEnter: (_) => setState(() => _hovered = true),
                    onExit: (_) => setState(() => _hovered = false),
                    child: Focus(
                      focusNode: _dividerFocus,
                      onFocusChange: (_) => setState(() {}),
                      onKeyEvent: (_, event) {
                        if (event is! KeyDownEvent &&
                            event is! KeyRepeatEvent) {
                          return KeyEventResult.ignored;
                        }
                        final key = event.logicalKey;
                        if (key == LogicalKeyboardKey.arrowLeft ||
                            key == LogicalKeyboardKey.arrowRight) {
                          _resize(
                            width +
                                (key == LogicalKeyboardKey.arrowRight
                                    ? 16
                                    : -16),
                            minWidth,
                            maxWidth,
                          );
                          _saveWidth();
                          return KeyEventResult.handled;
                        }
                        if (key == LogicalKeyboardKey.home) {
                          _reset();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Semantics(
                        label: '会话列表宽度',
                        value: '${width.round()} 像素',
                        increasedValue:
                            '${(width + 16).clamp(minWidth, maxWidth).round()} 像素',
                        decreasedValue:
                            '${(width - 16).clamp(minWidth, maxWidth).round()} 像素',
                        onIncrease: () {
                          _resize(width + 16, minWidth, maxWidth);
                          _saveWidth();
                        },
                        onDecrease: () {
                          _resize(width - 16, minWidth, maxWidth);
                          _saveWidth();
                        },
                        child: Tooltip(
                          message: '拖动调整宽度 · 双击恢复默认',
                          child: GestureDetector(
                            key: const ValueKey('desktop-conversation-divider'),
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: _reset,
                            onHorizontalDragStart: (_) {
                              setState(() => _dragging = true);
                            },
                            onHorizontalDragUpdate: (details) => _resize(
                              _preferredWidth.clamp(minWidth, maxWidth) +
                                  details.delta.dx,
                              minWidth,
                              maxWidth,
                            ),
                            onHorizontalDragEnd: (_) {
                              setState(() => _dragging = false);
                              _saveWidth();
                            },
                            onHorizontalDragCancel: () {
                              setState(() => _dragging = false);
                              _saveWidth();
                            },
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                width: active ? 3 : 1,
                                color: active
                                    ? DunesColors.brandPurple
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 双栏右侧尚未选中会话时的占位。
class ChatDualPaneEmpty extends StatelessWidget {
  const ChatDualPaneEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.resolve(
        context,
        DunesColors.bgSoft,
        role: DunesColorRole.surface,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 52,
                color: DunesColors.resolve(
                  context,
                  DunesColors.text3,
                ).withValues(alpha: 0.45),
              ),
              const SizedBox(height: 16),
              Text(
                '选择会话开始聊天',
                style: DunesTypography.sans(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.resolve(context, DunesColors.text2),
                  context: context,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '从左侧列表打开私聊或群聊',
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.resolve(context, DunesColors.text3),
                  context: context,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
