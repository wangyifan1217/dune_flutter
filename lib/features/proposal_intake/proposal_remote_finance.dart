import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'proposal_finance_formula.dart';
import 'proposal_intake_models.dart';

Map<String, dynamic> _map(Object? value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

({String scale, String margin}) proposalRemoteListFigures(ProposalIntakeRow row) {
  final main = _map(row.financeEstimate['main']);
  final scale = main['salesScale'] as num?;
  final margin = row.form['businessCostRedacted'] == true ? null : main['margin'] as num?;
  return (scale: scale == null ? '' : '$scale', margin: margin == null ? '' : '$margin');
}
double _number(Object? value) {
  if (value is! num || !value.isFinite) throw const FormatException('后端测算结果格式错误');
  return value.toDouble();
}
List<dynamic> _list(Object? value) => value is List ? value : const [];

ProposalFinanceEvaluation _evaluation(Map<String, dynamic> json) {
  ProposalFinanceLine line(Object? value) {
    final m = _map(value);
    return ProposalFinanceLine(
      name: '${m['name'] ?? ''}', amount: _number(m['amount']),
      formula: m['formula'] == null ? null : ProposalFinanceFormula.fromJson(m['formula']),
      substitution: '${m['substitution'] ?? ''}', pending: m['pending'] == true,
      missing: _list(m['missing']).map((e) => '$e').toList(),
      source: '${m['source'] ?? ''}', locked: m['locked'] == true,
      promotionMonthlyScale: (m['promotionMonthlyScale'] as num?)?.toDouble(),
    );
  }
  return ProposalFinanceEvaluation(
    salesScale: _number(json['salesScale']),
    revenueGroup: json['revenueGroup'] == null ? null : ProposalRevenueFormulaGroup.fromJson(json['revenueGroup']),
    revenueGroups: _list(json['revenueGroups']).map(ProposalRevenueFormulaGroup.fromJson).toList(),
    revenue: line(json['revenue']), procurement: line(json['procurement']),
    buckets: _map(json['buckets']).map((key, value) {
      final m = _map(value);
      return MapEntry(key, ProposalFinanceBucket(
        category: ProposalCostCategory.fromJson(m['category']),
        lines: _list(m['lines']).map(line).toList(),
        computedTotal: _number(m['total']),
      ));
    }),
    profit: _number(json['profit']), margin: (json['margin'] as num?)?.toDouble(),
    computedCostTotal: (_map(json['summary'])['costTotal'] as num?)?.toDouble(),
    profitSubstitution: '${json['profitSubstitution'] ?? ''}',
    marginSubstitution: '${json['marginSubstitution'] ?? ''}',
    products: _list(json['products']).map((raw) {
      final m = _map(raw);
      return ProposalProductFinanceEvaluation(
        sku: ProposalSkuDetailRow.fromJson(m['sku']), owner: '${m['owner'] ?? 'main'}',
        evaluation: _evaluation(_map(m['evaluation'])),
        promotionPlans: _list(m['promotionPlans']).map(ProposalPromotionTierPlan.fromJson).toList(),
      );
    }).toList(),
  );
}

class ProposalRemoteFinanceResult {
  ProposalRemoteFinanceResult.fromJson(Map<String, dynamic> json)
      : engineVersion = '${json['engineVersion'] ?? ''}',
        main = _evaluation(_map(json['main'])),
        children = json['children'] == null ? null : _evaluation(_map(json['children'])),
        total = _evaluation(_map(json['total'])),
        summary = _map(_map(json['total'])['summary']),
        mainSummary = _map(_map(json['main'])['summary']),
        childrenSummary = _map(_map(json['children'])['summary']) {
    settlements = _map(json['settlements']);
    if (engineVersion.isEmpty || summary['formulaVersion'] == null) {
      throw const FormatException('后端测算接口版本不兼容');
    }
  }
  final String engineVersion;
  final ProposalFinanceEvaluation main;
  final ProposalFinanceEvaluation? children;
  final ProposalFinanceEvaluation total;
  final Map<String, dynamic> summary, mainSummary, childrenSummary;
  late final Map<String, dynamic> settlements;

  Map<String, dynamic> settlement(String skuId, String rowId) => _map(settlements['$skuId:$rowId']);

  Map<String, dynamic> applyToForm(Map<String, dynamic> form) {
    Map<String, dynamic> apply(Map<String, dynamic> input, ProposalFinanceEvaluation value, Map<String, dynamic> summary) {
      final next = Map<String, dynamic>.from(input);
      next['revenue'] = value.revenue.amount;
      next['turnoverCash'] = summary['turnoverCash'];
      for (final bucket in value.buckets.values) {
        final c = bucket.category;
        if (form['businessCostRedacted'] == true && c.key == 'business') continue;
        next[c.totalKey] = bucket.total;
        next[c.amountsKey] = {for (final line in bucket.lines) line.name: line.amount};
      }
      if (form['businessCostRedacted'] != true) {
        next['profit'] = value.profit; next['margin'] = value.margin;
      }
      return next;
    }
    var next = apply(form, main, mainSummary);
    final groups = _map(form['productFinance']);
    groups['main'] = apply(proposalIntakeProductFinance(form, owner: 'main'), main, mainSummary);
    if (children != null) groups['children'] = apply(proposalIntakeProductFinance(form, owner: 'children'), children!, childrenSummary);
    next['productFinance'] = groups;
    return next;
  }
}

/// Only input normalization happens here. All financial arithmetic is performed
/// by the service; derived fields never become the next request's input.
Map<String, dynamic> proposalRemoteFinanceInputs(Map<String, dynamic> form) {
  const derived = {'revenue', 'profit', 'margin', 'projectCost', 'businessCost',
    'operatingCost', 'taxCost', 'turnoverCash', 'costItemAmounts',
    'businessCostItemAmounts', 'taxCostItemAmounts', 'operatingCostItemAmounts'};
  Object? clean(Object? value) {
    if (value is Map) return {for (final e in value.entries) if (!derived.contains(e.key)) '${e.key}': clean(e.value)};
    if (value is List) return value.map(clean).toList();
    return value;
  }
  return _map(clean(form));
}

class ProposalRemoteFinanceController extends ChangeNotifier {
  ProposalRemoteFinanceController(this.fetch);
  final Future<ProposalRemoteFinanceResult> Function(Map<String, dynamic>) fetch;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;
  String _key = '';
  Map<String, dynamic> _input = {};
  Future<ProposalRemoteFinanceResult>? _pending;
  int _pendingGeneration = -1;
  ProposalRemoteFinanceResult? result;
  Object? error;
  bool loading = false;

  void setForm(Map<String, dynamic> form) {
    final input = proposalRemoteFinanceInputs(form);
    final key = jsonEncode(input);
    if (key == _key) return;
    _key = key; _input = input; _generation++;
    loading = true; error = null; result = null;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_run().then<void>((_) {}, onError: (Object _) {}));
    });
  }

  Future<ProposalRemoteFinanceResult> _run() {
    if (_pendingGeneration == _generation && _pending != null) return _pending!;
    final generation = _generation;
    _pendingGeneration = generation;
    return _pending = (() async {
      try {
        final value = await fetch(_input);
        if (!_disposed && generation == _generation) { result = value; error = null; loading = false; notifyListeners(); }
        return value;
      } catch (e) {
        if (!_disposed && generation == _generation) { error = e; loading = false; notifyListeners(); }
        rethrow;
      }
    })();
  }

  Future<ProposalRemoteFinanceResult> calculateNow(Map<String, dynamic> form) async {
    setForm(form); _timer?.cancel();
    if (result != null) return result!;
    if (error != null) { _pending = null; _pendingGeneration = -1; loading = true; error = null; }
    final generation = _generation;
    final value = await _run();
    if (generation != _generation) throw StateError('填写内容已变化，请重新测算后保存');
    return value;
  }

  void retry() {
    _pending = null; _pendingGeneration = -1; loading = true; error = null; notifyListeners();
    unawaited(_run().then<void>((_) {}, onError: (Object _) {}));
  }

  @override
  void dispose() { _disposed = true; _generation++; _timer?.cancel(); super.dispose(); }
}
