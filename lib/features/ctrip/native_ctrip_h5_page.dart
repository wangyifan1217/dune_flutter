import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../tasks/native_task_home_pane.dart';
import 'ctrip_h5_browser.dart';
import 'ctrip_h5_service.dart';

const _ctripBlue = Color(0xFF1668E8);
const _ctripTeal = Color(0xFF0F8B96);

/// 携程商旅 H5 单点登录页。
///
/// 携程要求通过 POST Form 提交一次性 Token，且不支持 iframe/AJAX，
/// 所以这里只在 APP WebView 中提交表单，不把 AppSecurity 放到客户端。
class NativeCtripH5Page extends StatefulWidget {
  const NativeCtripH5Page({
    super.key,
    required this.session,
    this.embedded = false,
    this.onBack,
    this.onChromeChanged,
  });

  final AuthSession session;
  final bool embedded;
  final VoidCallback? onBack;
  final ValueChanged<TaskShellChrome>? onChromeChanged;

  @override
  State<NativeCtripH5Page> createState() => _NativeCtripH5PageState();
}

class _NativeCtripH5PageState extends State<NativeCtripH5Page> {
  late final CtripH5Service _service = CtripH5Service(widget.session);
  WebViewController? _controller;
  CtripH5Form? _form;
  String? _error;
  bool _loading = true;
  bool _canGoBack = false;
  String _initPage = 'Home';

  static const _pages = <MapEntry<String, String>>[
    MapEntry('Home', '首页'),
    MapEntry('FlightSearch', '机票'),
    MapEntry('HotelSearch', '酒店'),
    MapEntry('TrainSearch', '火车票'),
    MapEntry('CarSearch', '用车'),
    MapEntry('MyOrder', '我的订单'),
  ];

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: _onNavigationRequest,
            onPageStarted: (_) {
              if (mounted) setState(() => _loading = true);
            },
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
              unawaited(_updateCanGoBack());
            },
            onWebResourceError: (error) {
              if (!mounted) return;
              setState(() {
                _loading = false;
                _form = null;
                _error = error.description.isEmpty
                    ? '携程页面加载失败'
                    : error.description;
              });
            },
          ),
        );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _publishChrome();
        unawaited(_loadForm());
      }
    });
  }

  @override
  void dispose() {
    widget.onChromeChanged?.call(const TaskShellChrome());
    super.dispose();
  }

  void _publishChrome() {
    if (!mounted) return;
    widget.onChromeChanged?.call(
      TaskShellChrome(
        onBack: _canGoBack ? _goBack : null,
        trailing: IconButton(
          tooltip: '刷新携程商旅',
          onPressed: _loading ? null : () => unawaited(_loadForm()),
          icon: const Icon(Icons.refresh_rounded, size: 20),
          color: DunesColors.text2,
        ),
      ),
    );
  }

  Future<void> _loadForm() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _form = null;
      });
    }
    try {
      final form = await _service.fetchForm(initPage: _initPage);
      if (!mounted) return;
      setState(() {
        _form = form;
        _loading = false;
      });
      if (kIsWeb) {
        await _openBrowserForm(form);
      } else {
        await _submitForm(form);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _form = null;
        _error = _friendlyError(error);
      });
    }
    _publishChrome();
  }

  Future<void> _openBrowserForm(CtripH5Form form) async {
    final opened = await openCtripH5InBrowser(form);
    if (!opened && mounted) {
      setState(() {
        _error = '当前浏览器无法打开携程页面，请点击下方按钮重试';
      });
    }
  }

  Future<void> _submitForm(CtripH5Form form) async {
    final controller = _controller;
    if (controller == null || form.action.isEmpty) return;
    final encoded = Uri(queryParameters: form.fields).query;
    await controller.loadRequest(
      Uri.parse(form.action),
      method: LoadRequestMethod.post,
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Referer': 'https://secure.ctrip.com',
      },
      body: Uint8List.fromList(utf8.encode(encoded)),
    );
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.navigate;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'alipay' || scheme == 'alipays' || scheme == 'weixin') {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _updateCanGoBack() async {
    final controller = _controller;
    if (controller == null) return;
    final value = await controller.canGoBack();
    if (!mounted || value == _canGoBack) return;
    setState(() => _canGoBack = value);
    _publishChrome();
  }

  Future<void> _goBack() async {
    final controller = _controller;
    if (controller == null || !await controller.canGoBack()) return;
    await controller.goBack();
    await _updateCanGoBack();
  }

  String _friendlyError(Object error) {
    final text = '$error'.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    return text.isEmpty ? '携程商旅暂时无法打开，请稍后重试' : text;
  }

  @override
  Widget build(BuildContext context) {
    final content = _form != null && !kIsWeb && _controller != null
        ? _buildWebView()
        : _buildLanding();
    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('携程商旅'),
        leading: widget.onBack == null
            ? null
            : IconButton(
                tooltip: '返回',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : () => unawaited(_loadForm()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildWebView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _controller!),
        if (_loading)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Widget _buildLanding() {
    final hasForm = _form != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_ctripBlue, _ctripTeal],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _ctripBlue.withValues(alpha: 0.2),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.flight_takeoff_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '携程商旅',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '企业差旅，一站式预订与管理',
                        style: TextStyle(
                          color: Color(0xD9FFFFFF),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['机票', '酒店', '火车票', '用车']
                    .map(
                      (item) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          item,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5EAF2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '打开页面',
                style: TextStyle(
                  color: DunesColors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _initPage,
                decoration: const InputDecoration(
                  labelText: '登录后的默认页面',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _pages
                    .map(
                      (entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _loading
                    ? null
                    : (value) {
                        if (value == null || value == _initPage) return;
                        setState(() => _initPage = value);
                        unawaited(_loadForm());
                      },
              ),
              const SizedBox(height: 16),
              if (_loading) ...[
                const LinearProgressIndicator(minHeight: 3),
                const SizedBox(height: 10),
                Text(
                  hasForm ? '已获取登录表单，正在打开携程…' : '正在获取安全登录凭证…',
                  style: const TextStyle(color: DunesColors.text2, fontSize: 13),
                ),
              ] else if (_error != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFFE38B24),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: DunesColors.text2,
                          height: 1.45,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => unawaited(_loadForm()),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('重新获取'),
                  ),
                ),
              ] else if (kIsWeb && hasForm) ...[
                const Text(
                  '登录凭证已生成，正在通过携程支持的 SsoData 方式打开浏览器页面。',
                  style: TextStyle(
                    color: DunesColors.text2,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _form == null
                        ? null
                        : () => unawaited(_openBrowserForm(_form!)),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('打开携程页面'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _CtripInfoCard(
          icon: Icons.verified_user_outlined,
          title: '企业账号免登',
          body: '登录凭证由服务端临时生成，App 不保存携程 AppSecurity。',
        ),
        const SizedBox(height: 10),
        const _CtripInfoCard(
          icon: Icons.open_in_new_rounded,
          title: '原生 H5 体验',
          body: '机票、酒店、火车票和用车页面在 App 内连续打开，支付时可唤起对应客户端。',
        ),
      ],
    );
  }
}

class _CtripInfoCard extends StatelessWidget {
  const _CtripInfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _ctripBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _ctripBlue, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: DunesColors.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: DunesColors.text3,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
