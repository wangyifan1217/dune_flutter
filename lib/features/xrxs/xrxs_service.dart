import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';

class XrxsLoginUrl {
  const XrxsLoginUrl({required this.url, this.expiresAt});

  final String url;
  final DateTime? expiresAt;

  Uri get uri => Uri.parse(url);

  factory XrxsLoginUrl.fromJson(Map<String, dynamic> json) {
    return XrxsLoginUrl(
      url: '${json['url'] ?? ''}'.trim(),
      expiresAt: DateTime.tryParse('${json['expiresAt'] ?? ''}'),
    );
  }
}

class XrxsService {
  XrxsService(this.session, {http.Client? client})
    : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;

  Future<XrxsLoginUrl> fetchH5LoginUrl({String? sid, String? role}) =>
      _fetch('/xrxs/h5/login-url', sid: sid, role: role);

  Future<XrxsLoginUrl> fetchPcLoginUrl({String? sid, String? role}) =>
      _fetch('/xrxs/pc/login-url', sid: sid, role: role);

  Future<bool> openInSystemBrowser(XrxsLoginUrl login) {
    return launchUrl(login.uri, mode: LaunchMode.externalApplication);
  }

  Future<XrxsLoginUrl> _fetch(
    String path, {
    String? sid,
    String? role,
  }) async {
    final query = <String, String>{};
    final sidTrim = sid?.trim() ?? '';
    final roleTrim = role?.trim() ?? '';
    if (sidTrim.isNotEmpty) query['sid'] = sidTrim;
    if (roleTrim.isNotEmpty) query['role'] = roleTrim;
    var requestPath = path;
    if (query.isNotEmpty) {
      requestPath =
          '$path?${query.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    }
    final response = await dunesHttpGet(
      session,
      requestPath,
      client: _client,
    );
    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(payload, fallback: '薪人薪事暂时无法打开'));
    }
    if (payload['success'] != true) {
      throw Exception(_message(payload, fallback: '薪人薪事暂时无法打开'));
    }
    final data = payload['data'];
    if (data is! Map) throw Exception('薪人薪事返回的数据格式不正确');
    final login = XrxsLoginUrl.fromJson(Map<String, dynamic>.from(data));
    if (login.url.isEmpty) {
      throw Exception('薪人薪事登录地址为空');
    }
    return login;
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      return value is Map<String, dynamic>
          ? value
          : <String, dynamic>{'message': '服务返回格式不正确'};
    } catch (_) {
      return <String, dynamic>{'message': '服务返回格式不正确'};
    }
  }

  String _message(Map<String, dynamic> payload, {required String fallback}) {
    final message = '${payload['message'] ?? ''}'.trim();
    return message.isEmpty ? fallback : message;
  }
}
