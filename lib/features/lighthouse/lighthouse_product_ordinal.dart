// ═════════════════════════════════════════════════════════════════════════════
// 月末结构预测 · 贝叶斯多层有序 logit（试行 v2，2026-09）
//
//   问题：截至 T 日（T+1 口径，只用到昨天），产品 / 供给（省份）/ 渠道 三个维度的
//   每一个实体，本月全月某指标（核销规模 / 销售规模 / 收入 / 毛利）相对上月全月
//   会落在哪一档？
//     Y = 下滑（< −5%）/ 持平（±5% 内）/ 增长（> +5%），有序三档。
//
//   模型：贝叶斯多层（分层）有序 logistic 回归（累积 logit / 比例优势模型）
//     η = β₁·x_lin + β₂·x_lin·prog + β₃·x_pace + β₄·x_pace·prog + β₅·x_mom
//         + u[分组] + v[实体]
//     P(Y ≤ 下滑) = logistic(κ₁ − η)，P(Y ≤ 持平) = logistic(κ₂ − η)，κ₁ < κ₂
//     u ~ N(0, σ_g²)，v ~ N(0, σ_e²)（实体嵌套在分组内 → 部分汇聚）
//     先验 β ~ N(0, 2.5²)，κ ~ N(±1, 2.5²) 有序，σ ~ HalfNormal(1)；NUTS 采样
//   分组：产品 = 一级分类；供给 = 供应商二级分类；渠道 = 渠道一级分类。
//   协变量（截断 [−2, 2]）：
//     x_lin  = (日均外推月末 − 上月全月) ÷ |上月全月|
//     x_pace = (本月已发生 − 上月同期) ÷ |上月同期|
//     x_mom  = (近 7 天 − 前 7 天) ÷ |前 7 天|
//     prog   = 已过天数 ÷ 当月天数
//   参数 = 100 个后验样本（assets/lighthouse/structure_ordinal_model.json），
//   概率 = 逐样本计算后取平均（后验预测），自带参数不确定性。
//   训练脚本：沙丘go/lighthouse-go/scripts/forecast/ordinal_dims.py
// ═════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart' show rootBundle;

const _kAsset = 'assets/lighthouse/structure_ordinal_model.json';

/// 维度 → 中文名 / 实体称呼。
const lighthouseOrdinalDims = <String, ({String label, String unit, String group})>{
  'product': (label: '产品', unit: '个产品', group: '一级分类'),
  'supply': (label: '供给', unit: '个省份供给', group: '供应商分类'),
  'channel': (label: '渠道', unit: '个渠道', group: '渠道一级分类'),
};

/// 指标 → 列表行上的字段名。
const lighthouseOrdinalRowField = <String, String>{
  'verify': 'verifiedSales',
  'sales': 'sales',
  'revenue': 'revenue',
  'profit': 'profit',
};

const lighthouseOrdinalFixedEffects = <String>[
  'x_lin',
  'x_lin_prog',
  'x_pace',
  'x_pace_prog',
  'x_mom',
];

@immutable
class LighthouseOrdinalFeatures {
  const LighthouseOrdinalFeatures({
    required this.mtd,
    required this.prevSameDay,
    required this.prevTotal,
    required this.last7,
    required this.prev7,
    required this.day,
    required this.daysInMonth,
  });

  final double mtd;
  final double prevSameDay;
  final double prevTotal;
  final double last7;
  final double prev7;
  final int day;
  final int daysInMonth;

  static double _rel(double a, double b) =>
      ((a - b) / (b.abs() + 1)).clamp(-2.0, 2.0).toDouble();

  double get linearForecast => day <= 0 ? 0 : mtd / day * daysInMonth;
  double get xLin => _rel(linearForecast, prevTotal);
  double get xPace => _rel(mtd, prevSameDay);
  double get xMom => _rel(last7, prev7);
  double get prog => daysInMonth <= 0 ? 0 : day / daysInMonth;

