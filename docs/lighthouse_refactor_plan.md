# 灯塔接真数据改造清单 v1

> 目标：清掉所有"看起来动态、实际写死"的代码，让 Dart 主界面所有显示数据都来自真实接口。
> 用法：每个任务卡可独立作为一个 PR / Cursor session。任务编号 `FE-x` / `BE-x` 可直接在 commit / PR 里引用。
> 路径基准：`apps/dunes_mobile/lib/features/lighthouse/native_lighthouse_page.dart`（下文简称 `native_lighthouse_page.dart`）

---

## 前置：联调里程碑

| 里程碑 | 包含任务 | 依赖 | 估时 |
|---|---|---|---|
| **M1** 前端独立可发版 | FE-1, FE-2, FE-3 | 无 | 1 天 |
| **M2** Hero 数据完全走真 | BE-1, BE-2 → 前端联调 | BE | 1.5 天 |
| **M3** Trend / Delta 真数据 | BE-3 → FE-5, FE-6 | BE-3 完成 | 2 天 |
| **M4** 折扣进度提升空间 | BE-4 → FE-7 | BE-4 完成 | 1 天 |

**最快可发版路径**：M1 完成后即可发，用户立刻看不到"早上好，Suzy / 数据已同步 · 09:18"这类穿帮文案。

---

# 前端任务（FE）

## FE-1 ｜ Greeting / AppBar 硬编码全部动态化

**来源**：审计
**优先级**：P0
**估时**：0.5 天
**依赖**：可选依赖 BE-1 的 `lastSyncedAt` 字段，若 BE 还没好可以先用本地 fetched time 兜底

### 改动点 1：Greeting 日期 + 周几

**文件**：`native_lighthouse_page.dart` 约 1519 行

```dart
// 当前
Text('星期日 · 06.21', ...)

// 改为
Text(_formatDateLabel(), ...)
```

新增方法（写在 `_NativeLighthousePageState` 内）：

```dart
String _formatDateLabel() {
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  final now = DateTime.now();
  final w = weekdays[now.weekday - 1];
  final mm = now.month.toString().padLeft(2, '0');
  final dd = now.day.toString().padLeft(2, '0');
  return '星期$w · $mm.$dd';
}
```

### 改动点 2：Greeting 时段问候 + 用户名

**文件**：`native_lighthouse_page.dart` 约 1529 行

```dart
// 当前
Text('早上好，Suzy', ...)

// 改为
Text(_greetingText(), ...)
```

```dart
String _greetingText() {
  final hour = DateTime.now().hour;
  final greeting = hour < 6 ? '夜深了' :
                   hour < 11 ? '早上好' :
                   hour < 14 ? '中午好' :
                   hour < 18 ? '下午好' :
                   hour < 22 ? '晚上好' : '夜深了';
  final name = widget.session.username; // 或 widget.session.displayName，看 AuthSession 实际字段
  return '$greeting，$name';
}
```

> ⚠️ 在 Cursor 里搜 `class AuthSession` 确认实际暴露的字段名（`username` / `nickname` / `displayName` 任选其一）

### 改动点 3：sync pill 时间

**文件**：`native_lighthouse_page.dart` 约 1559 行

```dart
// 当前
Text('数据已同步 · 09:18', ...)

// 改为
Text('数据已同步 · ${_syncedAtLabel()}', ...)
```

新增字段 + 方法：

```dart
DateTime? _lastSyncedAt;  // 在 _loadBundle 成功后赋值

String _syncedAtLabel() {
  final t = _lastSyncedAt ?? DateTime.now();
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}
```

在 `_loadBundle` 接口成功回调里：

```dart
// 优先用后端字段（BE-1 完成后）
_lastSyncedAt = (bundle.metrics['lastSyncedAt'] is String)
    ? DateTime.tryParse(bundle.metrics['lastSyncedAt'] as String)
    : DateTime.now();  // BE 还没给则用本地时间兜底
```

### 改动点 4：AppBar 头像首字母

**文件**：`native_lighthouse_page.dart` 约 1474 行

```dart
// 当前
Text('SU', ...)

// 改为（取 username 前 2 个字符，处理中英文）
Text(_userInitials(), ...)
```

```dart
String _userInitials() {
  final name = widget.session.username;
  if (name.isEmpty) return '·';
  // 中文取前 1 字，英文取前 2 字符大写
  final isCJK = name.codeUnitAt(0) >= 0x4E00;
  return isCJK ? name.substring(0, 1) : name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
}
```

### 改动点 5：AppBar 版本号

**文件**：`native_lighthouse_page.dart` 约 1454 行

