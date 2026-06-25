import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session_guard.dart';
import '../auth/auth_session.dart';
import '../native/native_screen_host.dart';

/// App 主壳：全部页面由 Flutter 原生承载。
class DunesShell extends StatefulWidget {
  const DunesShell({
    super.key,
    required this.session,
    this.initialScreen = 'B2',
    this.onLogout,
  });

  final AuthSession session;
  final String initialScreen;
  final VoidCallback? onLogout;

  @override
  State<DunesShell> createState() => _DunesShellState();
}

class _DunesShellState extends State<DunesShell> {
  late final DunesNavigationController _navigation;

  // 记录从左边缘开始的横向拖动累计位移，用于实现 iOS 左滑返回。
  double _edgeDragDx = 0;

  @override
  void initState() {
    super.initState();
    _navigation = DunesNavigationController(initialScreen: widget.initialScreen);
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
              if (_navigation.canGoBack) {
                _navigation.back();
              } else {
                SystemNavigator.pop();
              }
            },
            child: Scaffold(
              backgroundColor: DunesColors.bgApp,
              body: Stack(
                children: [
                  NativeScreenHost(
                    session: widget.session,
                    navigation: _navigation,
                    onLogout: widget.onLogout,
                  ),
                  // iOS：从屏幕左边缘向右滑动当作返回（应用为自定义导航栈，需手动实现）。
                  if (_enableEdgeBack && _navigation.canGoBack)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 24,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragStart: (_) => _edgeDragDx = 0,
                        onHorizontalDragUpdate: (d) => _edgeDragDx += d.delta.dx,
                        onHorizontalDragEnd: (d) {
                          final v = d.primaryVelocity ?? 0;
                          if (_navigation.canGoBack && (_edgeDragDx > 40 || v > 300)) {
                            _navigation.back();
                          }
                          _edgeDragDx = 0;
                        },
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
