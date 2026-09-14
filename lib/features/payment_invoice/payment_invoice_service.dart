import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';
import 'payment_invoice_catalog.dart';

class PaymentInvoiceListResult {
  const PaymentInvoiceListResult({
    required this.rows,
    required this.scanned,
    this.total = 0,
    this.page = 1,
    this.pageSize = 10,
    this.usedMineFallback = false,
    this.serverPaged = false,
  });

  final List<PaymentInvoiceRow> rows;
  final int scanned;
  final int total;
  final int page;
  final int pageSize;
  final bool usedMineFallback;
  final bool serverPaged;
}

abstract class PaymentInvoiceProgressStore {
  Future<Map<String, PaymentInvoiceProgress>> load();
  Future<void> save(String key, PaymentInvoiceProgress progress);
}

class MemoryPaymentInvoiceProgressStore implements PaymentInvoiceProgressStore {
  MemoryPaymentInvoiceProgressStore([Map<String, PaymentInvoiceProgress>? seed])
    : _map = Map<String, PaymentInvoiceProgress>.from(seed ?? const {});

  final Map<String, PaymentInvoiceProgress> _map;

  @override
  Future<Map<String, PaymentInvoiceProgress>> load() async =>
      Map<String, PaymentInvoiceProgress>.from(_map);

  @override
  Future<void> save(String key, PaymentInvoiceProgress progress) async {
    _map[key] = progress;
  }
}

class PrefsPaymentInvoiceProgressStore implements PaymentInvoiceProgressStore {
  static const prefsKey = 'payment_invoice_progress_v1';

  @override
  Future<Map<String, PaymentInvoiceProgress>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, PaymentInvoiceProgress>{};
      for (final entry in decoded.entries) {
        if (entry.value is! Map) continue;
        final map = Map<String, dynamic>.from(entry.value as Map);
        final issued = parsePaymentInvoiceMoney(map['issuedAmount']) ?? 0;
        out['${entry.key}'] = PaymentInvoiceProgress(
          issuedAmount: issued,
          issueStatus: parseInvoiceIssueStatus(
            explicit: '${map['issueStatus'] ?? ''}',
            issued: issued,
          ),
        );
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> save(String key, PaymentInvoiceProgress progress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await load();
      current[key] = progress;
      await prefs.setString(
        prefsKey,
        jsonEncode({
          for (final entry in current.entries)
            entry.key: {
              'issuedAmount': entry.value.issuedAmount,
              'issueStatus': entry.value.issueStatus.name,
            },
        }),
      );
    } catch (_) {}
  }
}

class PaymentInvoiceService {
  PaymentInvoiceService({
    required this.session,
    http.Client? client,
    PaymentInvoiceProgressStore? progressStore,
  }) : _client = client,
       _progressStore = progressStore ?? PrefsPaymentInvoiceProgressStore();

  final AuthSession session;
  final http.Client? _client;
  final PaymentInvoiceProgressStore _progressStore;

  Future<PaymentInvoiceListResult> fetchLedger(PaymentInvoiceQuery query) async {
    final page = query.page < 1 ? 1 : query.page;
    final pageSize = query.pageSize < 1 ? 10 : query.pageSize;
    final fetched = await _fetchCandidates(
      PaymentInvoiceQuery(
        kind: query.kind,
        id: query.id,
        title: query.title,
        initiator: query.initiator,
        account: query.account,
        payAccountType: query.payAccountType,
        status: query.status,
        completed: query.completed,
        issueStatus: query.issueStatus,
        counterparty: query.counterparty,
        q: query.q,
        page: page,
        pageSize: pageSize,
        from: query.from,
        to: query.to,
      ),
    );
    final local = await _progressStore.load();
    final prepared = fetched.rows
        .where((row) => row.kind == query.kind)
        .map((row) => _applyLocal(row, local))
        .where((row) => matchesPaymentInvoiceQuery(row, query))
        .toList(growable: false);
    if (fetched.serverPaged) {
      return PaymentInvoiceListResult(
        rows: prepared,
        scanned: fetched.scanned,
        total: fetched.total,
        page: fetched.page,
        pageSize: fetched.pageSize,
        usedMineFallback: fetched.usedMineFallback,
        serverPaged: true,
      );
    }
    return PaymentInvoiceListResult(
      rows: _pageOf(prepared, page, pageSize),
      scanned: fetched.scanned,
      total: prepared.length,
      page: page,
      pageSize: pageSize,
      usedMineFallback: fetched.usedMineFallback,
    );
  }

