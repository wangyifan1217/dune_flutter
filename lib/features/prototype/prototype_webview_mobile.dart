import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../core/navigation/navigation_controller.dart';
import '../contacts/contacts_bridge.dart';
import '../nova/nova_web_storage.dart';
import 'mobile_injection.dart';

/// Android / iOS 端使用原生 WebView 承载 index.html。
class PrototypeWebView extends StatefulWidget {
  const PrototypeWebView({
    super.key,
    required this.navigation,
    this.initialScreen = 'B2',
    this.onLogout,
    this.authToken,
    this.apiBase,
    this.userId,
    this.displayName,
    this.phone,
    this.roles = const [],
    this.novaLocalStorage,
  });

  final DunesNavigationController navigation;
  final String initialScreen;
  final VoidCallback? onLogout;
  final String? authToken;
  final String? apiBase;
  final int? userId;
  final String? displayName;
  final String? phone;
  final List<String> roles;
  final Map<String, String>? novaLocalStorage;

  @override
  State<PrototypeWebView> createState() => PrototypeWebViewState();
}

class PrototypeWebViewState extends State<PrototypeWebView> {
  static const _bootstrapTimeout = Duration(seconds: 45);

  late final WebViewController _controller;
  Map<String, String> _restoredNovaStorage = const {};
  bool _ready = false;
  bool _bootstrapStarted = false;
  bool _fallbackLiteLoaded = false;
  bool _webReadySignalReceived = false;
  Timer? _bootstrapWatchdog;
  Timer? _emergencyUnlockTimer;

  void _trace(String message) {
    final uid = widget.userId ?? 0;
    debugPrint('[DUNES_WEBVIEW][uid:$uid] $message');
  }

