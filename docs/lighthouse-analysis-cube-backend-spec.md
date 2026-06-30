# 灯塔「数据分析」板块后端需求规格

> 对应前端：`lib/features/lighthouse/native_lighthouse_page.dart` 第 4 个 tab「分析」
> 对应后端：`lighthouse-go/internal/lighthouse/analysis.go` → `GET /api/v1/lighthouse/analysis/cube`
> 状态：接口骨架已存在，但 (1) 切到新生产库后查询报错；(2) 缺第 4 维度「负责人 owner」字段。本文档定义完整对齐需求。

---

## 1. 背景

前端「分析」tab 现在只渲染一个 **§ 01 3D 坐标**卡（旧的 § 02 机会清单已删除）。它把灯塔的经营数据投影成一个 **产品 × 供给方 × 渠道** 的三维立方体，并在每个「已发生正毛利」的坐标上点亮一个铜色亮点。在此基础上，前端新增了**第 4 维度「负责人(owner)」**：每个亮点归属一个负责人，顶部以横向 chip strip 聚合展示各负责人的坐标数与毛利，点击可在立方体里高亮该负责人聚类。

当前问题：
- 后端 `analysis/cube` 在新生产库上返回 `{"success":false,"message":"灯塔分析数据暂时不可用，请稍后再试"}`，前端只能展示空立方体 / 加载失败。
- 后端 `LitTriple` 没有 `owner` 字段，前端用 `_deriveCubeOwner(supplyName)` 基于 hashCode 假派生（6 个写死的名字），属于 mock 数据，必须替换为真实字段。

---

## 2. 接口契约

### 2.1 路由

```
GET /api/v1/lighthouse/analysis/cube
Authorization: Bearer <JWT>
```

经网关 `localhost:6090` 路由到 `lighthouse-go:6093`，或前端直连 `6093`。鉴权与 overview 一致。

### 2.2 Query 参数

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| `period` | string | 否 | `month` | `week` / `month` / `quarter` / `year` |
| `date` | string | 否 | 今日(UTC+8) | 参考日期 `YYYY-MM-DD`，用于解析所属周期 |
| `fuel` | string | 否 | 全部 | 油品筛选；`全部` 或空 = 不筛选 |
| `top_p` | int | 否 | `12` | 产品维取 Top N，范围 [1, 30] |
| `top_s` | int | 否 | `10` | 供给方维取 Top N，范围 [1, 30] |
| `top_c` | int | 否 | `10` | 渠道维取 Top N，范围 [1, 30] |
| `top_opp` | int | 否 | `8` | 预留；前端已不消费机会清单，可返回空数组 |

> `top_p / top_s / top_c` 决定立方体三轴长度。前端默认 12×10×10 = 最多 1200 格。

### 2.3 响应体

```jsonc
{
  "success": true,
  "data": {
    "products":   [ { "name": "中石油现金券", "group": "中石油", "profit": 123456.78 } ],
    "supplies":   [ { "name": "广东省分",     "group": "华南",   "profit": 98765.43  } ],
    "channels":   [ { "name": "产险渠道",     "group": "产险",   "profit": 54321.00  } ],
    "lit": [
      {
        "xi": 0, "yi": 2, "zi": 1,
        "x": "中石油现金券", "y": "广东省分", "z": "产险渠道",
        "x_group": "中石油", "y_group": "华南", "z_group": "产险",
        "supply_hun": "U", "channel_hun": "U",
        "value": 45678.90,
        "owner": "穆穆"
      }
    ],
    "opportunities": [],
    "stats": {
      "total_possible": 1200,
      "lit_count": 28,
      "coverage_pct": 2.3
    }
  }
}
```

### 2.4 字段语义

#### `products / supplies / channels` — 三轴维度成员
每个元素：
- `name` (string)：维度成员名（产品=tag1，供给方=tag2，渠道=tag3）
- `group` (string)：分组名（产品=`product_line_group`，供给方=`supply_class`，渠道=`channel_class`）；无分组时返回 `""`
- `profit` (float)：该成员在本周期内的正毛利合计（`HAVING profit > 0`），按降序排，取 Top N