```dart
// 当前
Text('LIGHTHOUSE · v13', ...)

// 改为（生产环境只显示 wordmark）
Text('LIGHTHOUSE', ...)
```

如果想要保留版本号给内部 build，用 `package_info_plus`：

```dart
// 在 initState 里读 PackageInfo 然后写到 _appVersion 字段
import 'package:package_info_plus/package_info_plus.dart';
// ...
PackageInfo.fromPlatform().then((p) => setState(() => _appVersion = p.version));
```

### 验收

- 不同时段打开 app，问候语正确切换
- 用户名显示当前登录用户
- 头像首字母对应当前用户
- 同步时间显示真实拉取时间（非 09:18）
- 日期不再是 6 月 21 日

---

## FE-2 ｜ Dropdown 按实际数据过滤白名单

**来源**：审计 + 会议（讲话人 1 提到 "WOA 这个里面有点 bug"）
**优先级**：P0
**估时**：0.5 天
**依赖**：无

### 背景

当前 `_kMetricByTab` 是写死的大白名单。用真实 JSON 验证发现，supply 维度里 `discount` 根本没字段、`woa` / `projectCost` / `deferred` 全 0；product 维度 `woa` 全 0。用户加上去只能看到 0 或空。

### 改动

**文件**：`native_lighthouse_page.dart`

**第 1 步**：新增辅助方法

```dart
/// 返回当前数据下，每行至少有一行非零值的字段集合
Set<String> _liveMetrics(String tab) {
  final whitelist = _kMetricByTab[tab] ?? const <String>[];
  final rows = _bundle?.rowsOf(tab) ?? const [];
  if (rows.isEmpty) return whitelist.toSet();  // 数据未加载时不过滤
  return whitelist.where((k) {
    return rows.any((r) {
      final v = r[k];
      if (v is! num) return false;
      return v != 0;
    });
  }).toSet();
}
```

**第 2 步**：替换 dropdown 里的 `available`（约 1256 行）

```dart
// 当前
final available = _kMetricByTab[tab] ?? [];

// 改为
final available = (_kMetricByTab[tab] ?? const <String>[])
    .where(_liveMetrics(tab).contains)
    .toList();
```

**第 3 步**：替换"已选指标 / 全部指标"显示用的 count（约 2023 行）

```dart
// 当前
final fullCount = (_kMetricByTab[tab] ?? []).length;

// 改为
final fullCount = _liveMetrics(tab).length;
```

**第 4 步**：保护 `_metrics[tab]` 不引用已死字段（在 `initState` 之后、`_loadBundle` 成功后）

```dart
void _pruneDeadMetrics() {
  for (final tab in ['product', 'supply', 'channel']) {
    final live = _liveMetrics(tab);
    _metrics[tab] = (_metrics[tab] ?? []).where(live.contains).toList();
    if (_metrics[tab]!.isEmpty) {
      _metrics[tab] = ['sales'];  // 至少保留一个，避免界面空白
    }
  }
}

// 在 _loadBundle 成功 setState 里加一行：
_pruneDeadMetrics();
```

### 验收

当前 JSON 数据下打开 dropdown：

- **product 维度**：可选 chip 不包含 `WOA`
- **supply 维度**：可选 chip 不包含 `WOA / 项目成本 / 抵扣延期分润 / 折扣进度`
- **channel 维度**：可选 chip 不包含 `WOA / 项目成本 / 抵扣延期分润`
- 当后端把这些字段补真后（BE-2），chip 自然恢复出现，无需改前端

---

## FE-3 ｜ 删掉"本期解读" toggle

**来源**：会议（讲话人 2 原话："这些指标是不是上面都写了"）
**优先级**：P0
**估时**：10 分钟
**依赖**：无

### 改动

**文件**：`native_lighthouse_page.dart`

要删的三处：

1. 状态字段 `bool _summaryOpen = false;`（在 `_NativeLighthousePageState` 顶部）
2. 整个 `Widget _buildSummaryToggle()` 方法
3. `_buildPanel` 里调用 toggle 的部分：

```dart
// 删除这一整块
const SizedBox(height: 12),
_buildSummaryToggle(),
if (_summaryOpen) ...[
  const SizedBox(height: 10),
  Text(
    '销售 ¥${p.salesV}${p.salesU}，${p.deltaVs} $deltaArrow${p.deltaVal}%...',
    ...
  ),
],
const SizedBox(height: 12),  // hero grid 上面那个 SizedBox
```

替换为：

```dart
const SizedBox(height: 14),  // 直接进入 hero grid
```

### 验收

