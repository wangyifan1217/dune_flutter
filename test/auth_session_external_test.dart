import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/auth/auth_session.dart';

void main() {
  test('AuthSession marks external user from JWT userType', () {
    final session = AuthSession.fromJwt(
      phone: '13800138000',
      userId: 0,
      token: _fakeJwt({'userType': 'EXTERNAL', 'userId': 42}),
      apiBase: 'http://example/api/v1',
    );
    expect(session.isExternalUser, isTrue);
    expect(session.userType, 'EXTERNAL');
    expect(session.userId, 42);
  });

  test('AuthSession marks org user by default', () {
    final session = AuthSession.fromJwt(
      phone: '13800138000',
      userId: 0,
      token: _fakeJwt({'userId': 7, 'roles': ['ADMIN']}),
      apiBase: 'http://example/api/v1',
    );
    expect(session.isExternalUser, isFalse);
    expect(session.userType, 'ORG');
  });

  test('AuthSession persists userType in json roundtrip', () {
    const session = AuthSession(
      phone: '13800138000',
      userId: 9,
      token: 't',
      apiBase: 'http://example/api/v1',
      roles: [],
      userType: 'EXTERNAL',
    );
    final restored = AuthSession.fromJson(session.toJson());
    expect(restored.userType, 'EXTERNAL');
    expect(restored.isExternalUser, isTrue);
  });
}

String _fakeJwt(Map<String, dynamic> claims) {
  final header = base64Url.encode(utf8.encode('{"alg":"HS256"}')).replaceAll('=', '');
  final payload = base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');
  return '$header.$payload.sig';
}
