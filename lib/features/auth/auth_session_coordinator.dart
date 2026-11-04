import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_session.dart';

/// 全局会话协调：单例持有最新 token，401 时静默 refresh（不走 sms/token）。
class AuthSessionCoordinator extends ChangeNotifier {
  AuthSessionCoordinator._();

  static final AuthSessionCoordinator instance = AuthSessionCoordinator._();

  AuthSession? _session;
  Future<AuthSession?>? _refreshInFlight;
  void Function(AuthSession session)? onSessionUpdated;
  String? _refreshLogoutToken;
  String? _refreshLogoutMessage;

  AuthSession? get session => _session;

  /// 这次请求带的令牌是否仍是当前正在使用的那张。
  bool tokenIsCurrent(String requestToken) {
    final current = _session?.token ?? '';
    return requestToken.isNotEmpty && requestToken == current;
  }

  /// 刷新接口明确要求下线，且刷新的仍是当前令牌时取出提示。已换掉的令牌返回 null。
  String? takeRefreshLogoutMessage() {
    final token = _refreshLogoutToken;
    final message = _refreshLogoutMessage;
    _refreshLogoutToken = null;
    _refreshLogoutMessage = null;
    if (token == null || message == null || message.isEmpty) return null;
    if (!tokenIsCurrent(token)) return null;
    return message;
  }

  void bind(AuthSession session, {void Function(AuthSession)? onUpdated}) {
    _session = session;
    if (onUpdated != null) onSessionUpdated = onUpdated;
    notifyListeners();
  }

  void updateSession(AuthSession session) {
    _session = session;
    onSessionUpdated?.call(session);
    notifyListeners();
  }

  void clear() {
    _session = null;
    _refreshInFlight = null;
    _refreshLogoutToken = null;
    _refreshLogoutMessage = null;
    notifyListeners();
  }

  /// 优先返回协调器中的最新 session，否则回退到调用方传入的副本。
  AuthSession resolve(AuthSession fallback) {
    final current = _session;
    if (current == null) return fallback;
    if (current.userId > 0 &&
        fallback.userId > 0 &&
        current.userId != fallback.userId) {
      return fallback;
    }
    return current;
  }

  /// 单飞 refresh：并发 401 只触发一次 `/auth/session/refresh`。
  Future<AuthSession?> refreshToken() async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final session = _session;
    if (session == null || session.token.isEmpty) return null;

    final future = _refreshOnce(session);
    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<AuthSession?> _refreshOnce(AuthSession session) async {
    try {
      final base = session.apiBase.replaceAll(RegExp(r'/$'), '');
      final resp = await http.post(
        Uri.parse('$base/auth/session/refresh'),
        headers: <String, String>{
          'Authorization': 'Bearer ${session.token}',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );
      if (shouldForceLogout(resp)) {
        // 只记录当前这张令牌的下线。旧令牌的 401 不能覆盖刚登录写入的新令牌。
        if (_session?.token == session.token) {
          _refreshLogoutToken = session.token;
          _refreshLogoutMessage = readApiMessage(resp.body);
        }
        return null;
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;

      final decoded = jsonDecode(resp.body);
      final body =
          decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
      final data = body['data'];
      final token = data is Map<String, dynamic>
          ? (data['token'] as String?)
          : body['token'] as String?;
      if (token == null || token.isEmpty) return null;
      if (_session?.token != session.token) return null;

      // 重新解析 JWT，把最新 roles 等写回会话（否则只换 token、角色仍旧）。
      final next = session.withRefreshedToken(token);
      updateSession(next);
      return next;
    } catch (_) {
      return null;
    }
  }

  static String readApiMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return (decoded['message'] ?? '').toString();
      }
    } catch (_) {}
    return body;
  }

  /// 当前令牌被明确踢下线或账号已不可用时才清登录。
  /// 网络失败、超时、500、饕开通失败，以及 invalid token，都不在这里。
  static bool shouldForceLogout(http.Response response) {
    final message = readApiMessage(response.body);
    // 停用账号：flow/im 中间件返回 401，登录接口返回 403，统一强制登出。
    if (response.statusCode == 403) {
      return message.contains('账号已停用');
    }
    if (response.statusCode != 401) return false;
    if (message.contains('其他设备登录')) return true;
    if (message.contains('账号已停用') || message.contains('账号不存在')) {
      return true;
    }
    return false;
  }

  static bool isRecoverable401(http.Response response) {
    return response.statusCode == 401 && !shouldForceLogout(response);
  }
}
