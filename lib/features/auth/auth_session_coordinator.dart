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

  AuthSession? get session => _session;

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
      if (shouldForceLogout(resp)) return null;
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;

      final decoded = jsonDecode(resp.body);
      final body =
          decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
      final data = body['data'];
      final token = data is Map<String, dynamic>
          ? (data['token'] as String?)
          : body['token'] as String?;
      if (token == null || token.isEmpty) return null;

      final next = session.copyWith(token: token);
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

  /// 明确被踢下线 / token 无效，不应再 refresh。
  static bool shouldForceLogout(http.Response response) {
    if (response.statusCode != 401) return false;
    final message = readApiMessage(response.body);
    if (message.contains('其他设备登录')) return true;
    if (message.contains('missing bearer token') ||
        message.contains('invalid token')) {
      return true;
    }
    return false;
  }

  static bool isRecoverable401(http.Response response) {
    return response.statusCode == 401 && !shouldForceLogout(response);
  }
}
