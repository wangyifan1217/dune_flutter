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
  Timer? _bootstrapWatchdog;

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
            // 仅以 HTML 首屏渲染为准收起全屏 loading，后续增强脚本后台继续注入。
            if (mounted && !_ready) {
              setState(() => _ready = true);
            }
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
    _bootstrapWatchdog?.cancel();
    _bootstrapWatchdog = Timer(_bootstrapTimeout, _markReady);
    final uid = widget.userId ?? 0;
    if (uid > 0) {
      _restoredNovaStorage = await NovaWebStorage.load(uid);
    }
    await _loadPrototype();
  }

  Future<void> _loadPrototype() async {
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
      await _runJs(await MobileInjection.centrifugeScript());
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
      await _runJs(
        MobileInjection.bootstrapScript(),
        timeout: const Duration(seconds: 45),
      );
      if (widget.initialScreen != 'B2') {
        await navigateTo(widget.initialScreen);
      }
    } catch (error, stack) {
      debugPrint('Prototype bootstrap failed: $error\n$stack');
    } finally {
      _markReady();
    }
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
      if (type == 'screen' || type == 'ready') {
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
    setState(() {
      _ready = false;
      _bootstrapStarted = false;
    });
    await _bootstrap();
  }

  @override
  void dispose() {
    _bootstrapWatchdog?.cancel();
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
