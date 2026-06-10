import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/dunes_theme.dart';
import '../shell/dunes_shell.dart';
import 'auth_service.dart';
import 'auth_session.dart';

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
    setState(() => _session = null);
    _clearSession();
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
      final session = AuthSession.fromJson(decoded);
      if (session.token.isNotEmpty && mounted) {
        setState(() {
          _session = session;
          _hydrating = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _hydrating = false);
  }

  Future<void> _persistSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionStorageKey, jsonEncode(session.toJson()));
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionStorageKey);
  }

  @override
  Widget build(BuildContext context) {
    if (_hydrating) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandHeader(
            kicker: 'DUNES · Unified Auth',
            title: '手机号登录',
            subtitle: '一个账号进入沙丘 App，统一 JWT 贯穿通讯、审批、知识库、汇报和会议纪要。',
          ),
          const SizedBox(height: 34),
          Text('手机号', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            autofocus: true,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
            decoration: _inputDecoration(
              hintText: '请输入手机号',
              errorText: _error,
              prefixText: '+86 ',
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _next(),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _next,
              style: FilledButton.styleFrom(
                backgroundColor: DunesColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: const Text('获取验证码'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '请使用名册中的真实手机号；开发环境验证码为 66666。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DunesColors.text3,
                  height: 1.5,
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
  static const _codeLen = 5;
  static const _devCode = '66666';

  final _digits = List.generate(_codeLen, (_) => TextEditingController());
  final _nodes = List.generate(_codeLen, (_) => FocusNode());
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _codeLen; i++) {
      _digits[i].text = _devCode[i];
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trySubmit();
    });
  }

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
      final session = await widget.auth.signInWithSmsCode(
        phone: widget.phone,
        code: _code,
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      widget.onSignedIn(session);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '登录失败，请确认网关 ${widget.auth.apiBase} 可访问');
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
    return _AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BackButton(onPressed: () => Navigator.of(context).pop()),
          const SizedBox(height: 18),
          _BrandHeader(
            kicker: 'SMS Verification',
            title: '输入验证码',
            subtitle: '验证码已发送至 +86 ${widget.phone}。填满 5 位后自动登录。',
          ),
          const SizedBox(height: 34),
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
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _loading
                ? const LinearProgressIndicator(minHeight: 2)
                : _error == null
                    ? Text(
                        '开发环境固定验证码：66666',
                        key: const ValueKey('hint'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: DunesColors.text3,
                              height: 1.5,
                            ),
                      )
                    : Text(
                        _error!,
                        key: const ValueKey('error'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: DunesColors.text,
        ),
        decoration: _inputDecoration().copyWith(
          counterText: '',
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.stageBg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              decoration: BoxDecoration(
                color: DunesColors.bgApp,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: DunesColors.borderSoft),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F1F2421),
                    blurRadius: 42,
                    offset: Offset(0, 20),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({
    required this.kicker,
    required this.title,
    required this.subtitle,
  });

  final String kicker;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kicker.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: DunesColors.accent,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontSize: 32,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 10),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: DunesColors.bgSoft,
        foregroundColor: DunesColors.text,
      ),
      icon: const Icon(Icons.chevron_left_rounded),
    );
  }
}

InputDecoration _inputDecoration({
  String? hintText,
  String? errorText,
  String? prefixText,
}) {
  return InputDecoration(
    hintText: hintText,
    errorText: errorText,
    prefixText: prefixText,
    filled: true,
    fillColor: DunesColors.bgSoft,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: DunesColors.borderSoft),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: DunesColors.borderSoft),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: DunesColors.accent, width: 1.4),
    ),
  );
}
