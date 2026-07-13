import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/dunes_theme.dart';
import '../nova/nova_auth_service.dart';
import 'auth_flow_ui.dart';
import 'auth_profile.dart';
import 'auth_service.dart';
import 'auth_session.dart';

/// 桌面端登录：手机号短信 或 App 扫码（对齐 admin-web PC 工作台）。
class DesktopLoginPage extends StatefulWidget {
  const DesktopLoginPage({
    super.key,
    required this.auth,
    required this.onSignedIn,
  });

  final AuthService auth;
  final ValueChanged<AuthSession> onSignedIn;

  @override
  State<DesktopLoginPage> createState() => _DesktopLoginPageState();
}

class _DesktopLoginPageState extends State<DesktopLoginPage> {
  /// sms | qr
  String _mode = 'qr';

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthAppLogo(size: 72),
          const SizedBox(height: 16),
          Text(
            '沙丘 · 桌面端',
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: DunesColors.text,
              letterSpacing: -0.02 * 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '使用手机号或 App 扫码登录',
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 14,
              color: DunesColors.text3,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          _ModeTabs(
            mode: _mode,
            onChanged: (m) => setState(() => _mode = m),
          ),
          const SizedBox(height: 24),
          if (_mode == 'qr')
            _DesktopQrLoginPane(
              auth: widget.auth,
              onSignedIn: widget.onSignedIn,
            )
          else
            _DesktopSmsLoginPane(
              auth: widget.auth,
              onSignedIn: widget.onSignedIn,
            ),
        ],
      ),
    );
  }
}

class _ModeTabs extends StatelessWidget {
  const _ModeTabs({required this.mode, required this.onChanged});

  final String mode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String id, String label) {
      final selected = mode == id;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(id),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF1A6FDB) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: DunesTypography.sans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : DunesColors.text2,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EEE8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          tab('qr', 'App 扫码登录'),
          tab('sms', '手机号登录'),
        ],
      ),
    );
  }
}

class _DesktopSmsLoginPane extends StatefulWidget {
  const _DesktopSmsLoginPane({
    required this.auth,
    required this.onSignedIn,
  });

  final AuthService auth;
  final ValueChanged<AuthSession> onSignedIn;

  @override
  State<_DesktopSmsLoginPane> createState() => _DesktopSmsLoginPaneState();
}

class _DesktopSmsLoginPaneState extends State<_DesktopSmsLoginPane> {
  final _phone = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _next() {
    final phone = _phone.text.trim();
    if (!RegExp(r'^\d{11}$').hasMatch(phone)) {
      setState(() => _error = '请输入 11 位手机号');
      return;
    }
    widget.auth
        .requestSmsCode(phone: phone)
        .then((_) {
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _DesktopCodeStep(
                auth: widget.auth,
                phone: phone,
                onSignedIn: widget.onSignedIn,
              ),
            ),
          );
        })
        .catchError((e) {
          if (!mounted) return;
          setState(() {
            _error = e is AuthException
                ? e.message
                : '网络异常，请确认网关 ${widget.auth.apiBase} 可访问';
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          style: DunesTypography.sans(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: DunesColors.text,
            letterSpacing: 1.2,
          ),
          decoration: authInputDecoration(hintText: '请输入手机号', errorText: _error)
              .copyWith(
                prefixIcon: const AuthPhonePrefix(),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 0,
                  minHeight: 0,
                ),
                contentPadding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
              ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _next(),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _next,
            style: authPrimaryButtonStyle,
            child: const Text('获取验证码'),
          ),
        ),
      ],
    );
  }
}

class _DesktopCodeStep extends StatefulWidget {
  const _DesktopCodeStep({
    required this.auth,
    required this.phone,
    required this.onSignedIn,
  });

  final AuthService auth;
  final String phone;
  final ValueChanged<AuthSession> onSignedIn;

  @override
  State<_DesktopCodeStep> createState() => _DesktopCodeStepState();
}

class _DesktopCodeStepState extends State<_DesktopCodeStep> {
  static const _codeLen = 6;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onCodeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onCodeChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    if (!mounted) return;
    setState(() {
      if (_error != null) _error = null;
    });
    if (_controller.text.length == _codeLen) unawaited(_trySubmit());
  }

  Future<void> _trySubmit() async {
    if (_loading || _controller.text.length != _codeLen) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var session = await widget.auth.signInWithSmsCode(
        phone: widget.phone,
        code: _controller.text,
      );
      session = await _finalizeDesktopSession(session);
      if (!mounted) return;
      widget.onSignedIn(session);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '登录失败，请确认网关 ${widget.auth.apiBase} 可访问');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthCodeEntryLayout(
      phone: widget.phone,
      loading: _loading,
      error: _error,
      onBack: () => Navigator.of(context).pop(),
      codeInput: AuthCodeInput(
        length: _codeLen,
        controller: _controller,
        focusNode: _focus,
        hasError: _error != null,
        onSubmitted: _trySubmit,
      ),
    );
  }
}