#### `lit[]` — 已点亮的坐标（正毛利三元组）
每个元素：
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `xi / yi / zi` | int | ✅ | 在 `products/supplies/channels` 数组里的下标（0-based） |
| `x / y / z` | string | ✅ | 维度成员名（冗余，便于前端直接展示，无需反查） |
| `x_group / y_group / z_group` | string | ✅ | 各维分组名；无则 `""` |
| `supply_hun / channel_hun` | string | 否 | `U` / `N` / `H` / `mixed` / `none`；用于前端 HUN 筛选 chip。可省略（前端默认 `none`） |
| `value` | float | ✅ | 该坐标本期正毛利（`SUM(profit)`，`HAVING value > 0`） |
| **`owner`** | string | **✅ 新增** | 该坐标归属的负责人名；详见 §3 |

去重规则：同一 `(xi,yi,zi)` 只保留一条（按 `value` 降序取首条）。`value <= 0` 的不进 `lit`。

#### `stats` — 统计
- `total_possible` (int) = `len(products) * len(supplies) * len(channels)`
- `lit_count` (int) = `len(lit)`
- `coverage_pct` (float) = `lit_count / total_possible * 100`，保留 1 位小数

> 前端底部图例用 `lit_count` / `total_possible` / `coverage_pct`，任一缺失则显示 `—`。

#### `opportunities[]` — 已废弃
前端已删除「未点亮坐标机会清单」板块。**可返回空数组 `[]`**，无需计算。保留字段仅为兼容旧前端缓存。

---

## 3. 第 4 维度「负责人(owner)」需求 ★重点

### 3.1 业务定义
每个 `lit` 坐标归属**一个**负责人。前端用 `owner` 做：
1. 顶部 chip strip 聚合：每个负责人显示「坐标数 + 毛利合计 + 占比条」
2. 立方体聚类高亮：点击某负责人，该 owner 的亮点保持完整，其他 owner 的亮点缩小淡化
3. 选中亮点详情卡：显示「负责人」一行

### 3.2 取数口径
负责人应来自**真实主数据**，不能在前端假派生。推荐口径（按优先级）：

1. **供给方维 → 供给方主数据 → 负责人**
   - 每个 `lit` 的 `y`（供给方名）查 `am_supplier`（或等价供给方主数据表）的 `owner_id` / `owner_name` / `负责人` 字段。
   - 即「同一供给方永远归同一负责人」，与前端现有 `_deriveCubeOwner` 的稳定性假设一致。
   - SQL 示意（在 `QueryAnalysisLitTriples` 里 JOIN 或在内存里用一次 `SELECT name, owner FROM am_supplier WHERE name IN (...)` 回填）：
     ```sql
     SELECT COALESCE(tag2,'') AS supply, MAX(am_supplier.owner_name) AS owner
     FROM <main_source> s
     LEFT JOIN am_supplier ON am_supplier.name = s.tag2
     WHERE ... AND s.tag2 IN (...)
     GROUP BY supply
     ```

2. **若供给方主数据暂无负责人列**：回退到「供给方所属分组(`supply_class`)的负责人」，由后端维护一份 `supply_class → owner` 映射（配置表或常量）。

3. **都没有**：返回 `owner = ""`，前端 chip strip 显示 `?` 并归到「未分配」。**绝不**返回写死的中文名假数据。

### 3.3 字段约束
- `owner` 为 string，非空时是真实姓名/工号名。
- 同一 `supply` 在一次响应里所有 `lit` 的 `owner` 必须一致（稳定性）。
- 无负责人时返回 `""`（空串），不要返回 `null` / `"未知"` / `"穆穆"` 这类占位。

### 3.4 后端改动点
- `LitTriple` 结构体新增 `Owner string \`json:"owner,omitempty"\``（`internal/lighthouse/analysis.go`）。
- `AnalysisLitRaw` 新增 `Owner string`。
- `QueryAnalysisLitTriples` 查询里补 owner 取数（JOIN 供给方主数据 或 二次查询回填）。
- `indexLit` 里把 `r.Owner` 透传到 `LitTriple.Owner`。
- `computeOpportunities` 无需改（前端不再消费）。

---

## 4. 新生产库适配（修复当前报错）

当前 `analysis/cube` 返回 `success:false`，根因是切库后 `QueryAnalysisTopDims` / `QueryAnalysisLitTriples` 的 SQL 不再匹配新库 schema。需确认：

