import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';

String normalizeGiphyMediaUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty) return '';
  if (url.startsWith('//')) return 'https:$url';
  return url;
}

class GiphyListItem {
  const GiphyListItem({
    required this.id,
    required this.previewUrl,
    required this.downloadUrl,
  });

  final String id;
  final String previewUrl;
  final String downloadUrl;

  factory GiphyListItem.fromRaw(Map<String, dynamic> raw) {
    final id = (raw['id'] ?? '').toString();
    final images = raw['images'];
    final imageMap = images is Map<String, dynamic>
        ? images
        : images is Map
        ? Map<String, dynamic>.from(images)
        : const <String, dynamic>{};

    String? pickUrl(String key) {
      final node = imageMap[key];
      if (node is Map) {
        final url = normalizeGiphyMediaUrl((node['url'] ?? '').toString());
        if (url.isNotEmpty) return url;
      }
      return null;
    }

    final previewUrl =
        pickUrl('preview_gif') ??
        pickUrl('downsized') ??
        pickUrl('fixed_height') ??
        pickUrl('original') ??
        '';
    final downloadUrl =
        pickUrl('original') ??
        pickUrl('downsized') ??
        pickUrl('fixed_height') ??
        previewUrl;

    return GiphyListItem(
      id: id,
      previewUrl: previewUrl,
      downloadUrl: downloadUrl,
    );
  }

  bool get isValid =>
      downloadUrl.isNotEmpty && (id.isNotEmpty || previewUrl.isNotEmpty);
}

class GiphySearchPage {
  const GiphySearchPage({required this.items, this.hasMore = false});

  final List<GiphyListItem> items;
  final bool hasMore;
}

/// 经 im-go 代理访问 GIPHY，客户端不持有 API Key。
class GiphyProxyService {
  GiphyProxyService({required AuthSession session, http.Client? client})
    : _session = session,
      _client = client ?? http.Client();

  final AuthSession _session;
  final http.Client _client;

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer ${_session.token}',
    'Content-Type': 'application/json',
  };

  String get _platform {
    if (kIsWeb) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  Future<GiphySearchPage> trending({int offset = 0, int limit = 30}) {
    return _fetch(
      '/giphy/trending',
      <String, String>{
        'offset': '$offset',
        'limit': '$limit',
        'platform': _platform,
      },
    );
  }

  /// 经后端代理拉取 GIF 原文件，避免客户端直连 GIPHY CDN 失败。
  Future<Uint8List> downloadGifBytes(GiphyListItem item) async {
    if (item.id.isNotEmpty) {
      try {
        return await _downloadViaBackend(item.id);
      } catch (_) {
        // 回退直连 CDN。
      }
    }
    return _downloadDirect(item.downloadUrl);
  }

  Future<Uint8List> _downloadViaBackend(String id) async {
    final uri = Uri.parse('${_session.apiBase}/giphy/download').replace(
      queryParameters: <String, String>{'id': id, 'platform': _platform},
    );
    final resp = await _client.get(uri, headers: _headers);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_parseApiError(resp.body, resp.statusCode, 'GIF 下载失败'));
    }
    if (resp.bodyBytes.isEmpty) {
      throw Exception('GIF 内容为空');
    }
    if (_looksLikeJsonError(resp)) {
      throw Exception(_parseApiError(resp.body, resp.statusCode, 'GIF 下载失败'));
    }
    return resp.bodyBytes;
  }

  Future<Uint8List> _downloadDirect(String url) async {
    final normalized = normalizeGiphyMediaUrl(url);
    if (normalized.isEmpty) throw Exception('GIF 地址无效');
    final resp = await _client.get(Uri.parse(normalized));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('GIF 下载失败: HTTP ${resp.statusCode}');
    }
    if (resp.bodyBytes.isEmpty) throw Exception('GIF 内容为空');
    return resp.bodyBytes;
  }

  Future<GiphySearchPage> search(
    String query, {
    int offset = 0,
    int limit = 30,
  }) {
    return _fetch(
      '/giphy/search',
      <String, String>{
        'q': query.trim(),
        'offset': '$offset',
        'limit': '$limit',
        'platform': _platform,
        'lang': 'zh-CN',
      },
    );
  }

  Future<GiphySearchPage> _fetch(
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse('${_session.apiBase}$path').replace(
      queryParameters: query,
    );
    final resp = await _client.get(uri, headers: _headers);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_parseApiError(resp.body, resp.statusCode, 'GIF 列表加载失败'));
    }

    final Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('GIF 列表响应无效');
      }
      body = decoded;
    } catch (_) {
      throw Exception('GIF 服务响应异常 (HTTP ${resp.statusCode})');
    }
    if (body['success'] == false) {
      throw Exception((body['message'] ?? 'GIF 列表加载失败').toString());
    }

    final payload = body['data'];
    final payloadMap = payload is Map<String, dynamic>
        ? payload
        : payload is Map
        ? Map<String, dynamic>.from(payload)
        : const <String, dynamic>{};
    final rows = payloadMap['data'];
    final items = <GiphyListItem>[];
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map) continue;
        final map = row is Map<String, dynamic>
            ? row
            : Map<String, dynamic>.from(row);
        final item = GiphyListItem.fromRaw(map);
        if (item.isValid) items.add(item);
      }
    }

    var hasMore = false;
    final pagination = payloadMap['pagination'];
    if (pagination is Map) {
      final total = (pagination['total_count'] as num?)?.toInt() ?? 0;
      final count = (pagination['count'] as num?)?.toInt() ?? items.length;
      final off = (pagination['offset'] as num?)?.toInt() ?? 0;
      hasMore = off + count < total;
    } else {
      hasMore = items.length >= int.tryParse(query['limit'] ?? '30')!;
    }

    return GiphySearchPage(items: items, hasMore: hasMore);
  }

  String _parseApiError(String body, int statusCode, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message = (decoded['message'] ?? '').toString().trim();
        if (message.isNotEmpty) {
          return _mapServerMessage(message, statusCode);
        }
      }
    } catch (_) {}
    if (statusCode == 503) return 'GIF 服务未配置，请联系管理员';
    if (statusCode == 401) return '登录已过期，请重新登录';
    if (statusCode == 404) return 'GIF 接口不存在，请确认 im-go 已更新';
    if (statusCode == 502) return 'GIF 服务暂不可用，请稍后重试';
    return '$fallback (HTTP $statusCode)';
  }

  String _mapServerMessage(String message, int statusCode) {
    final lower = message.toLowerCase();
    if (lower.contains('giphy not configured')) return 'GIF 服务未配置，请联系管理员';
    if (lower.contains('unauthorized')) return '登录已过期，请重新登录';
    if (lower.contains('not found')) return 'GIF 接口不存在，请确认网关已更新';
    if (lower.contains('giphy 上游') || lower.contains('gif 代理')) {
      return message;
    }
    if (lower.contains('upstream')) return 'GIF 服务暂不可用，请重启 API 网关';
    if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(message)) return message;
    if (statusCode == 503) return 'GIF 服务未配置，请联系管理员';
    return 'GIF 加载失败 (HTTP $statusCode)';
  }

  bool _looksLikeJsonError(http.Response resp) {
    final type = (resp.headers['content-type'] ?? '').toLowerCase();
    if (type.contains('json')) return true;
    final text = resp.body.trimLeft();
    return text.startsWith('{') && text.contains('"success"');
  }
}