  List<double> get design => [xLin, xLin * prog, xPace, xPace * prog, xMom];
}

@immutable
class LighthouseOrdinalResult {
  const LighthouseOrdinalResult({
    required this.name,
    required this.group,
    required this.features,
    required this.pDown,
    required this.pFlat,
    required this.pUp,
    required this.effect,
    required this.knownEntity,
    required this.knownGroup,
  });

  final String name;
  final String group;
  final LighthouseOrdinalFeatures features;
  final double pDown;
  final double pFlat;
  final double pUp;

  /// 实体随机效应（含分组）的后验均值：>0 同样信号下月底更易走高，<0 更易回落。
  final double effect;

  /// false = 训练期没出现过这个实体（新上线 / 改名），用分组效应代替。
  final bool knownEntity;
  final bool knownGroup;

  /// 0 下滑 / 1 持平 / 2 增长（后验概率最大的一档）
  int get verdict {
    if (pUp >= pDown && pUp >= pFlat) return 2;
    if (pDown >= pFlat) return 0;
    return 1;
  }

  double get confidence => math.max(pUp, math.max(pDown, pFlat));

  /// 期望风险金额：P(下滑) × 上月全月体量（排序用）。
  double get riskAmount => pDown * features.prevTotal.abs();
}

@immutable
class LighthouseOrdinalBacktest {
  const LighthouseOrdinalBacktest({
    required this.acc,
    required this.baseAcc,
    required this.brier,
    required this.baseBrier,
    required this.logloss,
    required this.n,
    required this.months,
    required this.classShare,
    required this.byDay,
  });

  final double acc;
  final double baseAcc;
  final double brier;
  final double baseBrier;
  final double logloss;
  final int n;
  final List<String> months;
  final List<double> classShare;
  final List<({int day, double acc, double baseAcc, int n})> byDay;

  bool get beatsBaseline => acc >= baseAcc;
}

/// 模型卡里要展示的一组元数据。
@immutable
class LighthouseOrdinalCard {
  const LighthouseOrdinalCard({
    required this.fixedMean,
    required this.sigmaGroup,
    required this.sigmaEntity,
    required this.rhat,
    required this.essMin,
    required this.nObs,
    required this.nEntity,
    required this.nGroup,
    required this.trainMonths,
    required this.backtest,
  });

  final Map<String, double> fixedMean;
  final double sigmaGroup;
  final double sigmaEntity;
  final double rhat;
  final double essMin;
  final int nObs;
  final int nEntity;
  final int nGroup;
  final List<String> trainMonths;
  final LighthouseOrdinalBacktest? backtest;
}

class LighthouseProductOrdinalModel {
  LighthouseProductOrdinalModel._(this._json);

  final Map<String, dynamic> _json;
  static LighthouseProductOrdinalModel? _cache;

