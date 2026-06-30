import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/dunes_defaults.dart';
import '../../core/theme/dunes_theme.dart';
import '../nova/nova_auth_service.dart';
import '../nova/nova_web_storage.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../push/push_service.dart';
import '../shell/dunes_shell.dart';
import '../shell/splash_screen.dart';
import '../update/app_update_dialog.dart';
import '../update/app_update_service.dart';
import 'auth_service.dart';
import 'auth_profile.dart';
import 'auth_session.dart';

const _authBlue = Color(0xFF1A6FDB);
const _authBlueDeep = Color(0xFF0D4A9E);
const _authBg = Color(0xFFF7F8FA);
const _authSurface = Colors.white;

class LoginFlow extends StatefulWidget {
  const LoginFlow({super.key, this.onHydrated});

  /// 会话校验（hydration）完成后回调一次，供启屏门控决定关闭时机。
  final VoidCallback? onHydrated;

  @override
  State<LoginFlow> createState() => _LoginFlowState();
}

class _LoginFlowState extends State<LoginFlow> {
  static const _sessionStorageKey = 'dunes_auth_session_v1';
  final _auth = AuthService();
  AuthSession? _session;
  bool _hydrating = true;
  bool _notifiedHydrated = false;
  bool _updateChecked = false;
  bool _showPostLoginSplash = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _restoreSession();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version.trim());
    } catch (_) {}
  }

  void _onSignedIn(AuthSession session) {
    setState(() {
      _session = session;
      _showPostLoginSplash = true;
    });
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
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            final body = jsonDecode(resp.body);
            final data = body is Map<String, dynamic>
                ? (body['data'] is Map<String, dynamic>
                      ? body['data'] as Map<String, dynamic>
                      : body)
                : const <String, dynamic>{};
            session = AuthSession.enrichFromUsersMe(session, data);
            await _persistSession(session);
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
      lighthouseAccess: session.lighthouseAccess,
    );
  }

  Future<void> _persistSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionStorageKey, jsonEncode(session.toJson()));
  }

  Future<void> _clearSession({int userId = 0}) async {
    await ConversationRealtimeHub.instance.dispose();
    await unbindPushSession();
    syncPushBadgeCount(0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionStorageKey);
    if (userId > 0) {
      await NovaWebStorage.clear(userId);
    }
  }

  Future<void> _checkAppUpdate() async {
    if (_updateChecked || !mounted) return;
    _updateChecked = true;
    final result = await AppUpdateService.instance.checkAndroidUpdate();
    if (!mounted || result == null || !result.updateAvailable) return;
    await showAppUpdateDialog(context, result);
  }

  @override
  Widget build(BuildContext context) {
    if (!_hydrating && !_notifiedHydrated) {
      _notifiedHydrated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onHydrated?.call();
      });
    }
    if (!_hydrating && !_updateChecked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkAppUpdate());
    }
    if (_hydrating) {
      return const Scaffold(
        backgroundColor: _authBg,
        body: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: _authBlue),
        ),
      );
    }
    final session = _session;
    if (session != null) {
      return Stack(
        children: [
          DunesShell(
            session: session,
            initialScreen: session.landingScreen,
            onLogout: _onSignedOut,
          ),
          if (_showPostLoginSplash)
            PostLoginSplashOverlay(
              version: _appVersion,
              onDismiss: () {
                if (mounted) setState(() => _showPostLoginSplash = false);
              },
            ),
        ],
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
    widget.auth
        .requestSmsCode(phone: phone)
        .then((_) {
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
            decoration: _inputDecoration(hintText: '请输入手机号', errorText: _error)
                .copyWith(
                  prefixIcon: const _PhonePrefix(),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 0,
                    minHeight: 0,
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
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

  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onCodeChanged);
    _focus.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onCodeChanged);
    _focus.removeListener(_onFocusChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _code => _controller.text;

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onCodeChanged() {
    if (!mounted) return;
    setState(() {
      if (_error != null) _error = null;
    });
    if (_code.length == _codeLen) _trySubmit();
  }

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
      session = await enrichSessionFromUsersMe(session);
      if (!mounted) return;
      widget.onSignedIn(session);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
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
          _CodeInput(
            length: _codeLen,
            controller: _controller,
            focusNode: _focus,
            hasError: _error != null,
            onSubmitted: _trySubmit,
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
                : _error != null
                ? Text(
                    _error!,
                    key: const ValueKey('error'),
                    textAlign: TextAlign.center,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      color: DunesColors.coral,
                      height: 1.5,
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('idle')),
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
          Container(width: 1, height: 22, color: const Color(0xFFE8ECF2)),
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

/// 验证码输入：单个隐藏的真实输入框叠在 6 个展示格子之上。
/// 这样可原生支持复制、粘贴（一次粘贴 6 位自动铺满）以及 App 风格的删除回退。
class _CodeInput extends StatelessWidget {
  const _CodeInput({
    required this.length,
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.onSubmitted,
  });

  final int length;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final code = controller.text;
    final focused = focusNode.hasFocus;
    return Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < length; i++)
              _CodeBox(
                char: i < code.length ? code[i] : '',
                active: focused && i == code.length && code.length < length,
                hasError: hasError,
              ),
          ],
        ),
        Positioned.fill(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            showCursor: false,
            cursorColor: Colors.transparent,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            enableInteractiveSelection: true,
            autofillHints: const [AutofillHints.oneTimeCode],
            style: const TextStyle(
              color: Colors.transparent,
              fontSize: 24,
              height: 1.0,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(length),
            ],
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (_) => onSubmitted(),
          ),
        ),
      ],
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({
    required this.char,
    required this.active,
    required this.hasError,
  });

  final String char;
  final bool active;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = hasError
        ? DunesColors.coral
        : active
        ? _authBlue
        : const Color(0xFFE8ECF2);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 48,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _authSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: active || hasError ? 1.5 : 1,
        ),
      ),
      child: Text(
        char,
        style: DunesTypography.sans(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: DunesColors.text,
        ),
      ),
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.child, this.showLogo = true});

  final Widget child;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _authBg,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                32,
                showLogo ? 48 : 24,
                32,
                24 + bottomInset,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: child,
              ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: Color(0xFFE8ECF2)),
      ),
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
    );
  }
}

final ButtonStyle _authPrimaryButtonStyle =
    FilledButton.styleFrom(
      backgroundColor: _authBlue,
      foregroundColor: Colors.white,
      disabledBackgroundColor: _authBlue.withValues(alpha: 0.45),
      elevation: 0,
      textStyle: DunesTypography.sans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.01 * 16,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ).copyWith(
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return _authBlueDeep.withValues(alpha: 0.12);
        }
        return null;
      }),
    );

InputDecoration _inputDecoration({String? hintText, String? errorText}) {
  return InputDecoration(
    hintText: hintText,
    errorText: errorText,
    hintStyle: DunesTypography.sans(fontSize: 16, color: DunesColors.text3),
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
