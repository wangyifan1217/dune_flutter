import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/http/session_http.dart';
import '../../core/platform/desktop_features.dart';
import '../auth/auth_session.dart';

class WorkbenchSsoApp {
  const WorkbenchSsoApp({
    required this.appKey,
    required this.title,
    this.subtitle = '',
  });

  final String appKey;
  final String title;
  final String subtitle;

  factory WorkbenchSsoApp.fromJson(Map<String, dynamic> json) {
    return WorkbenchSsoApp(
      appKey: '${json['appKey'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      subtitle: '${json['subtitle'] ?? ''}'.trim(),
    );
  }
}

class AmSsoLoginUrl {
  const AmSsoLoginUrl({required this.url, this.expiresAt});

  final String url;
  final DateTime? expiresAt;

  Uri get uri => Uri.parse(url);

  factory AmSsoLoginUrl.fromJson(Map<String, dynamic> json) {
    return AmSsoLoginUrl(
      url: '${json['url'] ?? ''}'.trim(),
      expiresAt: DateTime.tryParse('${json['expiresAt'] ?? ''}'),
    );
  }
}

class AmSsoService {
  AmSsoService(this.session, {http.Client? client})
    : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;

  Future<List<WorkbenchSsoApp>> listApps() async {
    final response = await dunesHttpGet(session, '/sso/apps', client: _client);
    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(payload, fallback: '无法加载免登入口'));
    }
    if (payload['success'] != true) {
      throw Exception(_message(payload, fallback: '无法加载免登入口'));
    }
    final data = payload['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => WorkbenchSsoApp.fromJson(Map<String, dynamic>.from(row)))
        .where((app) => app.appKey.isNotEmpty)
        .toList();
  }

  Future<AmSsoLoginUrl> fetchLoginUrl(String appKey) {
    final key = Uri.encodeComponent(appKey.trim());
    final path = isDesktopCommOnly
        ? '/sso/$key/pc/login-url'
        : '/sso/$key/h5/login-url';
    return _fetch(path);
  }

  Future<bool> openInSystemBrowser(AmSsoLoginUrl login) {
    return launchUrl(login.uri, mode: LaunchMode.externalApplication);
  }

  Future<AmSsoLoginUrl> _fetch(String path) async {
    final response = await dunesHttpGet(session, path, client: _client);
    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(payload, fallback: '暂时无法打开'));
    }
    if (payload['success'] != true) {
      throw Exception(_message(payload, fallback: '暂时无法打开'));
    }
    final data = payload['data'];
    if (data is! Map) throw Exception('返回的数据格式不正确');
    final login = AmSsoLoginUrl.fromJson(Map<String, dynamic>.from(data));
    if (login.url.isEmpty) {
      throw Exception('登录地址为空');
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
