import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../chat/native_audio_recorder.dart';
import '../shell/dunes_main_tab_bar.dart';
import '../shell/dunes_toast.dart';
import 'meeting_live_controller.dart';

String meetingRecordingElapsed(Duration duration) {
  final seconds = duration.inSeconds;
  final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}

void openCurrentMeeting(DunesNavigationController navigation) {
  if (!MeetingLiveController.instance.isActive) return;
  FocusManager.instance.primaryFocus?.unfocus();
  navigation.popTo('MM0');
}

/// Shell-owned lifecycle reminder. Page navigation itself never triggers a dialog.
class MeetingRecordingCoordinator extends StatefulWidget {
  const MeetingRecordingCoordinator({
    super.key,
    required this.navigation,
    required this.child,
  });

  final DunesNavigationController navigation;
  final Widget child;

  @override
  State<MeetingRecordingCoordinator> createState() =>
      _MeetingRecordingCoordinatorState();
}

class _MeetingRecordingCoordinatorState
    extends State<MeetingRecordingCoordinator>
    with WidgetsBindingObserver {
  final _live = MeetingLiveController.instance;
  bool _background = false;
  bool _activeWhenBackgrounded = false;
  int _resumeRevision = 0;
  int _epoch = 0;
  bool _pending = false;
  bool _checkingTap = false;
  Timer? _deferredPrompt;
  DialogRoute<bool>? _dialog;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _live.openRequests.addListener(_onNotificationTap);
    _live.active.addListener(_onSessionChanged);
    widget.navigation.addListener(_onNavigation);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_consumeTap()),
    );
  }

  @override
  void didUpdateWidget(covariant MeetingRecordingCoordinator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigation != widget.navigation) {
      oldWidget.navigation.removeListener(_onNavigation);
      widget.navigation.addListener(_onNavigation);
    }
  }

  void _onNotificationTap() => unawaited(_consumeTap());

  Future<bool> _consumeTap() async {
    if (_checkingTap) return false;
    _checkingTap = true;
    try {
      final tapped = await NativeAudioRecorder.instance
          .consumeMeetingNotificationTap();
      if (!mounted || !tapped || !_live.isActive) return false;
      _pending = false;
      _closeDialog();
      openCurrentMeeting(widget.navigation);
      return true;
    } finally {
      _checkingTap = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (!_background) {
        _resumeRevision = _live.autoResumeRevision;
        _activeWhenBackgrounded = _live.isActive;
      }
      _background = true;
      _epoch++;
      _pending = false;
      _deferredPrompt?.cancel();
      _closeDialog();
    } else if (state == AppLifecycleState.resumed) {
      final shouldRemind =
          _background && _activeWhenBackgrounded && _live.isActive;
      _background = false;
      if (shouldRemind) {
        final epoch = ++_epoch;
        unawaited(_onReturn(epoch));
      } else {
        unawaited(_consumeTap());
      }
    }
  }

  Future<void> _onReturn(int epoch) async {
    if (await _consumeTap()) return;
    await _live.syncOnForeground();
    if (!mounted ||
        epoch != _epoch ||
        _background ||
        !_live.isActive ||
        _live.isStopping ||
        widget.navigation.currentScreen == 'MM0') {
      return;
    }
    _pending = true;
    _showWhenReady();
  }

  void _onSessionChanged() {
    if (_live.isActive) return;
    _epoch++;
    _pending = false;
    _deferredPrompt?.cancel();
    _closeDialog();
  }

  void _onNavigation() {
    if (widget.navigation.currentScreen == 'MM0') {
      _pending = false;
      _closeDialog();
    }
  }

  void _closeDialog() {
    final route = _dialog;
    _dialog = null;
    // Remove only our own route; never pop an unrelated dialog or page.
    if (route?.navigator != null) route!.navigator!.removeRoute(route);
  }

  void _showWhenReady() {
    if (!mounted ||
        !_pending ||
        _dialog != null ||
        _background ||
        !_live.isActive) {
      return;
    }
    if (widget.navigation.currentScreen == 'MM0' || _live.isStopping) {
      _pending = false;
      return;
    }
    // Wait for existing sheets/auth dialogs instead of stacking another modal.
    if (ModalRoute.of(context)?.isCurrent != true ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      _deferredPrompt?.cancel();
      _deferredPrompt = Timer(
        const Duration(milliseconds: 500),
        _showWhenReady,
      );
      return;
    }
    _pending = false;
    FocusManager.instance.primaryFocus?.unfocus();
    final route = DialogRoute<bool>(
      context: context,
      builder: (_) => MeetingRecordingReturnDialog(
        wasAutomaticallyResumed: _live.autoResumeRevision > _resumeRevision,
      ),
    );
    _dialog = route;
    unawaited(
      Navigator.of(context, rootNavigator: true).push(route).then((open) {
        if (!mounted) return;
        if (_dialog == route) _dialog = null;
        if (open == true && _live.isActive) {
          openCurrentMeeting(widget.navigation);
        }
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.navigation.removeListener(_onNavigation);
    _live.openRequests.removeListener(_onNotificationTap);
    _live.active.removeListener(_onSessionChanged);
    _deferredPrompt?.cancel();
    final route = _dialog;
    _dialog = null;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.navigator != null) route.navigator!.removeRoute(route);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 顶部居中、支持自由拖拽与直接暂停/继续的「会议录音灵动岛」容器：
/// - 默认悬停顶部安全区居中，不遮挡底部 IM 输入框与底栏；
/// - 支持手指 / 鼠标自由拖拽到屏幕任意安全区域，自动贴合安全边界并避开软键盘；
/// - 内置一键暂停/继续录音按钮，点击胶囊主体或「返回」即可回到会议录音页。
class MeetingRecordingLayout extends StatefulWidget {
  const MeetingRecordingLayout({
    super.key,
    required this.child,
    required this.onOpen,
    this.visible = true,
    this.bottomNavigationExtent = 0,
  });

  final Widget child;
  final VoidCallback onOpen;
  final bool visible;
  final double bottomNavigationExtent;

  @override
  State<MeetingRecordingLayout> createState() => _MeetingRecordingLayoutState();
}

class _MeetingRecordingLayoutState extends State<MeetingRecordingLayout> {
  static const double _kIslandHeight = 38.0;
  static const double _kEstimatedMaxWidth = 248.0;

  final GlobalKey _islandKey = GlobalKey();
  Offset? _position;
  bool _dragging = false;

  Size _islandSize() {
    final box = _islandKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) return box.size;
    return const Size(_kEstimatedMaxWidth, _kIslandHeight);
  }

  Offset _clampPosition(
    Offset raw, {
    required Size viewport,
    required EdgeInsets padding,
    required double keyboardInset,
    required Size islandSize,
  }) {
    const margin = 10.0;
    final minX = margin;
    final maxX = (viewport.width - islandSize.width - margin).clamp(
      minX,
      double.infinity,
    );
    final minY = isDesktopCommOnly
        ? 10.0
        : (padding.top > 14 ? padding.top + 4.0 : 10.0);
    final bottomLimit =
        viewport.height -
        (keyboardInset > 0 ? keyboardInset : padding.bottom) -
        islandSize.height -
        margin;
    final maxY = bottomLimit > minY ? bottomLimit : minY;
    return Offset(raw.dx.clamp(minX, maxX), raw.dy.clamp(minY, maxY));
  }

  @override
  Widget build(BuildContext context) {
    final live = MeetingLiveController.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: live.active,
      child: widget.child,
      builder: (context, active, content) {
        if (!active && _position != null) {
          _position = null;
          _dragging = false;
        }
        final show = widget.visible && active;
        final media = MediaQuery.of(context);
        final topDefault = isDesktopCommOnly
            ? 10.0
            : (media.padding.top > 14 ? media.padding.top + 4.0 : 10.0);

        Widget buildIsland() {
          final bar = KeyedSubtree(
            key: _islandKey,
            child: MeetingRecordingBar(
              onOpen: widget.onOpen,
              dragging: _dragging,
            ),
          );
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) {
              final islandSize = _islandSize();
              final current =
                  _position ??
                  Offset(
                    ((media.size.width - islandSize.width) / 2).clamp(
                      10.0,
                      double.infinity,
                    ),
                    topDefault,
                  );
              setState(() {
                _position = current;
                _dragging = true;
              });
            },
            onPanUpdate: (details) {
              final islandSize = _islandSize();
              final base =
                  _position ??
                  Offset(
                    ((media.size.width - islandSize.width) / 2).clamp(
                      10.0,
                      double.infinity,
                    ),
                    topDefault,
                  );
              final next = _clampPosition(
                base + details.delta,
                viewport: media.size,
                padding: media.padding,
                keyboardInset: media.viewInsets.bottom,
                islandSize: islandSize,
              );
              setState(() => _position = next);
            },
            onPanEnd: (_) {
              if (!mounted) return;
              final islandSize = _islandSize();
              setState(() {
                _dragging = false;
                if (_position != null) {
                  _position = _clampPosition(
                    _position!,
                    viewport: media.size,
                    padding: media.padding,
                    keyboardInset: media.viewInsets.bottom,
                    islandSize: islandSize,
                  );
                }
              });
            },
            onPanCancel: () {
              if (mounted) setState(() => _dragging = false);
            },
            child: bar,
          );
        }

        final clampedPos = _position == null
            ? null
            : _clampPosition(
                _position!,
                viewport: media.size,
                padding: media.padding,
                keyboardInset: media.viewInsets.bottom,
                islandSize: _islandSize(),
              );

        return MeetingRecordingChromeInset(
          extra: 0.0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              content!,
              if (show)
                if (clampedPos == null)
                  Positioned(
                    top: topDefault,
                    left: 12,
                    right: 12,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: buildIsland(),
                    ),
                  )
                else
                  Positioned(
                    left: clampedPos.dx,
                    top: clampedPos.dy,
                    child: buildIsland(),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class MeetingRecordingBar extends StatefulWidget {
  const MeetingRecordingBar({
    super.key,
    required this.onOpen,
    this.dragging = false,
  });

  final VoidCallback onOpen;
  final bool dragging;

  @override
  State<MeetingRecordingBar> createState() => _MeetingRecordingBarState();
}

class _MeetingRecordingBarState extends State<MeetingRecordingBar> {
  bool _hovered = false;
  bool _pressed = false;
  bool _toggling = false;

  Future<void> _togglePause() async {
    if (_toggling) return;
    final live = MeetingLiveController.instance;
    if (!live.isActive || live.isStopping || live.saveFailed.value) return;
    HapticFeedback.selectionClick();
    setState(() => _toggling = true);
    try {
      if (live.paused.value) {
        await live.resume();
      } else {
        await live.pause();
      }
    } catch (e) {
      if (mounted) {
        final msg = '$e'.replaceFirst(RegExp(r'^Exception:\s*'), '');
        showDunesToast(
          context,
          msg.isEmpty ? '切换录音状态失败' : msg,
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = MeetingLiveController.instance;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        live.paused,
        live.recovering,
        live.saveFailed,
        live.elapsed,
        live.meetingTitle,
      ]),
      builder: (context, _) {
        final recovering = live.recovering.value;
        final paused = live.paused.value;
        final failed = live.saveFailed.value;
        final accentColor = paused && !recovering
            ? const Color(0xFFFFB340)
            : failed
            ? const Color(0xFFFF5B61)
            : const Color(0xFFB69BFF);
        final shortLabel = failed
            ? '待恢复'
            : recovering
            ? '恢复中…'
            : paused
            ? '已暂停'
            : '录音中';
        final fullLabel = failed
            ? '录音待恢复保存'
            : recovering
            ? '正在恢复录音…'
            : paused
            ? '会议录音已暂停'
            : '会议录音中';
        final elapsed = meetingRecordingElapsed(live.elapsed.value);
        final title = live.meetingTitle.value.trim();
        final canToggle = !recovering && !failed && !live.isStopping;

        final scale = disableAnim
            ? 1.0
            : widget.dragging
            ? 1.04
            : _pressed
            ? 0.96
            : 1.0;

        return Semantics(
          label: '$fullLabel，$elapsed，点击进入当前会议，可拖拽移动',
          button: true,
          child: MouseRegion(
            cursor: widget.dragging
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.click,
            onEnter: (_) {
              if (mounted) setState(() => _hovered = true);
            },
            onExit: (_) {
              if (mounted) setState(() => _hovered = false);
            },
            child: AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              child: Tooltip(
                message: title.isEmpty
                    ? '$fullLabel · 拖拽可移动，点击返回'
                    : '$title · 拖拽可移动，点击返回',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: widget.dragging ? 0.46 : 0.36,
                        ),
                        blurRadius: widget.dragging || _hovered ? 24 : 16,
                        spreadRadius: -4,
                        offset: Offset(0, widget.dragging ? 10 : 6),
                      ),
                      BoxShadow(
                        color: accentColor.withValues(
                          alpha: widget.dragging || _hovered ? 0.38 : 0.22,
                        ),
                        blurRadius: widget.dragging || _hovered ? 18 : 12,
                        spreadRadius: -5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                      child: AnimatedContainer(
                        key: const Key('meeting-recording-bar'),
                        duration: const Duration(milliseconds: 150),
                        height: 38,
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
                        decoration: BoxDecoration(
                          color: failed
                              ? const Color(0xF5210D0E)
                              : const Color(0xF50B0B10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: accentColor.withValues(
                              alpha: widget.dragging || _hovered ? 0.56 : 0.32,
                            ),
                            width: 0.85,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 点击左侧状态与计时区 -> 返回会议页
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (_) {
                                if (mounted) setState(() => _pressed = true);
                              },
                              onTapUp: (_) {
                                if (mounted) setState(() => _pressed = false);
                              },
                              onTapCancel: () {
                                if (mounted) setState(() => _pressed = false);
                              },
                              onTap: () {
                                HapticFeedback.selectionClick();
                                widget.onOpen();
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: accentColor.withValues(
                                        alpha: 0.18,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: recovering
                                        ? Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.8,
                                              color: accentColor,
                                            ),
                                          )
                                        : paused || failed
                                        ? Icon(
                                            failed
                                                ? Icons.warning_amber_rounded
                                                : Icons.pause_rounded,
                                            color: accentColor,
                                            size: 14,
                                          )
                                        : _MeetingIslandEqualizer(
                                            color: accentColor,
                                          ),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    shortLabel,
                                    maxLines: 1,
                                    style: DunesTypography.sans(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      context: context,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    elapsed,
                                    maxLines: 1,
                                    style: DunesTypography.sans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: accentColor,
                                      context: context,
                                    ).copyWith(
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (canToggle) ...[
                              const SizedBox(width: 7),
                              _IslandPauseToggleBtn(
                                paused: paused,
                                busy: _toggling,
                                accent: accentColor,
                                onTap: _togglePause,
                              ),
                            ],
                            const SizedBox(width: 5),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                widget.onOpen();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.24),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  failed ? '处理' : '返回',
                                  style: DunesTypography.sans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
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
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IslandPauseToggleBtn extends StatefulWidget {
  const _IslandPauseToggleBtn({
    required this.paused,
    required this.busy,
    required this.accent,
    required this.onTap,
  });

  final bool paused;
  final bool busy;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_IslandPauseToggleBtn> createState() => _IslandPauseToggleBtnState();
}

class _IslandPauseToggleBtnState extends State<_IslandPauseToggleBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    return Tooltip(
      message: widget.paused ? '继续录音' : '暂停录音',
      child: GestureDetector(
        key: const Key('meeting-island-toggle-pause'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (mounted) setState(() => _pressed = true);
        },
        onTapUp: (_) {
          if (mounted) setState(() => _pressed = false);
        },
        onTapCancel: () {
          if (mounted) setState(() => _pressed = false);
        },
        onTap: widget.busy ? null : widget.onTap,
        child: AnimatedScale(
          scale: _pressed && !disableAnim ? 0.88 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.paused
                  ? const Color(0xFF34C759).withValues(alpha: 0.24)
                  : Colors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.paused
                    ? const Color(0xFF34C759).withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.22),
                width: 0.7,
              ),
            ),
            child: widget.busy
                ? SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: widget.accent,
                    ),
                  )
                : Icon(
                    widget.paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    size: 15,
                    color: widget.paused
                        ? const Color(0xFF5CE682)
                        : Colors.white,
                  ),
          ),
        ),
      ),
    );
  }
}

/// 灵动岛实时声纹律动条（仅在录音活跃态挂载，暂停/结束立即释放，遵循减弱动画）。
class _MeetingIslandEqualizer extends StatefulWidget {
  const _MeetingIslandEqualizer({required this.color});

  final Color color;

  @override
  State<_MeetingIslandEqualizer> createState() =>
      _MeetingIslandEqualizerState();
}

class _MeetingIslandEqualizerState extends State<_MeetingIslandEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Icon(Icons.graphic_eq_rounded, color: widget.color, size: 20);
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final h1 = 6.0 + 10.0 * ((t + 0.1) % 1.0);
        final h2 = 8.0 + 11.0 * (1.0 - t);
        final h3 = 6.0 + 9.0 * ((t + 0.55) % 1.0);
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final h in [h1, h2, h3])
              Container(
                width: 3,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 1.4),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        );
      },
    );
  }
}

