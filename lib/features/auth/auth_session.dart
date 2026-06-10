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
  });

  final String phone;
  final int userId;
  final String token;
  final String apiBase;
  final List<String> roles;
  final String? displayName;
  final int? departmentId;

  String get landingScreen => 'C1';

  bool get canUseApproval =>
      roles.any((r) => {'BUSINESS', 'INITIATOR', 'FINANCE', 'ADMIN'}.contains(r));

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
    );
  }
}