- `grep -n "summaryOpen\|本期解读\|_buildSummaryToggle" native_lighthouse_page.dart` 应该 0 结果
- 编译通过、Hero panel 直接从 compose bar 接 hero grid

---

## FE-4 ｜ List item trend delta 改读真数据

**来源**：审计（`drift * 15 + 2.5` 完全是 mock）
**优先级**：P1
**估时**：0.5 天
**依赖**：BE-3 完成

### 改动

**文件**：`native_lighthouse_page.dart` 约 2148-2154 行

```dart
// 当前 mock
final rng = _SRng('$trendKey:$_period');
double drift = 0;
for (int i = 0; i < 5; i++) { drift += (rng.next() - 0.45) * 0.1; }
final delta = drift * 15 + (isNeg ? -1 : 1) * 2.5;
final dArrow = delta >= 0 ? '↑' : '↓';
final dColor = delta >= 0 ? LhColors.pos : LhColors.neg;

// 改为
final deltaPct = (r['deltaPct'] as num?)?.toDouble();
final hasDelta = deltaPct != null;
final delta = deltaPct ?? 0.0;
final dArrow = delta >= 0 ? '↑' : '↓';
final dColor = delta >= 0 ? LhColors.pos : LhColors.neg;
```

并在 trend row 渲染处加 `if (hasDelta)` 守护，没数据时整行 trend 隐藏，不显示假的 0%。

### 验收

- list item 上的 ↑ x.x% 数字与后端 `deltaPct` 字段一致
- 后端没给 `deltaPct` 的行：trend row 不显示

---

## FE-5 ｜ Sparkline 真趋势

**来源**：审计（整套 `_kTrendCfg` + `_trendBaseShape` + `_buildTrendSeries` 都是 mock）
**优先级**：P1
**估时**：1 天
**依赖**：BE-3 完成

### 改动

**文件**：`native_lighthouse_page.dart`

1. **删除写死的 trend 配置**：`_kTrendCfg`（252 行）、`_trendBaseShape`（311 行）
2. **重写 `_buildTrendSeries`**（约 340 行）：从 `r['trend']` 字段读，而不是 mock 生成

```dart
_TrendSeries? _buildTrendSeries(Map<String, dynamic> r) {
  final trend = r['trend'];
  if (trend is! Map) return null;
  final points = trend['points'];
  if (points is! List || points.isEmpty) return null;
  return _TrendSeries(
    profit: points.map((e) => (e as num).toDouble()).toList(),
    // revenue/cost 同理，或者只保留 profit 一条线
  );
}
```

3. **X 轴标签从后端读**：

```dart
final xLabels = (r['trend']?['xLabels'] as List?)?.cast<String>() ?? const <String>[];
```

4. **范围标签**：把"近 30 日趋势 · 06.01 — 06.30" 改成从 `r['trend']['rangeLabel']` 读

### 验收

- 不同 period 切换时，sparkline 曲线形状随真实业务数据变化（而不是钉死的 shape）
- 后端未返回 trend 字段的行：展开 sparkline 区域隐藏，或显示"暂无趋势数据"

---

## FE-6 ｜ Hero label / compose bar 完全去掉 _kPeriods fallback

**来源**：审计
**优先级**：P2
**估时**：0.5 天
**依赖**：BE-1 完成且稳定

### 改动

**文件**：`native_lighthouse_page.dart` 约 988-1042 行（`_heroInfo` getter）

BE-1 完成后，所有 hero 字段都由后端真给。这时可以把 fallback 逻辑收紧：

```dart
// 当前是逐字段 fallback 到 _kPeriods，可能掩盖后端缺字段的 bug
// 改成：metrics 为空时显示骨架/加载态，而不是 fallback 到假数据
_PeriodInfo? get _heroInfo {
  final m = _bundle?.metrics;
  if (m == null || m.isEmpty) return null;
  return _PeriodInfo.fromJson(m);  // 让 fromJson 抛错而不是吃掉
}
```

调用方加 `if (_heroInfo == null) return _SkeletonHero();` 守护。

之后 `_kPeriods` 整个常量可以删（彻底告别历史包袱）。

### 验收

- 把 BE 接口 mock 成 `metrics: {}` 时，前端显示 skeleton 不显示假数据
- `grep _kPeriods native_lighthouse_page.dart` → 0 结果

---

## FE-7 ｜ 折扣进度"提升空间利润"提示（详情页 supply）

**来源**：会议（讲话人 2 新需求）
**优先级**：P1
**估时**：0.5 天
**依赖**：BE-4 完成

### 改动

详情页 supply 维度展开行里，把 `BE-4` 返回的 `profitGainAtNextTier` 直接显示：

