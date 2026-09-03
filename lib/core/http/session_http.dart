import 'package:http/http.dart' as http;

import '../../features/auth/auth_session.dart';
import '../../features/auth/auth_session_coordinator.dart';
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

Future<http.Response> _dunesRequestWithRetry(
  AuthSession session,
  Future<http.Response> Function(AuthSession active) send, {
  http.Client? client,
  bool retried = false,
}) async {
  final active = AuthSessionCoordinator.instance.resolve(session);
  var resp = await send(active);
  if (!retried && AuthSessionCoordinator.isRecoverable401(resp)) {
    final refreshed = await AuthSessionCoordinator.instance.refreshToken();
    if (refreshed != null) {
      resp = await send(refreshed);
    }
  }
  AuthSessionGuard.instance.inspectResponse(resp);
  return resp;
}

Future<http.Response> dunesHttpGet(
  AuthSession session,
  String path, {
  Map<String, String>? headers,
  http.Client? client,
}) {
  final c = client ?? http.Client();
  return _dunesRequestWithRetry(
    session,
    (active) => c.get(
      dunesApiUri(active, path),
      headers: dunesAuthHeaders(active, headers),
    ),
    client: c,
  );
}

Future<http.Response> dunesHttpPost(
  AuthSession session,
  String path, {
  Object? body,
  Map<String, String>? headers,
  http.Client? client,
}) {
  final c = client ?? http.Client();
  return _dunesRequestWithRetry(
    session,
    (active) => c.post(
      dunesApiUri(active, path),
      headers: dunesAuthHeaders(active, headers),
      body: body,
    ),
    client: c,
  );
}

Future<http.Response> dunesHttpPatch(
  AuthSession session,
  String path, {
  Object? body,
  Map<String, String>? headers,
  http.Client? client,
}) {
  final c = client ?? http.Client();
  return _dunesRequestWithRetry(
    session,
    (active) => c.patch(
      dunesApiUri(active, path),
      headers: dunesAuthHeaders(active, headers),
      body: body,
    ),
    client: c,
  );
}

Future<http.Response> dunesHttpPut(
  AuthSession session,
  String path, {
  Object? body,
  Map<String, String>? headers,
  http.Client? client,
}) {
  final c = client ?? http.Client();
  return _dunesRequestWithRetry(
    session,
    (active) => c.put(
      dunesApiUri(active, path),
      headers: dunesAuthHeaders(active, headers),
      body: body,
    ),
    client: c,
  );
}

Future<http.Response> dunesHttpDelete(
  AuthSession session,
  String path, {
  Map<String, String>? headers,
  http.Client? client,
}) {
  final c = client ?? http.Client();
  return _dunesRequestWithRetry(
    session,
    (active) => c.delete(
      dunesApiUri(active, path),
      headers: dunesAuthHeaders(active, headers),
    ),
    client: c,
  );
}
