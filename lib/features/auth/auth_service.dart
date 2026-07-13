import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/dunes_defaults.dart';
import '../../core/platform/desktop_features.dart';
import 'auth_session.dart';
import 'registration_messages.dart';

class AuthService {
  AuthService({http.Client? client, String? apiBase})
      : _client = client ?? http.Client(),
        apiBase = apiBase ?? _defaultApiBase();

  final http.Client _client;
  final String apiBase;

  /// 桌面端与 PC 工作台同用 `pc` channel（后端 JWT 槽）；手机 APP 用 `app`。
  static String get loginChannel => isDesktopCommOnly ? 'pc' : 'app';

  static String _defaultApiBase() {
    const fromEnv = String.fromEnvironment('DUNES_API_BASE');
    if (fromEnv.isNotEmpty) return fromEnv;
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
      body: jsonEncode({'phone': phone, 'channel': loginChannel}),
    );
    if (resp.statusCode == 403) {
      final msg = _apiMessage(resp.body) ?? '账号已停用';
      throw AuthException(msg);
    }
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
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw AuthException('请输入 6 位验证码');
    }

    final uri = Uri.parse('$apiBase/auth/sms/token');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'code': code,
        'channel': loginChannel,
      }),
    );

    if (response.statusCode == 403) {
      final msg = _apiMessage(response.body) ?? '账号已停用';
      throw AuthException(msg);
    }
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

  Future<RegistrationPhoneCheck> checkRegistrationPhone(String phone) async {
    if (!RegExp(r'^\d{11}$').hasMatch(phone)) {
      throw AuthException('请输入 11 位手机号');
    }
    final uri = Uri.parse('$apiBase/auth/register/check?phone=${Uri.encodeQueryComponent(phone)}');
    final resp = await _client.get(uri);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AuthException(
        _registrationApiMessage(resp.body, fallback: '手机号校验失败'),
      );
    }
    final data = _unwrapData(resp.body);
    return RegistrationPhoneCheck.fromJson(data);
  }

  Future<void> requestRegistrationSmsCode({required String phone}) async {
    if (!RegExp(r'^\d{11}$').hasMatch(phone)) {
      throw AuthException('请输入 11 位手机号');
    }
    final uri = Uri.parse('$apiBase/auth/register/sms/request');
    final resp = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone}),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AuthException(
        _registrationApiMessage(resp.body, fallback: '发送验证码失败'),
      );
    }
  }

  Future<RegistrationSubmitResult> submitRegistration({
    required String phone,
    required String code,
    required String displayName,
    String organizationName = '',
    String referrerName = '',
  }) async {
    final uri = Uri.parse('$apiBase/auth/register/submit');
    final resp = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'code': code,
        'displayName': displayName,
        'organizationName': organizationName,
        'referrerName': referrerName,
      }),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AuthException(
        _registrationApiMessage(resp.body, fallback: '注册提交失败'),
      );
    }
    return RegistrationSubmitResult.fromJson(_unwrapData(resp.body));
  }

  Future<RegistrationStatusResult> registrationStatus(String phone) async {
    final uri = Uri.parse('$apiBase/auth/register/status?phone=${Uri.encodeQueryComponent(phone)}');
    final resp = await _client.get(uri);
    if (resp.statusCode == 404) {
      throw AuthException('未找到注册记录');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AuthException(
        _registrationApiMessage(resp.body, fallback: '查询注册状态失败'),
      );
    }
    return RegistrationStatusResult.fromJson(_unwrapData(resp.body));
  }

  /// PC / 桌面扫码登录：创建二维码会话（与 admin-web 工作台一致，channel=pc）。
  Future<AuthQrSession> createQrLoginSession() async {
    final uri = Uri.parse('$apiBase/auth/qr/session');
    final resp = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'channel': 'pc'}),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AuthException(_apiMessage(resp.body) ?? '二维码生成失败');
    }
    return AuthQrSession.fromJson(_unwrapData(resp.body));
  }

  Future<AuthQrStatus> pollQrLoginStatus({
    required String sessionId,
    required String clientSecret,
  }) async {
    final uri = Uri.parse('$apiBase/auth/qr/status');
    final resp = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'clientSecret': clientSecret,
      }),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AuthException(_apiMessage(resp.body) ?? '二维码状态获取失败');
    }
    return AuthQrStatus.fromJson(_unwrapData(resp.body));
  }

  Future<AuthSession> signInWithQrToken({
    required String sessionId,
    required String clientSecret,
  }) async {
    final uri = Uri.parse('$apiBase/auth/qr/token');
    final resp = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'clientSecret': clientSecret,
      }),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AuthException(_apiMessage(resp.body) ?? '扫码登录失败');
    }
    final data = _unwrapData(resp.body);
    final token = (data['token'] as String?)?.trim() ?? '';
    if (token.isEmpty) {
      throw AuthException('扫码登录失败：未返回 token');
    }
    return AuthSession.fromJwt(
      phone: '',
      userId: 0,
      token: token,
      apiBase: apiBase,
    );
  }

  static Map<String, dynamic> _unwrapData(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'];
        if (data is Map<String, dynamic>) return data;
        return decoded;
      }
    } catch (_) {}
    return const {};
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

  static String _registrationApiMessage(String body, {required String fallback}) {
    return localizeRegistrationMessage(_apiMessage(body), fallback: fallback);
  }
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class RegistrationPhoneCheck {
  const RegistrationPhoneCheck({
    required this.allowed,
    this.reason,
    this.applicationStatus,
  });

  final bool allowed;
  final String? reason;
  final String? applicationStatus;

  String? get localizedReason =>
      reason == null ? null : localizeRegistrationMessage(reason, fallback: '该手机号不可注册');

  factory RegistrationPhoneCheck.fromJson(Map<String, dynamic> json) {
    return RegistrationPhoneCheck(
      allowed: json['allowed'] == true,
      reason: json['reason'] as String?,
      applicationStatus: json['applicationStatus'] as String?,
    );
  }
}

