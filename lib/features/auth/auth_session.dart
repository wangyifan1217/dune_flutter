import 'dart:convert';

import '../../core/config/dunes_defaults.dart';

class AuthSession {
  const AuthSession({
    required this.phone,
    required this.userId,
    required this.token,
    required this.apiBase,
    required this.roles,
    this.displayName,
    this.departmentId,
    this.userType = 'ORG',
    this.novaLocalStorage,
    this.lighthouseAccess = false,
    this.qianjiAccess = false,
    this.qianjiAdminAccess = false,
    this.robotAccess = false,
    this.hrbpAccess = false,
  });

  final String phone;
  final int userId;
  final String token;
  final String apiBase;
  final List<String> roles;
  final String? displayName;
  final int? departmentId;
  final String userType;
  final bool lighthouseAccess;
  final bool qianjiAccess;
  final bool qianjiAdminAccess;
  final bool robotAccess;
  /// 后端下发的「任务汇总」能力开关；未下发时工作台会走接口探测。
  final bool hrbpAccess;

  bool get isExternalUser => userType.toUpperCase() == 'EXTERNAL';

  /// 本地联调网关时自动视为已开通灯塔（见 [DunesDefaults.localLighthouseAccessBypass]）。
  bool get effectiveLighthouseAccess =>
      lighthouseAccess || DunesDefaults.localLighthouseAccessBypass;

  bool get effectiveQianjiAccess =>
      qianjiAccess || DunesDefaults.localLighthouseAccessBypass;

  bool get effectiveQianjiAdminAccess =>
      qianjiAdminAccess || DunesDefaults.localLighthouseAccessBypass;

  bool get effectiveRobotAccess =>
      robotAccess || DunesDefaults.localLighthouseAccessBypass;

  AuthSession withLocalDevGrants() {
    var next = this;
    if (DunesDefaults.localLighthouseAccessBypass) {
      if (!next.lighthouseAccess) {
        next = next.copyWith(lighthouseAccess: true);
      }
      if (!next.qianjiAccess) {
        next = next.copyWith(qianjiAccess: true);
      }
      if (!next.qianjiAdminAccess) {
        next = next.copyWith(qianjiAdminAccess: true);
      }
      if (!next.robotAccess) {
        next = next.copyWith(robotAccess: true);
      }
    }
    return next;
  }

  /// Nova Provisioning 结果，注入 WebView localStorage（与 dunes JWT 分离）。
  final Map<String, String>? novaLocalStorage;

  static const _initialScreenFromDefine = String.fromEnvironment(
    'DUNES_INITIAL_SCREEN',
    defaultValue: '',
  );

  String get landingScreen =>
      _initialScreenFromDefine.isNotEmpty ? _initialScreenFromDefine : 'C1';

  bool get canUseApproval =>
      roles.any((r) => {'BUSINESS', 'INITIATOR', 'FINANCE', 'ADMIN'}.contains(r));

  AuthSession copyWith({
    String? phone,
    int? userId,
    String? token,
    String? apiBase,
    List<String>? roles,
    String? displayName,
    int? departmentId,
    String? userType,
    Map<String, String>? novaLocalStorage,
    bool? lighthouseAccess,
    bool? qianjiAccess,
    bool? qianjiAdminAccess,
    bool? robotAccess,
    bool? hrbpAccess,
  }) {
    return AuthSession(
      phone: phone ?? this.phone,
      userId: userId ?? this.userId,
      token: token ?? this.token,
      apiBase: apiBase ?? this.apiBase,
      roles: roles ?? this.roles,
      displayName: displayName ?? this.displayName,
      departmentId: departmentId ?? this.departmentId,
      userType: userType ?? this.userType,
      novaLocalStorage: novaLocalStorage ?? this.novaLocalStorage,
      lighthouseAccess: lighthouseAccess ?? this.lighthouseAccess,
      qianjiAccess: qianjiAccess ?? this.qianjiAccess,
      qianjiAdminAccess: qianjiAdminAccess ?? this.qianjiAdminAccess,
      robotAccess: robotAccess ?? this.robotAccess,
      hrbpAccess: hrbpAccess ?? this.hrbpAccess,
    );
  }

