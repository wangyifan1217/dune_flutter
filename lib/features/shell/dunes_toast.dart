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

/// 后台上传/同步实时进度灵动岛（独立槽位）。
OverlayEntry? _activeDunesProgressIsland;

bool dunesToastLooksLikeError(String message) {
  return RegExp(r'失败|无法|错误|无效|不能|为空|缺少|未就绪|不支持|未允许').hasMatch(message);
}

/// APP 端统一以顶部「灵动岛」形态展示；PC 端保留原有位置与样式。
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
  void removeEntry() {
    if (_activeDunesToast == entry) {
      entry.remove();
      _activeDunesToast = null;
    }
  }

  entry = OverlayEntry(
    builder: (ctx) => _DunesToastOverlay(
      message: message,
      kind: kind,
      alignment: alignment,
      duration: duration,
      onRemove: removeEntry,
    ),
  );

  _activeDunesToast = entry;
  overlay.insert(entry);
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

/// 展示后台任务（文件/录音/知识库上传等）实时进度灵动岛（仅 APP 端生效）。
void showDunesProgressIsland(
  BuildContext context, {
  required String title,
  double? progress,
}) {
  if (isDesktopCommOnly) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _activeDunesProgressIsland?.remove();
  _activeDunesProgressIsland = null;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _DunesProgressIslandOverlay(
      title: title,
      progress: progress,
      onDismiss: () {
        if (_activeDunesProgressIsland == entry) {
          entry.remove();
          _activeDunesProgressIsland = null;
        }
      },
    ),
  );
  _activeDunesProgressIsland = entry;
  overlay.insert(entry);
}

/// 关闭后台进度灵动岛。
void dismissDunesProgressIsland() {
  _activeDunesProgressIsland?.remove();
  _activeDunesProgressIsland = null;
}

class _DunesToastOverlay extends StatefulWidget {
  const _DunesToastOverlay({
    required this.message,
    required this.kind,
    required this.duration,
    required this.onRemove,
    this.alignment = Alignment.bottomCenter,
  });

  final String message;
  final DunesToastKind kind;
  final Duration duration;
  final VoidCallback onRemove;
  final Alignment alignment;

  @override
  State<_DunesToastOverlay> createState() => _DunesToastOverlayState();
}

class _DunesToastOverlayState extends State<_DunesToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    reverseDuration: const Duration(milliseconds: 210),
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
    reverseCurve: Curves.easeIn,
  );

  late final Animation<double> _expand = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  );

  Timer? _dismissTimer;
  bool _closing = false;

  bool get _useDynamicIsland => !isDesktopCommOnly;
  bool get _isCenter => isDesktopCommOnly && widget.alignment == Alignment.center;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    if (widget.kind == DunesToastKind.error) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    _dismissTimer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_closing) return;
    _closing = true;
    _dismissTimer?.cancel();
    try {
      if (mounted) await _controller.reverse();
    } catch (_) {}
    if (mounted) widget.onRemove();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _isError =>
      widget.kind == DunesToastKind.error ||
      dunesToastLooksLikeError(widget.message);

  bool get _isSuccess =>
      !_isError &&
      RegExp(r'已|成功|完成|通过|同步|刷新|复制|保存').hasMatch(widget.message);

  bool get _isWarning =>
      !_isError &&
      !_isSuccess &&
      RegExp(r'请|暂|注意|确认|稍后|超时|敬请').hasMatch(widget.message);

  IconData _toastIcon() {
    if (_isError) return Icons.error_rounded;
    if (_isSuccess) return Icons.check_circle_rounded;
    if (_isWarning) return Icons.info_rounded;
    return Icons.auto_awesome_rounded;
  }

  Color _iconColor() {
    if (_isError) return const Color(0xFFFF5B61);
    if (_isSuccess) return const Color(0xFF34C759);
    if (_isWarning) return const Color(0xFFFFB340);
    return const Color(0xFFB69BFF);
  }

  Color _textColor() {
    if (_isError) return const Color(0xFFFFB8BC);
    if (_isSuccess) return const Color(0xFFC8F7D6);
    if (_isWarning) return const Color(0xFFFFE4B5);
    return const Color(0xFFF2EEFF);
  }

  Color _shellBgColor() {
    if (_isError) return const Color(0xF5240E10);
    if (_isSuccess) return const Color(0xF50C1A12);
    if (_isWarning) return const Color(0xF51D150A);
    return const Color(0xF50D0C14);
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final iconColor = _iconColor();
    final textColor = _textColor();
    final isError = _isError;

    if (_useDynamicIsland) {
      final islandTop = topInset > 14 ? topInset - 2.0 : 10.0;
      final maxIslandWidth = (screenWidth - 28).clamp(220.0, 380.0);
      return Positioned(
        top: islandTop,
        left: 14,
        right: 14,
        child: Align(
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < -120) {
                unawaited(_dismiss());
              }
            },
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                if (reduceMotion) return child!;
                final t = _expand.value;
                final sx = (0.48 + t * 0.52).clamp(0.45, 1.06);
                final sy = (0.76 + t * 0.24).clamp(0.72, 1.04);
                final dy = (1.0 - t.clamp(0.0, 1.0)) * -18.0;
                return Opacity(
                  opacity: _fade.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: Transform(
                      alignment: Alignment.topCenter,
                      transform: Matrix4.diagonal3Values(sx, sy, 1.0),
                      child: child,
                    ),
                  ),
                );
              },
              child: _DynamicIslandShell(
                borderRadius: 24,
                accentColor: iconColor,
                isError: isError,
                bgColor: _shellBgColor(),
                padding: const EdgeInsets.fromLTRB(11, 9, 15, 9),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: 24,
                    maxWidth: maxIslandWidth,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_toastIcon(), size: 15, color: iconColor),
                      ),
                      const SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          widget.message,
                          textAlign: TextAlign.left,
                          softWrap: true,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            height: 1.38,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.1,
                            decoration: TextDecoration.none,
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
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1.0).animate(_expand),
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
                          color: isError
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
                            Icon(_toastIcon(), size: 16, color: iconColor),
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
    );
  }
}

