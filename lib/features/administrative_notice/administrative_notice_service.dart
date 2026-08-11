import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_service.dart';
import 'administrative_notice_models.dart';

class AdministrativeNoticeService {
  AdministrativeNoticeService({required this.session, http.Client? client})
      : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }

  dynamic _unwrap(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('行政通知请求失败：HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['success'] == false) {
      throw Exception((decoded['message'] ?? '行政通知请求失败').toString());
    }
    if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
    return decoded;
  }

  Future<bool> canAccess() async {
    final response = await dunesHttpGet(session, '/admin-notices/access', client: _client);
    final data = _unwrap(response);
    return data is Map && data['enabled'] == true;
  }

  Future<List<AdministrativeNoticeUser>> fetchUsers() async {
    final response = await dunesHttpGet(session, '/admin-notices/users', client: _client);
    final data = _unwrap(response);
    final rows = data is List ? data : (data is Map ? data['items'] : null);
    if (rows is! List) return const <AdministrativeNoticeUser>[];
    return rows.whereType<Map>().map((e) => AdministrativeNoticeUser.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<AdministrativeNotice>> fetchNotices() async {
    final response = await dunesHttpGet(session, '/admin-notices', client: _client);
    final data = _unwrap(response);
    final rows = data is List ? data : (data is Map ? data['items'] : null);
    if (rows is! List) return const <AdministrativeNotice>[];
    return rows.whereType<Map>().map((e) => AdministrativeNotice.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<AdministrativeNotice> fetchNotice(int id) async {
    final response = await dunesHttpGet(session, '/admin-notices/$id', client: _client);
    final data = _unwrap(response);
    if (data is! Map) throw Exception('行政通知数据为空');
    return AdministrativeNotice.fromJson(Map<String, dynamic>.from(data));
  }

  Future<AdministrativeNotice> createNotice({
    required String title,
    required String body,
    required List<int> recipientUserIds,
    List<Map<String, dynamic>> attachments = const <Map<String, dynamic>>[],
  }) async {
    final response = await dunesHttpPost(
      session,
      '/admin-notices',
      client: _client,
      body: jsonEncode(<String, dynamic>{
        'title': title,
        'body': body,
        'recipientUserIds': recipientUserIds,
        'attachments': attachments,
      }),
    );
    final data = _unwrap(response);
    if (data is! Map) throw Exception('行政通知创建失败');
    return AdministrativeNotice.fromJson(Map<String, dynamic>.from(data));
  }

  Future<AdministrativeNotice> acknowledge(int id) async {
    final response = await dunesHttpPost(session, '/admin-notices/$id/ack', client: _client);
    final data = _unwrap(response);
    if (data is! Map) throw Exception('行政通知确认失败');
    return AdministrativeNotice.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Map<String, dynamic>> upload(XFile file) async {
    final bytes = await file.readAsBytes();
    final name = file.name.isEmpty ? 'attachment' : file.name;
    final mime = file.mimeType ?? 'application/octet-stream';
    final uploader = ConversationService(session: session);
    try {
      final uploaded = await uploader.uploadAttachment(
        conversationId: 0,
        bytes: bytes,
        fileName: name,
        mimeType: mime,
      );
      return <String, dynamic>{
        'fileName': name,
        'mimeType': mime,
        'sizeBytes': bytes.length,
        'url': uploaded.url,
        'objectKey': uploaded.objectKey,
      };
    } finally {
      uploader.close();
    }
  }
}