class RegistrationSubmitResult {
  const RegistrationSubmitResult({
    required this.status,
    this.token,
    this.rejectReason,
  });

  final String status;
  final String? token;
  final String? rejectReason;

  factory RegistrationSubmitResult.fromJson(Map<String, dynamic> json) {
    final app = json['application'];
    String? rejectReason;
    if (app is Map<String, dynamic>) {
      rejectReason = app['rejectReason'] as String?;
    }
    return RegistrationSubmitResult(
      status: (json['status'] as String?) ?? '',
      token: json['token'] as String?,
      rejectReason: rejectReason,
    );
  }
}

class RegistrationStatusResult {
  const RegistrationStatusResult({
    required this.status,
    this.token,
    this.rejectReason,
  });

  final String status;
  final String? token;
  final String? rejectReason;

  factory RegistrationStatusResult.fromJson(Map<String, dynamic> json) {
    final app = json['application'];
    String? rejectReason;
    if (app is Map<String, dynamic>) {
      rejectReason = app['rejectReason'] as String?;
    }
    return RegistrationStatusResult(
      status: (json['status'] as String?) ?? '',
      token: json['token'] as String?,
      rejectReason: rejectReason,
    );
  }
}

class AuthQrSession {
  const AuthQrSession({
    required this.sessionId,
    required this.clientSecret,
    required this.qrCode,
    required this.ttlSeconds,
  });

  final String sessionId;
  final String clientSecret;
  final String qrCode;
  final int ttlSeconds;

  factory AuthQrSession.fromJson(Map<String, dynamic> json) {
    return AuthQrSession(
      sessionId: (json['sessionId'] as String?)?.trim() ?? '',
      clientSecret: (json['clientSecret'] as String?)?.trim() ?? '',
      qrCode: (json['qrCode'] as String?)?.trim() ?? '',
      ttlSeconds: (json['ttlSeconds'] as num?)?.toInt() ?? 120,
    );
  }
}

class AuthQrStatus {
  const AuthQrStatus({
    required this.status,
    this.confirmedUserName,
  });

  final String status;
  final String? confirmedUserName;

  bool get isPending => status == 'PENDING';
  bool get isConfirmed => status == 'CONFIRMED';
  bool get isExpired => status == 'EXPIRED' || status == 'CONSUMED';

  factory AuthQrStatus.fromJson(Map<String, dynamic> json) {
    return AuthQrStatus(
      status: (json['status'] as String?)?.trim() ?? '',
      confirmedUserName: (json['confirmedUserName'] as String?)?.trim(),
    );
  }
}
