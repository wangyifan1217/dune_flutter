import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/dunes_defaults.dart';
import 'auth_session.dart';

class AuthService {
  AuthService({http.Client? client, String? apiBase})
      : _client = client ?? http.Client(),
        apiBase = apiBase ?? _defaultApiBase();

  final http.Client _client;
  final String apiBase;

  static String _defaultApiBase() {
    const fromEnv = String.fromEnvironment('DUNES_API_BASE');
    if (fromEnv.isNotEmpty) return fromEnv;
    final host = Uri.base.host;
    if (host.isNotEmpty && host != 'localhost' && host != '127.0.0.1') {
      return 'http://$host:${DunesDefaults.gatewayPort}/api/v1';
    }
    return DunesDefaults.apiBase;
  }

  Future<void> requestSmsCode({required String phone}) async {
    if (!RegExp(r'^\d{11}$').hasMatch(phone)) {
      throw AuthException('请输入 11 位手机号');
    }
    final uri = Uri.parse('$apiBase/auth/sms/request');
    final resp = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone}),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final msg = _apiMessage(resp.body) ?? '发送验证码失败：${resp.statusCode}';
      throw AuthException(msg);
    }
  }

  Future<AuthSession> signInWithSmsCode({
    required String phone,
    required String code,
  }) async {
    if (!RegExp(r'^\d{11}$').hasMatch(phone)) {
      throw AuthException('请输入 11 位手机号');
    }
    if (!RegExp(r'^\d{5}$').hasMatch(code)) {
      throw AuthException('请输入 5 位验证码');
    }

    final uri = Uri.parse('$apiBase/auth/sms/token');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'code': code}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final msg = _apiMessage(response.body) ?? '登录失败：${response.statusCode}';
      throw AuthException(msg);
    }

    final decoded = jsonDecode(response.body);
    final body = decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
    final data = body['data'];
    final token = data is Map<String, dynamic>
        ? data['token'] as String?
        : body['token'] as String?;

    if (token == null || token.isEmpty) {
      throw AuthException('登录失败：未返回 token');
    }

    return AuthSession.fromJwt(
      phone: phone,
      userId: 0,
      token: token,
      apiBase: apiBase,
    );
  }

  static String? _apiMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final m = decoded['message'];
        if (m is String && m.isNotEmpty) return m;
      }
    } catch (_) {}
    return null;
  }
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