```dart
// 折扣进度展开区
if (discount['nextTier'] != null) ...[
  Text('下一档 ${discount['nextTier']}‰', ...),
  Text('还差 ¥${_fmt(discount['salesToNextTier'])} 可多赚 ¥${_fmt(discount['profitGainAtNextTier'])}',
    style: LhTypography.sans(size: 12, color: LhColors.copper, weight: FontWeight.w600)),
],
```

### 验收

- 真实数据下，supply 下钻的某行展开折扣进度，能看到"再做 317 万，多 30 万利润"这类直观提示

---

# 后端任务（BE）

## BE-1 ｜ 完整 `metrics` 对象返回

**来源**：审计
**优先级**：P0
**估时**：1 天

### 接口

`GET /api/v1/lighthouse/overview?period={day|week|month|quarter|year}&date={YYYY-MM-DD}`

### 当前问题

`metrics` 字段返回不全，前端因为字段缺失会逐字段 fallback 到写死的 `_kPeriods`，导致看上去"接通了"但实际还是假数据。

### 目标返回 schema

```jsonc
{
  "success": true,
  "data": { /* 三个维度的 list */ },
  "product_detail": { /* ... */ },
  "supply_detail": { /* ... */ },
  "channel_detail": { /* ... */ },
  "metrics": {
    "label": "本月 · 2026.06",          // 期间标签（前端会兜底用 DateTime.now 生成，但后端给优先）
    "short": "月",
    "salesV": 1.81,                    // 销售额数值
    "salesU": "亿",                    // 单位
    "deltaDir": "up",                  // up | down
    "deltaPct": 12.4,                  // ← 字段名用 deltaPct，前端两个 key 都兼容
    "deltaVs": "vs 上月",
    "profitV": 494.95, "profitU": "万",
    "gmvV": 2.50, "gmvU": "亿",
    "rate": 2.74,                      // 毛利率（百分比数）
    "lastSyncedAt": "2026-06-21T09:18:00+08:00",
    "compose": [
      {"name": "中石油", "pct": 67, "colorKey": "cnpc"},
      {"name": "平安",   "pct": 18, "colorKey": "pingan"},
      {"name": "DICT",   "pct": 9,  "colorKey": "dict"},
      {"name": "其他",   "pct": 6,  "colorKey": "unk"}
    ]
  }
}
```

### colorKey 取值表

| colorKey | 对应分类 |
|---|---|
| cnpc | 中石油 |
| sinopec | 中石化 |
| private | 民营 |
| carrier | 运营商 |
| pingan | 平安 |
| dict | DICT |
| multi | 多渠道 |
| unk | 其他/未知 |

### 验收

- 5 个 period 各请求一次，所有字段都有值
- 前端 `_heroInfo` 不再走任何 `fallback.xxx`（可在 PR 里临时把 `_kPeriods` 改成抛异常验证）

---

## BE-2 ｜ 补 supply 维度缺失字段

**来源**：审计 + 会议（WOA bug）
**优先级**：P1
**估时**：取决于业务侧排查 ETL

### 当前问题（用真实 JSON 验证）

| tab | 字段 | 状态 |
|---|---|---|
| product | `woa` | 13/13 全 0（**会议提到的 bug**） |
| supply | `discount` | **字段在 row 里完全不存在** |
| supply | `woa` | 67/67 全 0 |
| supply | `projectCost` | 67/67 全 0 |
| supply | `deferred` | 67/67 全 0 |
| channel | `woa` / `projectCost` / `deferred` | 全 0 |

### 目标

1. supply / channel row 里 `discount` 字段需要存在（即使值是 0 也比"字段不存在"好，前端解析一致）
2. 排查 WOA 为什么所有行都是 0 —— 是 ETL 取数 bug 还是业务上确实当前周期没有 WOA？
3. `projectCost` / `deferred` 同上：是没数据还是没接进来？

### 注

前端 FE-2 完成后，这些死字段会自动从 dropdown 隐藏，**不阻塞前端发版**。BE 修完后无需前端改动即可激活。

---

## BE-3 ｜ Row 级别 delta + trend series

**来源**：审计
**优先级**：P1
**估时**：1-2 天

### 改动

每个 row 在原有字段基础上新增：

```jsonc
{
  "name": "中石油现金券",
  "group": "中石油",
  "profit": 1083130,
  "sales": 160620000,
  // ... 现有字段 ...

  // 新增 ↓
  "deltaPct": 5.3,            // 相对上个 period 的毛利变化百分比
  "deltaDir": "up",           // up | down
  "prevProfit": 1028500,      // 前一周期毛利，给前端核验/展示用

  "trend": {
    "period": "month",
    "points": [12000, 15000, 14500, /* ... */],  // 长度 = period 对应粒度
    "xLabels": ["06/01", "06/02", /* ... */],
    "rangeLabel": "06.01 — 06.30"
  }
}
```

