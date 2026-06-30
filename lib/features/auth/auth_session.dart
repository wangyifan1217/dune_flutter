import 'dart:convert';

class AuthSession {
  const AuthSession({
    required this.phone,
    required this.userId,
    required this.token,
    required this.apiBase,
    required this.roles,
    this.displayName,
    this.departmentId,
    this.novaLocalStorage,
    this.lighthouseAccess = false,
  });

  final String phone;
  final int userId;
  final String token;
  final String apiBase;
  final List<String> roles;
  final String? displayName;
  final int? departmentId;
  final bool lighthouseAccess;

  /// Nova Provisioning 结果，注入 WebView localStorage（与 dunes JWT 分离）。
  final Map<String, String>? novaLocalStorage;

  String get landingScreen => 'C1';

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
    Map<String, String>? novaLocalStorage,
    bool? lighthouseAccess,
  }) {
    return AuthSession(
      phone: phone ?? this.phone,
      userId: userId ?? this.userId,
      token: token ?? this.token,
      apiBase: apiBase ?? this.apiBase,
      roles: roles ?? this.roles,
      displayName: displayName ?? this.displayName,
      departmentId: departmentId ?? this.departmentId,
      novaLocalStorage: novaLocalStorage ?? this.novaLocalStorage,
      lighthouseAccess: lighthouseAccess ?? this.lighthouseAccess,
    );
  }

  static AuthSession enrichFromUsersMe(
    AuthSession session,
    Map<String, dynamic> data,
  ) {
    return session.copyWith(
      displayName: (data['displayName'] ?? session.displayName)?.toString(),
      departmentId: (data['departmentId'] as num?)?.toInt() ?? session.departmentId,
      lighthouseAccess: data['lighthouseAccess'] == true,
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
    return AuthSession(
      phone: phone,
      userId: (claims['userId'] as num?)?.toInt() ?? userId,
      token: token,
      apiBase: apiBase,
      roles: roles,
      displayName: claims['displayName'] as String?,
      departmentId: (claims['departmentId'] as num?)?.toInt(),
      lighthouseAccess: claims['lighthouseAccess'] == true,
    );
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
      if (novaLocalStorage != null && novaLocalStorage!.isNotEmpty)
        'novaLocalStorage': novaLocalStorage,
      'lighthouseAccess': lighthouseAccess,
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
      novaLocalStorage: _parseNovaStorage(json['novaLocalStorage']),
      lighthouseAccess: json['lighthouseAccess'] == true,
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
