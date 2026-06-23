import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../prototype/prototype_webview.dart';

/// App 主壳：WebView 承载 76 屏原型 + 原生导航辅助层。
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
  final _webViewKey = GlobalKey<PrototypeWebViewState>();
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
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (_navigation.canGoBack) {
              await _webViewKey.currentState?.navigateBack();
            } else {
              SystemNavigator.pop();
            }
          },
          child: Scaffold(
            backgroundColor: DunesColors.bgApp,
            body: SafeArea(
              top: false,
              bottom: false,
              child: PrototypeWebView(
                key: _webViewKey,
                navigation: _navigation,
                initialScreen: widget.initialScreen,
                onLogout: widget.onLogout,
                authToken: widget.session.token,
                apiBase: widget.session.apiBase,
                userId: widget.session.userId,
                displayName: widget.session.displayName,
                phone: widget.session.phone,
                roles: widget.session.roles,
                novaLocalStorage: widget.session.novaLocalStorage,
              ),
            ),
          ),
        );
      },
    );
  }
}