  static Future<LighthouseProductOrdinalModel?> load() async {
    final c = _cache;
    if (c != null) return c;
    try {
      final raw = await rootBundle.loadString(_kAsset);
      final m = LighthouseProductOrdinalModel._(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      _cache = m;
      return m;
    } catch (_) {
      return null;
    }
  }

  String get version => '${_json['version'] ?? ''}';
  String get trainedFrom => '${_json['trainedFrom'] ?? ''}';
  String get trainedThrough => '${_json['trainedThrough'] ?? ''}';
  double get threshold => (_json['threshold'] as num?)?.toDouble() ?? 0.05;
  double get minPrevTotal =>
      (_json['minPrevTotal'] as num?)?.toDouble() ?? 1e5;

  Map<String, dynamic> _dim(String dim) {
    final dims = _json['dims'];
    if (dims is! Map || dims[dim] is! Map) return const {};
    final m = (dims[dim] as Map)['metrics'];
    return m is Map ? Map<String, dynamic>.from(m) : const {};
  }

  List<String> get dims => [
    for (final d in lighthouseOrdinalDims.keys)
      if (_dim(d).isNotEmpty) d,
  ];

  List<String> metricsOf(String dim) => _dim(dim).keys.toList();

  String labelOf(String metric) => switch (metric) {
    'verify' => '核销规模',
    'sales' => '销售规模',
    'revenue' => '收入',
    'profit' => '毛利',
    _ => metric,
  };

  static List<double> _vec(dynamic v) =>
      (v as List? ?? const []).map((e) => (e as num).toDouble()).toList();

  LighthouseOrdinalCard? card(String dim, String metric) {
    final m = _dim(dim)[metric];
    if (m is! Map) return null;
    LighthouseOrdinalBacktest? bt;
    final b = m['backtest'];
    if (b is Map) {
      bt = LighthouseOrdinalBacktest(
        acc: (b['acc'] as num).toDouble(),
        baseAcc: (b['baseAcc'] as num).toDouble(),
        brier: (b['brier'] as num).toDouble(),
        baseBrier: (b['baseBrier'] as num?)?.toDouble() ?? double.nan,
        logloss: (b['logloss'] as num?)?.toDouble() ?? double.nan,
        n: (b['n'] as num).toInt(),
        months: [for (final x in (b['months'] as List? ?? const [])) '$x'],
        classShare: _vec(b['classShare']),
        byDay: [
          for (final x in (b['byDay'] as List? ?? const []))
            if (x is Map)
              (
                day: (x['day'] as num).toInt(),
                acc: (x['acc'] as num).toDouble(),
                baseAcc: (x['baseAcc'] as num).toDouble(),
                n: (x['n'] as num).toInt(),
              ),
        ],
      );
    }
    final fm = m['fixedMean'];
    return LighthouseOrdinalCard(
      fixedMean: fm is Map
          ? {for (final e in fm.entries) '${e.key}': (e.value as num).toDouble()}
          : const {},
      sigmaGroup: (m['sigmaGroup'] as num?)?.toDouble() ?? double.nan,
      sigmaEntity: (m['sigmaEntity'] as num?)?.toDouble() ?? double.nan,
      rhat: (m['rhat'] as num?)?.toDouble() ?? double.nan,
      essMin: (m['essMin'] as num?)?.toDouble() ?? double.nan,
      nObs: (m['nObs'] as num?)?.toInt() ?? 0,
      nEntity: (m['nEntity'] as num?)?.toInt() ?? 0,
      nGroup: (m['nGroup'] as num?)?.toInt() ?? 0,
      trainMonths: [for (final x in (m['trainMonths'] as List? ?? const [])) '$x'],
      backtest: bt,
    );
  }

  /// 一个实体的三档后验预测概率；该维度 × 指标没有模型时返回 null。
  LighthouseOrdinalResult? score({
    required String dim,
    required String metric,
    required String name,
    required String group,
    required LighthouseOrdinalFeatures f,
  }) {
    final raw = _dim(dim)[metric];
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final bMap = m['b'] is Map ? Map<String, dynamic>.from(m['b'] as Map) : const <String, dynamic>{};
    final betas = [for (final k in lighthouseOrdinalFixedEffects) _vec(bMap[k])];
    final cut = m['cut'] as List? ?? const [];
    if (cut.length < 2 || betas.any((b) => b.isEmpty)) return null;
    final k1 = _vec(cut[0]);
    final k2 = _vec(cut[1]);
    final ents = Map<String, dynamic>.from(m['entity'] as Map? ?? const {});
    final groups = Map<String, dynamic>.from(m['group'] as Map? ?? const {});
    List<double>? a;
    var knownE = false;
    var knownG = false;
    final ek = ents['$name::$group'];
    if (ek != null) {
      a = _vec(ek);
      knownE = true;
      knownG = true;
    } else if (groups[group] != null) {
      a = _vec(groups[group]);
      knownG = true;
    }
    final n = [...betas.map((b) => b.length), k1.length, k2.length].reduce(math.min);
    if (n == 0) return null;
    final x = f.design;
    double sig(double z) => 1 / (1 + math.exp(-z));
    var s0 = 0.0;
    var s2 = 0.0;
    var aSum = 0.0;
    for (var i = 0; i < n; i++) {
      final ai = a != null && i < a.length ? a[i] : 0.0;
      aSum += ai;
      var eta = ai;
      for (var j = 0; j < x.length; j++) {
        eta += betas[j][i] * x[j];
      }
      s0 += sig(k1[i] - eta);
      s2 += 1 - sig(k2[i] - eta);
    }
    final pDown = s0 / n;
    final pUp = s2 / n;
    return LighthouseOrdinalResult(
      name: name,
      group: group,
      features: f,
      pDown: pDown,
      pUp: pUp,
      pFlat: math.max(0.0, 1 - pDown - pUp),
      effect: aSum / n,
      knownEntity: knownE,
      knownGroup: knownG,
    );
  }
}

/// 一个维度一次拉数的结果：每个指标一组实体结论。
@immutable
class LighthouseOrdinalBundle {
  const LighthouseOrdinalBundle({
    required this.model,
    required this.dim,
    required this.day,
    required this.daysInMonth,
    required this.month,
    required this.byMetric,
    required this.skippedSmall,
  });

