# 灯塔前端全字段清单

> 对应前端：`lib/features/lighthouse/native_lighthouse_page.dart` + `lighthouse_service.dart` + `lighthouse_data.dart`
> 本文档列出前端从后端读取的**全部字段**，不含对应关系（SQL 列映射），仅按接口和数据结构分组。

---

## 接口 1：`GET /api/v1/lighthouse/overview`

### Query 参数

| 参数 | 类型 | 必填 | 可选值 | 默认 | 说明 |
|------|------|------|--------|------|------|
| `period` | string | 否 | `day` / `week` / `month` / `quarter` / `year` | `month` | 周期；后端按此返回不同数据、环比、趋势 |
| `date` | string | 否 | `YYYY-MM-DD` | 今日(UTC+8) | 参考日期，用于解析所属周期 |
| `fuel` | string | 否 | 油品名 | 全部 | 油品筛选；`全部` 或空 = 不筛选 |

> **`period` 决定了以下所有字段的取值口径**：
> - `metrics.label` / `short` / `deltaVs` 随周期变（如 `month`→「2026年6月」「vs 上月」，`day`→「6月29日」「vs 昨日」）
> - 所有 `*DeltaPct` / `*DeltaDir` 环比是「本期 vs 上一同周期」
> - 行数据里的 `trend` 序列随周期变（日=近24小时，周=本周每日，月=近30日，季=本季每周，年=近12月）
> - `data.*[]` 行数组是当前周期内的聚合数据

### 顶层结构

| 字段 | 类型 | 说明 |
|------|------|------|
| `data` | map | 三个 tab 的行数组 |
| `product_detail` | map | 产品维度下钻 |
| `supply_detail` | map | 供给方维度下钻 |
| `channel_detail` | map | 渠道维度下钻 |
| `metrics` | map | 全局指标 |

---

### `data` 内的行数组

- `data.product[]`
- `data.supply[]`
- `data.channel[]`

每行对象字段：

| 字段 | 类型 | 适用 tab | 说明 |
|------|------|----------|------|
| `name` | string | 全部 | 维度成员名 |
| `group` | string | 全部 | 分组名 |
| `profit` | number | 全部 | 毛利 |
| `sales` | number | 全部 | 销售额 |
| `gmv` | number | 全部 | 引流 GMV |
| `gmv2` | number | product | GMV |
| `cost` | number | 全部 | 业务成本 |
| `revenue` | number | 全部 | 收入 |
| `tax` | number | 全部 | 税务成本 |
| `its` | number | product | ITS |
| `itsAfter` | number | product | 折后 ITS |
| `spread` | number | 全部 | 利差 |
| `woa` | number | 全部 | WOA |
| `totalCost` | number | product | 成本合计 |
| `saasFee` | number | supply/channel | SAAS 服务费 |
| `projectCost` | number | supply/channel | 项目成本 |
| `deferred` | number | supply/channel | 抵扣延期分润 |
| `hunU` | number | supply/channel | HUN-U 金额 |
| `hunN` | number | supply/channel | HUN-N 金额 |
| `hunH` | number | supply/channel | HUN-H 金额 |
| `deltaPct` | number | 全部 | 环比 fallback |
| `deltas` | map | 全部 | 各排序字段的环比，key=字段名 value=数值 |
| `trend` | map | 全部 | 趋势图（见下） |
| `discount` | map | supply | 折扣信息（见下） |

---

### `trend` 子对象（每行内）

| 字段 | 类型 | 说明 |
|------|------|------|
| `points` | number[] | 毛利序列（`profit` 的 fallback） |
| `profit` | number[] | 毛利序列 |
| `revenue` | number[] | 收入序列 |
| `cost` | number[] | 成本序列 |
| `labels` | string[] | X 轴标签 |
| `xLabels` | string[] | `labels` 的 fallback |
| `rangeLabel` | string | 区间描述 |

---

### `discount` 子对象（supply 行内）

| 字段 | 类型 | fallback 别名 | 说明 |
|------|------|----------------|------|
| `currentCumSales` | number | `cur` / `current_amount` | 当前累计销售额 |
| `target` | number | `next_threshold` | 下一档门槛 |
| `currentTier` | number | `curRate` / `current_rate` | 当前档折扣率 |
| `nextTier` | number | `nextRate` / `next_rate` | 下一档折扣率 |
| `rebate` | number | `estimated_rebate` | 预估返利 |
| `profitGainAtNextTier` | number | — | 升档后增量毛利 |
| `salesToNextTier` | number | `gap_to_next` | 距下一档差额 |
| `currentProgress` | number | — | 当前进度 [0,1] |
| `province` | string | — | 省份 |
| `mode` | string | `rule_type` / `base` | 折扣模式 |
| `subtag` | string | — | 子标签 |
| `tierLabel` | string | — | 档位标签 |
| `status` | string | — | 状态（如 `capped`） |

---

### `metrics` 对象

#### 周期信息

| 字段 | 类型 | 说明 |
|------|------|------|
| `label` | string | 周期标签（如「2026年6月」） |
| `short` | string | 周期短称 |
| `deltaVs` | string | 环比对比对象（如「vs 上月」） |

#### Hero 数值（每个指标一对 V / U）

