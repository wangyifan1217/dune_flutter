import 'dart:convert';

import 'package:http/http.dart' as http;

/// 资管出站根地址（接口 A/B）。flow-go 未部署时 APP 可直连兜底。
const kProposalImportTemplateAssetBase =
    'https://sel-prod.djien-qr.com/se-prod';

/// 提案导入模板（资管出站，经 flow-go 聚合；失败时本地目录兜底）。
class ProposalImportTemplateItem {
  const ProposalImportTemplateItem({
    required this.syncSource,
    required this.name,
    this.profileId = '',
    this.profileName = '',
    required this.available,
    this.downloadUrl = '',
    this.message = '',
  });

  final String syncSource;
  final String name;
  final String profileId;
  final String profileName;
  final bool available;
  final String downloadUrl;
  final String message;

  factory ProposalImportTemplateItem.fromJson(Map<String, dynamic> json) {
    return ProposalImportTemplateItem(
      syncSource: (json['syncSource'] ?? '').toString().trim(),
      name: (json['name'] ?? '').toString().trim(),
      profileId: (json['profileId'] ?? '').toString().trim(),
      profileName: (json['profileName'] ?? '').toString().trim(),
      available: json['available'] == true,
      downloadUrl: (json['downloadUrl'] ?? '').toString().trim(),
      message: (json['message'] ?? '').toString().trim(),
    );
  }
}

const _catalog = <({String syncSource, String name})>[
  (syncSource: 'DIGITALG', name: '数商'),
  (syncSource: 'YD', name: '运营商'),
  (syncSource: 'CX_MEMBER', name: '出行-订阅'),
  (syncSource: 'CX_BENEFIT', name: '出行-权益金'),
  (syncSource: 'MY', name: '民营'),
];

String proposalImportTemplateDownloadUrl(String syncSource) {
  final q = Uri.encodeQueryComponent(syncSource);
  return '$kProposalImportTemplateAssetBase/out/shaqiu/proposal-import-template/download?syncSource=$q';
}

Future<List<ProposalImportTemplateItem>> fetchProposalImportTemplates({
  required String apiBase,
  required String token,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    try {
      final fromApi = await _fetchFromDunesApi(
        apiBase: apiBase,
        token: token,
        client: c,
      );
      if (fromApi.isNotEmpty) return fromApi;
    } catch (_) {
      // flow-go 未部署时走资管直连兜底。
    }
    return _fetchFromAssetDirect(client: c);
  } finally {
    if (client == null) c.close();
  }
}

Future<List<ProposalImportTemplateItem>> _fetchFromDunesApi({
  required String apiBase,
  required String token,
  required http.Client client,
}) async {
  final base = apiBase.replaceAll(RegExp(r'/$'), '');
  final uri = Uri.parse('$base/proposals/import-templates');
  final resp = await client.get(
    uri,
    headers: {
      'Accept': 'application/json',
      if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
    },
  );
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw Exception('模板列表加载失败(${resp.statusCode})');
  }
  final decoded = jsonDecode(resp.body);
  if (decoded is! Map) {
    throw Exception('模板列表响应异常');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (map['success'] == false) {
    throw Exception((map['message'] ?? '模板列表加载失败').toString());
  }
  final data = map['data'];
  final rawItems = data is Map ? data['items'] : null;
  if (rawItems is! List) return const [];
  return rawItems
      .whereType<Map>()
      .map((e) => ProposalImportTemplateItem.fromJson(
            Map<String, dynamic>.from(e),
          ))
      .where((e) => e.syncSource.isNotEmpty)
      .toList(growable: false);
}

Future<List<ProposalImportTemplateItem>> _fetchFromAssetDirect({
  required http.Client client,
}) async {
  final out = <ProposalImportTemplateItem>[];
  for (final row in _catalog) {
    final resolveUri = Uri.parse(
      '$kProposalImportTemplateAssetBase/out/shaqiu/proposal-import-template',
    ).replace(queryParameters: {'syncSource': row.syncSource});
    try {
      final resp = await client.get(
        resolveUri,
        headers: const {'Accept': 'application/json'},
      );
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) {
        throw Exception('bad response');
      }
      final map = Map<String, dynamic>.from(decoded);
      final code = map['code'];
      final data = map['data'];
      if (code == 200 && data is Map) {
        final d = Map<String, dynamic>.from(data);
        final url = (d['downloadUrl'] ?? '').toString().trim();
        out.add(
          ProposalImportTemplateItem(
            syncSource: row.syncSource,
            name: row.name,
            profileId: (d['profileId'] ?? '').toString(),
            profileName: (d['profileName'] ?? '').toString(),
            available: true,
            downloadUrl: url.isNotEmpty
                ? url
                : proposalImportTemplateDownloadUrl(row.syncSource),
          ),
        );
        continue;
      }
      out.add(
        ProposalImportTemplateItem(
          syncSource: row.syncSource,
          name: row.name,
          available: false,
          message: (map['msg'] ?? '暂未提供沙丘导入模板').toString(),
        ),
      );
    } catch (_) {
      out.add(
        ProposalImportTemplateItem(
          syncSource: row.syncSource,
          name: row.name,
          available: false,
          message: '暂未提供沙丘导入模板',
        ),
      );
    }
  }
  return out;
}
