import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';

/// 携程 PC 单点登录表单（authorize/login）。
///
/// 官方要求：Form POST / SsoData GET，禁止 iframe；Ticket 一次性。
class CtripPCForm {
  const CtripPCForm({
    required this.action,
    required this.method,
    required this.fields,
    this.expiresAt,
  });

  final String action;
  final String method;
  final Map<String, String> fields;
  final DateTime? expiresAt;

  /// 按携程 PC 文档字段名组装（大小写敏感）。
  Map<String, String> signFields() {
    final values = <String, String>{
      'AppKey': _field('AppKey', 'appkey'),
      'Ticket': _field('Ticket', 'ticket', 'token'),
      'EmployeeID': _field('EmployeeID', 'EmployeeId', 'employeeid'),
      'Signature': _field('Signature', 'signature'),
      // ForCorp 参与签名；未传时后端固定为 "0"，必须带上。
      'ForCorp': _field('ForCorp', 'forcorp'),
    };
    _copyField(values, 'UID', 'UID', 'uid');
    _copyField(values, 'Email', 'Email', 'email');
    _copyField(values, 'TA', 'TA', 'ta');
    for (var i = 1; i <= 6; i++) {
      _copyField(values, 'Cost$i', 'Cost$i', 'cost$i');
    }
    _copyField(values, 'InitPage', 'InitPage', 'initpage');
    _copyField(values, 'CurrentLang', 'CurrentLang', 'currentlang');
    _copyField(values, 'Callback', 'Callback', 'callback');
    fields.forEach((key, value) {
      if (value.isEmpty) return;
      final exists = values.keys.any(
        (known) => known.toLowerCase() == key.toLowerCase(),
      );
      if (!exists) values[key] = value;
    });
    return values;
  }

  /// 官方 4.1.5 GET：业务参数 → value URL 编码 → Base64 → 再作为 SsoData。
  Uri browserUri() {
    final encodedFields = signFields().entries
        .map((entry) {
          final key = Uri.encodeComponent(entry.key);
          final value = Uri.encodeComponent(entry.value);
          return '$key=$value';
        })
        .join('&');
    final ssoData = base64.encode(utf8.encode(encodedFields));
    return Uri.parse(action).replace(queryParameters: {'SsoData': ssoData});
  }

  String _field(String primary, [String? alt1, String? alt2]) {
    for (final name in [primary, alt1, alt2]) {
      if (name == null) continue;
      final direct = fields[name];
      if (direct != null && direct.isNotEmpty) return direct;
      final match = fields.entries.firstWhere(
        (e) => e.key.toLowerCase() == name.toLowerCase(),
        orElse: () => const MapEntry('', ''),
      );
      if (match.value.isNotEmpty) return match.value;
    }
    return '';
  }

  void _copyField(
    Map<String, String> values,
    String target,
    String source, [
    String? alt,
  ]) {
    final value = _field(source, alt);
    if (value.isNotEmpty) values[target] = value;
  }

  factory CtripPCForm.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'];
    final fields = <String, String>{};
    if (rawFields is Map) {
      rawFields.forEach((key, value) {
        if (value != null) fields['$key'] = '$value';
      });
    }
    return CtripPCForm(
      action: '${json['action'] ?? ''}'.trim(),
      method: '${json['method'] ?? 'POST'}'.trim().toUpperCase(),
      fields: fields,
      expiresAt: DateTime.tryParse('${json['expiresAt'] ?? ''}'),
    );
  }
}

class CtripPCService {
  CtripPCService(this.session, {http.Client? client})
    : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;

  Future<CtripPCForm> fetchForm({String initPage = 'Home'}) async {
    final query = Uri(queryParameters: {'initPage': initPage}).query;
    final response = await dunesHttpGet(
      session,
      '/ctrip/pc/form?$query',
      client: _client,
    );
    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(payload, fallback: '携程商旅暂时无法打开'));
    }
    if (payload['success'] != true) {
      throw Exception(_message(payload, fallback: '携程商旅暂时无法打开'));
    }
    final data = payload['data'];
    if (data is! Map) throw Exception('携程商旅返回的数据格式不正确');
    final form = CtripPCForm.fromJson(Map<String, dynamic>.from(data));
    if (form.action.isEmpty || form.fields.isEmpty) {
      throw Exception('携程商旅登录表单为空');
    }
    return form;
  }

  /// 用系统浏览器打开 PC 单点（SsoData GET，符合官方「浏览器提交跳转」）。
  Future<bool> openInSystemBrowser(CtripPCForm form) async {
    final uri = form.browserUri();
    return launchUrl(uri, mode: LaunchMode.externalApplication);
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
