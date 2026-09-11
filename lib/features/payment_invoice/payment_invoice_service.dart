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
    this.usedMineFallback = false,
  });

  final List<PaymentInvoiceRow> rows;
  final int scanned;
  final bool usedMineFallback;
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

  static const _scanPageSize = 50;
  static const _maxScanPages = 6;
  static const _enrichCap = 80;

  Future<PaymentInvoiceListResult> fetchLedger(PaymentInvoiceQuery query) async {
    final fetched = await _fetchCandidates();
    final matched = fetched.rows
        .where((row) => row.kind == query.kind)
        .toList(growable: true);
    final local = await _progressStore.load();
    final enriched = await _enrich(matched, local);
    final filtered = enriched
        .where((row) => matchesPaymentInvoiceQuery(row, query))
        .toList(growable: false);
    return PaymentInvoiceListResult(
      rows: filtered,
      scanned: fetched.scanned,
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

  Future<PaymentInvoiceListResult> _fetchCandidates() async {
    try {
      final all = await _fetchAllProposals();
      if (all.rows.isNotEmpty || all.scanned > 0) return all;
    } catch (_) {}
    final mine = await _fetchMine();
    return PaymentInvoiceListResult(
      rows: mine,
      scanned: mine.length,
      usedMineFallback: true,
    );
  }

  Future<PaymentInvoiceListResult> _fetchAllProposals() async {
    final rows = <PaymentInvoiceRow>[];
    var scanned = 0;
    for (var page = 1; page <= _maxScanPages; page++) {
      final path =
          '/xflow/proposals/all?page=$page&pageSize=$_scanPageSize';
      final response = await dunesHttpGet(session, path, client: _client);
      if (response.statusCode == 401) {
        _unwrap(response);
      }
      if (response.statusCode == 403 ||
          response.statusCode == 404 ||
          response.statusCode == 501) {
        break;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _unwrap(response);
      }
      final data = _unwrap(response);
      final items = _itemsOf(data);
      if (items.isEmpty) break;
      scanned += items.length;
      for (final item in items.whereType<Map>()) {
        final row = paymentInvoiceRowFromListJson(
          Map<String, dynamic>.from(item),
        );
        if (row.id > 0 && row.kind != PaymentInvoiceKind.other) {
          rows.add(row);
        }
      }
      final total = data is Map ? _asInt(data['total']) : 0;
      if (items.length < _scanPageSize) break;
      if (total > 0 && scanned >= total) break;
    }
    return PaymentInvoiceListResult(rows: rows, scanned: scanned);
  }

  Future<List<PaymentInvoiceRow>> _fetchMine() async {
    final response = await dunesHttpGet(
      session,
      '/xflow/submissions/mine',
      client: _client,
    );
    final data = _unwrap(response);
    final items = _itemsOf(data);
    return [
      for (final item in items.whereType<Map>())
        paymentInvoiceRowFromListJson(Map<String, dynamic>.from(item)),
    ].where((row) => row.id > 0 && row.kind != PaymentInvoiceKind.other).toList();
  }

  Future<List<PaymentInvoiceRow>> _enrich(
    List<PaymentInvoiceRow> rows,
    Map<String, PaymentInvoiceProgress> local,
  ) async {
    final take = rows.take(_enrichCap).toList(growable: false);
    final enriched = <PaymentInvoiceRow>[];
    const batch = 8;
    for (var i = 0; i < take.length; i += batch) {
      final slice = take.sublist(i, i + batch > take.length ? take.length : i + batch);
      final next = await Future.wait(slice.map((row) => _enrichOne(row, local)));
      enriched.addAll(next);
    }
    if (rows.length > take.length) {
      enriched.addAll(
        rows.skip(take.length).map((row) => _applyLocal(row, local)),
      );
    }
    return enriched;
  }

  Future<PaymentInvoiceRow> _enrichOne(
    PaymentInvoiceRow row,
    Map<String, PaymentInvoiceProgress> local,
  ) async {
    var next = row;
    if (row.formValues.isEmpty ||
        row.purpose.isEmpty ||
        row.payeeAccount.isEmpty ||
        (row.kind == PaymentInvoiceKind.invoice && row.appliedAmount == null)) {
      try {
        final response = await dunesHttpGet(
          session,
          '/xflow/submissions/${Uri.encodeComponent(row.businessType)}/${row.id}',
          client: _client,
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = _unwrap(response);
          if (data is Map) {
            final map = Map<String, dynamic>.from(data);
            final form = map['formData'] ?? map['formValues'] ?? map['form'];
            next = applyPaymentInvoiceForm(
              next,
              form is Map ? Map<String, dynamic>.from(form) : const {},
              subStatus: '${map['subStatus'] ?? next.subStatus}',
            );
          }
        }
      } catch (_) {}
    }
    return _applyLocal(next, local);
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

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

class PaymentInvoiceProgressPendingException implements Exception {
  const PaymentInvoiceProgressPendingException();

  @override
  String toString() => '开票进度已记在本机，服务端回写接口尚未开通，刷新后可能仍在';
}
