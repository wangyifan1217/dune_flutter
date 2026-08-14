import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import '../xflow/proposal_import_template.dart';
import 'reconciliation_shucai_models.dart';

const _assetBaseOverride = String.fromEnvironment(
  'SHUCAI_ASSET_BASE',
  defaultValue: '',
);

/// 拉取数财一体标签二 + 标签三六 Tab。优先走 flow-go（APP 出口 IP 在白名单），
/// 失败时直连资管（本机已加白名单时可预览）。
class ReconciliationShucaiService {
  ReconciliationShucaiService({required AuthSession session, http.Client? client})
    : _session = session,
      _ownsClient = client == null,
      _client = client ?? http.Client();

  final AuthSession _session;
  final http.Client _client;
  final bool _ownsClient;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  String get _assetBase {
    if (_assetBaseOverride.trim().isNotEmpty) {
      return _assetBaseOverride.replaceAll(RegExp(r'/$'), '');
    }
    return kProposalImportTemplateAssetBase.replaceAll(RegExp(r'/$'), '');
  }

  Future<ShucaiSnapshot> fetch({
    String? asOfDate,
    String? cardType,
    bool refresh = false,
  }) async {
    final date = (asOfDate ?? '').trim().isNotEmpty
        ? asOfDate!.trim()
        : _today();
    final card = (cardType ?? '').trim();
    try {
      return await _fetchFromDunes(date, cardType: card, refresh: refresh);
    } catch (_) {
      if (card.isNotEmpty) rethrow;
      return _fetchFromAssetDirect(date);
    }
  }

  Future<ReconStatusResponse> fetchStatus({
    String? asOfDate,
    String? cardType,
  }) async {
    final base = _session.apiBase.replaceAll(RegExp(r'/$'), '');
    final query = <String, String>{};
    if ((asOfDate ?? '').trim().isNotEmpty) {
      query['asOfDate'] = asOfDate!.trim();
    }
    if ((cardType ?? '').trim().isNotEmpty) {
      query['cardType'] = cardType!.trim();
    }
    final uri = Uri.parse('$base/reconciliation/status').replace(
      queryParameters: query.isEmpty ? null : query,
    );
    final resp = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    final map = _decodeEnvelope(resp, fallback: '对账状态加载失败');
    return ReconStatusResponse.fromJson(map);
  }

  Future<void> confirm({
    required String asOfDate,
    required String cardType,
    String comment = '',
  }) async {
    final base = _session.apiBase.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/reconciliation/confirm');
    final resp = await _client
        .post(
          uri,
          headers: {
            ..._headers,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'asOfDate': asOfDate.trim(),
            'cardType': cardType.trim(),
            'comment': comment.trim(),
          }),
        )
        .timeout(const Duration(seconds: 20));
    _decodeEnvelope(resp, fallback: '确认失败');
  }

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (_session.token.trim().isNotEmpty)
      'Authorization': 'Bearer ${_session.token.trim()}',
  };

  Map<String, dynamic> _decodeEnvelope(
    http.Response resp, {
    required String fallback,
  }) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('$fallback(${resp.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! Map) throw Exception(fallback);
    final map = Map<String, dynamic>.from(decoded);
    if (map['success'] == false) {
      throw Exception((map['message'] ?? fallback).toString());
    }
    final data = map['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<ShucaiSnapshot> _fetchFromDunes(
    String asOfDate, {
    String cardType = '',
    bool refresh = false,
  }) async {
    final base = _session.apiBase.replaceAll(RegExp(r'/$'), '');
    final query = <String, String>{'asOfDate': asOfDate};
    if (cardType.trim().isNotEmpty) {
      query['cardType'] = cardType.trim();
    }
    if (refresh) {
      query['refresh'] = '1';
    }
    final uri = Uri.parse('$base/reconciliation/shucai').replace(
      queryParameters: query,
    );
    final resp = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 25));
    final data = _decodeEnvelope(resp, fallback: '对账加载失败');
    if (data.isEmpty) throw Exception('对账数据为空');
    return ShucaiSnapshot.fromJson(data);
  }

  Future<ShucaiSnapshot> _fetchFromAssetDirect(String asOfDate) async {
    final tag2Future = _getAsset(
      '/out/shaqiu/cnpc-shucai-tag2/list',
      {'asOfDate': asOfDate},
    );
    final tag3Futures = {
      for (final tab in ShucaiSnapshot.tag3TabOrder)
        tab: _getAsset('/out/shaqiu/shucai-tag3/list', {
          'tab': tab,
          'asOfDate': asOfDate,
        }),
    };
    final tag2 = await tag2Future;
    final tag3 = <String, dynamic>{};
    for (final entry in tag3Futures.entries) {
      try {
        tag3[entry.key] = await entry.value;
      } catch (_) {}
    }
    if (tag3.isEmpty) {
      throw Exception('标签三加载失败');
    }
    var tag2Markdown = '';
    try {
      tag2Markdown = await _getAssetString(
        '/out/shaqiu/cnpc-shucai-tag2/markdown',
        {'asOfDate': asOfDate},
      );
    } catch (_) {}
    final tag3Markdown = <String, String>{};
    for (final tab in ShucaiSnapshot.tag3TabOrder) {
      try {
        final text = await _getAssetString(
          '/out/shaqiu/shucai-tag3/markdown',
          {'tab': tab, 'asOfDate': asOfDate},
        );
        if (text.trim().isNotEmpty) tag3Markdown[tab] = text;
      } catch (_) {}
    }
    return ShucaiSnapshot.fromJson({
      'asOfDate': asOfDate,
      'tag2': tag2,
      'tag3': tag3,
      'tag2Markdown': tag2Markdown,
      'tag3Markdown': tag3Markdown,
    });
  }

  Future<String> _getAssetString(
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse('$_assetBase$path').replace(queryParameters: query);
    final resp = await _client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 20));
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! Map) return '';
    final map = Map<String, dynamic>.from(decoded);
    final code = map['code'];
    if (resp.statusCode == 403 || code == 403) {
      throw Exception((map['msg'] ?? 'IP不在白名单').toString());
    }
    if (resp.statusCode < 200 ||
        resp.statusCode >= 300 ||
        (code is num && code != 200 && code != 0)) {
      return '';
    }
    final data = map['data'];
    if (data is String) return data;
    return data == null ? '' : data.toString();
  }

  Future<Map<String, dynamic>> _getAsset(
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse('$_assetBase$path').replace(queryParameters: query);
    final resp = await _client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 20));
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! Map) throw Exception('资管响应异常');
    final map = Map<String, dynamic>.from(decoded);
    final code = map['code'];
    if (resp.statusCode == 403 || code == 403) {
      throw Exception((map['msg'] ?? 'IP不在白名单').toString());
    }
    if (resp.statusCode < 200 ||
        resp.statusCode >= 300 ||
        (code is num && code != 200 && code != 0)) {
      throw Exception((map['msg'] ?? '资管查询失败').toString());
    }
    final data = map['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  static String _today() {
    final n = DateTime.now();
    final y = n.year.toString().padLeft(4, '0');
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
