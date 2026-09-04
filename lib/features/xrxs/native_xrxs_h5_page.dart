import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../tasks/native_task_home_pane.dart';
import 'xrxs_h5_browser.dart';
import 'xrxs_service.dart';

const _xrxsNavHandler = 'xrxsNav';

/// 薪人薪事 H5 无自带返回，钩住 pushState / hash 以便容器提供「返回」。
const _xrxsHistoryScript = '''
(function () {
  if (window.__dunesXrxsNav) return;
  var nav = { depth: 0 };
  window.__dunesXrxsNav = nav;
  function notify() {
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('xrxsNav', nav.depth);
      }
    } catch (e) {}
  }
  var push = history.pushState;
  history.pushState = function () {
    nav.depth += 1;
    var ret = push.apply(this, arguments);
    notify();
    return ret;
  };
  window.addEventListener('hashchange', function () {
    nav.depth += 1;
    notify();
  });
  window.addEventListener('popstate', function () {
    if (nav.depth > 0) nav.depth -= 1;
    notify();
  });
})();
''';

/// 薪人薪事员工端 H5 免登容器。
class NativeXrxsH5Page extends StatefulWidget {
  const NativeXrxsH5Page({
    super.key,
    required this.session,
    required this.navigation,
    this.onBack,
    this.onChromeChanged,
    this.loginSid,
    this.loginRole,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final VoidCallback? onBack;
  final ValueChanged<TaskShellChrome>? onChromeChanged;

  /// 可选：免登直达审批详情（见 geturl redirectUrlType）。
  final String? loginSid;
  final String? loginRole;

  @override
  State<NativeXrxsH5Page> createState() => _NativeXrxsH5PageState();
}

class _NativeXrxsH5PageState extends State<NativeXrxsH5Page> {
  late final XrxsService _service = XrxsService(widget.session);
  final Completer<InAppWebViewController> _controllerReady =
      Completer<InAppWebViewController>();

  String? _error;
  bool _loading = true;
  bool _pageReady = false;
  bool _submitting = false;
  bool _historyCleared = false;
  bool _webViewCanGoBack = false;
  int _spaDepth = 0;
  WebUri? _rootUri;
  WebUri? _currentUri;

  bool get _atRoot {
    final cur = _currentUri;
    final root = _rootUri;
    if (cur == null || root == null) return true;
    return _uriKey(cur) == _uriKey(root);
  }

  /// 薪人薪事 H5 无自带返回，有历史或已离开落地页时才能回上一页。
  bool get _canH5Back {
    if (!_pageReady || !_historyCleared) return false;
    if (_webViewCanGoBack || _spaDepth > 0) return true;
    return !_atRoot;
  }

  @override
  void initState() {
    super.initState();
    widget.navigation
      ..backInterceptor = _handleSystemBack
      ..canBackInterceptor = () => _canH5Back || widget.onBack != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _publishChrome();
      unawaited(_openXrxs());
    });
  }

  @override
  void dispose() {
    if (widget.navigation.backInterceptor == _handleSystemBack) {
      widget.navigation
        ..backInterceptor = null
        ..canBackInterceptor = null;
    }
    widget.onChromeChanged?.call(const TaskShellChrome());
    super.dispose();
  }

  bool _exitToApp() {
    widget.onBack?.call();
    return widget.onBack != null;
  }

  /// 系统返回：先回薪人薪事上一页，没有历史再退出容器。
  bool _handleSystemBack() {
    if (_canH5Back) {
      unawaited(_goBackInH5());
      return true;
    }
    return _exitToApp();
  }

  String _uriKey(WebUri uri) {
    return '${uri.origin}${uri.path}?${uri.query}#${uri.fragment}';
  }

  bool _isUnsafeBackUrl(WebUri? url) {
    if (url == null || url.scheme == 'about') return true;
    final text = url.toString().toLowerCase();
    return text.contains('ticket=') ||
        text.contains('accesstoken') ||
        text.contains('/login/') ||
        text.contains('geturl');
  }

