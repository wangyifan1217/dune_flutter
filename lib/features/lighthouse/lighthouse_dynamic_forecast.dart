// 日级动态金额模型。正金额使用 Gamma / log link；有负值的金额使用
// Gaussian / identity link。日水平为随机游走，星期与月底系数联合估计。
// 参数后验采用 Laplace 近似；shape / 日水平波动为训练窗内的经验估计。
// 所有拟合只读取 cutoff 及以前，缺失日期不作为零观测。
import 'dart:math' as math;

class LighthouseDynamicForecast {
  const LighthouseDynamicForecast({
    required this.forecast,
    required this.actual,
    required this.weekdayFactors,
    required this.monthEndFactor,
    required this.lastDayFactor,
    required this.dailyLevel,
    required this.cumulativeMean,
    required this.cumulativeLo,
    required this.cumulativeHi,
    required this.paths,
    required this.signed,
    required this.observations,
  });
  final double forecast;
  final double actual;
  final List<double> weekdayFactors;
  final double monthEndFactor;
  final double lastDayFactor;
  final double dailyLevel;
  final List<double> cumulativeMean;
  final List<double> cumulativeLo;
  final List<double> cumulativeHi;
  final List<List<double>> paths;
  final bool signed;
  final int observations;
}

double lighthouseForecastQuantile(List<double> xs, double q) {
  if (xs.isEmpty) return double.nan;
  final sorted = [...xs]..sort();
  final pos = (sorted.length - 1) * q;
  final a = pos.floor();
  final b = pos.ceil();
  return sorted[a] + (sorted[b] - sorted[a]) * (pos - a);
}

List<double> _features(DateTime day) {
  final x = List<double>.filled(11, 0);
  if (day.weekday == 7) {
    for (var i = 0; i < 6; i++) {
      x[i] = -1;
    }
  } else {
    x[day.weekday - 1] = 1;
  }
  final days = DateTime(day.year, day.month + 1, 0).day;
  x[6] = day.day > days - 3 ? 1 : 0;
  x[7] = day.day == days ? 1 : 0;
  // 月初集中结算不能被星期/月底系数吸收，否则会把月底贡献误学成负数。
  for (var i = 0; i < 3; i++) {
    x[8 + i] = day.day == i + 1 ? 1 : 0;
  }
  return x;
}

double _dot(List<double> a, List<double> b) {
  var value = 0.0;
  for (var i = 0; i < a.length; i++) {
    value += a[i] * b[i];
  }
  return value;
}

List<List<double>> _cholesky(List<List<double>> a) {
  final n = a.length;
  final l = List.generate(n, (_) => List<double>.filled(n, 0));
  for (var i = 0; i < n; i++) {
    for (var j = 0; j <= i; j++) {
      var v = a[i][j];
      for (var k = 0; k < j; k++) {
        v -= l[i][k] * l[j][k];
      }
      if (i == j) {
        l[i][j] = math.sqrt(math.max(v, 1e-9));
      } else {
        l[i][j] = v / l[j][j];
      }
    }
  }
  return l;
}

List<double> _solveCholesky(List<List<double>> l, List<double> b) {
  final n = b.length;
  final y = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    var v = b[i];
    for (var j = 0; j < i; j++) {
      v -= l[i][j] * y[j];
    }
    y[i] = v / l[i][i];
  }
  return _solveUpper(l, y);
}

List<double> _solveUpper(List<List<double>> l, List<double> b) {
  final n = b.length;
  final x = List<double>.filled(n, 0);
  for (var i = n - 1; i >= 0; i--) {
    var v = b[i];
    for (var j = i + 1; j < n; j++) {
      v -= l[j][i] * x[j];
    }
    x[i] = v / l[i][i];
  }
  return x;
}

class _Tridiagonal {
  _Tridiagonal(List<double> diagonal, this.off) : diag = [...diagonal] {
    for (var i = 1; i < diag.length; i++) {
      diag[i] -= off * off / diag[i - 1];
    }
  }
  final List<double> diag;
  final double off;
  List<double> solve(List<double> b) {
    final v = [...b];
    for (var i = 1; i < v.length; i++) {
      v[i] -= off / diag[i - 1] * v[i - 1];
    }
    final out = List<double>.filled(v.length, 0);
    out.last = v.last / diag.last;
    for (var i = out.length - 2; i >= 0; i--) {
      out[i] = (v[i] - off * out[i + 1]) / diag[i];
    }
    return out;
  }
}