  /// refresh 后用新 JWT 刷新角色等声明字段；保留本地 nova / 访问开关。
  AuthSession withRefreshedToken(String newToken) {
    if (newToken.isEmpty) return this;
    final fromJwt = AuthSession.fromJwt(
      phone: phone,
      userId: userId,
      token: newToken,
      apiBase: apiBase,
    );
    return copyWith(
      token: newToken,
      userId: fromJwt.userId > 0 ? fromJwt.userId : userId,
      roles: fromJwt.roles,
      displayName: fromJwt.displayName ?? displayName,
      departmentId: fromJwt.departmentId ?? departmentId,
      userType: fromJwt.userType,
    );
  }

  static AuthSession enrichFromUsersMe(
    AuthSession session,
    Map<String, dynamic> data,
  ) {
    return session.copyWith(
      displayName: (data['displayName'] ?? session.displayName)?.toString(),
      departmentId: (data['departmentId'] as num?)?.toInt() ?? session.departmentId,
      userType: (data['userType'] ?? session.userType)?.toString() ?? session.userType,
      lighthouseAccess: data['lighthouseAccess'] == true,
      qianjiAccess: data['qianjiAccess'] == true,
      qianjiAdminAccess: data['qianjiAdminAccess'] == true,
      robotAccess: data['robotAccess'] == true,
      hrbpAccess: data['hrbpAccess'] == true,
    );
  }

  factory AuthSession.fromJwt({
    required String phone,
    required int userId,
    required String token,
    required String apiBase,
  }) {
    final claims = _decodeJwtClaims(token);
    final roles = (claims['roles'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final claimUserId = (claims['userId'] as num?)?.toInt();
    final subUserId = int.tryParse('${claims['sub'] ?? ''}'.trim());
    return AuthSession(
      phone: phone,
      userId: claimUserId ?? subUserId ?? userId,
      token: token,
      apiBase: apiBase,
      roles: roles,
      displayName: claims['displayName'] as String?,
      departmentId: (claims['departmentId'] as num?)?.toInt(),
      userType: _resolveUserType(claims),
      lighthouseAccess: claims['lighthouseAccess'] == true,
      qianjiAccess: claims['qianjiAccess'] == true,
      qianjiAdminAccess: claims['qianjiAdminAccess'] == true,
      robotAccess: claims['robotAccess'] == true,
      hrbpAccess: claims['hrbpAccess'] == true,
    );
  }

  static String _resolveUserType(Map<String, dynamic> claims) {
    final raw = (claims['userType'] as String?)?.trim();
    if (raw != null && raw.isNotEmpty) return raw.toUpperCase();
    if (claims['external'] == true) return 'EXTERNAL';
    return 'ORG';
  }

  static Map<String, dynamic> _decodeJwtClaims(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return const {};
    final normalized = base64Url.normalize(parts[1]);
    final decoded = utf8.decode(base64Url.decode(normalized));
    final claims = jsonDecode(decoded);
    return claims is Map<String, dynamic> ? claims : const {};
  }

  Map<String, dynamic> toJson() {
    return {
      'phone': phone,
      'userId': userId,
      'token': token,
      'apiBase': apiBase,
      'roles': roles,
      'displayName': displayName,
      'departmentId': departmentId,
      'userType': userType,
      if (novaLocalStorage != null && novaLocalStorage!.isNotEmpty)
        'novaLocalStorage': novaLocalStorage,
      'lighthouseAccess': lighthouseAccess,
      'qianjiAccess': qianjiAccess,
      'qianjiAdminAccess': qianjiAdminAccess,
      'robotAccess': robotAccess,
      'hrbpAccess': hrbpAccess,
    };
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final roles = (json['roles'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    return AuthSession(
      phone: json['phone'] as String? ?? '',
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      token: json['token'] as String? ?? '',
      apiBase: json['apiBase'] as String? ?? '',
      roles: roles,
      displayName: json['displayName'] as String?,
      departmentId: (json['departmentId'] as num?)?.toInt(),
      userType: (json['userType'] as String?)?.toUpperCase() ?? 'ORG',
      novaLocalStorage: _parseNovaStorage(json['novaLocalStorage']),
      lighthouseAccess: json['lighthouseAccess'] == true,
      qianjiAccess: json['qianjiAccess'] == true,
      qianjiAdminAccess: json['qianjiAdminAccess'] == true,
      robotAccess: json['robotAccess'] == true,
      hrbpAccess: json['hrbpAccess'] == true,
    );
  }

  static Map<String, String>? _parseNovaStorage(Object? raw) {
    if (raw is! Map) return null;
    final out = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value != null) out[key] = value.toString();
    });
    return out.isEmpty ? null : out;
  }
}
