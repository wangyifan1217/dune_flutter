import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session_guard.dart';
import '../auth/auth_session.dart';
import '../native/native_screen_host.dart';
import '../native/pilot_config.dart';
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
  bool _forceWebView = false;
  String? _lastSyncedWebScreen;
  String? _syncingTarget;

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
        final useNativePilot = !_forceWebView && isNativePilotScreen(_navigation.currentScreen);
        if (!useNativePilot) {
          final target = _navigation.currentScreen;
          if (_lastSyncedWebScreen != target && _syncingTarget != target) {
            _syncingTarget = target;
            _syncWebViewTarget(target);
          }
        }
        return AuthSessionGuardScope(
          session: widget.session,
          onSessionRevoked: () => widget.onLogout?.call(),
          child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (_navigation.canGoBack) {
              if (useNativePilot) {
                _navigation.back();
              } else {
                await _webViewKey.currentState?.navigateBack();
              }
            } else {
              SystemNavigator.pop();
            }
          },
          child: Scaffold(
            backgroundColor: DunesColors.bgApp,
            // WebView 常驻挂载，避免从原生页切到 B3/K1 等时重建导致空白。
            body: IndexedStack(
              index: useNativePilot ? 0 : 1,
              sizing: StackFit.expand,
              children: [
                NativeScreenHost(
                  session: widget.session,
                  navigation: _navigation,
                  onOpenWebView: _openCurrentInWebView,
                  onLogout: widget.onLogout,
                ),
                SafeArea(
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
              ],
            ),
          ),
        ),
        );
      },
    );
  }

  void _openCurrentInWebView() {
    if (!_forceWebView) {
      setState(() => _forceWebView = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _navigation.currentScreen;
      _syncingTarget = target;
      _syncWebViewTarget(target);
    });
  }

  void _syncWebViewTarget(String target, {int retries = 12}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = _webViewKey.currentState;
      if (state == null) {
        if (retries > 0) {
          _syncWebViewTarget(target, retries: retries - 1);
        } else if (_syncingTarget == target) {
          _syncingTarget = null;
        }
        return;
      }
      _lastSyncedWebScreen = target;
      if (_syncingTarget == target) {
        _syncingTarget = null;
      }
      unawaited(state.navigateTo(target));
    });
  }
}