  Future<void> _refreshCanGoBack(InAppWebViewController controller) async {
    var can = false;
    try {
      can = await controller.canGoBack();
    } catch (_) {}
    if (!mounted) return;
    if (_webViewCanGoBack != can) {
      setState(() => _webViewCanGoBack = can);
    }
  }

  Future<void> _goBackInH5() async {
    if (!_controllerReady.isCompleted) return;
    final controller = await _controllerReady.future;
    try {
      if (await controller.canGoBack()) {
        await controller.goBack();
        final url = await controller.getUrl();
        if (_isUnsafeBackUrl(url) && _rootUri != null) {
          await controller.loadUrl(urlRequest: URLRequest(url: _rootUri!));
        }
        return;
      }
    } catch (_) {}
    if (_spaDepth > 0) {
      try {
        await controller.evaluateJavascript(source: 'history.back();');
        return;
      } catch (_) {}
    }
    final root = _rootUri;
    if (root != null && !_atRoot) {
      try {
        await controller.loadUrl(urlRequest: URLRequest(url: root));
      } catch (_) {}
    }
  }

  void _publishChrome() {
    if (!mounted) return;
    widget.onChromeChanged?.call(
      TaskShellChrome(
        onBack: _exitToApp,
        trailing: IconButton(
          tooltip: '刷新薪人薪事',
          onPressed: _loading ? null : () => unawaited(_openXrxs()),
          icon: const Icon(Icons.refresh_rounded, size: 20),
          color: DunesColors.text2,
        ),
      ),
    );
  }

