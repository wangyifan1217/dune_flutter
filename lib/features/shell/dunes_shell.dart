import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/analytics/usage_analytics.dart';
import '../../core/navigation/navigation_controller.dart';
import '../../core/platform/desktop_features.dart';
import '../auth/auth_session_guard.dart';
import '../auth/auth_session.dart';
import '../chat/im_celebration.dart';
import '../chat/app_theme_guide.dart';
import '../native/native_screen_host.dart';
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

  // 记录从左边缘开始的横向拖动累计位移，用于实现 iOS 左滑返回。
  double _edgeDragDx = 0;
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
              if (!_navigation.handleBack()) {
                SystemNavigator.pop();
              }
            },
            child: Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              body: Column(
                children: [
                  // PC：有新版本时顶部常驻提示，点「稍后」后仍可见。
                  if (isDesktopCommOnly) const AppUpdateTopBanner(),
                  Expanded(
                    child: Stack(
                      children: [
                        NativeScreenHost(
                          session: widget.session,
                          navigation: _navigation,
                          onLogout: widget.onLogout,
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
                              onHorizontalDragStart: (_) => _edgeDragDx = 0,
                              onHorizontalDragUpdate: (d) =>
                                  _edgeDragDx += d.delta.dx,
                              onHorizontalDragEnd: (d) {
                                final v = d.primaryVelocity ?? 0;
                                if (_navigation.canHandleBack &&
                                    (_edgeDragDx > 40 || v > 300)) {
                                  _navigation.handleBack();
                                }
                                _edgeDragDx = 0;
                              },
                            ),
                          ),
                      ],
                    ),
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