/// 灵动岛曜石黑高光胶囊外壳（供普通提示、操作通知岛与结果反馈岛共用）。
class _DynamicIslandShell extends StatelessWidget {
  const _DynamicIslandShell({
    required this.child,
    required this.borderRadius,
    required this.accentColor,
    required this.isError,
    required this.padding,
    this.bgColor,
  });

  final Widget child;
  final double borderRadius;
  final Color accentColor;
  final bool isError;
  final EdgeInsetsGeometry padding;
  final Color? bgColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 24,
            spreadRadius: -4,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: accentColor.withValues(alpha: isError ? 0.28 : 0.20),
            blurRadius: 18,
            spreadRadius: -6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color:
                    bgColor ??
                    (isError
                        ? const Color(0xF5240E10)
                        : const Color(0xF50D0C14)),
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: accentColor.withValues(alpha: isError ? 0.38 : 0.26),
                  width: 0.8,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _DunesProgressIslandOverlay extends StatelessWidget {
  const _DunesProgressIslandOverlay({
    required this.title,
    required this.progress,
    required this.onDismiss,
  });

  final String title;
  final double? progress;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final islandTop = topInset > 14 ? topInset - 2.0 : 10.0;
    const accent = Color(0xFFB69BFF);

    return Positioned(
      top: islandTop,
      left: 20,
      right: 20,
      child: Align(
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -120) onDismiss();
          },
          child: _DynamicIslandShell(
            borderRadius: 999,
            accentColor: accent,
            isError: false,
            padding: const EdgeInsets.fromLTRB(10, 8, 16, 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 2.2,
                      color: accent,
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
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
                    isError
                        ? const Color(0xFFFDECEC)
                        : DunesColors.brandPurpleSoft,
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  widget.icon,
                  size: 21,
                  color: DunesColors.resolve(
                    context,
                    isError
                        ? const Color(0xFFC43D3D)
                        : DunesColors.brandPurple,
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
    final accentColor = isError
        ? const Color(0xFFFF5B61)
        : const Color(0xFFB69BFF);
    final islandTop = topInset > 14 ? topInset - 2.0 : 10.0;

    return Positioned(
      top: islandTop,
      left: 14,
      right: 14,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < -120) {
                unawaited(_close(act: false));
              }
            },
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.88, end: 1.0).animate(
                    CurvedAnimation(
                      parent: _controller,
                      curve: Curves.easeOutBack,
                    ),
                  ),
                  child: _DynamicIslandShell(
                    borderRadius: 26,
                    accentColor: accentColor,
                    isError: isError,
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        unawaited(_close(act: true));
                      },
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              widget.icon,
                              color: accentColor,
                              size: 17,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.message,
                              softWrap: true,
                              style: TextStyle(
                                color: isError
                                    ? const Color(0xFFFFB8BC)
                                    : const Color(0xFFF2EEFF),
                                fontSize: 13,
                                height: 1.38,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 5.5,
                            ),
                            decoration: BoxDecoration(
                              color: isError
                                  ? accentColor.withValues(alpha: 0.24)
                                  : DunesColors.brandPurple.withValues(
                                      alpha: 0.88,
                                    ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              widget.actionLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          IconButton(
                            onPressed: () => unawaited(_close(act: false)),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            iconSize: 17,
                            splashRadius: 16,
                            icon: Icon(
                              Icons.close_rounded,
                              color: Colors.white.withValues(alpha: 0.68),
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
    );
  }
}
