import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';
import 'meeting_storage_multipart.dart';
import 'native_meeting_models.dart';

class NativeMeetingService {
  NativeMeetingService({required this.session});

  final AuthSession session;
  static const bool _forceMeetingProxy = false;
  String? _resolvedMeetingBasePath;
  static const List<String> _meetingBasePathCandidates = <String>[
    '/ai/meeting-minutes',
  ];

  Future<List<NativeMeetingSummary>> fetchList({
    int page = 0,
    int size = 20,
    String keyword = '',
  }) async {
    final result = await fetchListPage(
      page: page,
      size: size,
      keyword: keyword,
    );
    return result.items;
  }

  Future<NativeMeetingListPageResult> fetchListPage({
    int page = 0,
    int size = 20,
    String keyword = '',
  }) async {
    final q = <String, String>{
      'owner': 'me',
      'page': page.toString(),
      'size': size.toString(),
    };
    final trimmedKeyword = keyword.trim();
    if (trimmedKeyword.isNotEmpty) {
      q['q'] = trimmedKeyword;
    }
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

  /// 千机·会议纪要监管：关键词（人名/会议名）+ 部门筛选。
  Future<NativeMeetingListPageResult> fetchSuperviseListPage({
    int page = 0,
    int size = 20,
    String keyword = '',
    int? departmentId,
  }) async {
    final q = <String, String>{
      'scope': 'supervise',
      'page': page.toString(),
      'size': size.toString(),
    };
    final k = keyword.trim();
    if (k.isNotEmpty) {
      q['q'] = k;
    }
    if (departmentId != null) {
      q['departmentId'] = departmentId.toString();
    }
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

  /// 监管范围通讯录人员（本人 + 下级），用于列表人员搜索。
  Future<List<NativeSupervisePerson>> fetchSupervisePeople({
    String keyword = '',
  }) async {
    final q = <String, String>{};
    final k = keyword.trim();
    if (k.isNotEmpty) {
      q['q'] = k;
    }
    final suffix = q.isEmpty ? '' : '?${Uri(queryParameters: q).query}';
    final resp = await _requestMeeting('GET', '/supervise/people$suffix');
    _ensureSuccess(resp);
    final data = _unwrapData(resp.body);
    final content =
        (data['content'] as List?) ?? (data['items'] as List?) ?? const [];
    return content
        .whereType<Map>()
        .map(
          (e) => NativeSupervisePerson.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList(growable: false);
  }

  /// 按部门统计会议总数（全部监管则全部门，否则本人及下级范围）。
  Future<NativeSuperviseDeptStatsResult> fetchSuperviseDeptStats() async {
    final resp = await _requestMeeting('GET', '/supervise/dept-stats');
    _ensureSuccess(resp);
    final data = _unwrapData(resp.body);
    return NativeSuperviseDeptStatsResult.fromJson(data);
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
    final meetingId = await createMeeting(
      title: title,
      meetingDate: meetingDate,
    );
    final filename = filenameFromPath(filePath);
    final upload = await uploadAudioFile(
      filePath: filePath,
      fileName: filename,
    );
    final audioObjectKey = (upload['objectKey'] ?? '').toString();
    final audioUrl = (upload['url'] ?? upload['objectKey'] ?? '').toString();
    final contentType = contentTypeForPath(filePath);

    // Use local async pipeline as source of truth: once confirmed, backend can
    // keep processing even if the user exits the app.
    await confirmUpload(
      meetingId: meetingId,
      audioObjectKey: audioObjectKey,
      audioUrl: audioUrl,
      contentType: contentType,
      durationSeconds: await resolveDurationSeconds(filePath),
    );
    return meetingId;
  }

  Future<Map<String, dynamic>> uploadAudioFile({
    required String filePath,
    required String fileName,
    String bucket = 'meeting-audio',
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0);
    const maxAttempts = 5;
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _uploadAudioPreferringMultipart(
          filePath: filePath,
          fileName: fileName,
          bucket: bucket,
          onProgress: onProgress,
        );
      } catch (e) {
        lastError = e;
        debugPrint(
          'Meeting audio upload attempt $attempt/$maxAttempts failed: $e',
        );
        if (attempt >= maxAttempts || !_isRetryableUploadError(e)) break;
        onProgress?.call(0);
        final jitter = math.Random().nextInt(2000);
        final baseMs = _retryDelayMsForError(e, attempt);
        await Future<void>.delayed(Duration(milliseconds: baseMs + jitter));
      }
    }
    if (lastError is Exception) throw lastError as Exception;
    throw Exception('$lastError');
  }

  int _retryDelayMsForError(Object error, int attempt) {
    final status = _readUploadStatusCode(error);
    if (status == 503 || status == 429) {
      return 3000 * attempt;
    }
    return 900 * attempt;
  }

  int? _readUploadStatusCode(Object error) {
    final text = error.toString();
    final match = RegExp(r'upload failed:\s*(\d{3})').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  bool _isRetryableUploadError(Object error) {
    final status = _readUploadStatusCode(error);
    if (status != null) {
      return status == 408 ||
          status == 429 ||
          status == 502 ||
          status == 503 ||
          status >= 500;
    }
    final msg = error.toString().toLowerCase();
    return msg.contains('timeout') ||
        msg.contains('socket') ||
        msg.contains('connection') ||
        msg.contains('排队') ||
        msg.contains('network') ||
        msg.contains('missing part etag');
  }

  Future<Map<String, dynamic>> _uploadAudioPreferringMultipart({
    required String filePath,
    required String fileName,
    required String bucket,
    void Function(double progress)? onProgress,
  }) async {
    final localFile = io.File(filePath);
    if (!await localFile.exists()) {
      throw Exception('录音文件不存在');
    }
    final fileSize = await localFile.length();
    if (fileSize <= 0) {
      throw Exception('录音文件为空');
    }
    if (!MeetingStorageMultipart.shouldUse(fileSize)) {
      return _uploadAudioViaStorageApi(
        filePath: filePath,
        fileName: fileName,
        bucket: bucket,
        onProgress: onProgress,
      );
    }
    try {
      return await _uploadAudioViaMultipart(
        file: localFile,
        filePath: filePath,
        fileName: fileName,
        fileSize: fileSize,
        bucket: bucket,
        onProgress: onProgress,
      );
    } catch (e) {
      if (!MeetingStorageMultipart.isUnsupported(e)) rethrow;
      debugPrint('Meeting multipart unsupported, fallback to single POST: $e');
      return _uploadAudioViaStorageApi(
        filePath: filePath,
        fileName: fileName,
        bucket: bucket,
        onProgress: onProgress,
      );
    }
  }

  Future<Map<String, dynamic>> _uploadAudioViaMultipart({
    required io.File file,
    required String filePath,
    required String fileName,
    required int fileSize,
    required String bucket,
    void Function(double progress)? onProgress,
  }) async {
    final contentType = contentTypeForPath(filePath);
    final init = await _storageJsonPost('/storage/multipart/init', {
      'bucket': bucket,
      'fileName': fileName,
      'contentType': contentType,
    });
    final objectKey = '${init['objectKey'] ?? ''}'.trim();
    final uploadId = '${init['uploadId'] ?? ''}'.trim();
    final partSize =
        (init['partSize'] as num?)?.toInt() ??
        MeetingStorageMultipart.defaultPartSize;
    if (objectKey.isEmpty || uploadId.isEmpty) {
      throw Exception('初始化分片上传失败');
    }
    final plans = MeetingStorageMultipart.planParts(
      fileSize,
      partSize: partSize,
    );
    if (plans.isEmpty) {
      throw Exception('录音文件为空');
    }
    final parts = <Map<String, dynamic>>[];
    var uploaded = 0;
    for (final plan in plans) {
      final etag = await _putMultipartPart(
        bucket: bucket,
        objectKey: objectKey,
        uploadId: uploadId,
        plan: plan,
        file: file,
      );
      parts.add({'partNumber': plan.partNumber, 'etag': etag});
      uploaded += plan.length;
      onProgress?.call((uploaded / fileSize).clamp(0.0, 0.99));
    }
    final done = await _storageJsonPost('/storage/multipart/complete', {
      'bucket': bucket,
      'objectKey': objectKey,
      'uploadId': uploadId,
      'contentType': contentType,
      'fileName': fileName,
      'fileSize': fileSize,
      'parts': parts,
    });
    onProgress?.call(1);
    final key = '${done['objectKey'] ?? objectKey}'.trim();
    if (key.isEmpty) {
      throw Exception('录音上传失败，未获得文件标识');
    }
    return <String, dynamic>{
      ...done,
      'objectKey': key,
      'bucket': done['bucket'] ?? bucket,
      'contentType': done['contentType'] ?? contentType,
      'fileName': done['fileName'] ?? fileName,
      'size': done['size'] ?? fileSize,
    };
  }

  Future<String> _putMultipartPart({
    required String bucket,
    required String objectKey,
    required String uploadId,
    required MeetingStoragePartPlan plan,
    required io.File file,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final signed = await _storageJsonPost('/storage/multipart/part-url', {
          'bucket': bucket,
          'objectKey': objectKey,
          'uploadId': uploadId,
          'partNumber': plan.partNumber,
        });
        final url = '${signed['url'] ?? ''}'.trim();
        if (url.isEmpty) {
          throw Exception('upload failed: missing part url');
        }
        final bytes = await _readFileRange(file, plan.offset, plan.length);
        final put = await http
            .put(
              Uri.parse(url),
              headers: {'Content-Length': '${bytes.length}'},
              body: bytes,
            )
            .timeout(
              const Duration(minutes: 10),
              onTimeout: () => throw Exception('分片上传超时，请检查网络后重试'),
            );
        if (put.statusCode < 200 || put.statusCode >= 300) {
          throw Exception('upload failed: ${put.statusCode} ${put.body}');
        }
        final etag = MeetingStorageMultipart.etagFromHeaders(put.headers);
        if (etag == null || etag.isEmpty) {
          throw Exception('upload failed: missing part etag');
        }
        return etag;
      } catch (e) {
        lastError = e;
        debugPrint(
          'Meeting multipart part ${plan.partNumber} attempt $attempt/3 failed: $e',
        );
        if (attempt >= 3 || !_isRetryableUploadError(e)) break;
        await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
      }
    }
    if (lastError is Exception) throw lastError as Exception;
    throw Exception('$lastError');
  }

  Future<List<int>> _readFileRange(io.File file, int offset, int length) async {
    final raf = await file.open();
    try {
      await raf.setPosition(offset);
      return await raf.read(length);
    } finally {
      await raf.close();
    }
  }

  Future<Map<String, dynamic>> _storageJsonPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await dunesHttpPost(
      session,
      path,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 45));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('upload failed: ${resp.statusCode} ${resp.body}');
    }
    return _unwrapData(resp.body);
  }

  Future<Map<String, dynamic>> _uploadAudioViaStorageApi({
    required String filePath,
    required String fileName,
    required String bucket,
    void Function(double progress)? onProgress,
  }) async {
    final localFile = io.File(filePath);
    if (!await localFile.exists()) {
      throw Exception('录音文件不存在');
    }
    final fileSize = await localFile.length();
    if (fileSize <= 0) {
      throw Exception('录音文件为空');
    }

    final uri = dunesApiUri(session, '/storage/upload');
    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer ${session.token}'
      ..fields['bucket'] = bucket;
    req.files.add(
      await _multipartFileFromPath(
        field: 'file',
        filePath: filePath,
        fileName: fileName,
        fileSize: fileSize,
        onProgress: onProgress,
      ),
    );

    final streamed = await req.send().timeout(
      const Duration(minutes: 30),
      onTimeout: () => throw Exception('上传超时，请检查网络后重试'),
    );
    final body = await streamed.stream.bytesToString().timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw Exception('上传响应超时，请稍后重试'),
    );
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('upload failed: ${streamed.statusCode} $body');
    }
    final data = _unwrapData(body);
    final objectKey = (data['objectKey'] ?? '').toString().trim();
    if (objectKey.isEmpty) {
      throw Exception('录音上传失败，未获得文件标识');
    }
    onProgress?.call(1);
    return data;
  }

  Future<http.MultipartFile> _multipartFileFromPath({
    required String field,
    required String filePath,
    required String fileName,
    required int fileSize,
    void Function(double progress)? onProgress,
  }) async {
    Stream<List<int>> chunked() async* {
      const chunkSize = 512 * 1024;
      final raf = await io.File(filePath).open(mode: io.FileMode.read);
      try {
        var sent = 0;
        while (true) {
          final chunk = await raf.read(chunkSize);
          if (chunk.isEmpty) break;
          yield chunk;
          sent += chunk.length;
          if (fileSize > 0) {
            onProgress?.call((sent / fileSize).clamp(0.0, 1.0));
          }
        }
      } finally {
        await raf.close();
      }
    }

    return http.MultipartFile(
      field,
      http.ByteStream(chunked()),
      fileSize,
      filename: fileName,
    );
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

  Future<void> saveDraftAudio({
    required int meetingId,
    required String audioObjectKey,
    required String audioUrl,
    required String contentType,
    required int durationSeconds,
  }) async {
    await _attachDraftAudio(
      meetingId: meetingId,
      audioObjectKey: audioObjectKey,
      audioUrl: audioUrl,
      contentType: contentType,
      durationSeconds: durationSeconds,
    );
  }

  Future<void> _attachDraftAudio({
    required int meetingId,
    required String audioObjectKey,
    required String audioUrl,
    required String contentType,
    required int durationSeconds,
  }) async {
    final audioPayload = <String, dynamic>{
      'audioObjectKey': audioObjectKey,
      'audioUrl': audioUrl,
      'audioContentType': contentType,
      'audioDurationSeconds': durationSeconds,
    };
    final errors = <String>[];

    Future<bool> tryDraftEndpoint({
      required String label,
      required String suffix,
      required Map<String, dynamic> body,
    }) async {
      try {
        final resp = await _requestMeeting(
          'POST',
          suffix,
          body: jsonEncode(body),
        );
        if (resp.statusCode == 404) {
          errors.add('$label 接口不存在(404)');
          return false;
        }
        _ensureSuccess(resp);
        final status = _readMeetingStatus(resp.body);
        if (_isDraftLikeStatus(status)) return true;
        if (status == 'TRANSCRIBING' || status == 'GENERATING') {
          errors.add('$label 已开始转写($status)');
        } else if (status.isNotEmpty) {
          errors.add('$label 返回状态异常($status)');
        } else {
          errors.add('$label 未返回草稿状态');
        }
      } on Exception catch (e) {
        errors.add('$label：${_stripExceptionPrefix(e)}');
      }
      return false;
    }

    // 优先 draft-audio；旧版 /upload 会忽略 saveAsDraft 并直接开始转写。
    if (await tryDraftEndpoint(
      label: 'draft-audio',
      suffix: '/$meetingId/draft-audio',
      body: audioPayload,
    )) {
      return;
    }
    if (await tryDraftEndpoint(
      label: 'upload',
      suffix: '/$meetingId/upload',
      body: <String, dynamic>{...audioPayload, 'saveAsDraft': true},
    )) {
      return;
    }

    final detail = errors.join('；');
    if (detail.contains('已开始转写') || detail.contains('TRANSCRIBING')) {
      throw Exception('会议纪要服务未更新，无法存草稿（已开始转写）');
    }
    throw Exception(detail.isEmpty ? '草稿保存失败，请稍后重试' : '草稿保存失败：$detail');
  }

  String _stripExceptionPrefix(Exception e) {
    return e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  }

  String _readMeetingStatus(String rawBody) {
    final data = _unwrapData(rawBody);
    final direct = (data['status'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct.toUpperCase();
    final meeting = data['meeting'];
    if (meeting is Map) {
      return (meeting['status'] ?? '').toString().trim().toUpperCase();
    }
    return '';
  }

  bool _isDraftLikeStatus(String status) {
    return status.isEmpty || status == 'DRAFT';
  }

  Future<int> saveMeetingDraft({
    required String title,
    required String meetingDate,
    required String filePath,
  }) async {
    final meetingId = await createMeeting(
      title: title,
      meetingDate: meetingDate,
    );
    if (meetingId <= 0) {
      throw Exception('创建会议记录失败，请重试');
    }
    final filename = filenameFromPath(filePath);
    final upload = await uploadAudioFile(
      filePath: filePath,
      fileName: filename,
    );
    final audioObjectKey = (upload['objectKey'] ?? '').toString().trim();
    if (audioObjectKey.isEmpty) {
      throw Exception('录音上传失败，未获得文件标识');
    }
    final audioUrl = _readUploadUrl(upload, audioObjectKey);
    final contentType = contentTypeForPath(filePath);
    await _attachDraftAudio(
      meetingId: meetingId,
      audioObjectKey: audioObjectKey,
      audioUrl: audioUrl,
      contentType: contentType,
      durationSeconds: await resolveDurationSeconds(filePath),
    );
    return meetingId;
  }

  String readUploadUrlForAttach(Map<String, dynamic> upload, String objectKey) {
    return _readUploadUrl(upload, objectKey);
  }

  String _readUploadUrl(Map<String, dynamic> upload, String objectKey) {
    final url = (upload['url'] ?? '').toString().trim();
    if (url.isNotEmpty) return url;
    final key = objectKey.trim();
    if (key.startsWith('http://') || key.startsWith('https://')) return key;
    return key;
  }

  Future<void> startTranscriptionForDraft(NativeMeetingDetail detail) async {
    final objectKey = detail.audioObjectKey.trim();
    if (objectKey.isEmpty) {
      throw Exception('草稿尚未关联录音文件');
    }
    await confirmUpload(
      meetingId: detail.meetingId,
      audioObjectKey: objectKey,
      audioUrl: detail.audioPlayUrl.trim().isNotEmpty
          ? detail.audioPlayUrl.trim()
          : objectKey,
      contentType: 'audio/wav',
      durationSeconds: detail.audioDurationSeconds,
    );
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

  Future<NativeMeetingKbUpload> uploadToKb(int meetingId) async {
    final resp = await _requestMeeting(
      'POST',
      '/$meetingId/upload-to-kb',
      body: '{}',
    );
    _ensureSuccess(resp);
    final data = _unwrapData(resp.body);
    return NativeMeetingKbUpload.fromJson(data);
  }

  Future<void> deleteMeeting(int meetingId) async {
    final resp = await _requestMeeting('DELETE', '/$meetingId');
    if (resp.statusCode == 204) return;
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.body.trim().isEmpty) return;
    }
    _ensureSuccess(resp);
  }

  /// Resolves a downloadable URL for meeting audio (play URL or fresh presign).
  Future<String> resolveAudioDownloadUrl(NativeMeetingDetail detail) async {
    final playUrl = detail.audioPlayUrl.trim();
    if (playUrl.isNotEmpty) return playUrl;

    final objectKey = detail.audioObjectKey.trim();
    if (objectKey.isEmpty) return '';

    final resp = await dunesHttpGet(
      session,
      '/storage/presigned-get?bucket=meeting-audio&objectKey=${Uri.encodeQueryComponent(objectKey)}',
    );
    _ensureSuccess(resp);
    final data = _unwrapData(resp.body);
    return (data['url'] ?? data['downloadUrl'] ?? '').toString().trim();
  }

  /// 导出会议纪要 PDF（优先 inline 直出；兼容旧版 302 重定向）。
  Future<Uint8List> exportPdfBytes(int meetingId) async {
    final uri = dunesApiUri(
      session,
      '/ai/meeting-minutes/$meetingId/export?format=pdf&inline=1',
    );
    final client = http.Client();
    try {
      final resp = await client.get(
        uri,
        headers: <String, String>{
          'Authorization': 'Bearer ${session.token}',
          'Accept': 'application/pdf',
        },
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final bytes = resp.bodyBytes;
        if (bytes.isEmpty) throw Exception('导出 PDF 为空');
        if (bytes.isNotEmpty && bytes.first == 0x7B) {
          final msg = _readErrorMessage(
            _unwrapDataFromDecoded(jsonDecode(utf8.decode(bytes))),
          );
          if (msg.isNotEmpty) throw Exception(msg);
        }
        return bytes;
      }

      // 兼容未部署 inline 的后端：走 302 预签名链接
      if (resp.statusCode == 301 ||
          resp.statusCode == 302 ||
          resp.statusCode == 303 ||
          resp.statusCode == 307 ||
          resp.statusCode == 308) {
        final location = resp.headers['location']?.trim();
        if (location == null || location.isEmpty) {
          throw Exception('导出链接不可用');
        }
        final pdfResp = await client.get(Uri.parse(location));
        if (pdfResp.statusCode < 200 || pdfResp.statusCode >= 300) {
          throw Exception('PDF 下载失败(${pdfResp.statusCode})');
        }
        return pdfResp.bodyBytes;
      }

      final bytes = resp.bodyBytes;
      if (bytes.isNotEmpty) {
        try {
          final body = _decodeJsonMap(utf8.decode(bytes));
          if (body is Map<String, dynamic>) {
            final msg = _readErrorMessage(body);
            if (msg.isNotEmpty) throw Exception(msg);
          }
        } catch (_) {}
      }
      throw Exception('导出 PDF 失败(${resp.statusCode})');
    } finally {
      client.close();
    }
  }

  String audioDownloadFileName(NativeMeetingDetail detail) {
    final key = detail.audioObjectKey.trim();
    if (key.isNotEmpty) {
      final name = key.split('/').last.trim();
      if (name.isNotEmpty) return name;
    }
    final title = detail.title.trim();
    final base = title.isNotEmpty
        ? title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        : 'meeting-${detail.meetingId}';
    return '$base.m4a';
  }

  String filenameFromPath(String path) {
    final p = path.replaceAll('\\', '/');
    final idx = p.lastIndexOf('/');
    return idx >= 0 ? p.substring(idx + 1) : p;
  }

  String contentTypeForPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final dot = normalized.lastIndexOf('.');
    final ext = dot >= 0 ? normalized.substring(dot + 1).toLowerCase() : '';
    switch (ext) {
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
      default:
        return 'audio/wav';
    }
  }

  /// 优先读取媒体元数据时长；失败时回退到文件大小估算。
  Future<int> resolveDurationSeconds(String path) async {
    if (!kIsWeb) {
      try {
        final player = AudioPlayer();
        try {
          final duration = await player
              .setFilePath(path)
              .timeout(const Duration(seconds: 20));
          if (duration != null && duration.inSeconds > 0) {
            return duration.inSeconds;
          }
          final loaded = player.duration;
          if (loaded != null && loaded.inSeconds > 0) {
            return loaded.inSeconds;
          }
        } finally {
          await player.dispose();
        }
      } catch (e) {
        debugPrint('Meeting duration probe failed for $path: $e');
      }
    }
    return guessDurationSeconds(path);
  }

  int guessDurationSeconds(String path) {
    final file = io.File(path);
    final size = file.existsSync() ? file.lengthSync() : 0;
    if (size <= 0) return 0;
    final ext = contentTypeForPath(path);
    if (ext == 'audio/mp4' || ext == 'audio/mpeg') {
      // ~32kbps AAC speech rough estimate.
      return (size / 4000).ceil();
    }
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
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = _decodeJsonMap(resp.body);
      if (body is Map<String, dynamic> && body['success'] == false) {
        final msg = _readErrorMessage(body);
        if (msg.isNotEmpty) throw Exception(msg);
      }
      return;
    }
    final body = _decodeJsonMap(resp.body);
    if (body is Map<String, dynamic>) {
      final msg = _readErrorMessage(body);
      if (msg.isNotEmpty) throw Exception(msg);
    }
    throw Exception('请求失败(${resp.statusCode})');
  }

  String _readErrorMessage(Map<String, dynamic> body) {
    return (body['message'] ?? body['msg'] ?? body['error'] ?? '')
        .toString()
        .trim();
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
      'audioObjectKey',
      'summary',
      'status',
      'asrProgress',
      'title',
      'meetingDate',
      'createdAt',
      'updatedAt',
      'kbUpload',
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
