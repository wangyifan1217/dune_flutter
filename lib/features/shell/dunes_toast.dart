import 'dart:async';

import 'package:flutter/material.dart';

enum DunesToastKind { normal, error }

OverlayEntry? _activeDunesToast;

/// 常驻可点击通知条（顶部横幅）。用独立槽位，与底部短暂 Toast 互不抢占。
OverlayEntry? _activeDunesActionToast;

bool dunesToastLooksLikeError(String message) {
  return RegExp(r'失败|无法|错误|无效|不能|为空|缺少|未就绪|不支持|未允许').hasMatch(message);
}

/// 对齐 WebView `.dunes-app-toast`：底部居中、圆角深色浮层。
void showDunesToast(
  BuildContext context,
  String message, {
  DunesToastKind kind = DunesToastKind.normal,
  Duration duration = const Duration(milliseconds: 2800),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _activeDunesToast?.remove();
  _activeDunesToast = null;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _DunesToastOverlay(
      message: message,
      kind: kind,
    ),
  );

  _activeDunesToast = entry;
  overlay.insert(entry);

  Future<void>.delayed(duration, () {
    if (_activeDunesToast == entry) {
      entry.remove();
      _activeDunesToast = null;
    }
  });
}

void showDunesSoonToast(BuildContext context, [String message = '敬请期待']) {
  showDunesToast(context, message);
}

/// 显示一条「常驻可点击」通知条：
/// - 不会自动消失（除非传入 [duration]），不会被普通 Toast 挤掉；
/// - 点击正文/操作按钮 → 先触发 [onTap]（如跳转页面）再自动消失；
/// - 点击右侧关闭按钮 → 仅消失，不触发 [onTap]。
/// 重复调用会替换上一条常驻通知条（用于刷新文案）。
void showDunesActionToast(
  BuildContext context,
  String message, {
  required VoidCallback onTap,
  String actionLabel = '查看',
  IconData icon = Icons.notifications_active_rounded,
  DunesToastKind kind = DunesToastKind.normal,
  Duration? duration,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _activeDunesActionToast?.remove();
  _activeDunesActionToast = null;

  late OverlayEntry entry;
  void removeEntry() {
    if (_activeDunesActionToast == entry) {
      entry.remove();
      _activeDunesActionToast = null;
    }
  }

  entry = OverlayEntry(
    builder: (ctx) => _DunesActionToastOverlay(
      message: message,
      actionLabel: actionLabel,
      icon: icon,
      kind: kind,
      autoDismiss: duration,
      onAction: onTap,
      onRemove: removeEntry,
    ),
  );

  _activeDunesActionToast = entry;
  overlay.insert(entry);
}

/// 主动收起当前常驻通知条（例如用户已进入对应页面/问题已不存在）。
void dismissDunesActionToast() {
  _activeDunesActionToast?.remove();
  _activeDunesActionToast = null;
}

class _DunesToastOverlay extends StatefulWidget {
  const _DunesToastOverlay({
    required this.message,
    required this.kind,
  });

  final String message;
  final DunesToastKind kind;

  @override
  State<_DunesToastOverlay> createState() => _DunesToastOverlayState();
}

class _DunesToastOverlayState extends State<_DunesToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.12),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 88 + bottomInset),
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: widget.kind == DunesToastKind.error
                          ? const Color(0xF0B43228)
                          : const Color(0xE6141414),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
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

class _DunesActionToastOverlay extends StatefulWidget {
  const _DunesActionToastOverlay({
    required this.message,
    required this.actionLabel,
    required this.icon,
    required this.kind,
    required this.onAction,
    required this.onRemove,
    this.autoDismiss,
  });

  final String message;
  final String actionLabel;
  final IconData icon;
  final DunesToastKind kind;
  final VoidCallback onAction;
  final VoidCallback onRemove;
  final Duration? autoDismiss;

  @override
  State<_DunesActionToastOverlay> createState() => _DunesActionToastOverlayState();
}

class _DunesActionToastOverlayState extends State<_DunesActionToastOverlay>
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

  Timer? _autoTimer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
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
    } catch (_) {
      // 动画期间组件可能已被移除，忽略即可。
    }
    if (act) widget.onAction();
    widget.onRemove();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final isError = widget.kind == DunesToastKind.error;
    final bg = isError ? const Color(0xF0B43228) : const Color(0xF21D2024);
    return Positioned(
      top: topInset + 10,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _close(act: true),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.actionLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _close(act: false),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      iconSize: 18,
                      splashRadius: 18,
                      icon: const Icon(Icons.close_rounded, color: Color(0xCCFFFFFF)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
