import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'contract_register_models.dart';

class ContractRegisterService {
  ContractRegisterService({required this.session});

  final AuthSession session;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<ContractRegisterAccess> fetchAccess() async {
    final resp = await http.get(
      _uri('/contract-registers/access'),
      headers: _headers,
    );
    final data = _unwrap(resp);
    final map = data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
    return ContractRegisterAccess(
      view: map['view'] == true,
      config: map['config'] == true,
      kbSync: map['kbSync'] == true,
    );
  }

  Future<ContractRegisterListResult> fetchListPage({
    int page = 0,
    int size = 20,
    String keyword = '',
  }) async {
    final q = <String, String>{
      'page': page.toString(),
      'pageSize': size.toString(),
    };
    final k = keyword.trim();
    if (k.isNotEmpty) q['q'] = k;
    final resp = await http.get(
      _uri('/contract-registers', q),
      headers: _headers,
    );
    final data = _unwrap(resp);
    final map = data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
    final content = (map['items'] as List?) ?? const [];
    final items = content
        .whereType<Map>()
        .map((e) => ContractRegisterRow.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    return ContractRegisterListResult(
      items: items,
      total: (map['total'] as num?)?.toInt() ?? items.length,
    );
  }

  Future<ContractRegisterRow> fetchDetail(int id) async {
    final resp = await http.get(
      _uri('/contract-registers/$id'),
      headers: _headers,
    );
    return ContractRegisterRow.fromJson(_asMap(_unwrap(resp)));
  }

  Future<ContractRegisterRow> create(Map<String, dynamic> body) async {
    final resp = await http.post(
      _uri('/contract-registers'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return ContractRegisterRow.fromJson(_asMap(_unwrap(resp)));
  }

  Future<ContractRegisterRow> update(int id, Map<String, dynamic> body) async {
    final resp = await http.put(
      _uri('/contract-registers/$id'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return ContractRegisterRow.fromJson(_asMap(_unwrap(resp)));
  }

  Future<ContractRegisterFile> uploadFile({
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
    final map = bodyText.isEmpty ? <String, dynamic>{} : jsonDecode(bodyText);
    if (map is! Map || map['success'] == false) {
      throw Exception('${(map is Map ? map['message'] : null) ?? '上传失败'}');
    }
    final data = map['data'];
    if (data is! Map) throw Exception('上传失败: 返回数据异常');
    return ContractRegisterFile(
      fileName: '${data['fileName'] ?? fileName}'.trim().isEmpty
          ? fileName
          : '${data['fileName'] ?? fileName}'.trim(),
      objectKey: '${data['objectKey'] ?? data['url'] ?? ''}'.trim(),
      bucket: '${data['bucket'] ?? 'xflow-proposals'}'.trim().isEmpty
          ? 'xflow-proposals'
          : '${data['bucket']}'.trim(),
      url: '${data['url'] ?? ''}'.trim(),
      sizeBytes: bytes.length,
      mimeType: '${data['contentType'] ?? mimeType}'.trim(),
    );
  }

  Future<String> resolveFileUrl(ContractRegisterFile file) async {
    if (file.url.startsWith('http')) return file.url;
    final key = file.objectKey.isNotEmpty ? file.objectKey : file.url;
    if (key.isEmpty) return '';
    final bucket = file.bucket.isEmpty ? 'xflow-proposals' : file.bucket;
    final resp = await http.get(
      _uri('/storage/presigned-get', {
        'bucket': bucket,
        'objectKey': key,
      }),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Accept': 'application/json',
      },
    );
    final map = _asMap(_unwrap(resp));
    return '${map['url'] ?? ''}'.trim();
  }

  Future<ContractRegisterAIParseResult> parseAI(int id) async {
    final resp = await http.post(
      _uri('/contract-registers/$id/ai-parse'),
      headers: _headers,
      body: '{}',
    );
    return ContractRegisterAIParseResult.fromJson(_asMap(_unwrap(resp)));
  }

  Future<ContractRegisterAIParseResult> withdrawAIParse(int id) async {
    final resp = await http.post(
      _uri('/contract-registers/$id/ai-parse/withdraw'),
      headers: _headers,
      body: '{}',
    );
    return ContractRegisterAIParseResult.fromJson(_asMap(_unwrap(resp)));
  }

  Future<ContractKbSyncResult> fetchKbSync() async {
    final resp = await http.get(
      _uri('/contract-registers/kb-sync'),
      headers: _headers,
    );
    return ContractKbSyncResult.fromJson(_asMap(_unwrap(resp)));
  }

  Future<ContractKbSyncResult> runKbSync() async {
    final resp = await http
        .post(
          _uri('/contract-registers/kb-sync'),
          headers: _headers,
          body: '{}',
        )
        .timeout(const Duration(seconds: 120));
    return ContractKbSyncResult.fromJson(_asMap(_unwrap(resp)));
  }

  Future<Uint8List> previewKbFile(int id) async {
    final resp = await http.get(
      _uri('/contract-registers/$id/kb-file/preview'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Accept': 'application/pdf',
      },
    );
    if (resp.statusCode >= 400) {
      var msg = 'HTTP ${resp.statusCode}';
      final body = resp.body;
      if (body.isNotEmpty &&
          (body.startsWith('{') || body.trimLeft().startsWith('{'))) {
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map) {
            msg = '${decoded['message'] ?? decoded['error'] ?? msg}';
          }
        } catch (_) {}
      }
      throw Exception(msg);
    }
    return resp.bodyBytes;
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    return Map<String, dynamic>.from(data as Map);
  }

  dynamic _unwrap(http.Response resp) {
    final body = resp.body.isEmpty ? <String, dynamic>{} : jsonDecode(resp.body);
    if (resp.statusCode >= 400) {
      final msg =
          body is Map ? (body['message'] ?? body['error'] ?? body) : body;
      throw Exception('HTTP ${resp.statusCode}: $msg');
    }
    if (body is Map && body.containsKey('data')) {
      return body['data'];
    }
    return body;
  }
}

class ContractRegisterAIParseResult {
  const ContractRegisterAIParseResult({
    this.status = 'none',
    this.message = '',
    this.canWithdraw = false,
    this.proposalRelated,
  });

  final String status;
  final String message;
  final bool canWithdraw;
  final ContractRegisterProposal? proposalRelated;

  factory ContractRegisterAIParseResult.fromJson(Map<String, dynamic> json) {
    final proposalRaw = json['proposalRelated'];
    return ContractRegisterAIParseResult(
      status: '${json['status'] ?? json['aiParseStatus'] ?? 'none'}'.trim().isEmpty
          ? 'none'
          : '${json['status'] ?? json['aiParseStatus']}'.trim(),
      message: '${json['message'] ?? ''}'.trim(),
      canWithdraw: json['aiParseCanWithdraw'] == true,
      proposalRelated: proposalRaw is Map
          ? ContractRegisterProposal.fromJson(Map<String, dynamic>.from(proposalRaw))
          : null,
    );
  }
}
