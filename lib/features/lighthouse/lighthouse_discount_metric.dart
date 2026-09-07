String lighthouseDiscountRateLabel(double? decimalRate) {
  if (decimalRate == null) return '—';
  final fixed = (decimalRate * 100).toStringAsFixed(2);
  final trimmed = fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  return '$trimmed%';
}

String? lighthouseDiscountDateRange(String? startRaw, String? endRaw) {
  if (startRaw == null || endRaw == null) return null;
  final start = DateTime.tryParse(
    startRaw.length >= 10 ? startRaw.substring(0, 10) : startRaw,
  );
  final end = DateTime.tryParse(
    endRaw.length >= 10 ? endRaw.substring(0, 10) : endRaw,
  );
  if (start == null || end == null) return null;
  String md(DateTime date) =>
      '${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  return '${md(start)}–${md(end)}';
}

/// 折扣区直接消费 /discounts 返回的 map，不依赖当期供给行是否挂载成功。
List<Map<String, dynamic>> lighthouseDiscountRowsFromMap(
  Map<String, dynamic> discounts,
) {
  final out = <Map<String, dynamic>>[];
  discounts.forEach((name, raw) {
    if (raw is! Map) return;
    final row = Map<String, dynamic>.from(raw);
    row.putIfAbsent('province', () => name);
    final cur =
        (row['currentCumSales'] as num?)?.toDouble() ??
        (row['cur'] as num?)?.toDouble() ??
        0;
    if (cur <= 0) return;
    out.add(row);
  });
  return out;
}

/// 省份规范化 —— 与后端 derive.go 的 provincePrefixes 保持同一份口径。
/// 台账名「广西壮族自治区」和后端 province「广西」必须归到同一个 key，
/// 否则光靠去后缀会得到「广西壮族」，广西 / 内蒙古 / 宁夏 / 新疆 / 西藏五个
/// 带民族名的省全都对不上，折扣条在这些行上永远不出现。
const List<String> _lhProvincePrefixes = [
  '内蒙古', '黑龙江', '宁夏', '广西', '新疆', '西藏',
  '北京', '天津', '上海', '重庆',
  '河北', '山西', '辽宁', '吉林', '江苏', '浙江', '安徽', '福建', '江西', '山东',
  '河南', '湖北', '湖南', '广东', '海南', '四川', '贵州', '云南', '陕西', '甘肃',
  '青海',
];

String lighthouseProvinceKey(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return '';
  for (final prefix in _lhProvincePrefixes) {
    if (name.startsWith(prefix)) return prefix;
  }
  return name.replaceAll(RegExp(r'(省|市|自治区|特别行政区)$'), '').trim();
}

/// 供给账本折扣 UI（冻结列条子 / 展开档位卡 / 进页预拉 /discounts）。
/// 关闭：点供给不再为每一行加高、加手势、加展开卡，避免 Flutter Web 整页卡死。
const bool lighthouseLedgerShowsDiscountUi = false;

/// 本地 debug 预览冻结列折扣条。仅在手动验收版式时临时开启：
/// 非虚拟化账本会为每个无记录行构建一套预览组件，Flutter Web 下可能耗尽渲染资源。
/// 正常运行只渲染 `/discounts` 返回的真实数据。
const bool lighthouseDiscountUsesLocalPreview = false;

/// 接口失败或空时，只灌几条样例到折扣 map。不是给每一行编一条。
const bool lighthouseDiscountUsesEmptyApiFixture = false;

Map<String, dynamic> lighthouseDiscountDebugFixture() {
  Map<String, dynamic> row(String name, double sales) => {
    ...lighthouseDiscountPreviewForRow(rowName: name, sales: sales),
    '_debugFixture': true,
  };

  return <String, dynamic>{
    '山西中石油': row('山西省', 1500000),
    '河南中石油': row('河南省', 5950000),
    '广东中石油': row('广东省', 3200000),
  };
}

