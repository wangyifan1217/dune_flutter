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
      token: _fakeJwt({
        'userId': 7,
        'roles': ['ADMIN'],
      }),
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

  test('AuthSession reads and persists Net TA access', () {
    final fromJwt = AuthSession.fromJwt(
      phone: '13800138000',
      userId: 0,
      token: _fakeJwt({'userId': 7, 'netTaAccess': true}),
      apiBase: 'http://example/api/v1',
    );
    expect(fromJwt.netTaAccess, isTrue);
    expect(fromJwt.effectiveNetTaAccess, isTrue);

    final restored = AuthSession.fromJson(fromJwt.toJson());
    expect(restored.netTaAccess, isTrue);
    expect(restored.effectiveNetTaAccess, isTrue);
  });

  test('AuthSession applies Net TA access from users/me', () {
    const base = AuthSession(
      phone: '13800138000',
      userId: 7,
      token: 't',
      apiBase: 'http://example/api/v1',
      roles: [],
    );

    final session = AuthSession.enrichFromUsersMe(base, {'netTaAccess': true});
    expect(session.netTaAccess, isTrue);
    expect(session.effectiveNetTaAccess, isTrue);
  });

  test('AuthSession reads and persists KPI performance access', () {
    final fromJwt = AuthSession.fromJwt(
      phone: '13800138000',
      userId: 0,
      token: _fakeJwt({'userId': 7, 'kpiPerformanceAccess': true}),
      apiBase: 'http://example/api/v1',
    );
    expect(fromJwt.kpiPerformanceAccess, isTrue);
    expect(fromJwt.effectiveKpiPerformanceAccess, isTrue);

    final restored = AuthSession.fromJson(fromJwt.toJson());
    expect(restored.kpiPerformanceAccess, isTrue);

    const base = AuthSession(
      phone: '13800138000',
      userId: 7,
      token: 't',
      apiBase: 'http://example/api/v1',
      roles: [],
    );
    final fromMe = AuthSession.enrichFromUsersMe(base, {
      'kpiPerformanceAccess': true,
    });
    expect(fromMe.kpiPerformanceAccess, isTrue);
  });

  test('AuthSession reads, copies and persists payroll report access', () {
    final fromJwt = AuthSession.fromJwt(
      phone: '13800138000',
      userId: 0,
      token: _fakeJwt({'userId': 7, 'payrollReportAccess': true}),
      apiBase: 'http://example/api/v1',
    );
    expect(fromJwt.payrollReportAccess, isTrue);
    expect(fromJwt.effectivePayrollReportAccess, isTrue);
    expect(
      fromJwt.copyWith(payrollReportAccess: false).payrollReportAccess,
      isFalse,
    );
    expect(AuthSession.fromJson(fromJwt.toJson()).payrollReportAccess, isTrue);

    const base = AuthSession(
      phone: '13800138000',
      userId: 7,
      token: 't',
      apiBase: 'http://example/api/v1',
      roles: [],
    );
    expect(
      AuthSession.enrichFromUsersMe(base, {
        'payrollReportAccess': true,
      }).payrollReportAccess,
      isTrue,
    );
  });

  test('AuthSession reads, copies and persists payment invoice access', () {
    final fromJwt = AuthSession.fromJwt(
      phone: '13800138000',
      userId: 0,
      token: _fakeJwt({'userId': 7, 'paymentInvoiceAccess': true}),
      apiBase: 'http://example/api/v1',
    );
    expect(fromJwt.paymentInvoiceAccess, isTrue);
    expect(fromJwt.effectivePaymentInvoiceAccess, isTrue);
    expect(
      fromJwt.copyWith(paymentInvoiceAccess: false).paymentInvoiceAccess,
      isFalse,
    );
    expect(AuthSession.fromJson(fromJwt.toJson()).paymentInvoiceAccess, isTrue);

    const base = AuthSession(
      phone: '13800138000',
      userId: 7,
      token: 't',
      apiBase: 'http://example/api/v1',
      roles: [],
    );
    expect(
      AuthSession.enrichFromUsersMe(base, {
        'paymentInvoiceAccess': true,
      }).paymentInvoiceAccess,
      isTrue,
    );
  });
}

String _fakeJwt(Map<String, dynamic> claims) {
  final header = base64Url
      .encode(utf8.encode('{"alg":"HS256"}'))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(utf8.encode(jsonEncode(claims)))
      .replaceAll('=', '');
  return '$header.$payload.sig';
}
