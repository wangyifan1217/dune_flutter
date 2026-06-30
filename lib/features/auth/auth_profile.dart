import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_session.dart';

Future<AuthSession> enrichSessionFromUsersMe(AuthSession session) async {
  try {
    final resp = await http.get(
      Uri.parse('${session.apiBase}/users/me'),
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) return session;
    final body = jsonDecode(resp.body);
    final data = body is Map<String, dynamic>
        ? (body['data'] is Map<String, dynamic>
              ? body['data'] as Map<String, dynamic>
              : body)
        : const <String, dynamic>{};
    return AuthSession.enrichFromUsersMe(session, data);
  } catch (_) {
    return session;
  }
}
