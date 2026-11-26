import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/analytics/usage_analytics.dart';
import '../../core/navigation/navigation_controller.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session_guard.dart';
import '../auth/auth_session.dart';
import '../chat/im_celebration.dart';
import '../chat/app_theme_guide.dart';
import '../native/native_screen_host.dart';
import '../meeting/meeting_live_controller.dart';
import '../meeting/meeting_recording_chrome.dart';
import '../nova/presence/nova_presence_host.dart';
import '../update/app_update_top_banner.dart';

/// App 主壳：全部页面由 Flutter 原生承载。
class DunesShell extends StatefulWidget {
  const DunesShell({
    super.key,
    required this.session,
    this.initialScreen = 'C1',
    this.onLogout,
  });

  final AuthSession session;
  final String initialScreen;
  final VoidCallback? onLogout;

  @override
  State<DunesShell> createState() => _DunesShellState();
}

class _DunesShellState extends State<DunesShell> with WidgetsBindingObserver {
  late final DunesNavigationController _navigation;
  final _presence = NovaPresenceHandle();

  // 记录从左边缘开始的横向拖动累计位移，用于实现 iOS 左滑返回。
  double _edgeDragDx = 0;
  double? _edgeDragY;
  bool _edgeDragUnfocused = false;
  bool _startingMobileEggs = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _navigation = DunesNavigationController(
      initialScreen: widget.initialScreen,
    );
    _bindUsage();
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_startMobileEggs()),
      );
    }
  }

  Future<void> _startMobileEggs() async {
    if (MeetingLiveController.instance.isActive) return;
    if (_startingMobileEggs) return;
    _startingMobileEggs = true;
    try {
      await AppEggThemeController.instance.load();
      await ImEggSettings.instance.ensureLoaded(
        apiBase: widget.session.apiBase,
        token: widget.session.token,
      );
      if (!mounted) return;
      await maybeShowFirstAppThemeGuide(context, widget.session.userId);
      if (!mounted) return;
      final holidayShown = await ImEggSettings.instance.maybeShowHolidayWelcome(
        context,
        widget.session.userId,
      );
      if (!holidayShown && mounted) {
        await ImEggSettings.instance.maybeShowDailyWelcome(
          context,
          widget.session.userId,
        );
      }
    } finally {
      _startingMobileEggs = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android)) {
      unawaited(_startMobileEggs());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navigation.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DunesShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.userId != widget.session.userId ||
        oldWidget.session.token != widget.session.token) {
      _bindUsage();
    }
  }

  void _bindUsage() {
    unawaited(
      UsageAnalytics.instance.bind(widget.session).then((_) {
        UsageAnalytics.instance.trackScreen(_navigation.currentScreen);
      }),
    );
  }

  bool get _enableEdgeBack => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _navigation,
      builder: (context, _) {
        return AuthSessionGuardScope(
          session: widget.session,
          onSessionRevoked: () => widget.onLogout?.call(),
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              if (_presence.closeIfOpen?.call() ?? false) return;
              FocusManager.instance.primaryFocus?.unfocus();
              if (!_navigation.handleBack()) {
                SystemNavigator.pop();
              }
            },
            child: CallbackShortcuts(
              bindings: isDesktopCommOnly
                  ? <ShortcutActivator, VoidCallback>{
                      const SingleActivator(
                        LogicalKeyboardKey.keyK,
                        control: true,
                      ): () {
                        if (_navigation.currentScreen != 'Z4') {
                          _navigation.go('Z4');
                        }
                      },
                      const SingleActivator(
                        LogicalKeyboardKey.keyK,
                        meta: true,
                      ): () {
                        if (_navigation.currentScreen != 'Z4') {
                          _navigation.go('Z4');
                        }
                      },
                      const SingleActivator(
                        LogicalKeyboardKey.digit1,
                        control: true,
                      ): () => _navigation.switchMainTab('C1'),
                      const SingleActivator(
                        LogicalKeyboardKey.digit1,
                        meta: true,
                      ): () => _navigation.switchMainTab('C1'),
                      const SingleActivator(
                        LogicalKeyboardKey.digit2,
                        control: true,
                      ): () {
                        if (!widget.session.isExternalUser) {
                          _navigation.switchMainTab('QJ');
                        }
                      },
                      const SingleActivator(
                        LogicalKeyboardKey.digit2,
                        meta: true,
                      ): () {
                        if (!widget.session.isExternalUser) {
                          _navigation.switchMainTab('QJ');
                        }
                      },
                      const SingleActivator(
                        LogicalKeyboardKey.digit3,
                        control: true,
                      ): () {
                        if (!widget.session.isExternalUser) {
                          _navigation.switchMainTab('LH');
                        }
                      },
                      const SingleActivator(
                        LogicalKeyboardKey.digit3,
                        meta: true,
                      ): () {
                        if (!widget.session.isExternalUser) {
                          _navigation.switchMainTab('LH');
                        }
                      },
                      const SingleActivator(
                        LogicalKeyboardKey.digit4,
                        control: true,
                      ): () {
                        if (!widget.session.isExternalUser) {
                          _navigation.switchMainTab('QJA');
                        }
                      },
                      const SingleActivator(
                        LogicalKeyboardKey.digit4,
                        meta: true,
                      ): () {
                        if (!widget.session.isExternalUser) {
                          _navigation.switchMainTab('QJA');
                        }
                      },
                    }
                  : const <ShortcutActivator, VoidCallback>{},
              child: Scaffold(
              // 由各子页面自身 Scaffold 管理键盘避让；外层壳不随键盘缩放，
              // 避免从 IM 会话收键盘返回列表时触发整页与毛玻璃底栏逐帧重排卡顿。
              resizeToAvoidBottomInset: false,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              body: Column(
                children: [
                  // PC：有新版本时顶部常驻提示，点「稍后」后仍可见。
                  if (isDesktopCommOnly) const AppUpdateTopBanner(),
                  Expanded(
                    child: NovaPresenceHost(
                      // 换票不换用户，不能销毁工作台并再次触发其入场换票。
                      key: ValueKey((
                        widget.session.apiBase,
                        widget.session.userId,
                      )),
                      session: widget.session,
                      handle: _presence,
                      navigation: _navigation,
                      child: Stack(
                        children: [
                          MeetingRecordingCoordinator(
                            navigation: _navigation,
                            child: NativeScreenHost(
                              session: widget.session,
                              navigation: _navigation,
                              onLogout: widget.onLogout,
                            ),
                          ),
                          // iOS：从屏幕左边缘向右滑动当作返回（应用为自定义导航栈，需手动实现）。
                          if (_enableEdgeBack && _navigation.canHandleBack)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: 24,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onHorizontalDragStart: (d) {
                                  setState(() {
                                    _edgeDragDx = 0;
                                    _edgeDragY = d.localPosition.dy;
                                  });
                                  _edgeDragUnfocused = false;
                                },
                                onHorizontalDragUpdate: (d) {
                                  final prev = _edgeDragDx;
                                  final next = (_edgeDragDx + d.delta.dx).clamp(
                                    0.0,
                                    120.0,
                                  );
                                  // 边缘右滑起步即先收起键盘，让键盘与页面切换错峰，避免松手瞬间卡顿。
                                  if (!_edgeDragUnfocused && next > 12) {
                                    _edgeDragUnfocused = true;
                                    FocusManager.instance.primaryFocus
                                        ?.unfocus();
                                  }
                                  if (prev <= 40 && next > 40) {
                                    HapticFeedback.mediumImpact();
                                  }
                                  setState(() {
                                    _edgeDragDx = next;
                                    _edgeDragY = d.localPosition.dy;
                                  });
                                },
                                onHorizontalDragCancel: () {
                                  setState(() {
                                    _edgeDragDx = 0;
                                    _edgeDragY = null;
                                  });
                                  _edgeDragUnfocused = false;
                                },
                                onHorizontalDragEnd: (d) {
                                  final v = d.primaryVelocity ?? 0;
                                  final shouldBack =
                                      _navigation.canHandleBack &&
                                      (_edgeDragDx > 40 || v > 300);
                                  setState(() {
                                    _edgeDragDx = 0;
                                    _edgeDragY = null;
                                  });
                                  _edgeDragUnfocused = false;
                                  if (shouldBack) {
                                    FocusManager.instance.primaryFocus
                                        ?.unfocus();
                                    HapticFeedback.selectionClick();
                                    _navigation.handleBack();
                                  }
                                },
                              ),
                            ),
                          if (_enableEdgeBack &&
                              _navigation.canHandleBack &&
                              _edgeDragDx > 4)
                            _EdgeBackIndicator(
                              dragDx: _edgeDragDx,
                              anchorY: _edgeDragY,
                            ),
                        ],
                      ),
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

/// iOS 边缘右滑跟手磨砂返回指示浮标（仅在拖动中挂载，平时零开销）。
class _EdgeBackIndicator extends StatelessWidget {
  const _EdgeBackIndicator({required this.dragDx, required this.anchorY});

  final double dragDx;
  final double? anchorY;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = (dragDx / 48.0).clamp(0.0, 1.0);
    final triggered = dragDx > 40;
    final top = ((anchorY ?? media.size.height * 0.5) - 24).clamp(
      media.padding.top + 56,
      media.size.height - media.padding.bottom - 96,
    );
    final accent = isDark ? const Color(0xFFC5B0FF) : DunesColors.brandPurple;

    return Positioned(
      left: -14 + progress * 22,
      top: top,
      child: IgnorePointer(
        child: AnimatedScale(
          scale: triggered ? 1.08 : (0.86 + progress * 0.14),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutBack,
          child: Opacity(
            opacity: progress,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  width: 38,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: triggered
                        ? accent.withValues(alpha: isDark ? 0.90 : 0.92)
                        : (isDark ? const Color(0xFF252436) : Colors.white)
                              .withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: triggered
                          ? Colors.white.withValues(alpha: 0.35)
                          : accent.withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.35 : 0.12,
                        ),
                        blurRadius: 14,
                        offset: const Offset(2, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 24,
                    color: triggered
                        ? Colors.white
                        : DunesColors.resolve(context, DunesColors.text),
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
