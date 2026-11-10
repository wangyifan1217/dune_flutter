import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';
import 'funding_proposal_models.dart';

/// 资金提案接口：flow-go `/api/v1/funding-proposals/*`。
class FundingProposalService {
  FundingProposalService({required this.session, http.Client? client})
    : _client = client;

  final AuthSession session;
  final http.Client? _client;

  static const _base = '/funding-proposals';

  Object? _unwrap(http.Response response) {
    Object? decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map
          ? decoded['message'] ?? decoded['error']
          : null;
      throw Exception('${message ?? '资金提案请求失败：HTTP ${response.statusCode}'}');
    }
    if (decoded is Map && decoded['success'] == false) {
      throw Exception('${decoded['message'] ?? '资金提案请求失败'}');
    }
    return decoded is Map && decoded.containsKey('data')
        ? decoded['data']
        : decoded;
  }

  Map<String, dynamic> _map(Object? data) =>
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

  Future<FundingAccess> fetchAccess() async {
    final res = await dunesHttpGet(session, '$_base/access', client: _client);
    return FundingAccess.fromJson(_map(_unwrap(res)));
  }

  Future<FundingOptions> fetchOptions() async {
    final res = await dunesHttpGet(session, '$_base/options', client: _client);
    return FundingOptions.fromJson(_map(_unwrap(res)));
  }

  Future<FundingEstimate> estimate(Map<String, dynamic> form) async {
    final res = await dunesHttpPost(
      session,
      '$_base/estimate',
      body: jsonEncode({'form': form}),
      client: _client,
    );
    return FundingEstimate.fromJson(_unwrap(res));
  }

  Future<FundingListResult> fetchList({
    String scope = 'mine',
    String status = '',
    String keyword = '',
    int page = 0,
    int pageSize = 30,
  }) async {
    final query = <String, String>{
      'scope': scope,
      'page': '$page',
      'pageSize': '$pageSize',
      if (status.isNotEmpty) 'status': status,
      if (keyword.trim().isNotEmpty) 'q': keyword.trim(),
    };
    final qs = query.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    final res = await dunesHttpGet(session, '$_base?$qs', client: _client);
    return FundingListResult.fromJson(_map(_unwrap(res)));
  }

  Future<FundingProposal> fetch(int id) async {
    final res = await dunesHttpGet(session, '$_base/$id', client: _client);
    return FundingProposal.fromJson(_map(_unwrap(res)));
  }

  Future<FundingProposal> create(Map<String, dynamic> form) async {
    final res = await dunesHttpPost(
      session,
      _base,
      body: jsonEncode({'form': form}),
      client: _client,
    );
    return FundingProposal.fromJson(_map(_unwrap(res)));
  }

  Future<FundingProposal> save(
    int id,
    Map<String, dynamic> form, {
    required int version,
  }) async {
    final res = await dunesHttpPatch(
      session,
      '$_base/$id',
      body: jsonEncode({'form': form, 'version': version}),
      client: _client,
    );
    return FundingProposal.fromJson(_map(_unwrap(res)));
  }

  Future<FundingProposal> saveMaterials(
    int id,
    Map<String, dynamic> materials, {
    required int version,
  }) async {
    final res = await dunesHttpPatch(
      session,
      '$_base/$id/materials',
      body: jsonEncode({'materials': materials, 'version': version}),
      client: _client,
    );
    return FundingProposal.fromJson(_map(_unwrap(res)));
  }

  Future<void> delete(int id, {required int version}) async {
    final res = await dunesHttpDelete(
      session,
      '$_base/$id?version=$version',
      client: _client,
    );
    _unwrap(res);
  }

  Future<FundingProposal> submit(
    int id,
    Map<String, dynamic> form, {
    required int version,
  }) async {
    final res = await dunesHttpPost(
      session,
      '$_base/$id/submit',
      body: jsonEncode({'form': form, 'version': version}),
      client: _client,
    );
    return FundingProposal.fromJson(_map(_unwrap(res)));
  }

  Future<FundingProposal> withdraw(
    int id, {
    required int version,
    String comment = '',
  }) async {
    final res = await dunesHttpPost(
      session,
      '$_base/$id/withdraw',
      body: jsonEncode({'version': version, 'comment': comment}),
      client: _client,
    );
    return FundingProposal.fromJson(_map(_unwrap(res)));
  }

  Future<FundingProposal> decide(
    int id, {
    required bool approved,
    required int version,
    String comment = '',
  }) async {
    final res = await dunesHttpPost(
      session,
      '$_base/$id/decision',
      body: jsonEncode({
        'approved': approved,
        'comment': comment,
        'version': version,
      }),
      client: _client,
    );
    return FundingProposal.fromJson(_map(_unwrap(res)));
  }
}
