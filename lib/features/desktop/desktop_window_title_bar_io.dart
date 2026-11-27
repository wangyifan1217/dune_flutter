import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_window_title_bar.dart';

Widget buildDesktopWindowTitleBar(BuildContext context) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
    return const SizedBox.shrink();
  }
  return const _WindowsIntegratedTitleBar();
}

class _WindowsIntegratedTitleBar extends StatefulWidget {
  const _WindowsIntegratedTitleBar();

  @override
  State<_WindowsIntegratedTitleBar> createState() =>
      _WindowsIntegratedTitleBarState();
}

class _WindowsIntegratedTitleBarState extends State<_WindowsIntegratedTitleBar>
    with WindowListener {
  bool _maximized = false;
  bool _listening = false;

  bool get _isFlutterTest => Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    if (!_isFlutterTest && Platform.isWindows) {
      _listening = true;
      windowManager.addListener(this);
      unawaited(_syncMaximized());
    }
  }

  @override
  void dispose() {
    if (_listening) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    try {
      final value = await windowManager.isMaximized();
      if (mounted && _maximized != value) {
        setState(() => _maximized = value);
      }
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted && !_maximized) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted && _maximized) setState(() => _maximized = false);
  }

  Future<void> _toggleMaximize() async {
    if (_isFlutterTest || !Platform.isWindows) return;
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  Future<void> _minimize() async {
    if (_isFlutterTest || !Platform.isWindows) return;
    try {
      await windowManager.minimize();
    } catch (_) {}
  }

  Future<void> _close() async {
    if (_isFlutterTest || !Platform.isWindows) return;
    try {
      await windowManager.close();
    } catch (_) {}
  }

  void _startDrag() {
    if (_isFlutterTest || !Platform.isWindows) return;
    try {
      unawaited(windowManager.startDragging());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 与 DunesDesktopTranslucentFrame 的外框渐变保持 100% 同色系，彻底消除顶栏色差断层。
    final bgGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: isDark
          ? const [Color(0xFF12101B), Color(0xFF181524), Color(0xFF12111C)]
          : const [Color(0xFFECE8F7), Color(0xFFF4F1FB), Color(0xFFEBE8F5)],
    );
    final fgColor = isDark ? const Color(0xFFD0C9D9) : const Color(0xFF4A4656);

    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: bgGradient),
        child: SizedBox(
          height: kDunesDesktopTitleBarHeight,
          child: Row(
            children: [
              // 左侧品牌标识 + 中间整条可拖拽/双击最大化区域
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (_) => _startDrag(),
                  onDoubleTap: _toggleMaximize,
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.asset(
                          'assets/images/app_logo_pc.png',
                          width: 14,
                          height: 14,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, _, _) => const SizedBox(
                            width: 14,
                            height: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '沙丘',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          color: fgColor.withValues(alpha: 0.72),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
              // 右上角沉浸式窗口控制按钮（最小化 / 最大化 / 关闭到托盘）
              _CaptionButton(
                tooltip: '最小化',
                isDark: isDark,
                onTap: _minimize,
                icon: Icon(
                  Icons.horizontal_rule_rounded,
                  size: 15,
                  color: fgColor,
                ),
              ),
              _CaptionButton(
                tooltip: _maximized ? '向下还原' : '最大化',
                isDark: isDark,
                onTap: _toggleMaximize,
                icon: Icon(
                  _maximized
                      ? Icons.filter_none_rounded
                      : Icons.crop_square_rounded,
                  size: _maximized ? 13 : 14.5,
                  color: fgColor,
                ),
              ),
              _CaptionButton(
                tooltip: '关闭',
                isDark: isDark,
                isClose: true,
                onTap: _close,
                icon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: fgColor,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.tooltip,
    required this.isDark,
    required this.icon,
    required this.onTap,
    this.isClose = false,
  });

  final String tooltip;
  final bool isDark;
  final Widget icon;
  final VoidCallback onTap;
  final bool isClose;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = !_hovered
        ? Colors.transparent
        : widget.isClose
        ? const Color(0xFFE81123)
        : (widget.isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0x124B348A));

    return Semantics(
      button: true,
      label: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 36,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: _hovered && widget.isClose
                ? IconTheme.merge(
                    data: const IconThemeData(color: Colors.white),
                    child: widget.icon,
                  )
                : widget.icon,
          ),
        ),
      ),
    );
  }
}