class _JointFit {
  const _JointFit(
    this.level,
    this.beta,
    this.precision,
    this.lastInfluence,
    this.lastConditionalVariance,
  );
  final List<double> level;
  final List<double> beta;
  final List<List<double>> precision;
  final List<double> lastInfluence;
  final double lastConditionalVariance;
}

// 消去三对角的每日水平后，只解小型日历系数系统。
_JointFit _jointFit(
  List<double> weights,
  List<double> targets,
  List<List<double>> features,
  double q,
  double initial,
) {
  final n = weights.length;
  final p = features.first.length;
  final qp = 1 / (q * q);
  final diagonal = List.generate(
    n,
    (i) => weights[i] + qp * (i == 0 || i == n - 1 ? 1 : 2),
  );
  diagonal[0] += 0.25;
  final tri = _Tridiagonal(diagonal, -qp);
  final rhs = List.generate(n, (i) => weights[i] * targets[i]);
  rhs[0] += 0.25 * initial;
  final a = tri.solve(rhs);
  final b = List.generate(
    p,
    (j) => List.generate(n, (i) => weights[i] * features[i][j]),
  );
  final u = [for (final col in b) tri.solve(col)];
  final s = List.generate(p, (_) => List<double>.filled(p, 0));
  final r = List<double>.filled(p, 0);
  for (var j = 0; j < p; j++) {
    // 缺少月底重复观测时，月底效应自然收缩到 0。
    s[j][j] = j < 6 ? 8 : 5;
    for (var i = 0; i < n; i++) {
      r[j] += b[j][i] * (targets[i] - a[i]);
      for (var k = 0; k < p; k++) {
        s[j][k] += b[j][i] * (features[i][k] - u[k][i]);
      }
    }
  }
  final precision = _cholesky(s);
  final beta = _solveCholesky(precision, r);
  final level = List.generate(
    n,
    (i) =>
        a[i] -
        List.generate(p, (j) => u[j][i] * beta[j]).fold(0.0, (v, x) => v + x),
  );
  final unit = List<double>.filled(n, 0)..last = 1;
  return _JointFit(level, beta, precision, [
    for (final col in u) col.last,
  ], tri.solve(unit).last);
}

class _RandomDraws {
  _RandomDraws(int seed) : random = math.Random(seed);
  final math.Random random;
  double normal() =>
      math.sqrt(-2 * math.log(1 - random.nextDouble())) *
      math.cos(2 * math.pi * random.nextDouble());
  double gamma(double shape) {
    if (shape < 1) {
      return gamma(shape + 1) * math.pow(1 - random.nextDouble(), 1 / shape);
    }
    final d = shape - 1 / 3;
    final c = 1 / math.sqrt(9 * d);
    while (true) {
      final z = normal();
      final t = 1 + c * z;
      if (t <= 0) continue;
      final v = t * t * t;
      final u = 1 - random.nextDouble();
      if (u < 1 - 0.0331 * z * z * z * z ||
          math.log(u) < 0.5 * z * z + d * (1 - v + math.log(v))) {
        return d * v;
      }
    }
  }
}

