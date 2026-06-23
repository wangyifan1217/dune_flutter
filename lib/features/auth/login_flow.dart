import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/dunes_defaults.dart';
import '../../core/theme/dunes_theme.dart';
import '../nova/nova_auth_service.dart';
import '../nova/nova_web_storage.dart';
import '../shell/dunes_shell.dart';
import 'auth_service.dart';
import 'auth_session.dart';

const _authBlue = Color(0xFF1A6FDB);
const _authBlueDeep = Color(0xFF0D4A9E);
const _authBg = Color(0xFFF7F8FA);
const _authSurface = Colors.white;

class LoginFlow extends StatefulWidget {
  const LoginFlow({super.key});

  @override
  State<LoginFlow> createState() => _LoginFlowState();
}

class _LoginFlowState extends State<LoginFlow> {
  static const _sessionStorageKey = 'dunes_auth_session_v1';
  final _auth = AuthService();
  AuthSession? _session;
  bool _hydrating = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  void _onSignedIn(AuthSession session) {
    setState(() => _session = session);
    _persistSession(session);
  }

  void _onSignedOut() {
    final uid = _session?.userId ?? 0;
    setState(() => _session = null);
    _clearSession(userId: uid);
  }

  Future<void> _restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionStorageKey);
      if (raw == null || raw.isEmpty) {
        if (mounted) setState(() => _hydrating = false);
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        if (mounted) setState(() => _hydrating = false);
        return;
      }
      var session = AuthSession.fromJson(decoded);
      final normalized = _normalizeApiHost(session);
      if (normalized.apiBase != session.apiBase) {
        session = normalized;
        await _persistSession(session);
      }
      if (session.token.isNotEmpty) {
        try {
          final resp = await http.get(
            Uri.parse('${session.apiBase}/users/me'),
            headers: {'Authorization': 'Bearer ${session.token}'},
          );
          if (resp.statusCode == 401) {
            await _clearSession(userId: session.userId);
            if (mounted) setState(() => _hydrating = false);
            return;
          }
        } catch (_) {}
        if (mounted) {
          setState(() {
            _session = session;
            _hydrating = false;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _hydrating = false);
  }

  AuthSession _normalizeApiHost(AuthSession session) {
    final expected = DunesDefaults.resolveGatewayHost();
    if (expected.isEmpty || session.apiBase.isEmpty) return session;
    final uri = Uri.tryParse(session.apiBase);
    if (uri == null || uri.host == expected) return session;
    return AuthSession(
      phone: session.phone,
      userId: session.userId,
      token: session.token,
      apiBase: DunesDefaults.apiBase,
      roles: session.roles,
      displayName: session.displayName,
      departmentId: session.departmentId,
      novaLocalStorage: session.novaLocalStorage,
    );
  }

  Future<void> _persistSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionStorageKey, jsonEncode(session.toJson()));
  }

  Future<void> _clearSession({int userId = 0}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionStorageKey);
    if (userId > 0) {
      await NovaWebStorage.clear(userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hydrating) {
      return const Scaffold(
        backgroundColor: _authBg,
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _authBlue,
          ),
        ),
      );
    }
    final session = _session;
    if (session != null) {
      return DunesShell(
        session: session,
        initialScreen: session.landingScreen,
        onLogout: _onSignedOut,
      );
    }
    return _PhoneStep(auth: _auth, onSignedIn: _onSignedIn);
  }
}

class _PhoneStep extends StatefulWidget {
  const _PhoneStep({required this.auth, required this.onSignedIn});

  final AuthService auth;
  final ValueChanged<AuthSession> onSignedIn;

  @override
  State<_PhoneStep> createState() => _PhoneStepState();
}