  Future<PaymentInvoiceRow> saveInvoiceProgress({
    required PaymentInvoiceRow row,
    required num issuedAmount,
    required InvoiceIssueStatus issueStatus,
  }) async {
    final progress = PaymentInvoiceProgress(
      issuedAmount: issuedAmount < 0 ? 0 : issuedAmount,
      issueStatus: issueStatus,
    );
    await _progressStore.save(_progressKey(row), progress);
    var persisted = false;
    final body = jsonEncode({
      'issuedAmount': progress.issuedAmount,
      'issueStatus': progress.issueStatus.name.toUpperCase(),
    });
    final paths = <String>[
      '/xflow/submissions/${Uri.encodeComponent(row.businessType)}/${row.id}/invoice-progress',
    ];
    for (final path in paths) {
      try {
        final posted = await dunesHttpPost(
          session,
          path,
          body: body,
          client: _client,
        );
        if (posted.statusCode >= 200 && posted.statusCode < 300) {
          persisted = true;
          break;
        }
        if (posted.statusCode == 404 || posted.statusCode == 405) {
          final patched = await dunesHttpPatch(
            session,
            path,
            body: body,
            client: _client,
          );
          if (patched.statusCode >= 200 && patched.statusCode < 300) {
            persisted = true;
            break;
          }
        }
      } catch (_) {}
    }
    final next = applyInvoiceProgress(row, progress);
    if (!persisted) {
      throw const PaymentInvoiceProgressPendingException();
    }
    return next;
  }

  Future<PaymentInvoiceListResult> _fetchCandidates(
    PaymentInvoiceQuery query,
  ) async {
    final filters = _listQuery(query);
    try {
      return await _fetchDedicated('/payment-invoices', query: filters);
    } catch (_) {}
    try {
      return await _fetchDedicated('/xflow/submissions', query: filters);
    } catch (_) {}
    try {
      final scoped = await _fetchMine(
        query: {
          'viewAll': '1',
          'scope': 'payment-invoice',
          ...filters,
        },
      );
      return PaymentInvoiceListResult(rows: scoped, scanned: scoped.length);
    } catch (_) {}
    final mine = await _fetchMine();
    return PaymentInvoiceListResult(
      rows: mine,
      scanned: mine.length,
      usedMineFallback: true,
    );
  }

