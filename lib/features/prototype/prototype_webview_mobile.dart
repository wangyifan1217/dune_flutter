import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  late final WebViewController _controller;
  Map<String, String> _restoredNovaStorage = const {};
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFBFAF6))
      ..addJavaScriptChannel(
        'DunesFlutterChannel',
        onMessageReceived: _onJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _injectBootstrap(),
        ),
      );

    _bootstrap();
    widget.navigation.addListener(_onNavChanged);
  }

  Future<void> _bootstrap() async {
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

  Future<void> _injectBootstrap() async {
    await _controller.runJavaScript(await MobileInjection.centrifugeScript());
    await _controller.runJavaScript(MobileInjection.authScript(
      token: widget.authToken,
      apiBase: widget.apiBase,
      userId: widget.userId,
      displayName: widget.displayName,
      phone: widget.phone,
      roles: widget.roles,
      novaLocalStorage: widget.novaLocalStorage,
      novaWebStorage: _restoredNovaStorage,
    ));
    await _controller.runJavaScript(MobileInjection.bootstrapScript());
    if (widget.initialScreen != 'B2') {
      await navigateTo(widget.initialScreen);
    }
    if (mounted) setState(() => _ready = true);
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
          if (id == 'C1' || id == 'C2' || id == 'C3' || id == 'C5' || id == 'C7' || id == 'C9') {
            _controller.runJavaScript(ContactsBridge.refreshScreen(id));
          }
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
    setState(() => _ready = false);
    await _bootstrap();
  }

  @override
  void dispose() {
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
