// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/navigation/navigation_controller.dart';
import 'mobile_injection.dart';

/// Flutter Web / Chrome 端使用 iframe 承载原型。
///
/// `webview_flutter_web` 目前不完整支持 JavaScriptMode / JS Channel 等 API，
/// 因此 Chrome 预览走 iframe，Android / iOS 继续走原生 WebView。
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

  @override
  State<PrototypeWebView> createState() => PrototypeWebViewState();
}

class PrototypeWebViewState extends State<PrototypeWebView> {
  late final String _viewType;
  late final html.IFrameElement _iframe;
  StreamSubscription<html.MessageEvent>? _messageSub;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'dunes-prototype-${DateTime.now().microsecondsSinceEpoch}';
    _iframe = html.IFrameElement()
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block'
      ..allow = 'clipboard-read; clipboard-write';

    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _iframe);
    _messageSub = html.window.onMessage.listen(_onFrameMessage);
    _loadPrototype();
  }

  Future<void> _loadPrototype() async {
    final source = await rootBundle.loadString('assets/prototype/index.html');
    final authed = await MobileInjection.preparePrototypeHtml(
      source,
      token: widget.authToken,
      apiBase: widget.apiBase,
      userId: widget.userId,
      displayName: widget.displayName,
      phone: widget.phone,
      roles: widget.roles,
    );
    _iframe.srcdoc = await _injectWebBridge(authed);
    if (mounted) setState(() => _ready = true);
  }

  Future<String> _injectWebBridge(String htmlSource) async {
    final centrifuge = await MobileInjection.centrifugeScript();
    final bridge = '''
<script>
$centrifuge
${MobileInjection.bootstrapScript()}
(function () {
  function activeId() {
    return document.querySelector('.screen.active')?.dataset?.screen || 'B2';
  }
  var notify = function (id) {
    try { parent.postMessage({ source: 'dunes-prototype', type: 'screen', id: id || activeId() }, '*'); } catch (e) {}
  };
  var oldSetScreen = typeof setScreen === 'function' ? setScreen : null;
  if (oldSetScreen) {
    setScreen = function (id, back) {
      var prev = activeId();
      if (prev === 'K2' && id !== 'K2' && window.DunesKbChat && typeof window.DunesKbChat.onLeave === 'function') {
        window.DunesKbChat.onLeave(prev);
      }
      oldSetScreen(id, back);
      if (id === 'B2' && typeof refreshUserProfile === 'function') refreshUserProfile();
      if (id === 'C4' && typeof window.__dunesWireNovaC4 === 'function') window.__dunesWireNovaC4();
      if (window.DunesInbox && typeof window.DunesInbox.onScreen === 'function') {
        window.DunesInbox.onScreen(id);
      }
      if (window.DunesContacts && typeof window.DunesContacts.onScreen === 'function') {
        window.DunesContacts.onScreen(id);
      }
      if (window.DunesImChat && typeof window.DunesImChat.onScreen === 'function') {
        window.DunesImChat.onScreen(id);
      }
      if (window.DunesKbChat && typeof window.DunesKbChat.onScreen === 'function') {
        window.DunesKbChat.onScreen(id);
      }
      if (window.DunesNovaChat) {
        prev = window.__dunesActiveScreenId || prev || '';
        if (prev === 'C4' && id !== 'C4' && typeof window.DunesNovaChat.onLeave === 'function') {
          window.DunesNovaChat.onLeave();
        }
        if (id === 'C4' && typeof window.DunesNovaChat.onScreen === 'function') {
          window.DunesNovaChat.onScreen(id);
        }
        window.__dunesActiveScreenId = id;
      }
      notify(id);
    };
  }
  window.addEventListener('message', function (event) {
    var data = event.data || {};
    if (data.source !== 'dunes-flutter') return;
    if (data.type === 'go' && data.id) {
      if (typeof go === 'function') go(data.id);
      else if (typeof setScreen === 'function') setScreen(data.id, false);
      notify(data.id);
    }
    if (data.type === 'back') {
      if (typeof back === 'function') back();
      notify();
    }
    if (data.type === 'refresh-contacts' && data.screen) {
      if (window.DunesInbox) window.DunesInbox.onScreen(data.screen);
      if (window.DunesContacts) window.DunesContacts.onScreen(data.screen);
      if (window.DunesImChat) window.DunesImChat.onScreen(data.screen);
    }
  });
  document.addEventListener('focusin', function (e) {
    var t = e.target;
    if (!t || !t.matches) return;
    if (t.matches('input,textarea,select,[contenteditable="true"],[contenteditable=""]')) {
      try { parent.postMessage({ source: 'dunes-prototype', type: 'html-input-focus' }, '*'); } catch (err) {}
    }
  }, true);
  setTimeout(function () {
    if (typeof refreshUserProfile === 'function') refreshUserProfile();
    if (typeof wireNovaC4 === 'function') wireNovaC4();
    notify(activeId());
  }, 120);
})();
</script>
''';
    return htmlSource.replaceFirst('</body>', '$bridge</body>');
  }

  void _onFrameMessage(html.MessageEvent event) {
    final data = event.data;
    if (data is! Map) return;
    if (data['source'] != 'dunes-prototype') return;
    final type = data['type'];
    if (type == 'logout') {
      widget.onLogout?.call();
      return;
    }
    if (type == 'html-input-focus') {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        FocusManager.instance.primaryFocus?.unfocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      });
      return;
    }
    final id = data['id'];
    if (id is String && id.isNotEmpty) {
      widget.navigation.syncFromWebView(id);
      if (id == 'C1' || id == 'C2' || id == 'C3' || id == 'C5' || id == 'C7' || id == 'C9') {
        _iframe.contentWindow?.postMessage(
          {'source': 'dunes-flutter', 'type': 'refresh-contacts', 'screen': id},
          '*',
        );
      }
    }
  }

  Future<void> navigateTo(String screenId) async {
    widget.navigation.go(screenId);
    _iframe.contentWindow?.postMessage(
      {'source': 'dunes-flutter', 'type': 'go', 'id': screenId},
      '*',
    );
  }

  Future<void> navigateBack() async {
    _iframe.contentWindow?.postMessage(
      {'source': 'dunes-flutter', 'type': 'back'},
      '*',
    );
  }

  Future<void> reloadPrototype() async {
    setState(() => _ready = false);
    await _loadPrototype();
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        HtmlElementView(viewType: _viewType),
        if (!_ready)
          const ColoredBox(
            color: Color(0xFFFBFAF6),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      ],
    );
  }
}