  Future<void> _openXrxs() async {
    if (_submitting) return;
    _submitting = true;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _pageReady = false;
        _historyCleared = false;
        _webViewCanGoBack = false;
        _spaDepth = 0;
        _rootUri = null;
        _currentUri = null;
      });
    }
    try {
      final login = await _service.fetchH5LoginUrl(
        sid: widget.loginSid,
        role: widget.loginRole,
      );
      if (!mounted) return;
      if (kIsWeb) {
        final opened = await openXrxsH5InBrowser(login.uri);
        if (!opened && mounted) {
          setState(() {
            _loading = false;
            _error = '当前浏览器无法打开薪人薪事，请点击重试';
          });
        }
        return;
      }

      final controller = await _controllerReady.future;
      await CookieManager.instance().deleteAllCookies();
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(login.url)));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _pageReady = false;
        _error = _friendlyError(error);
      });
    } finally {
      _submitting = false;
      _publishChrome();
    }
  }

  Future<NavigationActionPolicy> _handleNavigation(
    NavigationAction action,
  ) async {
    final uri = action.request.url;
    if (uri == null) return NavigationActionPolicy.ALLOW;
    final scheme = uri.scheme.toLowerCase();
    if (const {
      'http',
      'https',
      'about',
      'data',
      'blob',
      'javascript',
    }.contains(scheme)) {
      return NavigationActionPolicy.ALLOW;
    }
    unawaited(_launchExternal(uri));
    return NavigationActionPolicy.CANCEL;
  }

  Future<void> _launchExternal(WebUri uri) async {
    try {
      final ok = await launchUrl(
        Uri.parse(uri.toString()),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未安装可打开该链接的应用')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开外部应用')));
      }
    }
  }

  String _friendlyError(Object error) {
    final text = '$error'.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    return text.isEmpty ? '薪人薪事暂时无法打开，请稍后重试' : text;
  }

  @override
  Widget build(BuildContext context) {
    final content = kIsWeb ? _buildWebFallback() : _buildNativeBody();
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(52 + topInset),
        child: _buildAppTopBar(),
      ),
      body: kIsWeb
          ? content
          : Column(
              children: [
                _buildH5BackBar(),
                Expanded(child: content),
              ],
            ),
    );
  }

  Widget _buildAppTopBar() {
    return Material(
      color: DunesColors.bgApp,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 52,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _exitToApp,
                style: TextButton.styleFrom(
                  foregroundColor: DunesColors.accentDeep,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.arrow_back_ios_new, size: 16),
                label: Text(
                  '返回APP',
                  style: DunesTypography.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.accentDeep,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '薪人薪事',
                  textAlign: TextAlign.center,
                  style: DunesTypography.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: _loading ? null : () => unawaited(_openXrxs()),
                icon: const Icon(Icons.refresh_rounded, size: 22),
                color: DunesColors.text2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildH5BackBar() {
    final enabled = _canH5Back;
    return Material(
      color: Colors.white,
      child: Container(
        height: 44,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: enabled ? () => unawaited(_goBackInH5()) : null,
            style: TextButton.styleFrom(
              foregroundColor: enabled ? DunesColors.text : DunesColors.text3,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            icon: const Icon(Icons.arrow_back_ios_new, size: 14),
            label: Text(
              '返回',
              style: DunesTypography.sans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: enabled ? DunesColors.text : DunesColors.text3,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNativeBody() {
    return Stack(
      fit: StackFit.expand,
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri('about:blank')),
          initialUserScripts: UnmodifiableListView([
            UserScript(
              source: _xrxsHistoryScript,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              contentWorld: ContentWorld.PAGE,
            ),
          ]),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            thirdPartyCookiesEnabled: true,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            useShouldOverrideUrlLoading: true,
            useWideViewPort: true,
            loadWithOverviewMode: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            userAgent:
                'Mozilla/5.0 (Linux; Android 13; Mobile) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/120.0.0.0 Mobile Safari/537.36',
          ),
          onWebViewCreated: (controller) {
            controller.addJavaScriptHandler(
              handlerName: _xrxsNavHandler,
              callback: (args) {
                final depth = args.isNotEmpty
                    ? int.tryParse('${args.first}') ?? 0
                    : 0;
                if (!mounted) return null;
                if (_spaDepth != depth) {
                  setState(() => _spaDepth = depth);
                }
                return null;
              },
            );
            if (!_controllerReady.isCompleted) {
              _controllerReady.complete(controller);
            }
          },
          onLoadStart: (_, url) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _error = null;
            });
          },
          onLoadStop: (controller, url) async {
            if (!mounted || url?.scheme == 'about') return;
            if (!_isUnsafeBackUrl(url)) {
              if (!_historyCleared) {
                try {
                  await controller.clearHistory();
                } catch (_) {}
                try {
                  await controller.evaluateJavascript(
                    source:
                        'if (window.__dunesXrxsNav) window.__dunesXrxsNav.depth = 0;',
                  );
                } catch (_) {}
                _historyCleared = true;
                _rootUri = url;
                _spaDepth = 0;
              }
              _currentUri = url;
              await _refreshCanGoBack(controller);
            }
            if (!mounted) return;
            setState(() {
              _loading = false;
              _pageReady = true;
            });
          },
          onUpdateVisitedHistory: (controller, url, _) async {
            if (!mounted || url == null || url.scheme == 'about') return;
            if (_isUnsafeBackUrl(url)) return;
            _currentUri = url;
            if (_historyCleared) {
              _rootUri ??= url;
            }
            await _refreshCanGoBack(controller);
            if (mounted) setState(() {});
          },
          onReceivedError: (_, request, error) {
            if (request.isForMainFrame != true || !mounted) return;
            setState(() {
              _loading = false;
              _pageReady = false;
              _error = error.description;
            });
          },
          shouldOverrideUrlLoading: (_, action) => _handleNavigation(action),
        ),
        if (_loading)
          const ColoredBox(
            color: Colors.white,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          ),
        if (_error != null && !_pageReady) _buildErrorBody(_error!),
      ],
    );
  }

  Widget _buildWebFallback() {
    if (_error != null) return _buildErrorBody(_error!);
    return const ColoredBox(
      color: Colors.white,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
    );
  }

  Widget _buildErrorBody(String message) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFFE38B24),
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DunesColors.text2,
                  height: 1.45,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => unawaited(_openXrxs()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新打开'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
