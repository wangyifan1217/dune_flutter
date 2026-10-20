import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import 'proposal_intake_models.dart';
import 'proposal_intake_unreviewed.dart';
import 'proposal_remote_finance.dart';

class ProposalIntakeService {
  ProposalIntakeService({required this.session});

  final AuthSession session;

  Future<ProposalRemoteFinanceResult> estimateFinance(Map<String, dynamic> form) async {
    final response = await http.post(
      _uri('/proposal-intakes/estimate'), headers: _headers,
      body: jsonEncode({'form': proposalRemoteFinanceInputs(form)}),
    ).timeout(const Duration(seconds: 20));
    return ProposalRemoteFinanceResult.fromJson(_asMap(_unwrap(response)));
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
  };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  /// 导出提案归档 Excel。不传 [revision] 导出当前生效版；传了导出那一版的快照。
  /// 返回文件内容和服务端给的文件名（提案编号_名称_V1_日期.xlsx）。
  Future<({Uint8List bytes, String fileName})> exportExcel(
    int id, {
    int? revision,
  }) async {
    if (!kProposalIntakeArchiveExportEnabled) {
      throw Exception('归档导出已关闭');
    }
    final response = await http
        .get(
          _uri(
            '/proposal-intakes/$id/export',
            revision == null ? null : {'revision': '$revision'},
          ),
          headers: {'Authorization': 'Bearer ${session.token}'},
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _unwrap(response);
      throw Exception('导出失败（${response.statusCode}）');
    }
    return (
      bytes: response.bodyBytes,
      fileName: proposalExportFileName(
        response.headers['content-disposition'] ?? '',
        fallback: '提案_$id.xlsx',
      ),
    );
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

  Future<List<ProposalApprovedPurchaseHit>> fetchApprovedPurchases({
    String keyword = '',
  }) async {
    final needle = keyword.trim();
    if (needle.isEmpty) return const [];
    final data = _unwrap(
      await http.get(
        _uri('/proposal-intakes/approved-purchases', {'q': needle}),
        headers: _headers,
      ),
    );
    final rows = data is List
        ? data
        : (data is Map ? (data['items'] as List? ?? const []) : const []);
    return rows
        .whereType<Map>()
        .map(
          (item) => ProposalApprovedPurchaseHit.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .where((item) => item.id > 0)
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
    String sector = '',
    String period = '',
    bool actionable = false,
    bool relatedOnly = false,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      if (keyword.trim().isNotEmpty) 'q': keyword.trim(),
      if (status.trim().isNotEmpty) 'status': status.trim(),
      if (kind.trim().isNotEmpty) 'kind': kind.trim(),
      if (sector.trim().isNotEmpty) 'sector': sector.trim(),
      if (period.trim().isNotEmpty) 'period': period.trim(),
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

  Future<ProposalIntakeRow> duplicate(int id) async {
    final data = _unwrap(
      await http.post(
        _uri('/proposal-intakes/$id/duplicate'),
        headers: _headers,
      ),
    );
    return ProposalIntakeRow.fromJson(_asMap(data));
  }

  Future<ProposalIntakeRow> fetchDetail(
    int id, {
    int chatConversationId = 0,
    int chatMessageId = 0,
  }) async {
    final data = _unwrap(
      await http.get(
        _uri(
          '/proposal-intakes/$id',
          _chatReadQuery(
            chatConversationId: chatConversationId,
            chatMessageId: chatMessageId,
          ),
        ),
        headers: _headers,
      ),
    );
    return ProposalIntakeRow.fromJson(_asMap(data));
  }

  Map<String, String>? _chatReadQuery({
    required int chatConversationId,
    required int chatMessageId,
  }) {
    if (chatConversationId <= 0 || chatMessageId <= 0) return null;
    return {
      'chatConversationId': '$chatConversationId',
      'chatMessageId': '$chatMessageId',
    };
  }

  Future<ProposalIntakeRow> saveMeetingMinutes(
    int id,
    int version,
    List<Map<String, dynamic>> minutes,
  ) async {
    final data = _unwrap(
      await http.patch(
        _uri('/proposal-intakes/$id/meeting-minutes'),
        headers: _headers,
        body: jsonEncode({
          'version': version,
          'meetingMinutes': minutes,
        }),
      ),
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
          'kind': normalizeProposalIntakeKind(row.kind),
          'status': row.status,
          'form': row.form,
          'review': row.review,
          'version': row.version,
        }),
      ),
    );
    return ProposalIntakeRow.fromJson(_asMap(data));
  }