| 项 | 旧库 | 新生产库 | 动作 |
|----|------|----------|------|
| 主数据表 | (旧表名) | ? | 核对 `period.MainSource()` 返回的表名在新库存在 |
| `tag1 / tag2 / tag3` | 产品/供给/渠道 | ? | 确认新库这三列仍叫这名，否则改 `analysisDimSpecs` |
| `product_line_group / supply_class / channel_class` | 分组列 | ? | 同上，改 `groupExpr` |
| `profit / sales_amount` | 金额列 | ? | 确认列名与正负号口径 |
| `is_del / customer_sign_entity` | 过滤/HUN | ? | 确认存在 |
| `am_supplier` | 供给方主数据 | ? | 确认表名 + 负责人列名（§3） |

> 建议先在新库上手动跑 `QueryAnalysisTopDims` 的三条 SQL，定位是哪一列/哪一表不存在，再批量改 `analysisDimSpecs` 与 `hunClassSQL()`。修复后 `lit` 应能返回非空数组。

---

## 5. 缓存与超时

沿用现有：
- cache key：`analysis_cube:{period}:{dateKey}:{fuel}:{topP}:{topS}:{topC}:{topOpp}`
- TTL 默认 10min，stale TTL = TTL + 30min
- singleflight（`s.Group.Do`）防击穿
- 查询超时默认 2s（`s.Timeout`），新库若慢可适当调高，但单个 cube 请求不应超过 5s

---

## 6. 错误处理

| 场景 | HTTP | body |
|------|------|------|
| 鉴权失败 | 401 | 网关统一处理 |
| `period` 非法 | 400 | `{"success":false,"message":"..."}` |
| 新库查询失败 | 200 | `{"success":false,"message":"灯塔分析数据暂时不可用，请稍后再试"}`（现状） |
| 成功但无数据 | 200 | `{"success":true,"data":{"products":[],"supplies":[],"channels":[],"lit":[],"opportunities":[],"stats":{"total_possible":0,"lit_count":0,"coverage_pct":0}}}` |

> **重要**：无数据时不要返回 `success:false`，应返回空结构的 `success:true`，让前端展示「数据不足，无法生成 3D 坐标」占位（`_buildCubeBody` 已处理 `products.isEmpty`）。

---

## 7. 验收标准

1. ✅ 切到新生产库后，`GET /analysis/cube?period=month` 返回 `success:true`，`lit` 非空（至少 1 条）。
2. ✅ 每个 `lit` 元素含 `owner` 字段，值来自供给方主数据；同一 supply 的 owner 一致。
3. ✅ `owner` 无对应主数据时返回 `""`，不出现 `穆穆/小张/小李/王经理/小赵/陈总` 这类前端 mock 池里的名字。
4. ✅ `stats.total_possible == len(products)*len(supplies)*len(channels)`，`lit_count == len(lit)`。
5. ✅ `xi/yi/zi` ∈ [0, dim_len)，且 `(x,y,z)` 与 `products[xi]/supplies[yi]/channels[zi].name` 一致。
6. ✅ 切 `period=week` 能返回本周数据；切 `fuel=汽油` 能过滤。
7. ✅ 前端刷新「分析」tab：负责人 strip 显示真实姓名 + 坐标数 + 毛利；立方体亮点数与 `lit_count` 一致；点亮点详情卡「负责人」行显示真实 owner。

---

## 8. 前端 mock 待清理（后端就绪后）

后端 `owner` 接通后，前端需删除以下 mock（`native_lighthouse_page.dart`）：
- `_kCubeOwners` 常量池（约 L5093）
- `_deriveCubeOwner(String supplyName)` 函数（约 L5096）
- `_parseCubeData` 里 `ownerName` 的 fallback 分支（约 L1071-1074），改为直接 `item['owner']?.toString() ?? ''`

> 这些在 `native_lighthouse_page-4.dart` 里已就位，后端返回 `owner` 后即可去掉 fallback。

---

## 9. 非目标（本期不做）

- 机会清单(opportunities)的重新接入：前端已删除该板块，后端可返回空数组，无需维护 `computeOpportunities` 的几何平均估算逻辑（可保留代码但不投入精力校准）。
- 负责人维度的独立 Top N 筛选：本期 owner 只做聚类高亮，不做「按 owner 过滤立方体」的服务端筛选（前端纯客户端聚合）。
- 立方体旋转 / 4D 渲染：仍为固定等距投影 3D，owner 用聚类 spider 线表示，非真 4D。