LighthouseDynamicForecast? lighthouseDynamicForecast({
  required Map<DateTime, double> daily,
  required DateTime cutoff,
  bool signed = false,
  int simulations = 1600,
}) {
  final end = DateTime(cutoff.year, cutoff.month, cutoff.day);
  daily = {
    for (final e in daily.entries)
      if (e.value.isFinite)
        DateTime(e.key.year, e.key.month, e.key.day): e.value,
  };
  final entries =
      daily.entries
          .where((e) => !e.key.isAfter(end) && e.value.isFinite)
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
  if (entries.length < 56) return null;
  final start =
      entries.first.key.isAfter(end.subtract(const Duration(days: 239)))
      ? entries.first.key
      : end.subtract(const Duration(days: 239));
  final dates = <DateTime>[];
  for (var t = start; !t.isAfter(end); t = t.add(const Duration(days: 1))) {
    dates.add(t);
  }
  signed = signed || entries.any((e) => e.value < 0);
  final observed = [
    for (final t in dates)
      if (daily[t] != null) daily[t]!,
  ];
  if (observed.length < 56) return null;
  final magnitudes = observed
      .where((v) => v.abs() > 1e-9)
      .map((v) => v.abs())
      .toList();
  if (magnitudes.length < 28) return null;
  final scale = lighthouseForecastQuantile(magnitudes, 0.5);
  final initial = signed
      ? observed.reduce((a, b) => a + b) / observed.length / scale
      : 0.0;
  final x = [for (final day in dates) _features(day)];
  final y = [
    for (final day in dates) daily[day] == null ? null : daily[day]! / scale,
  ];
  final changes = <double>[];
  for (var i = 7; i < y.length; i++) {
    final a = y[i];
    final b = y[i - 7];
    if (a == null || b == null || (!signed && (a <= 0 || b <= 0))) continue;
    changes.add((signed ? a - b : math.log(a / b)).abs());
  }
  final spread = changes.isEmpty
      ? 0.2
      : lighthouseForecastQuantile(changes, 0.5) / 0.954;
  final noise = spread.clamp(0.06, 1.5).toDouble();
  final q = (noise * 0.12).clamp(0.012, 0.12).toDouble();
  final shape = (1 / (noise * noise)).clamp(1.0, 200.0).toDouble();
  var level = List<double>.filled(dates.length, initial);
  final parameters = x.first.length;
  var beta = List<double>.filled(parameters, 0);
  _JointFit? fit;
  double objective(List<double> ll, List<double> bb) {
    var value = 0.125 * math.pow(ll.first - initial, 2);
    for (var j = 0; j < parameters; j++) {
      value += 0.5 * (j < 6 ? 8 : 5) * bb[j] * bb[j];
    }
    for (var i = 0; i < ll.length; i++) {
      if (i > 0) {
        value += 0.5 * math.pow((ll[i] - ll[i - 1]) / q, 2);
      }
      final yy = y[i];
      if (yy == null || (!signed && yy <= 0)) continue;
      final eta = ll[i] + _dot(x[i], bb);
      value += signed
          ? 0.5 * math.pow((yy - eta) / noise, 2)
          : shape * (eta + yy * math.exp((-eta).clamp(-25.0, 25.0)));
    }
    return value.toDouble();
  }

  for (var iteration = 0; iteration < (signed ? 2 : 24); iteration++) {
    final w = List<double>.filled(y.length, 0);
    final z = List<double>.filled(y.length, 0);
    for (var i = 0; i < y.length; i++) {
      final yy = y[i];
      if (yy == null || (!signed && yy <= 0)) continue;
      final eta = level[i] + _dot(x[i], beta);
      if (signed) {
        w[i] = 1 / (noise * noise);
        z[i] = yy;
      } else {
        final ratio = (yy * math.exp((-eta).clamp(-25.0, 25.0))).clamp(
          0.0001,
          1e4,
        );
        w[i] = shape * ratio;
        z[i] = eta + (ratio - 1) / ratio;
      }
    }
    fit = _jointFit(w, z, x, q, initial);
    final before = objective(level, beta);
    var step = 1.0;
    var nextLevel = fit.level;
    var nextBeta = fit.beta;
    while (objective(nextLevel, nextBeta) > before + 1e-8 && step > 1 / 1024) {
      step *= 0.5;
      nextLevel = List.generate(
        level.length,
        (i) => level[i] + step * (fit!.level[i] - level[i]),
      );
      nextBeta = List.generate(
        parameters,
        (i) => beta[i] + step * (fit!.beta[i] - beta[i]),
      );
    }
    final movement = List.generate(
      level.length,
      (i) => (nextLevel[i] - level[i]).abs(),
    ).reduce(math.max);
    level = nextLevel;
    beta = nextBeta;
    if (movement < 1e-5) break;
  }
  if (fit == null) return null;
  // 最终 mode 的 Hessian，避免把上一次 Newton 步的曲率当后验协方差。
  final weights = List.generate(y.length, (i) {
    final yy = y[i];
    if (yy == null || (!signed && yy <= 0)) return 0.0;
    return signed
        ? 1 / (noise * noise)
        : shape *
              (yy * math.exp(-(level[i] + _dot(x[i], beta)))).clamp(1e-4, 1e4);
  });
  final posterior = _jointFit(
    weights,
    List<double>.filled(y.length, 0),
    x,
    q,
    initial,
  );
  final p = posterior.precision;
  final u = posterior.lastInfluence;
  final zeros = observed.where((v) => v == 0).length;
  final positiveProbability = signed || zeros == 0
      ? 1.0
      : (observed.length - zeros + 0.5) / (observed.length + 1);
  final totalDays = DateTime(end.year, end.month + 1, 0).day;
  final cumulative = <double>[];
  var actual = 0.0;
  for (var day = 1; day <= end.day; day++) {
    final amount = daily[DateTime(end.year, end.month, day)];
    if (amount == null) return null;
    actual += amount;
    cumulative.add(actual);
  }
  final projected = [...cumulative];
  var running = actual;
  for (var day = end.day + 1; day <= totalDays; day++) {
    final xf = _features(DateTime(end.year, end.month, day));
    final delta = List.generate(parameters, (i) => xf[i] - u[i]);
    final variance =
        posterior.lastConditionalVariance +
        _dot(delta, _solveCholesky(p, delta)) +
        q * q * (day - end.day);
    final mean = level.last + _dot(xf, beta);
    running +=
        scale *
        (signed
            ? mean
            : positiveProbability *
                  math.exp((mean + variance / 2).clamp(-25.0, 25.0)));
    projected.add(running);
  }
  final paths = <List<double>>[];
  final random = _RandomDraws(719 + end.year * 400 + end.month * 32 + end.day);
  for (var draw = 0; draw < simulations; draw++) {
    final db = _solveUpper(
      p,
      List.generate(parameters, (_) => random.normal()),
    );
    final sampledBeta = List.generate(parameters, (i) => beta[i] + db[i]);
    var sampledLevel =
        level.last -
        _dot(u, db) +
        math.sqrt(math.max(0, posterior.lastConditionalVariance)) *
            random.normal();
    var probability = positiveProbability;
    if (!signed && zeros > 0) {
      final a = random.gamma(observed.length - zeros + 0.5);
      final b = random.gamma(zeros + 0.5);
      probability = a / (a + b);
    }
    var sum = actual;
    final path = [...cumulative];
    for (var day = end.day + 1; day <= totalDays; day++) {
      sampledLevel += q * random.normal();
      final eta =
          sampledLevel +
          _dot(_features(DateTime(end.year, end.month, day)), sampledBeta);
      final amount = signed
          ? scale * (eta + noise * random.normal())
          : random.random.nextDouble() > probability
          ? 0.0
          : scale *
                math.exp(eta.clamp(-25.0, 25.0)) *
                random.gamma(shape) /
                shape;
      sum += amount;
      path.add(sum);
    }
    paths.add(path);
  }
  final lo = [...cumulative];
  final hi = [...cumulative];
  for (var day = end.day; day < totalDays; day++) {
    final values = [for (final path in paths) path[day]];
    lo.add(
      values.isEmpty ? projected[day] : lighthouseForecastQuantile(values, 0.1),
    );
    hi.add(
      values.isEmpty ? projected[day] : lighthouseForecastQuantile(values, 0.9),
    );
  }
  final wf = [
    for (var weekday = 1; weekday <= 7; weekday++)
      signed
          ? scale *
                (weekday == 7
                    ? -beta.take(6).reduce((a, b) => a + b)
                    : beta[weekday - 1])
          : math.exp(
              weekday == 7
                  ? -beta.take(6).reduce((a, b) => a + b)
                  : beta[weekday - 1],
            ),
  ];
  return LighthouseDynamicForecast(
    forecast: projected.last,
    actual: actual,
    weekdayFactors: wf,
    monthEndFactor: signed ? beta[6] * scale : math.exp(beta[6]),
    lastDayFactor: signed ? beta[7] * scale : math.exp(beta[7]),
    dailyLevel: signed
        ? scale * level.last
        : scale * positiveProbability * math.exp(level.last),
    cumulativeMean: projected,
    cumulativeLo: lo,
    cumulativeHi: hi,
    paths: paths,
    signed: signed,
    observations: observed.length,
  );
}
