import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';
import 'native_meeting_models.dart';

class NativeMeetingService {
  NativeMeetingService({required this.session});

  final AuthSession session;
  static const bool _forceMeetingProxy = false;
  String? _resolvedMeetingBasePath;
  static const List<String> _meetingBasePathCandidates = <String>[
    '/ai/meeting-minutes',
    '/meeting-beta/ai/meeting-minutes',
  ];

  Future<List<NativeMeetingSummary>> fetchList({
    int page = 0,
    int size = 20,
  }) async {
    final result = await fetchListPage(page: page, size: size);
    return result.items;
  }

  Future<NativeMeetingListPageResult> fetchListPage({
    int page = 0,
    int size = 20,
  }) async {
    final q = <String, String>{
      'owner': 'me',
      'page': page.toString(),
      'size': size.toString(),
    };
    final resp = await _requestMeeting(
      'GET',
      '?${Uri(queryParameters: q).query}',
    );
    _ensureSuccess(resp);
    final data = _unwrapData(resp.body);
    final content =
        (data['content'] as List?) ?? (data['items'] as List?) ?? const [];
    final items = content
        .whereType<Map>()
        .map((e) => NativeMeetingSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    return NativeMeetingListPageResult(
      items: items,
      totalCount: _readTotalCount(data, fallback: items.length),
    );
  }

  Future<int> fetchMyCount() async {
    try {
      final result = await fetchListPage(page: 0, size: 1);
      return result.totalCount;
    } catch (_) {
      return 0;
    }
  }

  Future<int> createMeeting({
    required String title,
    required String meetingDate,
  }) async {
    final resp = await _requestMeeting(
      'POST',
      '',
      body: jsonEncode(<String, dynamic>{
        'title': title,
        'meetingDate': meetingDate,
        'attendees': const <Object>[],
      }),
    );
    _ensureSuccess(resp);
    final data = _unwrapData(resp.body);
    final id = data['meetingId'] ?? data['id'] ?? data['meeting_id'];
    if (id is num) return id.toInt();
    if (id is String) return int.tryParse(id) ?? 0;
    return 0;
  }

  Future<int> createByMeetingDoc({
    required String title,
    required String meetingDate,
    required String filePath,
  }) async {
    final meetingId = await createMeeting(title: title, meetingDate: meetingDate);
    final filename = filenameFromPath(filePath);
    final upload = await uploadAudioFile(filePath: filePath, fileName: filename);
    final audioObjectKey = (upload['objectKey'] ?? '').toString();
    final audioUrl = (upload['url'] ?? upload['objectKey'] ?? '').toString();
    final contentType = (upload['contentType'] ?? 'audio/wav').toString();

    // Use local async pipeline as source of truth: once confirmed, backend can
    // keep processing even if the user exits the app.
    await confirmUpload(
      meetingId: meetingId,
      audioObjectKey: audioObjectKey,
      audioUrl: audioUrl,
      contentType: contentType,
      durationSeconds: guessDurationSeconds(filePath),
    );
    return meetingId;
  }

  Future<Map<String, dynamic>> uploadAudioFile({
    required String filePath,
    required String fileName,
    String bucket = 'meeting-audio',
  }) async {
    final uri = dunesApiUri(session, '/storage/upload');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer ${session.token}';
    req.fields['bucket'] = bucket;
    req.files.add(
      await http.MultipartFile.fromPath('file', filePath, filename: fileName),
    );
    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('upload failed: ${streamed.statusCode} $body');
    }
    return _unwrapData(body);
  }

  Future<void> confirmUpload({
    required int meetingId,
    required String audioObjectKey,
    required String audioUrl,
    required String contentType,
    required int durationSeconds,
  }) async {
    final resp = await _requestMeeting(
      'POST',
      '/$meetingId/upload',
      body: jsonEncode(<String, dynamic>{
        'audioObjectKey': audioObjectKey,
        'audioUrl': audioUrl,
        'audioContentType': contentType,
        'audioDurationSeconds': durationSeconds,
      }),
    );
    _ensureSuccess(resp);
  }

  Future<NativeMeetingDetail> fetchDetail(int meetingId) async {
    final resp = await _requestMeeting('GET', '/$meetingId');
    _ensureSuccess(resp);
    final data = _normalizeMeetingPayload(_unwrapData(resp.body));
    return NativeMeetingDetail.fromJson(data);
  }