Map<String, dynamic> lighthouseDiscountResolveForDisplay(
  Map<String, dynamic> apiDiscounts, {
  bool allowFixture = false,
}) {
  if (apiDiscounts.isNotEmpty) {
    return Map<String, dynamic>.from(apiDiscounts);
  }
  if (!allowFixture || !lighthouseDiscountUsesEmptyApiFixture) {
    return const {};
  }
  return lighthouseDiscountDebugFixture();
}

bool lighthouseDiscountMapUsesDebugFixture(
  Map<String, dynamic> discounts,
) => discounts.values.whereType<Map>().any(
  (value) => value['_debugFixture'] == true,
);

const int lighthouseDiscountFixtureRowLimit = 3;

bool lighthouseDiscountShouldUseFixtureForRow(
  Map<String, dynamic> discounts,
  int rowIndex,
) => lighthouseDiscountMapUsesDebugFixture(discounts) &&
    rowIndex >= 0 &&
    rowIndex < lighthouseDiscountFixtureRowLimit;

/// 按该行销售额编一条「第2档 / 还差 X万」。不是真返点。
///
/// 必须带 [tierCount] + [tiers]：展开区档位卡靠阶梯才能画出格子，
/// 缺这两项时占位阶梯退成 null，卡会整段消失。
Map<String, dynamic> lighthouseDiscountPreviewForRow({
  required String rowName,
  double sales = 0,
}) {
  final cur = sales > 0 ? sales : 800000;
  final gap = (cur * 0.35).clamp(50000, 5e7);
  final next = cur + gap;
  return <String, dynamic>{
    'province': lighthouseProvinceKey(rowName),
    'currentCumSales': cur,
    'tierLevel': 2,
    'tierCount': 4,
    'tierLabel': '第2档',
    'next_threshold': next,
    'salesToNextTier': gap,
    'ruleType': '月阶梯',
    'calcMode': 1,
    'tiers': <Map<String, dynamic>>[
      {'level': 1, 'minValue': 0.0, 'permille': 0.8, 'reached': true},
      {
        'level': 2,
        'minValue': cur * 0.5,
        'permille': 1.2,
        'reached': true,
      },
      {'level': 3, 'minValue': next, 'permille': 1.8, 'reached': false},
      {
        'level': 4,
        'minValue': next * 1.7,
        'permille': 2.5,
        'reached': false,
      },
    ],
  };
}

/// 后端没给 tierCount 时，用当前档 + 是否有下一档推出格子数。
/// 0 会让 [LighthouseDiscountLadder.placeholder] 返回 null，条子就点不开。
int lighthouseDiscountPlaceholderTierCount({
  int? tierCount,
  int currentLevel = 1,
  bool hasNext = false,
}) {
  if (tierCount != null && tierCount > 0) return tierCount;
  final level = currentLevel < 1 ? 1 : currentLevel;
  if (hasNext) return level + 1;
  return level;
}

/// 供给行「山西省 + 中石油」对应后端供应商 key「山西中石油」。
String lighthouseDiscountSupplyMatchKey(String rowName, String rowGroup) {
  final province = lighthouseProvinceKey(rowName);
  final group = rowGroup.trim();
  if (province.isEmpty || group.isEmpty) return '';
  return '$province$group';
}

/// 调试预览最多挂到前几行。全表灌假条会把非虚拟化账本在 Flutter Web 上卡死。
const int lighthouseDiscountLocalPreviewLimit = 2;

bool lighthouseDiscountAllowsLocalPreview(int rowIndex) =>
    lighthouseDiscountUsesLocalPreview &&
    rowIndex >= 0 &&
    rowIndex < lighthouseDiscountLocalPreviewLimit;