### 粒度对照

| period | points 长度 | 单点粒度 |
|---|---:|---|
| day | 24 | 小时 |
| week | 7 | 天 |
| month | 30 / 31 | 天 |
| quarter | 13 | 周 |
| year | 12 | 月 |

### 体量评估

supply 67 行 × 30 点 ≈ 2000 个浮点 ≈ ~30KB，可接受。如果担心列表接口体积，可以**只在 detail 接口给 trend**，列表接口只给 `deltaPct` + `prevProfit`。前端方案两种都能 work。

### 验收

- 任意行的 deltaPct 用 `(profit - prevProfit) / prevProfit * 100` 验算一致
- trend.points 之和 ≈ profit（按数据分布逻辑应该匹配）

---

## BE-4 ｜ 折扣进度提升空间计算

**来源**：会议讲话人 2 新需求
**优先级**：P1
**估时**：1-2 天（讲话人 1 也说"得单独算一个表"）

### 接口

在 supply 详情数据里新增 `discount` 对象：

```jsonc
{
  "name": "内蒙古中石油",
  // ... 其他字段 ...
  "discount": {
    "currentTier": 0.4,           // 当前档位（‰）
    "nextTier": 0.5,              // 下一档位
    "currentCumSales": 12800000,  // 当前累计销售
    "currentProgress": 0.79,      // 完成度 79%
    "salesToNextTier": 3170000,   // 还差多少
    "profitGainAtNextTier": 300000 // 升档后多赚多少利润
  }
}
```

### 计算逻辑（讲话人 2 原话翻译）

```
若全额累进：
  profitGainAtNextTier = currentCumSales × (nextTier - currentTier) / 1000

例：
  currentCumSales = 3000万，currentTier = 0.4‰，nextTier = 0.5‰
  profitGainAtNextTier = 30,000,000 × (0.5 - 0.4) / 1000 = 30,000  → 3 万

  实际会议数据：3000万规模、提一档 → 30 万（计算用的是 1pt = 1‰）
```

> ⚠️ 具体公式以业务方累进规则为准。讲话人 1 强调"得用供给的那个规则来算 / 业务系统算"。

### 注

讲话人 1："问一下会不会影响速度呢？本来就也延迟几分钟，算一下也没事" —— **接受几分钟 ETL 延迟，不需要实时**。

### 验收

- 真实数据下，前端 FE-7 能直接显示"再做 ¥X 万，多赚 ¥Y 万利润"
- 业务方手算验证一两条数字一致

---

# 附：当前所有硬编码兜底位置（审计快照）

| 行 | 内容 | 处置 |
|---:|---|---|
| 57-113 | `_kPeriods` 5 套写死数据 | FE-6 完成后整体删除 |
| 161 | `_kCategoryOverride['product']` | 改为从 row distinct（与 supply/channel 一致） |
| 252-308 | `_kTrendCfg` 5 个 period 配置 | FE-5 完成后整体删除 |
| 311-340 | `_trendBaseShape` | FE-5 完成后整体删除 |
| 1454 | `LIGHTHOUSE · v13` | FE-1 |
| 1474 | 头像 `SU` | FE-1 |
| 1519 | `星期日 · 06.21` | FE-1 |
| 1529 | `早上好，Suzy` | FE-1 |
| 1559 | `数据已同步 · 09:18` | FE-1 |
| 2148-2152 | trend delta 的 `drift * 15 + 2.5` | FE-4 |
| 836-840 | `_kMetricByTab` 大白名单 | FE-2（保留常量但运行时过滤） |

---

# 给 Cursor 的喂养建议

每个任务卡可以直接复制粘贴到 Cursor，但建议这样组织 prompt：

```
# 上下文
我在改 native_lighthouse_page.dart，正在执行任务 FE-x。
读完任务卡里的"改动点"，按要求修改代码。
注意保持原有的视觉风格和缩进。

# 任务卡
[贴上对应任务卡的完整内容]

# 额外要求
- 只改这一个任务范围内的代码，不要顺手优化其他地方
- 改完跑一遍编译，确保不会因为引用而把其他模块编译挂了
- 在文件顶部加一行注释 // [FE-x] 标记此次改动
```

按 FE-1 → FE-2 → FE-3 顺序做（M1 里程碑），合一个 PR，发版。
之后等 BE 完成 BE-1 ~ BE-4 再做后续。
