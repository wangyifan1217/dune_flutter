import 'package:http/http.dart' as http;

import '../../features/auth/auth_session.dart';
import '../../features/auth/auth_session_guard.dart';

Uri dunesApiUri(AuthSession session, String path) {
  final base = session.apiBase.replaceAll(RegExp(r'/$'), '');
  final normalized = path.startsWith('/') ? path : '/$path';
  return Uri.parse('$base$normalized');
}

Map<String, String> dunesAuthHeaders(
  AuthSession session, [
  Map<String, String>? extra,
]) {
  return <String, String>{
    'Authorization': 'Bearer ${session.token}',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    ...?extra,
  };
}

Future<http.Response> dunesHttpGet(
  AuthSession session,
  String path, {
  Map<String, String>? headers,
  http.Client? client,
}) async {
  final resp = await (client ?? http.Client()).get(
    dunesApiUri(session, path),
    headers: dunesAuthHeaders(session, headers),
  );
  AuthSessionGuard.instance.inspectStatusCode(resp.statusCode);
  return resp;
}

Future<http.Response> dunesHttpPost(
  AuthSession session,
  String path, {
  Object? body,
  Map<String, String>? headers,
  http.Client? client,
}) async {
  final resp = await (client ?? http.Client()).post(
    dunesApiUri(session, path),
    headers: dunesAuthHeaders(session, headers),
    body: body,
  );
  AuthSessionGuard.instance.inspectStatusCode(resp.statusCode);
  return resp;
}

Future<http.Response> dunesHttpDelete(
  AuthSession session,
  String path, {
  Map<String, String>? headers,
  http.Client? client,
}) async {
  final resp = await (client ?? http.Client()).delete(
    dunesApiUri(session, path),
    headers: dunesAuthHeaders(session, headers),
  );
  AuthSessionGuard.instance.inspectStatusCode(resp.statusCode);
  return resp;
}