  final LighthouseProductOrdinalModel model;
  final String dim;
  final int day;
  final int daysInMonth;

  /// 本月（1 号）。
  final DateTime month;
  final Map<String, List<LighthouseOrdinalResult>> byMetric;

  /// 上月体量不到门槛、没进模型的实体（按指标）。
  final Map<String, List<String>> skippedSmall;
}

/// 把 5 段区间的列表行拼成特征并打分。
/// [rows] 键：cur / prevSameDay / prevTotal / last7 / prev7；值 = 「名称::分组」→ 行。
LighthouseOrdinalBundle lighthouseScoreEntities({
  required LighthouseProductOrdinalModel model,
  required String dim,
  required Map<String, Map<String, Map<String, dynamic>>> rows,
  required int day,
  required int daysInMonth,
  required DateTime month,
}) {
  double v(String seg, String key, String field) {
    final x = rows[seg]?[key]?[field];
    return x is num ? x.toDouble() : 0.0;
  }

  final keys = <String>{...?rows['cur']?.keys, ...?rows['prevTotal']?.keys};
  final out = <String, List<LighthouseOrdinalResult>>{};
  final skipped = <String, List<String>>{};
  for (final metric in model.metricsOf(dim)) {
    final field = lighthouseOrdinalRowField[metric];
    if (field == null) continue;
    final list = <LighthouseOrdinalResult>[];
    for (final key in keys) {
      final cut = key.lastIndexOf('::');
      final name = cut < 0 ? key : key.substring(0, cut);
      final group = cut < 0 ? '' : key.substring(cut + 2);
      final f = LighthouseOrdinalFeatures(
        mtd: v('cur', key, field),
        prevSameDay: v('prevSameDay', key, field),
        prevTotal: v('prevTotal', key, field),
        last7: v('last7', key, field),
        prev7: v('prev7', key, field),
        day: day,
        daysInMonth: daysInMonth,
      );
      if (f.prevTotal.abs() < model.minPrevTotal) {
        if (f.prevTotal.abs() > 0 || f.mtd.abs() > 0) {
          (skipped[metric] ??= <String>[]).add(name);
        }
        continue;
      }
      final r = model.score(
        dim: dim,
        metric: metric,
        name: name,
        group: group,
        f: f,
      );
      if (r != null) list.add(r);
    }
    list.sort((a, b) => b.riskAmount.compareTo(a.riskAmount));
    out[metric] = list;
  }
  return LighthouseOrdinalBundle(
    model: model,
    dim: dim,
    day: day,
    daysInMonth: daysInMonth,
    month: month,
    byMetric: out,
    skippedSmall: skipped,
  );
}
