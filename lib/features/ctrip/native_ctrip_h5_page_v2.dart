import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/native_permissions.dart';
import '../auth/auth_session.dart';
import '../tasks/native_task_home_pane.dart';
import 'ctrip_document_start_geo.dart';
import 'ctrip_h5_browser.dart';
import 'ctrip_h5_service.dart';

const _paymentSchemes = <String>{'alipay', 'alipays', 'weixin', 'wechat'};
const _mapAppSchemes = <String>{
  'amapuri',
  'androidamap',
  'iosamap',
  'baidumap',
  'qqmap',
  'comgooglemaps',
  'google.navigation',
};

/// 携程商旅容器。
///
/// 定位桥以 document-start 方式注入，保证早于携程及地图 SDK 的首屏脚本。
/// 顶部和系统返回键都直接退出携程，返回 APP 工作台。
class NativeCtripH5Page extends StatefulWidget {
  const NativeCtripH5Page({
    super.key,
    required this.session,
    required this.navigation,
    this.embedded = false,
    this.onBack,
    this.onChromeChanged,
    this.initPage = 'Home',
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final bool embedded;
  final VoidCallback? onBack;
  final ValueChanged<TaskShellChrome>? onChromeChanged;
  final String initPage;

  @override
  State<NativeCtripH5Page> createState() => _NativeCtripH5PageState();
}

class _NativeCtripH5PageState extends State<NativeCtripH5Page> {
  late final CtripH5Service _service = CtripH5Service(widget.session);
  final CtripDocumentStartGeo _geo = CtripDocumentStartGeo();
  final Completer<InAppWebViewController> _controllerReady =
      Completer<InAppWebViewController>();

  String? _error;
  bool _loading = true;
  bool _pageReady = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    widget.navigation
      ..backInterceptor = _exitToApp
      ..canBackInterceptor = () => widget.onBack != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _publishChrome();
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    final allowed = await ensureLocationPermission();
    if (!allowed) {
      final status = await Permission.locationWhenInUse.status;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(locationPermissionHint(status))));
      }
    } else {
      final result = await _geo.prefetch();
      if (mounted && result['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result['message'] ?? '原生定位失败'}')),
        );
      }
    }
    if (mounted) await _openCtrip();
  }

  @override
  void dispose() {
    if (widget.navigation.backInterceptor == _exitToApp) {
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

  void _publishChrome() {
    if (!mounted) return;
    widget.onChromeChanged?.call(
      TaskShellChrome(
        onBack: _exitToApp,
        trailing: IconButton(
          tooltip: '刷新携程商旅',
          onPressed: _loading ? null : () => unawaited(_openCtrip()),
          icon: const Icon(Icons.refresh_rounded, size: 20),
          color: DunesColors.text2,
        ),
      ),
    );
  }

  Future<void> _openCtrip() async {
    if (_submitting) return;
    _submitting = true;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _pageReady = false;
      });
    }
    try {
      final form = await _service.fetchForm(initPage: widget.initPage);
      if (!mounted) return;
      if (kIsWeb) {
        final opened = await openCtripH5InBrowser(form);
        if (!opened && mounted) {
          setState(() {
            _loading = false;
            _error = '当前浏览器无法打开携程页面，请点击重试';
          });
        }
        return;
      }

      final controller = await _controllerReady.future;
      await CookieManager.instance().deleteAllCookies();
      await controller.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(form.action),
          method: 'POST',
          headers: const {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept-Language': 'zh-CN,zh;q=0.9',
            'Referer': 'https://ct.ctrip.com/',
          },
          body: Uint8List.fromList(utf8.encode(form.postBody())),
        ),
      );
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
    if (_paymentSchemes.contains(scheme)) {
      unawaited(_launchExternal(uri, tip: '正在打开支付应用，完成后请返回沙丘X'));
    } else if (_mapAppSchemes.contains(scheme) || scheme == 'geo') {
      unawaited(_launchExternal(uri, tip: '已打开地图应用，返回即可继续使用沙丘X'));
    }
    return NavigationActionPolicy.CANCEL;
  }

  Future<void> _launchExternal(WebUri uri, {String? tip}) async {
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
      } else if (tip != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tip)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开外部应用')));
      }
    }
  }

  Future<GeolocationPermissionShowPromptResponse> _allowGeolocation(
    String origin,
  ) async {
    await ensureLocationPermission();
    // 严格对齐携程文档：callback.invoke(origin, true, false)。
    // Android 应用级权限由上面的系统弹窗控制，WebView origin 始终放行。
    return GeolocationPermissionShowPromptResponse(
      origin: origin,
      allow: true,
      retain: false,
    );
  }

  Future<PermissionResponse> _allowWebResources(
    PermissionRequest request,
  ) async {
    final cameraRequested =
        request.resources.contains(PermissionResourceType.CAMERA) ||
        request.resources.contains(
          PermissionResourceType.CAMERA_AND_MICROPHONE,
        );
    final microphoneRequested =
        request.resources.contains(PermissionResourceType.MICROPHONE) ||
        request.resources.contains(
          PermissionResourceType.CAMERA_AND_MICROPHONE,
        );
    final allowed =
        (!cameraRequested || await ensureCameraPermission()) &&
        (!microphoneRequested || await ensureMicrophonePermission());
    return PermissionResponse(
      resources: request.resources,
      action: allowed
          ? PermissionResponseAction.GRANT
          : PermissionResponseAction.DENY,
    );
  }

  String _friendlyError(Object error) {
    final text = '$error'.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    return text.isEmpty ? '携程商旅暂时无法打开，请稍后重试' : text;
  }

  @override
  Widget build(BuildContext context) {
    final content = kIsWeb ? _buildWebFallback() : _buildNativeBody();
    if (widget.embedded) {
      return Column(
        children: [
          _buildAppTopBar(),
          Expanded(child: content),
        ],
      );
    }
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(52 + topInset),
        child: _buildAppTopBar(),
      ),
      body: content,
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
                  '携程商旅',
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
                onPressed: _loading ? null : () => unawaited(_openCtrip()),
                icon: const Icon(Icons.refresh_rounded, size: 22),
                color: DunesColors.text2,
              ),
            ],
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
              source: ctripGeoDocumentStartScript,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              contentWorld: ContentWorld.PAGE,
            ),
          ]),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            geolocationEnabled: true,
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
              handlerName: ctripGeoHandlerName,
              callback: (arguments) {
                final options = arguments.isNotEmpty
                    ? arguments.first
                    : <String, dynamic>{};
                return _geo.handleCall(options);
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
          onLoadStop: (_, url) {
            if (!mounted || url?.scheme == 'about') return;
            setState(() {
              _loading = false;
              _pageReady = true;
            });
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
          onGeolocationPermissionsShowPrompt: (_, origin) =>
              _allowGeolocation(origin),
          onPermissionRequest: (_, request) => _allowWebResources(request),
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
                onPressed: () => unawaited(_openCtrip()),
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
