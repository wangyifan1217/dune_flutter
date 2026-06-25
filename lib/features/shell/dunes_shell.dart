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

  @override
  void initState() {
    super.initState();
    _navigation = DunesNavigationController(initialScreen: widget.initialScreen);
  }

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
              body: NativeScreenHost(
                session: widget.session,
                navigation: _navigation,
                onLogout: widget.onLogout,
              ),
            ),
          ),
        );
      },
    );
  }
}
