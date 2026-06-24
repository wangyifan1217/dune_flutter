import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../conversation/conversation_realtime_hub.dart';
import '../shell/dunes_toast.dart';
import 'auth_session.dart';

/// 检测账号是否已在其他设备登录（token 失效 / HTTP 401），并触发退出。
class AuthSessionGuard {
  AuthSessionGuard._();

  static final AuthSessionGuard instance = AuthSessionGuard._();

  AuthSession? _session;
  VoidCallback? _onRevoked;
  bool _revoking = false;
  bool _checking = false;
  DateTime? _lastCheck;
  DateTime? _lastActivityCheck;

  static const _activityDebounce = Duration(seconds: 2);
  static const _checkCooldown = Duration(seconds: 2);

  void bind({
    required AuthSession session,
    required VoidCallback onRevoked,
  }) {
    _session = session;
    _onRevoked = onRevoked;
    _revoking = false;
  }

  void unbind() {
    _session = null;
    _onRevoked = null;
    _revoking = false;
    _checking = false;
  }

  void inspectStatusCode(int statusCode) {
    if (statusCode == 401) {
      unawaited(revoke());
    }
  }

  void inspectResponse(http.Response response) {
    inspectStatusCode(response.statusCode);
  }

  Future<void> checkOnUserActivity() async {
    if (_revoking || _session == null) return;
    final now = DateTime.now();
    if (_lastActivityCheck != null &&
        now.difference(_lastActivityCheck!) < _activityDebounce) {
      return;
    }
    _lastActivityCheck = now;
    await checkNow();
  }

  Future<void> checkNow() async {
    if (_revoking || _checking || _session == null) return;
    final now = DateTime.now();
    if (_lastCheck != null && now.difference(_lastCheck!) < _checkCooldown) {
      return;
    }
    final session = _session!;
    _checking = true;
    _lastCheck = now;
    try {
      final resp = await http.get(
        Uri.parse('${session.apiBase}/users/me'),
        headers: <String, String>{
          'Authorization': 'Bearer ${session.token}',
          'Accept': 'application/json',
        },
      );
      inspectStatusCode(resp.statusCode);
    } catch (_) {
      // 网络异常不强制退出。
    } finally {
      _checking = false;
    }
  }

  Future<void> revoke({String? message}) async {
    if (_revoking) return;
    _revoking = true;
    final callback = _onRevoked;
    unbind();
    await ConversationRealtimeHub.instance.dispose();
    callback?.call();
  }
}

/// 包裹主壳：用户点击任意处 + 定时轮询 + 回到前台时校验会话。
class AuthSessionGuardScope extends StatefulWidget {
  const AuthSessionGuardScope({
    super.key,
    required this.session,
    required this.onSessionRevoked,
    required this.child,
    this.revokedMessage = '账号已在其他设备登录，请重新登录',
  });

  final AuthSession session;
  final VoidCallback onSessionRevoked;
  final Widget child;
  final String revokedMessage;

  @override
  State<AuthSessionGuardScope> createState() => _AuthSessionGuardScopeState();
}

class _AuthSessionGuardScopeState extends State<AuthSessionGuardScope>
    with WidgetsBindingObserver {
  Timer? _periodicTimer;
  bool _revoked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindGuard();
    _periodicTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(AuthSessionGuard.instance.checkNow());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(AuthSessionGuard.instance.checkNow());
    });
  }

  @override
  void didUpdateWidget(covariant AuthSessionGuardScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.token != widget.session.token ||
        oldWidget.session.userId != widget.session.userId) {
      _revoked = false;
      _bindGuard();
    }
  }

  void _bindGuard() {
    AuthSessionGuard.instance.bind(
      session: widget.session,
      onRevoked: _handleRevoked,
    );
  }

  void _handleRevoked() {
    if (_revoked || !mounted) return;
    _revoked = true;
    showDunesToast(
      context,
      widget.revokedMessage,
      kind: DunesToastKind.error,
      duration: const Duration(milliseconds: 3200),
    );
    widget.onSessionRevoked();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(AuthSessionGuard.instance.checkNow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicTimer?.cancel();
    AuthSessionGuard.instance.unbind();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        unawaited(AuthSessionGuard.instance.checkOnUserActivity());
      },
      child: widget.child,
    );
  }
}
