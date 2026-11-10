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
  bool retried = false,
}) async {
  final active = AuthSessionCoordinator.instance.resolve(session);
  var resp = await send(active);
  var sentToken = active.token;
  if (!retried &&
      AuthSessionCoordinator.isRecoverable401(resp) &&
      AuthSessionCoordinator.instance.tokenIsCurrent(sentToken)) {
    final refreshed = await AuthSessionCoordinator.instance.refreshToken();
    AuthSessionGuard.instance.consumeRefreshLogout();
    if (refreshed != null &&
        AuthSessionCoordinator.instance.tokenIsCurrent(refreshed.token)) {
      resp = await send(refreshed);
      sentToken = refreshed.token;
    }
  }
  AuthSessionGuard.instance.inspectResponse(resp, requestToken: sentToken);
  return resp;
}

Future<http.Response> _withClient(
  http.Client? client,
  Future<http.Response> Function(http.Client client) send,
) {
  if (client != null) return send(client);
  final owned = http.Client();
  return send(owned).whenComplete(owned.close);
}

Future<http.Response> dunesHttpGet(
  AuthSession session,
  String path, {
  Map<String, String>? headers,
  http.Client? client,
}) {
  return _withClient(
    client,
    (c) => _dunesRequestWithRetry(
      session,
      (active) => c.get(
        dunesApiUri(active, path),
        headers: dunesAuthHeaders(active, headers),
      ),
    ),
  );
}

Future<http.Response> dunesHttpPost(
  AuthSession session,
  String path, {
  Object? body,
  Map<String, String>? headers,
  http.Client? client,
}) {
  return _withClient(
    client,
    (c) => _dunesRequestWithRetry(
      session,
      (active) => c.post(
        dunesApiUri(active, path),
        headers: dunesAuthHeaders(active, headers),
        body: body,
      ),
    ),
  );
}

Future<http.Response> dunesHttpPatch(
  AuthSession session,
  String path, {
  Object? body,
  Map<String, String>? headers,
  http.Client? client,
}) {
  return _withClient(
    client,
    (c) => _dunesRequestWithRetry(
      session,
      (active) => c.patch(
        dunesApiUri(active, path),
        headers: dunesAuthHeaders(active, headers),
        body: body,
      ),
    ),
  );
}

Future<http.Response> dunesHttpPut(
  AuthSession session,
  String path, {
  Object? body,
  Map<String, String>? headers,
  http.Client? client,
}) {
  return _withClient(
    client,
    (c) => _dunesRequestWithRetry(
      session,
      (active) => c.put(
        dunesApiUri(active, path),
        headers: dunesAuthHeaders(active, headers),
        body: body,
      ),
    ),
  );
}

Future<http.Response> dunesHttpDelete(
  AuthSession session,
  String path, {
  Map<String, String>? headers,
  http.Client? client,
}) {
  return _withClient(
    client,
    (c) => _dunesRequestWithRetry(
      session,
      (active) => c.delete(
        dunesApiUri(active, path),
        headers: dunesAuthHeaders(active, headers),
      ),
    ),
  );
}
