import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../tasks/native_task_home_pane.dart';
import 'xrxs_service.dart';

/// 桌面端薪人薪事 PC 免登入口：取一次性 URL 后在系统浏览器打开。
class NativeXrxsPCPage extends StatefulWidget {
  const NativeXrxsPCPage({
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
  final String? loginSid;
  final String? loginRole;

  @override
  State<NativeXrxsPCPage> createState() => _NativeXrxsPCPageState();
}

class _NativeXrxsPCPageState extends State<NativeXrxsPCPage> {
  late final XrxsService _service = XrxsService(widget.session);

  String? _error;
  bool _loading = true;
  bool _opened = false;
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
      unawaited(_openXrxs());
    });
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
          tooltip: '重新打开薪人薪事',
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
        _opened = false;
      });
    }
    try {
      final login = await _service.fetchPcLoginUrl(
        sid: widget.loginSid,
        role: widget.loginRole,
      );
      if (!mounted) return;
      final opened = await _service.openInSystemBrowser(login);
      if (!mounted) return;
      if (!opened) {
        setState(() {
          _loading = false;
          _error = '无法打开系统浏览器，请检查默认浏览器设置后重试';
        });
        return;
      }
      setState(() {
        _loading = false;
        _opened = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _opened = false;
        _error = _friendlyError(error);
      });
    } finally {
      _submitting = false;
      _publishChrome();
    }
  }

  String _friendlyError(Object error) {
    final text = '$error'.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    return text.isEmpty ? '薪人薪事暂时无法打开，请稍后重试' : text;
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(52 + topInset),
        child: _buildAppTopBar(),
      ),
      body: _buildBody(),
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
                  '返回',
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
                tooltip: '重新打开',
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

  Widget _buildBody() {
    if (_loading) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    if (_error != null) {
      return _buildMessage(
        icon: Icons.info_outline_rounded,
        iconColor: const Color(0xFFE38B24),
        message: _error!,
        actionLabel: '重新打开',
      );
    }
    if (_opened) {
      return _buildMessage(
        icon: Icons.open_in_browser_rounded,
        iconColor: DunesColors.accentDeep,
        message: '已在系统浏览器中打开薪人薪事 PC 员工端。\n办理完成后可关闭浏览器标签，返回沙丘继续工作。',
        actionLabel: '再次打开',
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildMessage({
    required IconData icon,
    required Color iconColor,
    required String message,
    required String actionLabel,
  }) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 40),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 14,
                  height: 1.5,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => unawaited(_openXrxs()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