class MeetingRecordingReturnDialog extends StatelessWidget {
  const MeetingRecordingReturnDialog({
    super.key,
    required this.wasAutomaticallyResumed,
  });
  final bool wasAutomaticallyResumed;

  @override
  Widget build(BuildContext context) {
    final live = MeetingLiveController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        live.paused,
        live.recovering,
        live.saveFailed,
        live.meetingTitle,
      ]),
      builder: (context, _) {
        final paused = live.paused.value;
        final failed = live.saveFailed.value;
        final recovering = live.recovering.value;
        final title = failed
            ? '会议录音已中断'
            : recovering
            ? '正在恢复会议录音'
            : paused
            ? '会议录音已暂停'
            : wasAutomaticallyResumed
            ? '会议录音已自动继续'
            : '会议录音仍在进行';
        final message = failed
            ? '当前录音会话已中断，请进入会议恢复并保存已有录音。'
            : recovering
            ? '正在尝试恢复当前会议，请进入会议查看最新状态。'
            : paused
            ? (live.userPaused
                  ? '你已主动暂停录音。需要继续时，可以进入当前会议操作。'
                  : '暂时无法恢复录音，已有录音会保留。请进入会议检查并继续录音。')
            : wasAutomaticallyResumed
            ? '已恢复当前会议的录音。你可以继续使用其他功能，或返回会议查看。'
            : '你可以继续使用其他功能，或返回会议查看录音。';
        final color = DunesColors.resolve(
          context,
          paused && !recovering ? DunesColors.amber : DunesColors.brandPurple,
        );
        final text = DunesColors.resolve(context, DunesColors.text);
        final muted = DunesColors.resolve(context, DunesColors.text2);
        return Dialog(
          key: const Key('meeting-return-dialog'),
          backgroundColor: DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.surface,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      paused ? Icons.pause_rounded : Icons.graphic_eq_rounded,
                      color: color,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: DunesTypography.sans(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: text,
                      context: context,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      height: 1.7,
                      color: muted,
                      context: context,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: DunesColors.resolve(
                        context,
                        DunesColors.brandPurpleSoft,
                        role: DunesColorRole.surface,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          live.meetingTitle.value.trim().isEmpty
                              ? '现场会议'
                              : live.meetingTitle.value,
                          style: DunesTypography.sans(
                            fontSize: 14,
                            color: text,
                            context: context,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '已录音 ${meetingRecordingElapsed(live.elapsed.value)}',
                          style: DunesTypography.sans(
                            fontSize: 12,
                            color: muted,
                            context: context,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final buttons = [
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: text,
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            side: BorderSide(
                              color: DunesColors.resolve(
                                context,
                                DunesColors.borderSoft,
                                role: DunesColorRole.border,
                              ),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          child: const Text('留在当前页'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: DunesColors.brandPurple,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          child: Text(paused || failed ? '进入会议处理' : '查看会议'),
                        ),
                      ];
                      if (constraints.maxWidth < 270 ||
                          MediaQuery.textScalerOf(context).scale(14) > 18) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buttons[1],
                            const SizedBox(height: 8),
                            buttons[0],
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: buttons[0]),
                          const SizedBox(width: 10),
                          Expanded(child: buttons[1]),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
