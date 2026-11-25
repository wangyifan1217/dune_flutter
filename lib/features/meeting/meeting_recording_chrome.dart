import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../chat/native_audio_recorder.dart';
import '../shell/dunes_main_tab_bar.dart';
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

double _meetingRecordingBarHeight(BuildContext context) {
  final textHeight = MediaQuery.textScalerOf(context).scale(13);
  return 54 + textHeight * 2 - 16;
}

/// 悬浮在页面上，不把整页顶出一块底色。
/// 底栏由调用方绘制在 [bottomNavigationExtent] 以下，这里按看得见的胶囊高度贴上去。
class MeetingRecordingLayout extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final live = MeetingLiveController.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: live.active,
      child: child,
      builder: (context, active, content) {
        final show = visible && active;
        final media = MediaQuery.of(context);
        final barHeight = show ? _meetingRecordingBarHeight(context) : 0.0;
        final safe = bottomNavigationExtent > 0 ? 0.0 : media.padding.bottom;
        final barBottom = show ? bottomNavigationExtent + safe + 8 : 0.0;
        final clearance = show ? barBottom + barHeight + 8 : 0.0;
        // 列表原本只让出 96 的底栏堆叠。条贴着 56 的胶囊后，还差出来的一截补进滚动留白。
        final reserved = bottomNavigationExtent > 0
            ? kDunesAppBottomNavStackHeight +
                  (media.viewPadding.bottom > kDunesAppBottomNavMinGap
                      ? media.viewPadding.bottom
                      : kDunesAppBottomNavMinGap)
            : 0.0;
        final extra = clearance > reserved ? clearance - reserved : 0.0;
        final liftedBottom = media.padding.bottom >= clearance
            ? media.padding.bottom
            : clearance;
        final page = !show || liftedBottom == media.padding.bottom
            ? content!
            : MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(bottom: liftedBottom),
                ),
                child: content!,
              );
        return MeetingRecordingChromeInset(
          extra: extra,
          child: Stack(
            fit: StackFit.expand,
            children: [
              page,
              if (show)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: barBottom,
                  height: barHeight,
                  child: MeetingRecordingBar(onOpen: onOpen),
                ),
            ],
          ),
        );
      },
    );
  }
}

class MeetingRecordingBar extends StatelessWidget {
  const MeetingRecordingBar({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final live = MeetingLiveController.instance;
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
        final label = failed
            ? '录音待恢复保存'
            : recovering
            ? '正在恢复录音…'
            : paused
            ? '会议录音已暂停'
            : '会议录音中';
        final title = live.meetingTitle.value.trim();
        return Semantics(
          label:
              '$label，${meetingRecordingElapsed(live.elapsed.value)}，点击进入当前会议',
          button: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.38),
                  blurRadius: 22,
                  spreadRadius: -4,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.24),
                  blurRadius: 16,
                  spreadRadius: -6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: failed
                        ? const Color(0xF5210D0E)
                        : const Color(0xF50B0B10),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.30),
                      width: 0.8,
                    ),
                  ),
                  child: Material(
                    key: const Key('meeting-recording-bar'),
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: onOpen,
                      splashColor: accentColor.withValues(alpha: 0.14),
                      highlightColor: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: recovering
                                  ? Padding(
                                      padding: const EdgeInsets.all(9),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: accentColor,
                                      ),
                                    )
                                  : paused || failed
                                  ? Icon(
                                      failed
                                          ? Icons.warning_amber_rounded
                                          : Icons.pause_rounded,
                                      color: accentColor,
                                      size: 20,
                                    )
                                  : _MeetingIslandEqualizer(color: accentColor),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: DunesTypography.sans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      context: context,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          title.isEmpty ? '现场会议' : title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: DunesTypography.sans(
                                            fontSize: 11.5,
                                            color: Colors.white.withValues(
                                              alpha: 0.68,
                                            ),
                                            context: context,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        meetingRecordingElapsed(
                                          live.elapsed.value,
                                        ),
                                        style: DunesTypography.sans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: accentColor,
                                          context: context,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                paused || failed ? '处理' : '返回',
                                style: DunesTypography.sans(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  context: context,
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
