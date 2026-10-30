import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../auth/auth_session.dart';

class QianjiChatService {
  QianjiChatService(this.session);
  final AuthSession session;
  Uri _uri(String path) => Uri.parse(
    '${session.apiBase.replaceAll(RegExp(r'/+$'), '')}/qianji/chat$path',
  );
  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
  };
  Future<dynamic> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = _uri(path);
    // A contextual query may recheck the previous result, parse an intent and
    // call a board's detail endpoint before responding.
    const timeout = Duration(seconds: 45);
    final response = switch (method) {
      'GET' => await http.get(uri, headers: _headers).timeout(timeout),
      'DELETE' => await http.delete(uri, headers: _headers).timeout(timeout),
      _ =>
        await http
            .post(uri, headers: _headers, body: jsonEncode(body ?? {}))
            .timeout(timeout),
    };
    if (response.statusCode >= 400) {
      throw Exception(
        response.statusCode == 403 ? '当前没有饕的访问权限' : '服务暂不可用，请稍后重试',
      );
    }
    if (response.bodyBytes.isEmpty) return null;
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data is Map && data.containsKey('data') ? data['data'] : data;
  }

  Future<List<dynamic>> conversations({int offset = 0}) async =>
      (await _request('GET', '?offset=$offset') as List);
  Future<int> create() async =>
      ((await _request('POST', ''))['id'] as num).toInt();
  Future<void> delete(int id) async => _request('DELETE', '/$id');
  Future<List<dynamic>> turns(int id, {int? before}) async =>
      (await _request(
            'GET',
            '/$id/turns${before == null ? '' : '?before=$before'}',
          )
          as List);
  Future<Map<String, dynamic>> send(
    int id,
    String scope,
    String question,
  ) async => Map<String, dynamic>.from(
    await _request('POST', '/$id/turns', {'scope': scope, 'question': question})
        as Map,
  );

  Future<Uint8List> exportTurn(int conversationId, int turnId) async {
    final uri = _uri('/$conversationId/turns/export?turnId=$turnId');
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 90));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        response.statusCode == 403
            ? '当前没有查看该查询结果的权限'
            : '无法生成 Excel，请确认这轮查询包含明细数据',
      );
    }
    return response.bodyBytes;
  }
}
