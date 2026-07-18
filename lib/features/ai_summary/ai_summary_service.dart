import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';
import 'ai_summary_models.dart';

class AiSummaryService {
  AiSummaryService({required AuthSession session, http.Client? client})
    : _session = session,
      _client = client;

  final AuthSession _session;
  final http.Client? _client;

  Future<List<AiSummaryTemplate>> fetchTemplates() async {
    final resp = await dunesHttpGet(
      _session,
      '/ai/summaries/templates',
      client: _client,
    );
    final data = _unwrap(resp, fallback: '模板加载失败');
    final items = data is Map<String, dynamic> ? data['items'] : null;
    if (items is! List) return const <AiSummaryTemplate>[];
    return items
        .whereType<Map<String, dynamic>>()
        .map(AiSummaryTemplate.fromJson)
        .toList(growable: false);
  }

  Future<AiSummaryListPage> fetchList({int page = 1, int size = 20}) async {
    final resp = await dunesHttpGet(
      _session,
      '/ai/summaries?page=$page&size=$size',
      client: _client,
    );
    final data = _unwrap(resp, fallback: '总结列表加载失败');
    if (data is! Map<String, dynamic>) {
      return const AiSummaryListPage(
        items: <AiSummaryItem>[],
        page: 1,
        size: 20,
        total: 0,
        hasMore: false,
      );
    }
    return AiSummaryListPage.fromJson(data);
  }

  /// 通讯页预览：取最近一条已成功的总结（默认不展示空占位）。
  Future<AiSummaryItem?> fetchLatestPreview() async {
    final page = await fetchList(page: 1, size: 20);
    for (final item in page.items) {
      if (item.isSuccess) return item;
    }
    return null;
  }

  Future<AiSummaryItem> fetchDetail(int id) async {
    final resp = await dunesHttpGet(
      _session,
      '/ai/summaries/$id',
      client: _client,
    );
    final data = _unwrap(resp, fallback: '总结详情加载失败');
    if (data is! Map<String, dynamic>) {
      throw Exception('总结详情为空');
    }
    return AiSummaryItem.fromJson(data);
  }

  Future<AiSummaryItem> create({
    required String theme,
    required String template,
    required List<int> conversationIds,
    required DateTime from,
    required DateTime to,
    List<int> memberUserIds = const <int>[],
  }) async {
    final body = jsonEncode(<String, dynamic>{
      'theme': theme.trim(),
      'template': template,
      'conversationIds': conversationIds,
      'memberUserIds': memberUserIds,
      'from': _formatRfc3339(from),
      'to': _formatRfc3339(to),
    });
    final resp = await dunesHttpPost(
      _session,
      '/ai/summaries',
      body: body,
      client: _client,
    );
    final data = _unwrap(resp, fallback: '创建总结失败');
    if (data is! Map<String, dynamic>) {
      throw Exception('创建总结失败');
    }
    return AiSummaryItem.fromJson(data);
  }

  Future<AiSummaryItem> refresh(
    int id, {
    List<int>? conversationIds,
    DateTime? from,
    DateTime? to,
  }) async {
    final body = <String, dynamic>{};
    if (conversationIds != null && conversationIds.isNotEmpty) {
      body['conversationIds'] = conversationIds;
    }
    if (from != null && to != null) {
      body['from'] = _formatRfc3339(from);
      body['to'] = _formatRfc3339(to);
    }
    final resp = await dunesHttpPost(
      _session,
      '/ai/summaries/$id/refresh',
      body: jsonEncode(body),
      client: _client,
    );
    if (resp.statusCode == 409) {
      throw Exception('总结正在生成中');
    }
    final data = _unwrap(resp, fallback: '重新生成失败');
    if (data is! Map<String, dynamic>) {
      throw Exception('重新生成失败');
    }
    return AiSummaryItem.fromJson(data);
  }

  Future<void> delete(int id) async {
    final resp = await dunesHttpDelete(
      _session,
      '/ai/summaries/$id',
      client: _client,
    );
    _unwrap(resp, fallback: '删除失败');
  }

  /// 轮询直到终态；可并发多个任务各自调用。
  Future<AiSummaryItem> pollUntilDone(
    int id, {
    Duration interval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 5),
    void Function(AiSummaryItem item)? onUpdate,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final item = await fetchDetail(id);
      onUpdate?.call(item);
      if (!item.isGenerating) return item;
      if (DateTime.now().isAfter(deadline)) {
        throw Exception('生成超时，请稍后在列表中查看');
      }
      await Future<void>.delayed(interval);
    }
  }

  dynamic _unwrap(http.Response resp, {required String fallback}) {
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(resp.body);
      body = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'success': false, 'message': fallback};
    } catch (_) {
      throw Exception('$fallback: HTTP ${resp.statusCode}');
    }
    if (resp.statusCode < 200 ||
        resp.statusCode >= 300 ||
        body['success'] == false) {
      final msg = (body['message'] ?? body['error']?['message'] ?? fallback)
          .toString();
      throw Exception(msg);
    }
    return body['data'];
  }

  static String _formatRfc3339(DateTime dt) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final oh = offset.inHours.abs().toString().padLeft(2, '0');
    final om = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '$y-$m-${d}T$hh:$mm:$ss$sign$oh:$om';
  }

  /// 本地「某一天」的 [from, to) 半开区间。
  static (DateTime from, DateTime to) dayRange(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (start, end);
  }

  /// 含首尾日的周期 → [from, to) 半开区间（to 为结束日次日 0 点）。
  static (DateTime from, DateTime to) inclusiveDayRange(
    DateTime start,
    DateTime end,
  ) {
    final from = DateTime(start.year, start.month, start.day);
    var last = DateTime(end.year, end.month, end.day);
    if (last.isBefore(from)) last = from;
    final to = last.add(const Duration(days: 1));
    return (from, to);
  }
}