| 字段 | 类型 | 说明 |
|------|------|------|
| `salesV` | number | 销售额数值 |
| `salesU` | string | 销售额单位 |
| `profitV` | number | 毛利数值 |
| `profitU` | string | 毛利单位 |
| `gmvV` | number | 引流 GMV 数值 |
| `gmvU` | string | 引流 GMV 单位 |
| `gmv2V` | number | GMV 数值 |
| `gmv2U` | string | GMV 单位 |
| `revenueV` | number | 收入数值 |
| `revenueU` | string | 收入单位 |
| `costV` | number | 成本数值 |
| `costU` | string | 成本单位 |
| `taxV` | number | 税务成本数值 |
| `taxU` | string | 税务成本单位 |
| `rate` | number | 毛利率（百分比数） |

#### Hero 环比（每个指标一对 DeltaPct / DeltaDir）

| 字段 | 类型 | 说明 |
|------|------|------|
| `salesDeltaPct` | number | 销售额环比 % |
| `salesDeltaDir` | string | 销售额环比方向 `up`/`down`/`flat` |
| `profitDeltaPct` | number | 毛利环比 % |
| `profitDeltaDir` | string | 毛利环比方向 |
| `gmvDeltaPct` | number | 引流 GMV 环比 % |
| `gmvDeltaDir` | string | 引流 GMV 环比方向 |
| `gmv2DeltaPct` | number | GMV 环比 % |
| `gmv2DeltaDir` | string | GMV 环比方向 |
| `revenueDeltaPct` | number | 收入环比 % |
| `revenueDeltaDir` | string | 收入环比方向 |
| `costDeltaPct` | number | 成本环比 % |
| `costDeltaDir` | string | 成本环比方向 |
| `taxDeltaPct` | number | 税务成本环比 % |
| `taxDeltaDir` | string | 税务成本环比方向 |
| `rateDeltaPp` | number | 毛利率环比（百分点 pp） |
| `rateDeltaDir` | string | 毛利率环比方向 |

#### 环比 fallback

| 字段 | 类型 | 说明 |
|------|------|------|
| `deltaPct` | number | 通用环比 %（`salesDeltaPct` 缺失时用） |
| `deltaDir` | string | 通用环比方向（`salesDeltaDir` 缺失时用） |

#### compose 数组（产品构成）

`metrics.compose[]`：

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 成员名 |
| `pct` | number | 占比 |
| `colorKey` | string | 颜色标识（`cnpc`/`sinopec`/`private`/`carrier`/`pingan`/`dict`/`multi`/`unk`） |

#### 同步时间（前端已改用本地时刻，可选保留）

| 字段 | 类型 | 说明 |
|------|------|------|
| `lastSyncedAt` | string | RFC3339；前端不再消费，可不放 |

---

### `product_detail` / `supply_detail` / `channel_detail`

结构：`map[key] = { subTab: [row, ...] }`

subTab key：

| 类型 | subTab keys |
|------|-------------|
| `product_detail` | `supply`, `channel`, `project`, `productName` |
| `supply_detail` | `product`, `channel`, `project`, `productName` |
| `channel_detail` | `product`, `supply`, `project`, `productName` |

每个 subTab 下的行对象与 `data` 行对象**字段相同**（`name`, `group`, `sales`, `gmv`, `cost`, `profit`, `revenue`, `tax` 等数值列）。

---

## 接口 2：`GET /api/v1/lighthouse/analysis/cube`

### Query 参数

| 参数 | 类型 | 必填 | 可选值 | 默认 | 说明 |
|------|------|------|--------|------|------|
| `period` | string | 否 | `day` / `week` / `month` / `quarter` / `year` | `month` | 同 overview，决定 cube 数据的周期口径 |
| `date` | string | 否 | `YYYY-MM-DD` | 今日(UTC+8) | 参考日期 |
| `fuel` | string | 否 | 油品名 | 全部 | 油品筛选 |
| `top_p` | int | 否 | [1, 30] | `12` | 产品维取 Top N |
| `top_s` | int | 否 | [1, 30] | `10` | 供给方维取 Top N |
| `top_c` | int | 否 | [1, 30] | `10` | 渠道维取 Top N |
| `top_opp` | int | 否 | [0, 50] | `8` | 预留（前端已不消费机会清单） |

### 顶层 `data`

#### `products[]` / `supplies[]` / `channels[]`

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 维度成员名 |
| `group` | string | 分组名 |
| `profit` | number | 该成员本期正毛利合计 |

#### `lit[]` — 已点亮的坐标

| 字段 | 类型 | 说明 |
|------|------|------|
| `xi` | int | products 数组下标 |
| `yi` | int | supplies 数组下标 |
| `zi` | int | channels 数组下标 |
| `x` | string | 产品名 |
| `y` | string | 供给方名 |
| `z` | string | 渠道名 |
| `x_group` | string | 产品分组 |
| `y_group` | string | 供给方分组 |
| `z_group` | string | 渠道分组 |
| `supply_hun` | string | 供给方 HUN 分类 `U`/`N`/`H`/`mixed`/`none` |
| `channel_hun` | string | 渠道 HUN 分类 |
| `value` | number | 该坐标本期正毛利 |
| `owner` | string | **★ 新增** 负责人名；无则 `""` |

#### `opportunities[]` — 已废弃

前端已删除机会清单板块，可返回空数组 `[]`。

#### `stats`

| 字段 | 类型 | 说明 |
|------|------|------|
| `total_possible` | int | `len(products) × len(supplies) × len(channels)` |
| `lit_count` | int | `len(lit)` |
| `coverage_pct` | float | 覆盖率 %，保留 1 位小数 |