/// 冻结列折扣条取数：先按行名精确命中 /discounts 的 key（广西壮族自治区），
/// 再按「省份+分类」命中（山西中石油），再按省份 key 命中（广西），
/// 最后回落到供给行上挂载的 discount 对象。
Map<String, dynamic>? lighthouseDiscountForRow({
  required Map<String, dynamic> discountsByName,
  required String rowName,
  String rowGroup = '',
  Object? attached,
}) {
  final name = rowName.trim();
  if (name.isNotEmpty) {
    final direct = discountsByName[name];
    if (direct is Map) return Map<String, dynamic>.from(direct);

    final group = rowGroup.trim();
    final matchKey = lighthouseDiscountSupplyMatchKey(name, group);
    if (matchKey.isNotEmpty) {
      final byGroup = discountsByName[matchKey];
      if (byGroup is Map) return Map<String, dynamic>.from(byGroup);
    }

    final allowProvinceFallback =
        group.isEmpty || group.contains('中石油') || group.contains('中石化');
    final key = lighthouseProvinceKey(name);
    if (allowProvinceFallback && key.isNotEmpty) {
      final byProvince = discountsByName[key];
      if (byProvince is Map) return Map<String, dynamic>.from(byProvince);
      for (final entry in discountsByName.entries) {
        if (lighthouseProvinceKey(entry.key) != key) continue;
        final value = entry.value;
        if (value is Map) return Map<String, dynamic>.from(value);
      }
    }
  }
  if (attached is Map) return Map<String, dynamic>.from(attached);
  return null;
}

/// 冻结列宽度只有一百出头，「还差 1.50万」再和「第2档」分列必裁单位。
/// 统一成一句，数字去掉无意义的尾零：15000 → 1.5万。
String lighthouseDiscountCompactWan(double amount) {
  if (amount.abs() >= 1e8) {
    final yi = amount / 1e8;
    final digits = yi.abs() >= 10 ? 1 : 2;
    return '${_lhTrimTrailingZeros(yi.toStringAsFixed(digits))}亿';
  }
  final wan = amount / 1e4;
  final digits = wan.abs() >= 100 ? 0 : 1;
  return '${_lhTrimTrailingZeros(wan.toStringAsFixed(digits))}万';
}

String _lhTrimTrailingZeros(String raw) =>
    raw.replaceFirst(RegExp(r'\.0+$'), '');

// ── 折扣条模型 ──────────────────────────────────────────────────────────
//   一行字 + 一根条要同时回答三件事：现在第几档 / 还差多少 / 来不来得及。
//   前两件放文字，第三件放条 —— 冻结列去掉展开钮只剩约 87pt，
//   「第2档 差27.9万」已经吃到 76pt，「剩9天」再进去必截断。
//
//   条的语义与走势图统一：实心 = 已发生，浅色延伸 = 按当前速度到周期末的位置，
//   条尾 = 下一档门槛。浅色段够到条尾 = 这个周期能过档。
//   外推公式沿用运营会定的那一条：已发生 ÷ 已过天数 × 周期总天数。
//   注意周期是「规则自己的周期」（月阶梯=当月、年阶梯=当年），与看板 period 无关。

/// 折扣规则周期的时间进度。周期时间来自 calc_record 的 period_start/end_time。
class LighthouseDiscountPace {
  const LighthouseDiscountPace({
    required this.elapsedDays,
    required this.totalDays,
  });

  /// 已过天数，含当天。
  final int elapsedDays;

  /// 周期自然日天数。
  final int totalDays;

  int get remainDays => totalDays - elapsedDays;

  double get progress =>
      totalDays <= 0 ? 0 : (elapsedDays / totalDays).clamp(0.0, 1.0).toDouble();
}