  /// 复核中其他人打勾会抬版本。冲突时拉最新稿、只合并未复核改动再写一次。
  Future<ProposalIntakeRow> saveResolvingConflict(ProposalIntakeRow row) async {
    try {
      return await save(row);
    } catch (error) {
      if (row.id <= 0 ||
          !proposalIntakeIsConflictMessage(friendlyErrorText(error))) {
        rethrow;
      }
      final latest = await fetchDetail(row.id);
      final merged = proposalIntakePreserveUserFinanceEdits(
        original: row.form,
        persist: proposalIntakeKeepUnreviewedForm(
          baseline: latest.form,
          current: row.form,
          review: latest.review,
        ),
      );
      return save(
        latest.copyWith(
          title: row.title,
          kind: row.kind,
          form: merged,
          status: row.status,
        ),
      );
    }
  }

  Future<ProposalIntakeWriteResult> saveReview(
    int id,
    String section,
    bool approved,
    int version, {
    String comment = '',
    List<String> sections = const <String>[],
    bool withdraw = false,
  }) async {
    final data = _unwrap(
      await http.post(
        _uri('/proposal-intakes/$id/reviews'),
        headers: _headers,
        body: jsonEncode({
          'section': section,
          'sections': sections,
          'approved': approved,
          if (withdraw) 'withdraw': true,
          'comment': comment,
          'version': version,
        }),
      ),
    );
    return ProposalIntakeWriteResult.fromJson(_asMap(data));
  }

  Future<ProposalIntakeWriteResult> submit(int id) async {
    final data = _unwrap(
      await http.post(
        _uri('/proposal-intakes/$id/submit'),
        headers: _headers,
        body: '{}',
      ),
    );
    return ProposalIntakeWriteResult.fromJson(_asMap(data));
  }

  Future<ProposalIntakeWriteResult> handoff(
    int id,
    String action,
    int version,
  ) async {
    final data = _unwrap(
      await http.post(
        _uri('/proposal-intakes/$id/handoff'),
        headers: _headers,
        body: jsonEncode({'action': action, 'version': version}),
      ),
    );
    return ProposalIntakeWriteResult.fromJson(_asMap(data));
  }

  Future<ProposalIntakeWriteResult> decidePresident({
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
    return ProposalIntakeWriteResult.fromJson(_asMap(data));
  }

  /// 时限详情；功能关闭或该提案未纳入时返回 null。
  Future<ProposalSlaDetail?> fetchSla(int id) async {
    final data = _unwrap(
      await http.get(_uri('/proposal-intakes/$id/sla'), headers: _headers),
    );
    return ProposalSlaDetail.tryParse(data);
  }

  Future<ProposalSlaDetail?> appealSla({
    required int id,
    required int scoreId,
    required String reason,
  }) async {
    final data = _unwrap(
      await http.post(
        _uri('/proposal-intakes/$id/sla/appeals'),
        headers: _headers,
        body: jsonEncode({'scoreId': scoreId, 'reason': reason}),
      ),
    );
    return ProposalSlaDetail.tryParse(data);
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

/// 从 Content-Disposition 里取文件名：优先 filename*=UTF-8''…（中文名），其次 filename="…"。
String proposalExportFileName(String header, {String fallback = '提案.xlsx'}) {
  final star = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false)
      .firstMatch(header);
  if (star != null) {
    try {
      final name = Uri.decodeComponent(star.group(1)!.trim());
      if (name.isNotEmpty) return name;
    } catch (_) {}
  }
  final plain = RegExp(r'filename="?([^";]+)"?', caseSensitive: false)
      .firstMatch(header);
  final name = plain?.group(1)?.trim() ?? '';
  return name.isEmpty ? fallback : name;
}
