import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';
import 'attendance_models.dart';

class AttendanceService {
  AttendanceService(this.session, {http.Client? client})
    : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;

  void close() => _client.close();

  Future<AttendanceFaceStatus> fetchFaceStatus() async {
    final response =
        await dunesHttpGet(
          session,
          '/attendance/face/status',
          client: _client,
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw Exception('查询人脸状态超时，请重试'),
        );
    final data = _unwrap(response);
    if (data is! Map ||
        data['faceRequired'] is! bool ||
        data['enrolled'] is! bool) {
      throw Exception('人脸状态返回格式错误');
    }
    return AttendanceFaceStatus.fromJson(Map<String, dynamic>.from(data));
  }

  Future<AttendanceFaceStatus> enrollFace(AttendanceFacePhoto photo) async {
    final data = await _sendFaceImage('/attendance/face/enroll', photo, '人脸录入');
    final status = AttendanceFaceStatus.fromJson(data);
    if (!status.enrolled) throw Exception('人脸录入未完成，请重试');
    return status;
  }

  Future<Map<String, dynamic>> _sendFaceImage(
    String path,
    AttendanceFacePhoto photo,
    String operation,
  ) async {
    try {
      final response = await dunesHttpPost(
        session,
        path,
        body: photo.bytes,
        headers: {'Content-Type': photo.contentType},
        client: _client,
      ).timeout(const Duration(seconds: 35));
      final data = _unwrap(response);
      if (data is! Map) throw Exception('$operation返回格式错误');
      return Map<String, dynamic>.from(data);
    } on TimeoutException {
      throw Exception('$operation超时，请刷新状态后重试');
    } on http.ClientException {
      throw Exception('$operation网络异常，请检查网络后重试');
    }
  }

  Future<AttendanceFaceVerification> verifyFace({
    required String type,
    required Uint8List image,
    required String contentType,
  }) async {
    final data = await _sendFaceImage(
      '/attendance/face/verify?type=${Uri.encodeQueryComponent(type)}',
      AttendanceFacePhoto(image, contentType),
      '人脸核验',
    );
    return AttendanceFaceVerification.fromJson(data);
  }

  Future<AttendanceToday> fetchToday() async {
    final response = await dunesHttpGet(
      session,
      '/attendance/today',
      client: _client,
    );
    final data = _unwrap(response);
    if (data is! Map) throw Exception('打卡状态返回格式错误');
    return AttendanceToday.fromJson(Map<String, dynamic>.from(data));
  }

  Future<AttendanceHistoryBatch> fetchHistory({
    required int page,
    int size = 20,
  }) async {
    final response = await dunesHttpGet(
      session,
      '/attendance/history?page=$page&size=$size',
      client: _client,
    );
    final data = _unwrap(response);
    if (data is! Map) throw Exception('打卡历史返回格式错误');
    return AttendanceHistoryBatch.fromJson(Map<String, dynamic>.from(data));
  }

  Future<AttendancePunch> punch({
    required String type,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    String? ssid,
    String? bssid,
    String? faceVerificationToken,
    required String platform,
  }) async {
    final response = await dunesHttpPost(
      session,
      '/attendance/punch',
      body: jsonEncode({
        'type': type,
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'ssid': ssid ?? '',
        'bssid': bssid ?? '',
        'platform': platform,
        if (faceVerificationToken?.isNotEmpty == true)
          'faceVerificationToken': faceVerificationToken,
      }),
      client: _client,
    );
    final data = _unwrap(response);
    if (data is! Map) throw Exception('打卡结果返回格式错误');
    return AttendancePunch.fromJson(Map<String, dynamic>.from(data));
  }

  dynamic _unwrap(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw Exception('服务器返回格式错误');
    }
    if (decoded is! Map) throw Exception('服务器返回格式错误');
    final body = Map<String, dynamic>.from(decoded);
    if (response.statusCode >= 400 || body['success'] == false) {
      throw Exception('${body['message'] ?? '请求失败（${response.statusCode}）'}');
    }
    return body['data'];
  }
}
