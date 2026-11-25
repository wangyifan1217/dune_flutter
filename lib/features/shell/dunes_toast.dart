import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';
import '../../core/platform/desktop_features.dart';
import '../push/desktop_notification_card.dart';

enum DunesToastKind { normal, error }

OverlayEntry? _activeDunesToast;

/// 常驻可点击通知条（顶部横幅）。用独立槽位，与底部短暂 Toast 互不抢占。
OverlayEntry? _activeDunesActionToast;

bool dunesToastLooksLikeError(String message) {
  return RegExp(r'失败|无法|错误|无效|不能|为空|缺少|未就绪|不支持|未允许').hasMatch(message);
}

/// 对齐 WebView `.dunes-app-toast`：默认底部居中；可传 [alignment] 改到屏幕中央。
void showDunesToast(
  BuildContext context,
  String message, {
  DunesToastKind kind = DunesToastKind.normal,
  Duration duration = const Duration(milliseconds: 2800),
  Alignment alignment = Alignment.bottomCenter,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _activeDunesToast?.remove();
  _activeDunesToast = null;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) =>
        _DunesToastOverlay(message: message, kind: kind, alignment: alignment),
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

/// 屏幕正中央提示（任务等模块操作反馈）。
void showDunesCenterToast(
  BuildContext context,
  String message, {
  DunesToastKind? kind,
  Duration duration = const Duration(milliseconds: 2800),
}) {
  showDunesToast(
    context,
    message,
    kind:
        kind ??
        (dunesToastLooksLikeError(message)
            ? DunesToastKind.error
            : DunesToastKind.normal),
    duration: duration,
    alignment: Alignment.center,
  );
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
    this.alignment = Alignment.bottomCenter,
  });

  final String message;
  final DunesToastKind kind;
  final Alignment alignment;

  @override
  State<_DunesToastOverlay> createState() => _DunesToastOverlayState();
}

class _DunesToastOverlayState extends State<_DunesToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  late final Animation<double> _scale = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
  );

  bool get _isCenter => widget.alignment == Alignment.center;

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: _isCenter ? const Offset(0, 0.06) : const Offset(0, -0.35),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    if (widget.kind == DunesToastKind.error) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData _toastIcon() {
    if (widget.kind == DunesToastKind.error) return Icons.error_rounded;
    final msg = widget.message;
    if (RegExp(r'已|成功|完成|通过|同步|刷新|复制|保存').hasMatch(msg)) {
      return Icons.check_circle_rounded;
    }
    return Icons.auto_awesome_rounded;
  }

  Color _iconColor() {
    if (widget.kind == DunesToastKind.error) return const Color(0xFFFF6961);
    final msg = widget.message;
    if (RegExp(r'已|成功|完成|通过|同步|刷新|复制|保存').hasMatch(msg)) {
      return const Color(0xFF34C759);
    }
    return const Color(0xFFB9A8EC);
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final effectiveAlignment = _isCenter
        ? Alignment.center
        : Alignment.topCenter;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true,
        child: Align(
          alignment: effectiveAlignment,
          child: Padding(
            padding: _isCenter
                ? const EdgeInsets.symmetric(horizontal: 32)
                : EdgeInsets.fromLTRB(20, topInset + 10, 20, 0),
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: ScaleTransition(
                  scale: _scale,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 320),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: widget.kind == DunesToastKind.error
                                ? const Color(0xEB9E2A22)
                                : const Color(0xEB1C1C1E),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.14),
                              width: 0.7,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x38000000),
                                blurRadius: 22,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _toastIcon(),
                                size: 16,
                                color: _iconColor(),
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  widget.message,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: -0.1,
                                  ),
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
  State<_DunesActionToastOverlay> createState() =>
      _DunesActionToastOverlayState();
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
    if (!mounted) return;
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
    if (isDesktopCommOnly) {
      final isError = widget.kind == DunesToastKind.error;
      return DesktopNotificationPosition(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: DesktopNotificationCard(
              title: isError ? '需要关注' : '工作提醒',
              body: widget.message,
              actionLabel: widget.actionLabel,
              isError: isError,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: DunesColors.resolve(
                    context,
                    isError ? const Color(0xFFFDECEC) : const Color(0xFFEAF2FF),
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  widget.icon,
                  size: 21,
                  color: DunesColors.resolve(
                    context,
                    isError ? const Color(0xFFC43D3D) : const Color(0xFF176CE5),
                  ),
                ),
              ),
              onTap: () => _close(act: true),
              onClose: () => _close(act: false),
              onEnter: () => _autoTimer?.cancel(),
              onExit: () {
                final auto = widget.autoDismiss;
                if (!_closing && auto != null) {
                  _autoTimer?.cancel();
                  _autoTimer = Timer(auto, () => _close(act: false));
                }
              },
            ),
          ),
        ),
      );
    }
    final topInset = MediaQuery.paddingOf(context).top;
    final isError = widget.kind == DunesToastKind.error;
    final bg = isError
        ? DunesColors.resolve(
            context,
            const Color(0xF0B43228),
            role: DunesColorRole.surface,
          )
        : DunesColors.resolve(
            context,
            const Color(0xF21D2024),
            role: DunesColorRole.surface,
          );
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
                  color: DunesColors.resolveNullable(
                    context,
                    bg,
                    role: DunesColorRole.surface,
                  ),
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
                    Icon(
                      widget.icon,
                      color: DunesColors.resolve(context, Colors.white),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          color: DunesColors.resolve(context, Colors.white),
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: DunesColors.resolve(
                          context,
                          Colors.white,
                          role: DunesColorRole.surface,
                        ).withOpacity(0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.actionLabel,
                        style: TextStyle(
                          color: DunesColors.resolve(context, Colors.white),
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
                      icon: Icon(
                        Icons.close_rounded,
                        color: DunesColors.resolveNullable(
                          context,
                          Color(0xCCFFFFFF),
                        ),
                      ),
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
