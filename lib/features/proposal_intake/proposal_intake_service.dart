import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'proposal_intake_models.dart';

class ProposalIntakeService {
  ProposalIntakeService({required this.session});

  final AuthSession session;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
  };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<ProposalIntakeAccess> fetchAccess() async {
    final data = _unwrap(
      await http.get(_uri('/proposal-intakes/access'), headers: _headers),
    );
    return ProposalIntakeAccess.fromJson(_asMap(data));
  }

  Future<ProposalIntakeOptions> fetchOptions() async {
    final data = _unwrap(
      await http.get(_uri('/proposal-intakes/options'), headers: _headers),
    );
    return ProposalIntakeOptions.fromJson(_asMap(data));
  }

  Future<List<ProposalPerson>> fetchPeople() async {
    final data = _unwrap(await http.get(_uri('/org/users'), headers: _headers));
    final rows = data is List ? data : const [];
    return rows
        .whereType<Map>()
        .map((item) => ProposalPerson.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.userId > 0 && item.name.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<ProposalContractChoice>> fetchContracts({
    String keyword = '',
  }) async {
    final needle = keyword.trim();
    final data = _unwrap(
      await http.get(
        _uri('/proposal-intakes/contracts', {
          if (needle.isNotEmpty) 'q': needle,
        }),
        headers: _headers,
      ),
    );
    final rows = data is List ? data : const [];
    return rows
        .whereType<Map>()
        .map(
          (item) =>
              ProposalContractChoice.fromJson(Map<String, dynamic>.from(item)),
        )
        .where(
          (item) =>
              item.id > 0 &&
              (item.contractNo.isNotEmpty || item.contractName.isNotEmpty),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> fetchContractDetail(int id) async {
    final data = _unwrap(
      await http.get(
        _uri('/proposal-intakes/contracts/$id'),
        headers: _headers,
      ),
    );
    return _asMap(data);
  }

  Future<ProposalIntakeUploadedFile> uploadFile({
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    final req = http.MultipartRequest('POST', _uri('/storage/upload'));
    req.headers['Authorization'] = 'Bearer ${session.token}';
    req.fields['bucket'] = 'xflow-proposals';
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: fileName),
    );
    final streamed = await req.send();
    final bodyText = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('上传失败: HTTP ${streamed.statusCode}');
    }
    final decoded = bodyText.isEmpty ? null : jsonDecode(bodyText);
    if (decoded is! Map || decoded['success'] == false) {
      final message = decoded is Map ? decoded['message'] : null;
      throw Exception('${message ?? '上传失败'}');
    }
    final data = decoded['data'];
    if (data is! Map) throw Exception('上传失败: 返回数据异常');
    final map = Map<String, dynamic>.from(data);
    final savedName = '${map['fileName'] ?? fileName}'.trim();
    return ProposalIntakeUploadedFile(
      fileName: savedName.isEmpty ? fileName : savedName,
      objectKey: '${map['objectKey'] ?? map['url'] ?? ''}'.trim(),
      url: '${map['url'] ?? ''}'.trim(),
      sizeBytes: bytes.length,
      mimeType: '${map['contentType'] ?? mimeType}'.trim(),
    );
  }

  Future<ProposalIntakeListResult> fetchList({
    int page = 0,
    int pageSize = 20,
    String keyword = '',
    String status = '',
    String kind = '',
    bool actionable = false,
    bool relatedOnly = false,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      if (keyword.trim().isNotEmpty) 'q': keyword.trim(),
      if (status.trim().isNotEmpty) 'status': status.trim(),
      if (kind.trim().isNotEmpty) 'kind': kind.trim(),
      if (actionable) 'actionable': '1',
      if (relatedOnly) 'related': '1',
    };
    final data = _unwrap(
      await http.get(_uri('/proposal-intakes', query), headers: _headers),
    );
    return ProposalIntakeListResult.fromJson(_asMap(data));
  }

  Future<ProposalIntakeRow> create({
    String title = '',
    String kind = 'sales',
    Map<String, dynamic> form = const {},
    Map<String, dynamic> review = const {},
  }) async {
    final data = _unwrap(
      await http.post(
        _uri('/proposal-intakes'),
        headers: _headers,
        body: jsonEncode({
          'title': title,
          'kind': normalizeProposalIntakeKind(kind),
          'status': 'draft',
          'form': form,
          'review': review,
        }),
      ),
    );
    return ProposalIntakeRow.fromJson(_asMap(data));
  }

  Future<ProposalIntakeRow> fetchDetail(int id) async {
    final data = _unwrap(
      await http.get(_uri('/proposal-intakes/$id'), headers: _headers),
    );
    return ProposalIntakeRow.fromJson(_asMap(data));
  }

  Future<ProposalIntakeRow> save(ProposalIntakeRow row) async {
    final data = _unwrap(
      await http.patch(
        _uri('/proposal-intakes/${row.id}'),
        headers: _headers,
        body: jsonEncode({
          'title': row.title,
          'status': row.status,
          'form': row.form,
          'review': row.review,
          'version': row.version,
        }),
      ),
    );
    return ProposalIntakeRow.fromJson(_asMap(data));
  }

  Future<ProposalIntakeRow> saveReview(
    int id,
    String section,
    bool approved,
    int version, {
    String comment = '',
  }) async {
    final data = _unwrap(
      await http.post(
        _uri('/proposal-intakes/$id/reviews'),
        headers: _headers,
        body: jsonEncode({
          'section': section,
          'approved': approved,
          'comment': comment,
          'version': version,
        }),
      ),
    );
    return ProposalIntakeRow.fromJson(_asMap(data));
  }

  Future<ProposalIntakeRow> submit(int id) async {
    final data = _unwrap(
      await http.post(
        _uri('/proposal-intakes/$id/submit'),
        headers: _headers,
        body: '{}',
      ),
    );
    return ProposalIntakeRow.fromJson(_asMap(data));
  }

  Future<ProposalIntakeRow> handoff(int id, String action, int version) async {
    final data = _unwrap(
      await http.post(
        _uri('/proposal-intakes/$id/handoff'),
        headers: _headers,
        body: jsonEncode({'action': action, 'version': version}),
      ),
    );
    return ProposalIntakeRow.fromJson(_asMap(data));
  }

  Future<ProposalIntakeRow> decidePresident({
    required int id,
    required bool approved,
    required int version,
    String comment = '',
  }) async {
    final data = _unwrap(
      await http.post(
        _uri('/proposal-intakes/$id/president'),
        headers: _headers,
        body: jsonEncode({
          'approved': approved,
          'comment': comment,
          'version': version,
        }),
      ),
    );
    return ProposalIntakeRow.fromJson(_asMap(data));
  }

  Future<void> delete(int id) async {
    _unwrap(
      await http.delete(_uri('/proposal-intakes/$id'), headers: _headers),
    );
  }

  Object? _unwrap(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final map = decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      throw Exception('${map?['message'] ?? '请求失败（${response.statusCode}）'}');
    }
    if (decoded is Map && decoded.containsKey('success')) {
      final map = Map<String, dynamic>.from(decoded);
      if (map['success'] != true) {
        throw Exception('${map['message'] ?? '请求失败'}');
      }
      return map['data'];
    }
    return decoded;
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }
}
