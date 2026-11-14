import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../chat/native_audio_recorder.dart';
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

/// Reserves space for the bar, so page buttons and chat composers remain usable.
/// Root-page navigation is drawn by the caller, below [bottomNavigationExtent].
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
        // Keep the subtree shape stable when starting/stopping recording.
        final textHeight = MediaQuery.textScalerOf(context).scale(13);
        final extent = show ? 54 + textHeight * 2 : 0.0;
        final safe = bottomNavigationExtent > 0
            ? 0.0
            : MediaQuery.paddingOf(context).bottom;
        return Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: EdgeInsets.only(
                bottom: show ? extent + safe + bottomNavigationExtent : 0,
              ),
              child: content,
            ),
            if (show)
              Positioned(
                left: 16,
                right: 16,
                bottom: bottomNavigationExtent + safe + 8,
                height: extent - 16,
                child: MeetingRecordingBar(onOpen: onOpen),
              ),
          ],
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
        final color = DunesColors.resolve(
          context,
          paused && !recovering ? DunesColors.amber : DunesColors.brandPurple,
        );
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
          child: Material(
            key: const Key('meeting-recording-bar'),
            color: DunesColors.resolve(
              context,
              Colors.white,
              role: DunesColorRole.surface,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: DunesColors.resolve(
                  context,
                  DunesColors.brandPurpleLine,
                  role: DunesColorRole.border,
                ),
              ),
            ),
            elevation: 2,
            shadowColor: DunesColors.brandPurple.withValues(alpha: 0.12),
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: recovering
                          ? Padding(
                              padding: const EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: color,
                              ),
                            )
                          : Icon(
                              paused
                                  ? Icons.pause_rounded
                                  : Icons.graphic_eq_rounded,
                              color: color,
                              size: 22,
                            ),
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
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text,
                              ),
                              context: context,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title.isEmpty ? '现场会议' : title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DunesTypography.sans(
                                    fontSize: 12,
                                    color: DunesColors.resolve(
                                      context,
                                      DunesColors.text2,
                                    ),
                                    context: context,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                meetingRecordingElapsed(live.elapsed.value),
                                style: DunesTypography.sans(
                                  fontSize: 12,
                                  color: DunesColors.resolve(
                                    context,
                                    DunesColors.text2,
                                  ),
                                  context: context,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      paused || failed ? '处理' : '查看',
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: color,
                        context: context,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: color, size: 18),
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
