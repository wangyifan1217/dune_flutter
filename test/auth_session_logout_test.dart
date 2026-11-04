import 'dart:convert';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/auth/auth_session_coordinator.dart';
import 'package:dunes_app/features/auth/auth_session_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  AuthSession sessionWith(String token) {
    return AuthSession(
      phone: '13800138000',
      userId: 7,
      token: token,
      apiBase: 'https://nova.heunion.com/api/v1',
      roles: const [],
    );
  }

  http.Response response(int status, String message) {
    return http.Response(
      jsonEncode(<String, dynamic>{'message': message}),
      status,
      headers: {'content-type': 'application/json'},
    );
  }

  tearDown(() {
    AuthSessionGuard.instance.unbind();
    AuthSessionCoordinator.instance.clear();
  });

  test('only the current token message forces logout', () {
    expect(
      AuthSessionCoordinator.shouldForceLogout(
        response(401, '账号已在其他设备登录，请重新登录'),
      ),
      isTrue,
    );
    expect(
      AuthSessionCoordinator.shouldForceLogout(response(401, '账号已停用')),
      isTrue,
    );
    expect(
      AuthSessionCoordinator.shouldForceLogout(response(403, '账号已停用')),
      isTrue,
    );
    expect(
      AuthSessionCoordinator.shouldForceLogout(response(401, '账号不存在')),
      isTrue,
    );
    expect(
      AuthSessionCoordinator.shouldForceLogout(response(401, 'invalid token')),
      isFalse,
    );
    expect(
      AuthSessionCoordinator.shouldForceLogout(
        response(401, 'missing bearer token'),
      ),
      isFalse,
    );
    expect(
      AuthSessionCoordinator.shouldForceLogout(response(500, '服务器繁忙')),
      isFalse,
    );
    expect(
      AuthSessionCoordinator.shouldForceLogout(
        response(503, 'NOVA 账号开通失败，请联系管理员'),
      ),
      isFalse,
    );
  });

  test('a replaced token 401 does not clear the new login', () async {
    final coordinator = AuthSessionCoordinator.instance;
    final guard = AuthSessionGuard.instance;
    coordinator.bind(sessionWith('new-token'));
    var revoked = 0;
    guard.bind(session: sessionWith('new-token'), onRevoked: () => revoked++);

    guard.inspectResponse(
      response(401, '账号已在其他设备登录，请重新登录'),
      requestToken: 'old-token',
    );
    await pumpEventQueue();

    expect(revoked, 0);
    expect(coordinator.session?.token, 'new-token');
  });

  test('the current token is logged out on another-device login', () async {
    final coordinator = AuthSessionCoordinator.instance;
    final guard = AuthSessionGuard.instance;
    coordinator.bind(sessionWith('current-token'));
    var revoked = 0;
    guard.bind(
      session: sessionWith('current-token'),
      onRevoked: () => revoked++,
    );

    guard.inspectResponse(
      response(401, '账号已在其他设备登录，请重新登录'),
      requestToken: 'current-token',
    );
    await pumpEventQueue();

    expect(revoked, 1);
    expect(coordinator.session, isNull);
  });

  test('invalid token and nova failure keep the current login', () async {
    final coordinator = AuthSessionCoordinator.instance;
    final guard = AuthSessionGuard.instance;
    coordinator.bind(sessionWith('current-token'));
    var revoked = 0;
    guard.bind(
      session: sessionWith('current-token'),
      onRevoked: () => revoked++,
    );

    guard.inspectResponse(
      response(401, 'invalid token'),
      requestToken: 'current-token',
    );
    guard.inspectResponse(
      response(503, 'NOVA 账号开通失败'),
      requestToken: 'current-token',
    );
    guard.inspectResponse(
      response(500, '服务器繁忙'),
      requestToken: 'current-token',
    );
    await pumpEventQueue();

    expect(revoked, 0);
    expect(coordinator.session?.token, 'current-token');
  });
}