DateTime? _lhParseDay(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final text = raw.trim();
  final parsed = DateTime.tryParse(
    text.length >= 10 ? text.substring(0, 10) : text,
  );
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

LighthouseDiscountPace? lighthouseDiscountPace({
  String? startRaw,
  String? endRaw,
  DateTime? now,
}) {
  final start = _lhParseDay(startRaw);
  final end = _lhParseDay(endRaw);
  if (start == null || end == null) return null;
  final total = end.difference(start).inDays + 1;
  if (total <= 0) return null;
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  var elapsed = today.difference(start).inDays + 1;
  // 周期没开始按第 1 天，已结束按满 —— 外推不能除以 0，也不能超过周期。
  if (elapsed < 1) elapsed = 1;
  if (elapsed > total) elapsed = total;
  return LighthouseDiscountPace(elapsedDays: elapsed, totalDays: total);
}

// ── 过档多赚 ────────────────────────────────────────────────────────────
//   「到了 X 能多赚 Y」的 Y。两种计费模式的 Y 完全不是一回事，不能共用一个公式：
//
//   全额累进（calc_mode=2）：过线那一刻整个基数按新费率重算 —— 收益是一次性跳变，
//     多赚 = 期末基数 × 费率差。差 27.9 万可能换来几十万返点，这是最该喊出来的数。
//
//   超额累进（calc_mode=1）：只有超出门槛的部分享新费率 —— 过线那一刻多赚 0，
//     收益来自过线之后还能做多少。所以必须用「按当前速度到期末的量」减门槛，
//     没有速度就说不出来，返回 null，绝不拿门槛金额冒充收益。
//
//   费率一律用 ‰ 口径（与 spec §4.1「累计基数 ×（下档−本档）÷ 1000」一致）。

/// [target] 下一档门槛；[projected] 按当前速度到周期末的量。
/// 返回 null = 这一行说不出多赚多少（缺下一档费率，或超额累进缺速度）。
double? lighthouseDiscountGainAtNextTier({
  int? calcMode,
  double? target,
  double? currentPermille,
  double? nextPermille,
  double? projected,
}) {
  if (target == null || target <= 0) return null;
  if (currentPermille == null || nextPermille == null) return null;
  final diff = nextPermille - currentPermille;
  if (diff <= 0) return null;

  // 超额累进：只有超出门槛那一段享新费率。
  if (calcMode == 1) {
    if (projected == null) return null;
    final over = projected - target;
    if (over <= 0) return null;
    return over * diff / 1000;
  }

  // 全额累进（含未标注模式）：整个基数重算，基数至少是门槛。
  final base = (projected != null && projected > target) ? projected : target;
  return base * diff / 1000;
}

/// 冻结列折扣条的完整形态。
class LighthouseDiscountStrip {
  const LighthouseDiscountStrip({
    required this.line,
    required this.fill,
    this.forecast,
    this.reachable,
    this.paceOnly = false,
    this.pace,
    this.gain,
  });

  /// 一行文案，如「第2档 差27.9万」。
  final String line;

  /// 实心段 0~1。
  final double fill;

  /// 浅色预测段终点 0~1；null = 不画（没有周期或没有门槛）。
  final double? forecast;

  /// 按当前速度这个周期能否过档；null = 没门槛，不做判断。
  final bool? reachable;

  /// true = 这根条画的不是金额进度（没门槛时的退路），用半透明区分。
  final bool paceOnly;

  /// 过到下一档能多赚多少（元）；null = 这一行说不出来。
  final double? gain;

  final LighthouseDiscountPace? pace;
}

/// 组装折扣条。
///
/// 这一格只回答一个问题：**这一档怎么样了**。四种答案共用一套语法，
/// 不混进「返多少」这种另一个问题的答案 —— 两种动词挤在同一个位置就是看不懂的根源。
///   · 第2档 差27.9万 —— 下一档门槛已知，还差这么多，条上带按当前速度的预测段
///   · 第1档 已完成   —— 这一档达成了（calc_record 有 reach_time），下一档门槛后端还没给
///   · 第1档 进行中   —— 这一档还没达成，条画周期走了多少
///   · 第4档 已封顶   —— 最高档
///   · 固定折扣       —— 没有档位这回事
LighthouseDiscountStrip lighthouseDiscountStripFor({
  required bool isFixed,
  required bool isCapped,
  required double cur,
  bool reached = false,
  double? nextThreshold,
  double? gapToNext,
  int? tierLevel,
  String? tierLabel,
  String? periodStart,
  String? periodEnd,
  DateTime? now,
  int? calcMode,
  double? currentPermille,
  double? nextPermille,
  double? gainFromApi,
  bool preferGain = false,
}) {
  final tier = (tierLabel != null && tierLabel.trim().isNotEmpty)
      ? tierLabel.trim()
      : '第${(tierLevel == null || tierLevel < 1) ? 1 : tierLevel}档';
  final pace = lighthouseDiscountPace(
    startRaw: periodStart,
    endRaw: periodEnd,
    now: now,
  );

  if (isCapped) {
    return LighthouseDiscountStrip(line: '$tier 已封顶', fill: 1, pace: pace);
  }

  // 固定折扣没有档位这回事，进度和「第几档」都不适用，只报状态。
  if (isFixed) {
    return LighthouseDiscountStrip(
      line: '固定折扣',
      fill: 1,
      paceOnly: true,
      pace: pace,
    );
  }

  // 门槛：优先绝对门槛，其次用「已发生 + 缺口」倒推。
  double? target;
  if (nextThreshold != null && nextThreshold > 0) {
    target = nextThreshold;
  } else if (gapToNext != null && gapToNext > 0) {
    target = cur + gapToNext;
  }

  if (target != null && target > 0) {
    final gap = target - cur;
    double? forecast;
    bool? reachable;
    double? projected;
    if (pace != null && cur > 0) {
      projected = cur / pace.elapsedDays * pace.totalDays;
      forecast = (projected / target).clamp(0.0, 1.0).toDouble();
      reachable = projected >= target;
    }
    // 后端算得出来的以后端为准（全额累进过线即得，是确定值，财务能复核）；
    // 超额累进后端不给 —— 收益取决于过线之后还能做多少，只有前端有速度，
    // 这时才用本地公式外推。两边永远不会同时给同一个数。
    final gain =
        gainFromApi ??
        lighthouseDiscountGainAtNextTier(
          calcMode: calcMode,
          target: target,
          currentPermille: currentPermille,
          nextPermille: nextPermille,
          projected: projected,
        );
    // 冻结列一行只装得下一个数：差多少是「要做什么」，多赚多少是「为什么值得做」。
    // 默认给「差」——它是可执行的那个；开了 preferGain 就换成「多赚」。
    final showGain = preferGain && gain != null && gain > 0;
    final String line;
    if (gap <= 0) {
      line = '$tier 已达标';
    } else if (showGain) {
      line = '$tier 多赚${lighthouseDiscountCompactWan(gain)}';
    } else {
      line = '$tier 差${lighthouseDiscountCompactWan(gap)}';
    }
    return LighthouseDiscountStrip(
      line: line,
      fill: (cur / target).clamp(0.0, 1.0).toDouble(),
      forecast: forecast,
      reachable: reachable,
      pace: pace,
      gain: gain,
    );
  }

  // 没门槛（第 1 档最常见）：按达成与否说话。
  //   已完成 —— 这一档到了，条画满（半透明，跟封顶的实色区分）；
  //   进行中 —— 还没到，条画周期走了多少，让人看出还剩多少时间。
  return LighthouseDiscountStrip(
    line: reached ? '$tier 已完成' : '$tier 进行中',
    fill: reached ? 1 : (pace?.progress ?? 0),
    paceOnly: true,
    pace: pace,
  );
}

// ── 折扣阶梯 ────────────────────────────────────────────────────────────
//   冻结列那条小条子回答「这一档怎么样了」，一句话；
//   展开区的「折扣档位」卡回答「一共几档、每档多少、我卡在哪」，一张图。
//   两者共用同一份 DiscountInfo，不重复取数。
//
//   阶梯与进度轨是**两层**，不是一条：
//     · 档位是序数（第几档）—— 上层等宽格，宽度不承载金额
//     · 门槛是基数（多少钱）—— 下层一条连续轨，按金额线性，刻度落在各档门槛
//   挤成一条的话：等宽就骗了金额，按金额等比又会把窄档压成看不见的一截。

/// 阶梯里的一档。费率一律 ‰，与 currentTier / nextRate 同口径。
class LighthouseDiscountTier {
  const LighthouseDiscountTier({
    required this.level,
    required this.minValue,
    required this.permille,
    required this.reached,
    this.maxValue,
    this.isPlaceholder = false,
  });

  final int level;
  final double minValue;
  final double permille;

  /// 这一档过没过。后端按 tierLevel 判，前端不重算。
  final bool reached;

  final double? maxValue;

  /// true = 后端没下发这一档，门槛与费率是占位，界面上必须画「—」。
  /// 绝不按等差猜门槛：阶梯几乎都是不等距的，猜出来的数会被当成真的。
  final bool isPlaceholder;

  String get label => '第$level档';
}

/// 一条规则的完整阶梯 + 当前位置。
class LighthouseDiscountLadder {
  const LighthouseDiscountLadder({
    required this.tiers,
    required this.currentLevel,
    required this.axisMax,
    this.hasFullLadder = true,
  });

  final List<LighthouseDiscountTier> tiers;

  /// 当前档 level。
  final int currentLevel;

  /// 进度轨右端点对应的金额。
  final double axisMax;

  /// false = 后端只给了当前档与下一档，阶梯里有占位格。
  final bool hasFullLadder;

  bool get isEmpty => tiers.isEmpty;

  LighthouseDiscountTier? get current {
    for (final t in tiers) {
      if (t.level == currentLevel) return t;
    }
    return null;
  }

  LighthouseDiscountTier? get next {
    for (final t in tiers) {
      if (t.level > currentLevel) return t;
    }
    return null;
  }

  /// 金额 → 进度轨上的 0~1 位置。
  double fracOf(double amount) {
    if (axisMax <= 0) return 0;
    return (amount / axisMax).clamp(0.0, 1.0).toDouble();
  }

  /// 解析 /lighthouse/discounts 的 tiers 数组。
  ///
  /// 后端还没发 tiers 时走 [placeholder]：按 tierCount 画出格子数，
  /// 只有当前档和下一档填真数，其余画「—」。宁可空着也不猜。
  static LighthouseDiscountLadder? fromApi(
    Object? raw, {
    required int currentLevel,
  }) {
    if (raw is! List || raw.isEmpty) return null;
    final tiers = <LighthouseDiscountTier>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();
      final level = (m['level'] as num?)?.toInt();
      final min = (m['minValue'] as num?)?.toDouble();
      final rate = (m['permille'] as num?)?.toDouble();
      if (level == null || min == null || rate == null) continue;
      final max = (m['maxValue'] as num?)?.toDouble();
      tiers.add(
        LighthouseDiscountTier(
          level: level,
          minValue: min,
          permille: rate,
          maxValue: (max == null || max <= 0) ? null : max,
          reached: m['reached'] == true || level <= currentLevel,
        ),
      );
    }
    if (tiers.isEmpty) return null;
    tiers.sort((a, b) => a.level.compareTo(b.level));
    return LighthouseDiscountLadder(
      tiers: tiers,
      currentLevel: currentLevel,
      axisMax: _axisMaxOf(tiers),
      hasFullLadder: true,
    );
  }

  /// 后端未下发完整阶梯时的退路。
  static LighthouseDiscountLadder? placeholder({
    required int tierCount,
    required int currentLevel,
    double? currentPermille,
    double? nextPermille,
    double? currentMin,
    double? nextThreshold,
  }) {
    if (tierCount <= 0) return null;
    final tiers = <LighthouseDiscountTier>[];
    for (var level = 1; level <= tierCount; level++) {
      final isCurrent = level == currentLevel;
      final isNext = level == currentLevel + 1;
      final known = (isCurrent && currentPermille != null) ||
          (isNext && nextPermille != null);
      tiers.add(
        LighthouseDiscountTier(
          level: level,
          minValue: isCurrent
              ? (currentMin ?? 0)
              : (isNext ? (nextThreshold ?? 0) : 0),
          permille: isCurrent
              ? (currentPermille ?? 0)
              : (isNext ? (nextPermille ?? 0) : 0),
          reached: level <= currentLevel,
          isPlaceholder: !known,
        ),
      );
    }
    // 右端点不知道最高档在哪，用下一档门槛外推一点，坐标轴末位画「—」。
    final axis = (nextThreshold != null && nextThreshold > 0)
        ? nextThreshold * 1.2
        : 0.0;
    return LighthouseDiscountLadder(
      tiers: tiers,
      currentLevel: currentLevel,
      axisMax: axis,
      hasFullLadder: false,
    );
  }

  /// 最后一道兜底：连 tierCount 都没有，但当前档 / 下一档是知道的。
  ///
  /// 这一层存在的唯一理由是：冻结列那条折扣条一旦可点，展开区就**必须**有东西
  /// 出来。返回 null 会让用户点了个寂寞 —— 那比档位画得不全糟得多。
  static LighthouseDiscountLadder? minimal({
    required int currentLevel,
    double? currentPermille,
    double? nextPermille,
    double? nextThreshold,
  }) {
    final level = currentLevel < 1 ? 1 : currentLevel;
    final tiers = <LighthouseDiscountTier>[
      LighthouseDiscountTier(
        level: level,
        minValue: 0,
        permille: currentPermille ?? 0,
        reached: true,
        isPlaceholder: currentPermille == null,
      ),
      if (nextThreshold != null && nextThreshold > 0)
        LighthouseDiscountTier(
          level: level + 1,
          minValue: nextThreshold,
          permille: nextPermille ?? 0,
          reached: false,
          isPlaceholder: nextPermille == null,
        ),
    ];
    if (tiers.length == 1 && currentPermille == null) return null;
    return LighthouseDiscountLadder(
      tiers: tiers,
      currentLevel: level,
      axisMax: (nextThreshold != null && nextThreshold > 0)
          ? nextThreshold * 1.2
          : 0,
      hasFullLadder: false,
    );
  }

  static double _axisMaxOf(List<LighthouseDiscountTier> tiers) {
    var maxMin = 0.0;
    for (final t in tiers) {
      if (t.minValue > maxMin) maxMin = t.minValue;
      if (t.maxValue != null && t.maxValue! > maxMin) maxMin = t.maxValue!;
    }
    // 最高档没有上界时，轨的右端就是最高档门槛本身 —— 再往右是无限，画不出来。
    return maxMin <= 0 ? 0 : maxMin;
  }
}

/// 按当前速度到周期末的量。没有周期或没有已发生量就说不出来。
double? lighthouseDiscountProjected({
  required double cur,
  LighthouseDiscountPace? pace,
}) {
  if (pace == null || pace.elapsedDays <= 0 || cur <= 0) return null;
  return cur / pace.elapsedDays * pace.totalDays;
}

/// 按当前速度，哪一天能过 [threshold]。返回 null = 到不了或说不出来。
DateTime? lighthouseDiscountReachDay({
  required double cur,
  required double threshold,
  required LighthouseDiscountPace? pace,
  DateTime? now,
}) {
  if (pace == null || pace.elapsedDays <= 0 || cur <= 0) return null;
  if (threshold <= cur) return now ?? DateTime.now();
  final perDay = cur / pace.elapsedDays;
  if (perDay <= 0) return null;
  final needDays = ((threshold - cur) / perDay).ceil();
  if (needDays > pace.remainDays) return null; // 这个周期到不了
  final ref = now ?? DateTime.now();
  return DateTime(ref.year, ref.month, ref.day + needDays);
}
