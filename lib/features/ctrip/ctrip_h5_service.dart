import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';

class CtripH5Form {
  const CtripH5Form({
    required this.action,
    required this.method,
    required this.fields,
    this.expiresAt,
  });

  final String action;
  final String method;
  final Map<String, String> fields;
  final DateTime? expiresAt;

  /// 按携程文档字段名组装 Form 字段（大小写敏感）。
  Map<String, String> signFields() {
    final values = <String, String>{
      'AccessUserId': _field('AccessUserId', 'accessuserid'),
      'Token': _field('Token', 'token'),
      'Appid': _field('Appid', 'appid', 'AppId'),
      'EmployeeId': _field('EmployeeId', 'employeeid'),
      'Signature': _field('Signature', 'signature'),
    };
    _copyField(values, 'InitPage', 'InitPage', 'initpage');
    _copyField(values, 'CorpPayType', 'CorpPayType', 'corppaytype');
    _copyField(values, 'Language', 'Language', 'language');
    _copyField(values, 'Callback', 'Callback', 'callback');
    _copyField(values, 'OnError', 'OnError', 'onerror');
    for (var i = 1; i <= 6; i++) {
      _copyField(values, 'CostCenter$i', 'CostCenter$i', 'costcenter$i');
    }
    // 透传后端可能给出的其余字段，避免漏参。
    fields.forEach((key, value) {
      if (value.isEmpty) return;
      final exists = values.keys.any(
        (known) => known.toLowerCase() == key.toLowerCase(),
      );
      if (!exists) values[key] = value;
    });
    return values;
  }

  /// 原生 WebView POST Form 正文。
  String postBody() {
    return Uri(queryParameters: signFields()).query;
  }

  /// 携程 H5 文档中的浏览器兼容方式：将已编码的表单字段整体 Base64
  /// 后放进 SsoData。Token 只存在于这一次性 URL 中，不会额外作为查询参数
  /// 发送。
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

  factory CtripH5Form.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'];
    final fields = <String, String>{};
    if (rawFields is Map) {
      rawFields.forEach((key, value) {
        if (value != null) fields['$key'] = '$value';
      });
    }
    return CtripH5Form(
      action: '${json['action'] ?? ''}'.trim(),
      method: '${json['method'] ?? 'POST'}'.trim().toUpperCase(),
      fields: fields,
      expiresAt: DateTime.tryParse('${json['expiresAt'] ?? ''}'),
    );
  }
}

class CtripH5Service {
  CtripH5Service(this.session, {http.Client? client})
    : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;

  Future<CtripH5Form> fetchForm({String initPage = 'Home'}) async {
    final query = Uri(queryParameters: {'initPage': initPage}).query;
    final response = await dunesHttpGet(
      session,
      // AuthSession.apiBase already ends with /api/v1.
      '/ctrip/h5/form?$query',
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
    final form = CtripH5Form.fromJson(Map<String, dynamic>.from(data));
    if (form.action.isEmpty || form.fields.isEmpty) {
      throw Exception('携程商旅登录表单为空');
    }
    return form;
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