  Future<void> _measureStep(String name, Future<void> Function() run) async {
    final sw = Stopwatch()..start();
    _trace('$name:start');
    try {
      await run();
      _trace('$name:ok ${sw.elapsedMilliseconds}ms');
    } catch (error) {
      _trace('$name:fail ${sw.elapsedMilliseconds}ms error=$error');
      rethrow;
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = _createController();
    _bootstrap();
    widget.navigation.addListener(_onNavChanged);
  }

  WebViewController _createController() {
    final params = () {
      if (WebViewPlatform.instance is WebKitWebViewPlatform) {
        return WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
        );
      }
      return const PlatformWebViewControllerCreationParams();
    }();

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFBFAF6))
      ..addJavaScriptChannel(
        'DunesFlutterChannel',
        onMessageReceived: _onJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _trace('onPageFinished');
            // 仅以 HTML 首屏渲染为准收起全屏 loading，后续增强脚本后台继续注入。
            if (mounted && !_ready) {
              setState(() => _ready = true);
            }
            _scheduleEmergencyUnlock();
            unawaited(_injectBootstrap());
          },
          onWebResourceError: (error) {
            debugPrint(
              'WebView resource error: ${error.errorCode} ${error.description}',
            );
          },
        ),
      );

    return controller;
  }

  Future<void> _bootstrap() async {
    final sw = Stopwatch()..start();
    _trace('_bootstrap:start');
    _webReadySignalReceived = false;
    _emergencyUnlockTimer?.cancel();
    _fallbackLiteLoaded = false;
    _bootstrapWatchdog?.cancel();
    _bootstrapWatchdog = Timer(_bootstrapTimeout, _markReady);
    final uid = widget.userId ?? 0;
    if (uid > 0) {
      _restoredNovaStorage = await NovaWebStorage.load(uid);
    }
    try {
      await _measureStep('loadPrototype:full', () => _loadPrototype());
    } catch (error, stack) {
      _trace('loadPrototype:full failed, retry lite mode');
      debugPrint('Prototype load failed, retry lite mode: $error\n$stack');
      if (_fallbackLiteLoaded) rethrow;
      _fallbackLiteLoaded = true;
      await _measureStep(
        'loadPrototype:lite',
        () => _loadPrototype(lightweightAssets: true),
      );
    }
    _trace('_bootstrap:done ${sw.elapsedMilliseconds}ms');
  }

  Future<void> _loadPrototype({bool lightweightAssets = false}) async {
    final source = await rootBundle.loadString('assets/prototype/index.html');
    await _controller.loadHtmlString(
      await MobileInjection.preparePrototypeHtml(
        source,
        token: widget.authToken,
        apiBase: widget.apiBase,
        userId: widget.userId,
        displayName: widget.displayName,
        phone: widget.phone,
        roles: widget.roles,
        novaLocalStorage: widget.novaLocalStorage,
        novaWebStorage: _restoredNovaStorage,
        lightweightAssets: lightweightAssets,
      ),
      baseUrl: MobileInjection.prototypeBaseUrl,
    );
  }

  Future<void> _runJs(String script, {Duration? timeout}) {
    return _controller
        .runJavaScript(script)
        .timeout(timeout ?? const Duration(seconds: 30));
  }

  Future<void> _injectBootstrap() async {
    if (_bootstrapStarted) return;
    _bootstrapStarted = true;

    try {
      await _measureStep('inject:js_error_bridge', _installJsErrorBridge);
      await _measureStep('inject:centrifuge', () async {
        await _runJs(await MobileInjection.centrifugeScript());
      });
      await _measureStep('inject:auth', () async {
        await _runJs(MobileInjection.authScript(
          token: widget.authToken,
          apiBase: widget.apiBase,
          userId: widget.userId,
          displayName: widget.displayName,
          phone: widget.phone,
          roles: widget.roles,
          novaLocalStorage: widget.novaLocalStorage,
          novaWebStorage: _restoredNovaStorage,
        ));
      });
      await _measureStep('inject:bootstrap', () async {
        await _runJs(
          MobileInjection.bootstrapScript(),
          timeout: const Duration(seconds: 45),
        );
      });
      if (widget.initialScreen != 'B2') {
        await _measureStep('inject:navigate_initial', () async {
          await navigateTo(widget.initialScreen);
        });
      }
    } catch (error, stack) {
      debugPrint('Prototype bootstrap failed: $error\n$stack');
    } finally {
      _markReady();
    }
  }

  void _scheduleEmergencyUnlock() {
    _emergencyUnlockTimer?.cancel();
    _emergencyUnlockTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || _webReadySignalReceived) return;
      _trace('emergency-unlock:trigger');
      unawaited(_emergencyUnlockWebView());
    });
  }

  Future<void> _emergencyUnlockWebView() async {
    try {
      await _runJs('''
        (function () {
          try {
            document.body.classList.add('flutter-app-mode');
            var screens = document.querySelectorAll('.screen');
            for (var i = 0; i < screens.length; i++) {
              screens[i].classList.remove('dunes-screen-loading');
            }
            var masks = document.querySelectorAll('.dunes-screen-loading-mask');
            for (var j = 0; j < masks.length; j++) {
              masks[j].style.display = 'none';
            }
            var active = document.querySelector('.screen.active');
            if (!active && typeof setScreen === 'function') {
              setScreen('B2', false);
              active = document.querySelector('.screen.active');
            }
            if (!active) {
              var b2 = document.querySelector('.screen[data-screen="B2"]');
              if (b2) {
                for (var k = 0; k < screens.length; k++) {
                  screens[k].classList.remove('active');
                }
                b2.classList.add('active');
                active = b2;
              }
            }
            if (active) {
              var content = active.querySelector('.content');
              if (content) {
                content.style.visibility = '';
                content.style.pointerEvents = '';
              }
              var stream = active.querySelector('.msg-stream');
              if (stream) {
                stream.style.visibility = '';
                stream.style.pointerEvents = '';
              }
            }
            if (window.DunesFlutterChannel && window.DunesFlutterChannel.postMessage) {
              var sid = (active && active.dataset && active.dataset.screen) ? active.dataset.screen : 'B2';
              window.DunesFlutterChannel.postMessage(JSON.stringify({ type: 'ready', id: sid }));
            }
          } catch (e) {}
        })();
      ''', timeout: const Duration(seconds: 6));
      _trace('emergency-unlock:done');
    } catch (error) {
      _trace('emergency-unlock:fail error=$error');
    }
  }

  Future<void> _installJsErrorBridge() async {
    await _runJs('''
      (function () {
        if (window.__dunesJsErrorBridgeInstalled) return;
        window.__dunesJsErrorBridgeInstalled = true;
        function post(type, payload) {
          try {
            if (!window.DunesFlutterChannel || !window.DunesFlutterChannel.postMessage) return;
            window.DunesFlutterChannel.postMessage(JSON.stringify({
              type: type,
              data: payload || {}
            }));
          } catch (e) {}
        }
        window.addEventListener('error', function (event) {
          post('js-error', {
            message: event && event.message ? String(event.message) : 'unknown error',
            source: event && event.filename ? String(event.filename) : '',
            line: event && event.lineno ? Number(event.lineno) : 0,
            column: event && event.colno ? Number(event.colno) : 0,
            stack: event && event.error && event.error.stack ? String(event.error.stack) : ''
          });
        });
        window.addEventListener('unhandledrejection', function (event) {
          var reason = '';
          try {
            var raw = event ? event.reason : '';
            reason = typeof raw === 'string' ? raw : JSON.stringify(raw);
          } catch (e) {
            reason = String((event && event.reason) || '');
          }
          post('js-unhandledrejection', { reason: reason });
        });
        post('js-bridge-ready', { ok: true });
      })();
    ''');
  }

  void _markReady() {
    _bootstrapWatchdog?.cancel();
    _bootstrapWatchdog = null;
    if (!mounted || _ready) return;
    setState(() => _ready = true);
  }

  void _onJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final type = data['type'] as String?;
      if (type == 'logout') {
        widget.onLogout?.call();
        return;
      }
      if (type == 'nova-storage') {
        final raw = data['data'];
        if (raw is Map && widget.userId != null && widget.userId! > 0) {
          NovaWebStorage.save(
            widget.userId!,
            Map<String, dynamic>.from(raw),
          );
        }
        return;
      }
      if (type == 'js-bridge-ready') {
        _trace('js-bridge-ready');
        return;
      }
      if (type == 'js-error') {
        final raw = data['data'];
        final payload = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
        _trace(
          'js-error msg=${payload['message'] ?? ''} '
          'src=${payload['source'] ?? ''}:${payload['line'] ?? 0}:${payload['column'] ?? 0}',
        );
        final stack = payload['stack'];
        if (stack is String && stack.isNotEmpty) {
          debugPrint('[DUNES_WEBVIEW][js-stack] $stack');
        }
        return;
      }
      if (type == 'js-unhandledrejection') {
        final raw = data['data'];
        final payload = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
        _trace('js-unhandledrejection reason=${payload['reason'] ?? ''}');
        return;
      }
      if (type == 'screen' || type == 'ready') {
        _webReadySignalReceived = true;
        _emergencyUnlockTimer?.cancel();
        final id = data['id'] as String?;
        if (id != null) {
          widget.navigation.syncFromWebView(id);
          if (id == 'C1' ||
              id == 'C2' ||
              id == 'C3' ||
              id == 'C5' ||
              id == 'C7' ||
              id == 'C9') {
            _controller.runJavaScript(ContactsBridge.refreshScreen(id));
          }
        }
        if (type == 'ready') {
          _markReady();
        }
      }
    } catch (_) {}
  }

  void _onNavChanged() {
    // WebView 驱动导航，Flutter 侧仅展示状态栏信息。
  }

  Future<void> navigateTo(String screenId) async {
    await _controller.runJavaScript(MobileInjection.goToScreen(screenId));
  }

  Future<void> navigateBack() async {
    await _controller.runJavaScript(MobileInjection.goBack());
  }

  Future<void> reloadPrototype() async {
    _emergencyUnlockTimer?.cancel();
    setState(() {
      _ready = false;
      _bootstrapStarted = false;
      _webReadySignalReceived = false;
    });
    await _bootstrap();
  }

  @override
  void dispose() {
    _bootstrapWatchdog?.cancel();
    _emergencyUnlockTimer?.cancel();
    widget.navigation.removeListener(_onNavChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _controller),
        if (!_ready)
          const ColoredBox(
            color: Color(0xFFFBFAF6),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      ],
    );
  }
}
