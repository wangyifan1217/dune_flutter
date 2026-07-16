import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';
import 'wechat_personal_models.dart';

class WechatPersonalService {
  WechatPersonalService({required this.session, http.Client? client})
      : _client = client;

  final AuthSession session;
  final http.Client? _client;

  Future<WechatPersonalStatus> fetchStatus() async {
    final resp = await dunesHttpGet(
      session,
      '/me/wechat/personal/status',
      client: _client,
    );
    return _parseStatus(resp);
  }

  Future<WechatPersonalStatus> startQr() async {
    final resp = await dunesHttpPost(
      session,
      '/me/wechat/personal/qr/start',
      body: '{}',
      client: _client,
    );
    return _parseStatus(resp);
  }

  Future<void> unbind() async {
    final resp = await dunesHttpDelete(
      session,
      '/me/wechat/personal',
      client: _client,
    );
    _ensureSuccess(resp);
  }

  WechatPersonalStatus _parseStatus(http.Response resp) {
    final data = _ensureSuccess(resp);
    if (data is Map<String, dynamic>) {
      return WechatPersonalStatus.fromJson(data);
    }
    return const WechatPersonalStatus(bound: false, status: '');
  }

  Object? _ensureSuccess(http.Response resp) {
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    if (resp.statusCode >= 200 &&
        resp.statusCode < 300 &&
        body?['success'] != false) {
      return body?['data'];
    }

    final message = (body?['message'] ?? body?['msg'] ?? body?['error'] ?? '')
        .toString()
        .trim();
    if (message.isNotEmpty) throw Exception(message);
    if (resp.statusCode == 401) throw Exception('登录已过期，请重新登录');
    if (resp.statusCode == 409) {
      throw Exception('Nova 账号尚未就绪，请稍后再试');
    }
    throw Exception('请求失败(${resp.statusCode})');
  }
}