  Future<PaymentInvoiceListResult> _fetchDedicated(
    String path, {
    Map<String, String> query = const {},
  }) async {
    final response = await dunesHttpGet(
      session,
      _withQuery(path, query),
      client: _client,
    );
    if (response.statusCode == 401) {
      _unwrap(response);
    }
    if (response.statusCode == 403 ||
        response.statusCode == 404 ||
        response.statusCode == 405 ||
        response.statusCode == 501) {
      throw Exception('HTTP ${response.statusCode}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _unwrap(response);
    }
    final data = _unwrap(response);
    final items = _itemsOf(data);
    final rows = [
      for (final item in items.whereType<Map>())
        paymentInvoiceRowFromListJson(Map<String, dynamic>.from(item)),
    ].where((row) => row.id > 0 && row.kind != PaymentInvoiceKind.other).toList();
    final total = data is Map ? _asInt(data['total']) : rows.length;
    final page = data is Map ? _asInt(data['page']) : 0;
    final pageSize = data is Map ? _asInt(data['pageSize']) : 0;
    return PaymentInvoiceListResult(
      rows: rows,
      scanned: items.length,
      total: total > 0 ? total : rows.length,
      page: page < 1 ? 1 : page,
      pageSize: pageSize,
      serverPaged: data is Map && data.containsKey('page'),
    );
  }

  Future<List<PaymentInvoiceRow>> _fetchMine({
    Map<String, String>? query,
  }) async {
    final response = await dunesHttpGet(
      session,
      _withQuery('/xflow/submissions/mine', query ?? const {}),
      client: _client,
    );
    final data = _unwrap(response);
    final items = _itemsOf(data);
    return [
      for (final item in items.whereType<Map>())
        paymentInvoiceRowFromListJson(Map<String, dynamic>.from(item)),
    ].where((row) => row.id > 0 && row.kind != PaymentInvoiceKind.other).toList();
  }

  Map<String, String> _listQuery(PaymentInvoiceQuery query) {
    final out = <String, String>{
      'kind': query.kind == PaymentInvoiceKind.invoice ? 'invoice' : 'payment',
      'page': '${query.page < 1 ? 1 : query.page}',
      'pageSize': '${query.pageSize < 1 ? 10 : query.pageSize}',
    };
    final q = query.q.trim();
    if (q.isNotEmpty) out['q'] = q;
    if (query.payAccountType.trim() == '对公') out['party'] = 'public';
    if (query.payAccountType.trim() == '对私') out['party'] = 'private';
    if (query.completed.trim() == 'yes') out['status'] = 'done';
    if (query.completed.trim() == 'no') out['status'] = 'open';
    if (query.kind == PaymentInvoiceKind.invoice &&
        query.issueStatus.trim().isNotEmpty) {
      out['issueStatus'] = query.issueStatus.trim();
    }
    if (query.from != null) {
      out['from'] = query.from!.toIso8601String().split('T').first;
    }
    if (query.to != null) {
      out['to'] = query.to!.toIso8601String().split('T').first;
    }
    return out;
  }

  String _withQuery(String path, Map<String, String> query) {
    if (query.isEmpty) return path;
    final encoded = query.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return '$path?$encoded';
  }

  List<PaymentInvoiceRow> _pageOf(
    List<PaymentInvoiceRow> rows,
    int page,
    int pageSize,
  ) {
    if (rows.isEmpty) return const [];
    final start = (page - 1) * pageSize;
    if (start >= rows.length) return const [];
    final end = start + pageSize > rows.length ? rows.length : start + pageSize;
    return rows.sublist(start, end);
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  PaymentInvoiceRow _applyLocal(
    PaymentInvoiceRow row,
    Map<String, PaymentInvoiceProgress> local,
  ) {
    final progress = local[_progressKey(row)];
    if (progress == null) return row;
    return applyInvoiceProgress(row, progress);
  }

  String _progressKey(PaymentInvoiceRow row) =>
      '${row.businessType}:${row.id}';

  dynamic _unwrap(http.Response response) {
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map
          ? decoded['message'] ?? decoded['error']
          : decoded;
      throw Exception('${message ?? '付款发票审批请求失败：HTTP ${response.statusCode}'}');
    }
    if (decoded is Map && decoded['success'] == false) {
      throw Exception('${decoded['message'] ?? '付款发票审批请求失败'}');
    }
    return decoded is Map && decoded.containsKey('data')
        ? decoded['data']
        : decoded;
  }

  List<dynamic> _itemsOf(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      final items = data['items'] ?? data['rows'] ?? data['list'];
      if (items is List) return items;
    }
    return const [];
  }
}

class PaymentInvoiceProgressPendingException implements Exception {
  const PaymentInvoiceProgressPendingException();

  @override
  String toString() => '开票进度已记在本机，服务端回写接口尚未开通，刷新后可能仍在';
}
