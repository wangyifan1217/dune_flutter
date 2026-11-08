import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';
import 'attendance_models.dart';

class AttendanceService {
  AttendanceService(this.session, {http.Client? client})
    : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;

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
