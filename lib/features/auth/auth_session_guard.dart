import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../conversation/conversation_realtime_hub.dart';
import '../shell/dunes_toast.dart';
import 'auth_session.dart';
import 'auth_session_coordinator.dart';

/// 会话失效检测：资料/权限不会每秒变，禁止把带 JOIN 的 `/users/me` 当心跳。
///
/// 只在这些时机请求：
/// - 登录后进入主壳（首帧一次）
/// - 从后台回到前台
/// - 定时 45 秒（防踢下线；当前令牌收到「其他设备登录 / 账号已停用」时经 [inspectResponse] 踢出）
///
/// 上一次还没返回时不再发下一次，避免网关 ESTAB 堆积。
class AuthSessionGuard {
  AuthSessionGuard._();

  static final AuthSessionGuard instance = AuthSessionGuard._();

  AuthSession? _session;
  VoidCallback? _onRevoked;
  bool _revoking = false;
  bool _checking = false;

  static const _requestTimeout = Duration(seconds: 15);

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

  void inspectStatusCode(int statusCode, {http.Response? response}) {
    if (statusCode != 401 && statusCode != 403) return;
    if (response != null) {
      inspectResponse(response);
      return;
    }
    // 无 response 体时不直接踢下线，交给带 retry 的 HTTP 层处理。
  }

  void inspectResponse(http.Response response, {String? requestToken}) {
    if (response.statusCode != 401 && response.statusCode != 403) return;
    if (!_shouldRevokeForUnauthorized(response)) return;
    final sent = (requestToken ?? _bearerFrom(response) ?? '').trim();
    // 旧请求带的是已经换掉的令牌时，忽略这次 401，避免清掉刚登录写入的新令牌。
    if (!AuthSessionCoordinator.instance.tokenIsCurrent(sent)) return;
    final message = AuthSessionCoordinator.readApiMessage(response.body);
    unawaited(revoke(
      message: message.contains('账号已停用') ? '账号已停用，请联系管理员' : null,
    ));
  }

  /// 刷新接口对当前令牌回了下线文案时，走和业务 401 相同的清登录。
  void consumeRefreshLogout() {
    final message = AuthSessionCoordinator.instance.takeRefreshLogoutMessage();
    if (message == null) return;
    unawaited(revoke(
      message: message.contains('账号已停用') ? '账号已停用，请联系管理员' : null,
    ));
  }

  static String? _bearerFrom(http.Response response) {
    final headers = response.request?.headers;
    if (headers == null) return null;
    final raw = headers['authorization'] ?? headers['Authorization'];
    if (raw == null) return null;
    final trimmed = raw.trim();
    final lower = trimmed.toLowerCase();
    if (!lower.startsWith('bearer ')) return null;
    final token = trimmed.substring(7).trim();
    return token.isEmpty ? null : token;
  }

  bool _shouldRevokeForUnauthorized(http.Response response) {
    return AuthSessionCoordinator.shouldForceLogout(response);
  }

  Future<void> checkNow() async {
    if (_revoking || _checking || _session == null) return;
    var session = AuthSessionCoordinator.instance.resolve(_session!);
    _checking = true;
    try {
      var resp = await http
          .get(
            Uri.parse('${session.apiBase}/users/me'),
            headers: <String, String>{
              'Authorization': 'Bearer ${session.token}',
              'Accept': 'application/json',
            },
          )
          .timeout(_requestTimeout);
      var sentToken = session.token;
      if (AuthSessionCoordinator.isRecoverable401(resp) &&
          AuthSessionCoordinator.instance.tokenIsCurrent(sentToken)) {
        final refreshed = await AuthSessionCoordinator.instance.refreshToken();
        consumeRefreshLogout();
        if (refreshed != null &&
            AuthSessionCoordinator.instance.tokenIsCurrent(refreshed.token)) {
          session = refreshed;
          _session = refreshed;
          sentToken = refreshed.token;
          resp = await http
              .get(
                Uri.parse('${session.apiBase}/users/me'),
                headers: <String, String>{
                  'Authorization': 'Bearer $sentToken',
                  'Accept': 'application/json',
                },
              )
              .timeout(_requestTimeout);
        }
      }
      inspectResponse(resp, requestToken: sentToken);
    } catch (_) {
      // 超时、断网不强制退出。下一轮只认当前令牌的「其他设备登录 / 账号已停用」。
    } finally {
      _checking = false;
    }
  }

  String? _pendingRevokeMessage;

  /// 取出本次强制登出的提示文案（如「账号已停用」），默认文案由调用方兜底。
  String? consumePendingRevokeMessage() {
    final message = _pendingRevokeMessage;
    _pendingRevokeMessage = null;
    return message;
  }

  Future<void> revoke({String? message}) async {
    if (_revoking) return;
    _revoking = true;
    _pendingRevokeMessage = message;
    final callback = _onRevoked;
    unbind();
    AuthSessionCoordinator.instance.clear();
    await ConversationRealtimeHub.instance.dispose();
    callback?.call();
  }
}

/// 包裹主壳：登录后、回到前台、每 45 秒校验会话。不在点击时打 `/users/me`。
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
    _periodicTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(AuthSessionGuard.instance.checkNow());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bindGuard();
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
    AuthSessionCoordinator.instance.bind(
      widget.session,
      onUpdated: (_) {
        if (!mounted) return;
        AuthSessionGuard.instance.bind(
          session: AuthSessionCoordinator.instance.session ?? widget.session,
          onRevoked: _handleRevoked,
        );
      },
    );
    AuthSessionGuard.instance.bind(
      session: widget.session,
      onRevoked: _handleRevoked,
    );
  }

  void _handleRevoked() {
    if (_revoked || !mounted) return;
    _revoked = true;
    final message = AuthSessionGuard.instance.consumePendingRevokeMessage() ??
        widget.revokedMessage;
    showDunesToast(
      context,
      message,
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
  Widget build(BuildContext context) => widget.child;
}