class _DesktopQrLoginPane extends StatefulWidget {
  const _DesktopQrLoginPane({
    required this.auth,
    required this.onSignedIn,
  });

  final AuthService auth;
  final ValueChanged<AuthSession> onSignedIn;

  @override
  State<_DesktopQrLoginPane> createState() => _DesktopQrLoginPaneState();
}

class _DesktopQrLoginPaneState extends State<_DesktopQrLoginPane> {
  AuthQrSession? _session;
  String _statusText = '正在生成二维码…';
  String _uiState = 'loading'; // loading|waiting|confirming|expired|error
  int _countdown = 0;
  bool _claiming = false;
  Timer? _pollTimer;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_createSession());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _createSession() async {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    setState(() {
      _session = null;
      _claiming = false;
      _uiState = 'loading';
      _statusText = '正在生成二维码…';
      _countdown = 0;
    });
    try {
      final session = await widget.auth.createQrLoginSession();
      if (!mounted) return;
      setState(() {
        _session = session;
        _countdown = session.ttlSeconds;
        _uiState = 'waiting';
        _statusText = '请使用手机 App「我的」页扫码登录';
      });
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 1800),
        (_) => unawaited(_poll()),
      );
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_countdown <= 1) {
          setState(() {
            _countdown = 0;
            _uiState = 'expired';
            _statusText = '二维码已过期，请刷新';
          });
          _pollTimer?.cancel();
          _tickTimer?.cancel();
          return;
        }
        setState(() => _countdown -= 1);
      });
      unawaited(_poll());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uiState = 'error';
        _statusText = e is AuthException ? e.message : '二维码生成失败';
      });
    }
  }

  Future<void> _poll() async {
    final session = _session;
    if (session == null || _claiming) return;
    if (_uiState == 'expired' || _uiState == 'error') return;
    try {
      final status = await widget.auth.pollQrLoginStatus(
        sessionId: session.sessionId,
        clientSecret: session.clientSecret,
      );
      if (!mounted) return;
      if (status.isConfirmed) {
        _claiming = true;
        _pollTimer?.cancel();
        _tickTimer?.cancel();
        setState(() {
          _uiState = 'confirming';
          _statusText = (status.confirmedUserName?.isNotEmpty ?? false)
              ? '已由 ${status.confirmedUserName} 扫码，正在登录…'
              : '扫码确认成功，正在登录…';
        });
        var authSession = await widget.auth.signInWithQrToken(
          sessionId: session.sessionId,
          clientSecret: session.clientSecret,
        );
        authSession = await _finalizeDesktopSession(authSession);
        if (!mounted) return;
        widget.onSignedIn(authSession);
        return;
      }
      if (status.isExpired) {
        _pollTimer?.cancel();
        _tickTimer?.cancel();
        setState(() {
          _uiState = 'expired';
          _statusText = '二维码已过期，请刷新';
        });
        return;
      }
      setState(() {
        _uiState = 'waiting';
        _statusText = '等待 App 扫码确认…';
      });
    } catch (e) {
      if (!mounted || _claiming) return;
      final msg = e is AuthException ? e.message : '';
      if (msg.contains('过期') || msg.contains('失效') || msg.contains('不存在')) {
        _pollTimer?.cancel();
        _tickTimer?.cancel();
        setState(() {
          _uiState = 'expired';
          _statusText = '二维码已失效，请刷新';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrPayload = _session?.qrCode ?? '';
    final showQr = qrPayload.isNotEmpty &&
        (_uiState == 'waiting' || _uiState == 'confirming');

    return Column(
      children: [
        Container(
          width: 220,
          height: 220,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE8E4DC)),
          ),
          child: showQr
              ? QrImageView(
                  data: qrPayload,
                  version: QrVersions.auto,
                  size: 196,
                  backgroundColor: Colors.white,
                )
              : (_uiState == 'loading'
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.qr_code_2_rounded,
                      size: 64,
                      color: DunesColors.text3,
                    )),
        ),
        const SizedBox(height: 16),
        Text(
          _statusText,
          textAlign: TextAlign.center,
          style: DunesTypography.sans(
            fontSize: 13,
            color: DunesColors.text2,
            height: 1.45,
          ),
        ),
        if (_countdown > 0 && _uiState == 'waiting') ...[
          const SizedBox(height: 6),
          Text(
            '$_countdown 秒后过期',
            style: DunesTypography.sans(
              fontSize: 12,
              color: DunesColors.text3,
            ),
          ),
        ],
        if (_uiState == 'expired' || _uiState == 'error') ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _createSession,
              child: const Text('刷新二维码'),
            ),
          ),
        ],
      ],
    );
  }
}

Future<AuthSession> _finalizeDesktopSession(AuthSession session) async {
  session = await enrichSessionFromUsersMe(session);
  if (!session.isExternalUser) {
    try {
      final nova = await NovaAuthService().provisionAfterLogin(
        apiBase: session.apiBase,
        dunesToken: session.token,
        phone: session.phone,
      );
      session = session.copyWith(novaLocalStorage: nova.toLocalStorageEntries());
    } catch (_) {}
  }
  return session;
}
