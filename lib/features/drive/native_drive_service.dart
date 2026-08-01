import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';
import 'native_drive_models.dart';

class NativeDriveService {
  NativeDriveService({required this.session, http.Client? client})
    : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;

  Future<List<DriveSpace>> fetchSpaces() async {
    final data = await _get('/drive/spaces');
    final rows = data is List ? data : const <dynamic>[];
    return rows
        .whereType<Map>()
        .map((row) => DriveSpace.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<DriveItem>> fetchItems({
    required int spaceId,
    int? parentId,
    String query = '',
  }) async {
    final params = <String, String>{'spaceId': '$spaceId'};
    if (parentId != null && parentId > 0) params['parentId'] = '$parentId';
    if (query.trim().isNotEmpty) params['query'] = query.trim();
    final data = await _get(
      '/drive/items?${Uri(queryParameters: params).query}',
    );
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    final rows = map['items'] is List
        ? map['items'] as List
        : const <dynamic>[];
    return rows
        .whereType<Map>()
        .map((row) => DriveItem.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<DriveItem>> fetchTrash() async {
    final data = await _get('/drive/trash');
    final rows = data is List ? data : const <dynamic>[];
    return rows
        .whereType<Map>()
        .map((row) {
          final raw = row['item'] is Map ? row['item'] as Map : row;
          return DriveItem.fromJson(Map<String, dynamic>.from(raw));
        })
        .toList(growable: false);
  }

  Future<DriveSpace> createSpace(
    String name, {
    String description = '',
    List<Map<String, dynamic>> members = const [],
  }) async {
    final data = await _post('/drive/spaces', {
      'name': name,
      'description': description,
      'members': members,
    });
    return DriveSpace.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<DriveUser>> fetchUsers({String query = ''}) async {
    final suffix = query.trim().isEmpty
        ? ''
        : '?query=${Uri.encodeQueryComponent(query.trim())}';
    final data = await _get('/drive/users$suffix');
    final rows = data is List ? data : const <dynamic>[];
    return rows
        .whereType<Map>()
        .map((row) => DriveUser.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchMembers(int spaceId) async {
    final data = await _get('/drive/spaces/$spaceId/members');
    final rows = data is List ? data : const <dynamic>[];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<void> replaceMembers(
    int spaceId,
    List<Map<String, dynamic>> members,
  ) async {
    await _put('/drive/spaces/$spaceId/members', members);
  }

  Future<void> renameSpace(int spaceId, String name) async {
    await _patch('/drive/spaces/$spaceId', {'name': name});
  }

  Future<void> deleteSpace(int spaceId) => _delete('/drive/spaces/$spaceId');

  Future<DriveItem> createFolder({
    required int spaceId,
    int? parentId,
    required String name,
  }) async {
    final data = await _post('/drive/folders', {
      'spaceId': spaceId,
      if (parentId != null) 'parentId': parentId,
      'name': name,
    });
    return DriveItem.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriveItem> rename(int id, String name) async {
    final data = await _patch('/drive/items/$id', {'name': name});
    return DriveItem.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> trash(int id) => _delete('/drive/items/$id');

  Future<void> restoreTrash(int id) =>
      _post('/drive/trash/$id/restore', const {});

  Future<void> purgeTrash(int id) => _delete('/drive/trash/$id');

  Future<void> move({required int id, required int spaceId, int? parentId}) =>
      _post('/drive/items/$id/move', {
        'spaceId': spaceId,
        if (parentId != null) 'parentId': parentId,
      });

  Future<void> copy({required int id, required int spaceId, int? parentId}) =>
      _post('/drive/items/$id/copy', {
        'spaceId': spaceId,
        if (parentId != null) 'parentId': parentId,
      });

  Future<List<DriveVersion>> fetchVersions(int itemId) async {
    final data = await _get('/drive/items/$itemId/versions');
    final rows = data is Map && data['versions'] is List
        ? data['versions'] as List
        : const <dynamic>[];
    return rows
        .whereType<Map>()
        .map((row) => DriveVersion.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> restoreVersion(int itemId, int versionId) =>
      _post('/drive/items/$itemId/versions/$versionId/restore', const {});

  Future<void> uploadVersion({required int itemId, required XFile file}) async {
    final request = http.MultipartRequest(
      'POST',
      dunesApiUri(session, '/drive/items/$itemId/versions'),
    );
    request.headers.addAll(dunesAuthHeaders(session)..remove('Content-Type'));
    request.files.add(
      http.MultipartFile(
        'file',
        file.openRead(),
        await file.length(),
        filename: file.name,
        contentType: file.mimeType == null
            ? null
            : MediaType.parse(file.mimeType!),
      ),
    );
    final response = await _client.send(request);
    _unwrap(await http.Response.fromStream(response));
  }

  Future<List<DriveShareLink>> fetchShareLinks(int itemId) async {
    final data = await _get('/drive/items/$itemId/share-links');
    final rows = data is List ? data : const <dynamic>[];
    return rows
        .whereType<Map>()
        .map((row) => DriveShareLink.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<DriveShareLink> createShareLink(
    int itemId, {
    String password = '',
    int expiresDays = 7,
  }) async {
    final data = await _post('/drive/items/$itemId/share-links', {
      'password': password,
      'expiresDays': expiresDays,
    });
    return DriveShareLink.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> revokeShareLink(int linkId) =>
      _delete('/drive/share-links/$linkId');

  /// 标记当前用户已将此微盘文件存入自己的知识库。
  Future<void> markKbSaved(int itemId, {int version = 0}) =>
      _post('/drive/items/$itemId/kb-save', {
        if (version > 0) 'version': version,
      });

  /// 标记当前用户已将此微盘文件下载到本地。
  Future<void> markDownloaded(int itemId, {int version = 0}) =>
      _post('/drive/items/$itemId/downloaded', {
        if (version > 0) 'version': version,
      });

  /// 标记 IM 附件已存入微盘（按人、按 sourceKey）。
  Future<void> markChatSaved({
    required String sourceKey,
    int driveItemId = 0,
    String fileName = '',
  }) =>
      _post('/drive/chat-saves', {
        'sourceKey': sourceKey,
        if (driveItemId > 0) 'driveItemId': driveItemId,
        if (fileName.trim().isNotEmpty) 'fileName': fileName.trim(),
      });

  /// 查询哪些 IM 附件 sourceKey 已存入微盘。
  Future<Set<String>> fetchChatSavedKeys(Iterable<String> keys) async {
    final list = keys
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(100)
        .toList(growable: false);
    if (list.isEmpty) return const <String>{};
    final query = list.map(Uri.encodeQueryComponent).join(',');
    final data = await _get('/drive/chat-saves?keys=$query');
    final rows = data is Map && data['savedKeys'] is List
        ? data['savedKeys'] as List
        : const <dynamic>[];
    return rows.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toSet();
  }

  Future<DriveItem> upload({
    required int spaceId,
    int? parentId,
    required XFile file,
    void Function(double progress)? onProgress,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      dunesApiUri(session, '/drive/files'),
    );
    request.headers.addAll(dunesAuthHeaders(session)..remove('Content-Type'));
    request.fields['spaceId'] = '$spaceId';
    if (parentId != null) request.fields['parentId'] = '$parentId';
    final total = await file.length();
    var sent = 0;
    Stream<List<int>> chunked() async* {
      await for (final chunk in file.openRead()) {
        yield chunk;
        sent += chunk.length;
        if (total > 0) {
          onProgress?.call((sent / total).clamp(0.0, 0.99));
        }
      }
    }

    request.files.add(
      http.MultipartFile(
        'file',
        http.ByteStream(chunked()),
        total,
        filename: file.name,
        contentType: file.mimeType == null
            ? null
            : MediaType.parse(file.mimeType!),
      ),
    );
    onProgress?.call(0.01);
    final response = await _client.send(request);
    final body = await http.Response.fromStream(response);
    onProgress?.call(1);
    return DriveItem.fromJson(Map<String, dynamic>.from(_unwrap(body) as Map));
  }

  /// 从内存字节上传到微盘（供 IM 存入微盘等场景）。
  Future<DriveItem> uploadBytes({
    required int spaceId,
    int? parentId,
    required List<int> bytes,
    required String fileName,
    String? mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      dunesApiUri(session, '/drive/files'),
    );
    request.headers.addAll(dunesAuthHeaders(session)..remove('Content-Type'));
    request.fields['spaceId'] = '$spaceId';
    if (parentId != null) request.fields['parentId'] = '$parentId';
    final name = fileName.trim().isEmpty ? '文件' : fileName.trim();
    final mediaType = (mimeType ?? '').trim().isEmpty
        ? null
        : MediaType.parse(mimeType!.trim());
    onProgress?.call(0.01);
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: name,
        contentType: mediaType,
      ),
    );
    final response = await _client.send(request);
    final body = await http.Response.fromStream(response);
    onProgress?.call(1);
    return DriveItem.fromJson(Map<String, dynamic>.from(_unwrap(body) as Map));
  }

  void close() {
    _client.close();
  }

  Uri contentUri(int itemId, {bool inline = false}) => dunesApiUri(
    session,
    '/drive/items/$itemId/content${inline ? '?inline=1' : ''}',
  );

  Map<String, String> contentHeaders() => dunesAuthHeaders(session);

  Future<dynamic> _get(String path) async {
    final response = await dunesHttpGet(session, path, client: _client);
    return _unwrap(response);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final response = await dunesHttpPost(
      session,
      path,
      body: jsonEncode(body),
      client: _client,
    );
    return _unwrap(response);
  }

  Future<dynamic> _delete(String path) async {
    final response = await dunesHttpDelete(session, path, client: _client);
    return _unwrap(response);
  }

  Future<dynamic> _patch(String path, Map<String, dynamic> body) async {
    final response = await _client.patch(
      dunesApiUri(session, path),
      headers: dunesAuthHeaders(session),
      body: jsonEncode(body),
    );
    return _unwrap(response);
  }

  Future<dynamic> _put(String path, Object body) async {
    final response = await _client.put(
      dunesApiUri(session, path),
      headers: dunesAuthHeaders(session),
      body: jsonEncode(body),
    );
    return _unwrap(response);
  }

  dynamic _unwrap(http.Response response) {
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      body = <String, dynamic>{};
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        (body is Map && body['success'] == false)) {
      final message = body is Map ? '${body['message'] ?? ''}' : '';
      throw Exception(
        message.trim().isEmpty
            ? '网盘请求失败（HTTP ${response.statusCode}）'
            : message,
      );
    }
    if (body is Map && body.containsKey('data')) return body['data'];
    return body;
  }
}
