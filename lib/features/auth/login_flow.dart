import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/dunes_defaults.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../desktop/windows_desktop_tray.dart';
import '../nova/nova_auth_service.dart';
import '../nova/nova_web_storage.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../push/push_service.dart';
import '../shell/dunes_shell.dart';
import '../shell/splash_screen.dart';
import '../update/app_update_dialog.dart';
import '../update/app_update_service.dart';
import 'auth_flow_ui.dart';
import 'auth_service.dart';
import 'auth_profile.dart';
import 'auth_session.dart';
import 'auth_session_coordinator.dart';
import 'desktop_login_page.dart';
const _authBlue = authBlue;
const _authBg = authBg;
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
    if (isDesktopCommOnly) {
      setWindowsTrayOnBeforeQuit(() async {
        final uid = _session?.userId ?? 0;
        AuthSessionCoordinator.instance.clear();
        if (mounted) setState(() => _session = null);
        await _clearSession(userId: uid);
      });
    }
    Future<void>.delayed(const Duration(seconds: 8), () {
      if (mounted && _hydrating) setState(() => _hydrating = false);
    });
  }

  @override
  void dispose() {
    if (isDesktopCommOnly) {
      setWindowsTrayOnBeforeQuit(null);
    }
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version.trim());
    } catch (_) {}
  }

  void _onSignedIn(AuthSession session) {
    session = session.withLocalDevGrants();
    if (session.userId <= 0) {
      session = AuthSession.fromJwt(
        phone: session.phone,
        userId: 0,
        token: session.token,
        apiBase: session.apiBase,
      ).copyWith(
        displayName: session.displayName,
        departmentId: session.departmentId,
        roles: session.roles,
        novaLocalStorage: session.novaLocalStorage,
        lighthouseAccess: session.lighthouseAccess,
      ).withLocalDevGrants();
    }
    AuthSessionCoordinator.instance.bind(
      session,
      onUpdated: _onSessionRefreshed,
    );
    setState(() {
      _session = session;
      // 已屏蔽登录后启屏，登录成功后直接进 IM。
      _showPostLoginSplash = false;
    });
    _persistSession(session);
  }

  void _onSessionRefreshed(AuthSession session) {
    if (!mounted) return;
    if (_session?.userId != null &&
        _session!.userId > 0 &&
        session.userId != _session!.userId) {
      return;
    }
    setState(() => _session = session);
    unawaited(_persistSession(session));
  }

  void _onSignedOut() {
    final uid = _session?.userId ?? 0;
    AuthSessionCoordinator.instance.clear();
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
      var session = AuthSession.fromJson(decoded).withLocalDevGrants();
      if (session.userId <= 0 && session.token.isNotEmpty) {
        session = AuthSession.fromJwt(
          phone: session.phone,
          userId: 0,
          token: session.token,
          apiBase: session.apiBase,
        ).copyWith(
          displayName: session.displayName,
          departmentId: session.departmentId,
          roles: session.roles,
          novaLocalStorage: session.novaLocalStorage,
          lighthouseAccess: session.lighthouseAccess,
        ).withLocalDevGrants();
      }
      final normalized = _normalizeApiHost(session);
      if (normalized.apiBase != session.apiBase) {
        session = normalized;
        await _persistSession(session);
      }
      if (session.token.isNotEmpty) {
        AuthSessionCoordinator.instance.bind(
          session,
          onUpdated: _onSessionRefreshed,
        );
        try {
          var resp = await http
              .get(
                Uri.parse('${session.apiBase}/users/me'),
                headers: {'Authorization': 'Bearer ${session.token}'},
              )
              .timeout(const Duration(seconds: 5));
          if (AuthSessionCoordinator.isRecoverable401(resp)) {
            final refreshed =
                await AuthSessionCoordinator.instance
                    .refreshToken()
                    .timeout(const Duration(seconds: 5));
            if (refreshed != null) {
              session = refreshed;
              resp = await http
                  .get(
                    Uri.parse('${session.apiBase}/users/me'),
                    headers: {'Authorization': 'Bearer ${session.token}'},
                  )
                  .timeout(const Duration(seconds: 5));
            }
          }
          if (resp.statusCode == 401) {
            await _clearSession(userId: session.userId);
            AuthSessionCoordinator.instance.clear();
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
            session = AuthSession.enrichFromUsersMe(session, data).withLocalDevGrants();
            AuthSessionCoordinator.instance.updateSession(session);
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
    AuthSession next = session;
    if (expected.isNotEmpty && session.apiBase.isNotEmpty) {
      final uri = Uri.tryParse(session.apiBase);
      if (uri != null && uri.host != expected) {
        next = AuthSession(
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
    }
    return next.withLocalDevGrants();
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
    final result = await AppUpdateService.instance.checkUpdate();
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
    return isDesktopCommOnly
        ? DesktopLoginPage(auth: _auth, onSignedIn: _onSignedIn)
        : _PhoneStep(auth: _auth, onSignedIn: _onSignedIn);
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
    return AuthScaffold(
      child: Column(        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthAppLogo(size: 88),
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
            decoration: authInputDecoration(hintText: '请输入手机号', errorText: _error)
                .copyWith(
                  prefixIcon: const AuthPhonePrefix(),                  prefixIconConstraints: const BoxConstraints(
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
              style: authPrimaryButtonStyle,
              child: const Text('获取验证码'),
            ),
          ),
          // 「扫码邀请注册」入口暂隐藏，需要时再打开。
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