  Future<void> regenerate(int meetingId) async {
    final resp = await _requestMeeting(
      'POST',
      '/$meetingId/regenerate',
      body: '{}',
    );
    _ensureSuccess(resp);
  }

  Future<void> deleteMeeting(int meetingId) async {
    final resp = await _requestMeeting('DELETE', '/$meetingId');
    if (resp.statusCode == 204 ||
        (resp.statusCode >= 200 && resp.statusCode < 300)) {
      return;
    }
    _ensureSuccess(resp);
  }

  String filenameFromPath(String path) {
    final p = path.replaceAll('\\', '/');
    final idx = p.lastIndexOf('/');
    return idx >= 0 ? p.substring(idx + 1) : p;
  }

  int guessDurationSeconds(String path) {
    final file = File(path);
    final size = file.existsSync() ? file.lengthSync() : 0;
    if (size <= 0) return 0;
    // 16k/16bit/mono wav rough estimate fallback.
    return (size / 32000).ceil();
  }

  Map<String, dynamic> _unwrapData(String raw) {
    final body = _decodeJsonMap(raw);
    return _unwrapDataFromDecoded(body);
  }

  Map<String, dynamic> _unwrapDataFromDecoded(dynamic body) {
    if (body is! Map<String, dynamic>) return <String, dynamic>{};
    final data = body['data'];
    if (data is Map<String, dynamic>) return data;
    return body;
  }

  dynamic _decodeJsonMap(String raw) {
    final content = raw.trim();
    if (content.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(content);
    } on FormatException {
      // Some error paths return plain text/HTML; keep UI alive and avoid
      // surfacing raw JSON parsing errors to the page.
      return <String, dynamic>{'message': content};
    }
  }

  void _ensureSuccess(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw Exception('请求失败(${resp.statusCode})');
  }

  Future<http.Response> _requestMeeting(
    String method,
    String suffix, {
    Object? body,
  }) async {
    http.Response? lastNotFound;
    for (final basePath in _basePathCandidates()) {
      final path = '$basePath$suffix';
      final http.Response resp;
      switch (method) {
        case 'GET':
          resp = await dunesHttpGet(session, path);
        case 'DELETE':
          resp = await dunesHttpDelete(session, path);
        default:
          resp = await dunesHttpPost(session, path, body: body);
      }
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _resolvedMeetingBasePath = basePath;
        return resp;
      }
      if (resp.statusCode == 404) {
        lastNotFound = resp;
        continue;
      }
      return resp;
    }
    if (lastNotFound != null) return lastNotFound;
    throw Exception('meeting endpoint unavailable');
  }

  Iterable<String> _basePathCandidates() sync* {
    if (_forceMeetingProxy) {
      yield _meetingBasePathCandidates.first;
      return;
    }
    final resolved = _resolvedMeetingBasePath;
    if (resolved != null) yield resolved;
    for (final candidate in _meetingBasePathCandidates) {
      if (candidate != resolved) yield candidate;
    }
  }
}

class NativeMeetingListPageResult {
  const NativeMeetingListPageResult({
    required this.items,
    required this.totalCount,
  });

  final List<NativeMeetingSummary> items;
  final int totalCount;
}

int _readTotalCount(Map<String, dynamic> data, {required int fallback}) {
  for (final key in const [
    'totalElements',
    'total',
    'totalCount',
    'count',
    'totalItems',
  ]) {
    final raw = data[key];
    if (raw is num && raw >= 0) return raw.toInt();
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null && parsed >= 0) return parsed;
    }
  }
  return fallback;
}

Map<String, dynamic> _normalizeMeetingPayload(Map<String, dynamic> json) {
  final meeting = json['meeting'];
  if (meeting is Map) {
    final merged = Map<String, dynamic>.from(meeting);
    for (final key in const [
      'transcript',
      'minutes',
      'actionItems',
      'audioPlayUrl',
      'audioUrl',
      'summary',
      'status',
      'asrProgress',
      'title',
      'meetingDate',
      'createdAt',
      'updatedAt',
    ]) {
      if (!merged.containsKey(key) && json.containsKey(key)) {
        merged[key] = json[key];
      }
    }
    if (!merged.containsKey('meetingId')) {
      for (final key in const ['meetingId', 'id', 'meeting_id']) {
        if (json.containsKey(key)) {
          merged[key] = json[key];
          break;
        }
      }
    }
    return merged;
  }
  return json;
}