class _PhoneStepState extends State<_PhoneStep> {
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
    widget.auth.requestSmsCode(phone: phone).then((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _CodeStep(
            auth: widget.auth,
            phone: phone,
            onSignedIn: widget.onSignedIn,
          ),
        ),
      );
    }).catchError((e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AppLogo(size: 88),
          const SizedBox(height: 20),
          Text(
            '沙丘',
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: DunesColors.text,
              letterSpacing: -0.02 * 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '企业协作 · 审批 · 通讯',
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 14,
              color: DunesColors.text3,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          Text(
            '手机号登录',
            style: DunesTypography.sans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            autofocus: true,
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
            decoration: _inputDecoration(
              hintText: '请输入手机号',
              errorText: _error,
            ).copyWith(
              prefixIcon: const _PhonePrefix(),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              contentPadding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _next(),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _next,
              style: _authPrimaryButtonStyle,
              child: const Text('获取验证码'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeStep extends StatefulWidget {
  const _CodeStep({
    required this.auth,
    required this.phone,
    required this.onSignedIn,
  });

  final AuthService auth;
  final String phone;
  final ValueChanged<AuthSession> onSignedIn;

  @override
  State<_CodeStep> createState() => _CodeStepState();
}

class _CodeStepState extends State<_CodeStep> {
  static const _codeLen = 6;

  final _digits = List.generate(_codeLen, (_) => TextEditingController());
  final _nodes = List.generate(_codeLen, (_) => FocusNode());
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _digits) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _code => _digits.map((c) => c.text).join();

  Future<void> _trySubmit() async {
    if (_loading || _code.length != _codeLen) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var session = await widget.auth.signInWithSmsCode(
        phone: widget.phone,
        code: _code,
      );
      try {
        final nova = await NovaAuthService().provisionAfterLogin(
          apiBase: session.apiBase,
          dunesToken: session.token,
          phone: session.phone,
        );
        session = AuthSession(
          phone: session.phone,
          userId: session.userId,
          token: session.token,
          apiBase: session.apiBase,
          roles: session.roles,
          displayName: session.displayName,
          departmentId: session.departmentId,
          novaLocalStorage: nova.toLocalStorageEntries(),
        );
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      widget.onSignedIn(session);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '登录失败，请确认网关 ${widget.auth.apiBase} 可访问');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged(int index, String value) {
    if (value.length > 1) {
      final chars = value.replaceAll(RegExp(r'\D'), '').split('');
      for (var i = 0; i < _digits.length; i++) {
        _digits[i].text = i < chars.length ? chars[i] : '';
      }
      _nodes[(chars.length.clamp(1, _codeLen) - 1).toInt()].requestFocus();
    } else if (value.isNotEmpty && index < _nodes.length - 1) {
      _nodes[index + 1].requestFocus();
    }
    if (_error != null) setState(() => _error = null);
    _trySubmit();
  }

  @override
  Widget build(BuildContext context) {
    final maskedPhone = widget.phone.replaceRange(3, 7, '****');

    return _AuthScaffold(
      showLogo: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _BackButton(onPressed: () => Navigator.of(context).pop()),
          ),
          const SizedBox(height: 12),
          const _AppLogo(size: 64),
          const SizedBox(height: 24),
          Text(
            '输入验证码',
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '验证码已发送至 +86 $maskedPhone',
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 14,
              color: DunesColors.text3,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 36),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < _codeLen; i++)
                _CodeBox(
                  controller: _digits[i],
                  focusNode: _nodes[i],
                  onChanged: (v) => _onChanged(i, v),
                ),
            ],
          ),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _loading
                ? const LinearProgressIndicator(
                    minHeight: 2,
                    color: _authBlue,
                    backgroundColor: Color(0xFFE8EDF5),
                  )
                : _error == null
                    ? Text(
                        '开发环境固定验证码：66666',
                        key: const ValueKey('hint'),
                        textAlign: TextAlign.center,
                        style: DunesTypography.sans(
                          fontSize: 12,
                          color: DunesColors.text3,
                          height: 1.5,
                        ),
                      )
                    : Text(
                        _error!,
                        key: const ValueKey('error'),
                        textAlign: TextAlign.center,
                        style: DunesTypography.sans(
                          fontSize: 13,
                          color: DunesColors.coral,
                          height: 1.5,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _PhonePrefix extends StatelessWidget {
  const _PhonePrefix();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+86',
            style: DunesTypography.sans(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 1,
            height: 22,
            color: const Color(0xFFE8ECF2),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _AppLogo extends StatelessWidget {
  const _AppLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _authSurface,
          boxShadow: [
            BoxShadow(
              color: _authBlue.withValues(alpha: 0.18),
              blurRadius: size * 0.28,
              offset: Offset(0, size * 0.08),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          'assets/images/app_logo.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: const Color(0xFFE8F0FE),
            alignment: Alignment.center,
            child: Icon(
              Icons.terrain_rounded,
              size: size * 0.44,
              color: _authBlue,
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 56,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(1),
        ],
        style: DunesTypography.sans(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: DunesColors.text,
        ),
        decoration: _inputDecoration().copyWith(
          counterText: '',
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: _authSurface,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.child,
    this.showLogo = true,
  });

  final Widget child;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _authBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(32, showLogo ? 48 : 24, 32, 24 + bottomInset),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: _authSurface,
        foregroundColor: DunesColors.text,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        side: const BorderSide(color: Color(0xFFE8ECF2)),
      ),
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
    );
  }
}

final ButtonStyle _authPrimaryButtonStyle = FilledButton.styleFrom(
  backgroundColor: _authBlue,
  foregroundColor: Colors.white,
  disabledBackgroundColor: _authBlue.withValues(alpha: 0.45),
  elevation: 0,
  textStyle: DunesTypography.sans(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.01 * 16,
  ),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  ),
).copyWith(
  overlayColor: WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.pressed)) {
      return _authBlueDeep.withValues(alpha: 0.12);
    }
    return null;
  }),
);

InputDecoration _inputDecoration({
  String? hintText,
  String? errorText,
}) {
  return InputDecoration(
    hintText: hintText,
    errorText: errorText,
    hintStyle: DunesTypography.sans(
      fontSize: 16,
      color: DunesColors.text3,
    ),
    filled: true,
    fillColor: _authSurface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE8ECF2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE8ECF2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _authBlue, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: DunesColors.coral),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: DunesColors.coral, width: 1.5),
    ),
  );
}
