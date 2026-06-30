# 灯塔「折扣进度」后端接入说明（给 BE-4）

> 用途：后端按本文实现 `supply` 行级 `discount` 对象后，前端可删除 `_kDiscount` 本地快照，折扣进度 UI 直接接真数据。
> 关联任务：`BE-4`（后端）→ 前端已预留解析逻辑，无需再改 UI 结构。

---

## 1. 前端展示位置

| 位置 | 行为 |
|------|------|
| Tab | 仅 **`supply`（供给方）** 一级列表行 |
| 入口 | 行名旁显示 `折扣` 标签；点行右侧下拉箭头展开 |
| 默认视图 | 有 `discount` 对象时，**默认打开「折扣进度」**（不是趋势） |
| 切换 | 展开区顶部有 `趋势 / 折扣进度` 两个 tab |

**没有 `discount` 对象的行**：不显示折扣标签，展开后只有趋势图。

---

## 2. 接口与挂载位置

**接口**：`GET /api/v1/lighthouse/overview?period={day|week|month|quarter|year}&date=YYYY-MM-DD&fuel=汽油`

**挂载**：在 `data.supply[]` 的**每个一级行**上增加 `discount` 对象（详情子行暂不需要，下一轮再做）。

```jsonc
{
  "success": true,
  "data": {
    "data": {
      "supply": [
        {
          "name": "内蒙古中石油",
          "group": "中石油",
          "sales": 43535172.2,
          "profit": 531049.2,
          // ... 现有字段 ...

          "discount": {
            "currentTier": 2.5,
            "nextTier": null,
            "currentCumSales": 46239599.30,
            "currentProgress": 1.0,
            "salesToNextTier": 0,
            "profitGainAtNextTier": 0,
            "status": "capped",
            "base": "引流"
          }
        }
      ]
    }
  }
}
```

> 注意：外层仍是 `body.data`，不要直接 `fromJson(body)`。

---

## 3. `discount` 字段契约（后端 → 前端）

### 3.1 推荐字段（BE-4 标准）

| 字段 | 类型 | 单位/格式 | 前端用途 |
|------|------|-----------|----------|
| `currentTier` | number | **‰ 数值**（如 `2.5` 表示 2.5‰） | 本档折扣率，显示为 `2.5%` |
| `nextTier` | number \| null | ‰；已封顶时为 `null` | 下一档折扣率 |
| `currentCumSales` | number | **元** | 当前累计基数（本档卡片「¥X万」） |
| `currentProgress` | number | 0~1 | 到下一档完成度（进度条 %） |
| `salesToNextTier` | number | **元** | 距下一档还差多少（「距下一档」） |
| `profitGainAtNextTier` | number | **元** | 升一档预计多赚利润（「预计多赚」） |
| `status` | string | 见下表 | 控制 UI 三种状态 |
| `base` | string | `引流` / `门槛` / `核销` / `销售` | 计算口径文案 |

### 3.2 `status` 枚举

| 值 | 含义 | 前端展示 |
|----|------|----------|
| `below_first` | 未达首档 | 本档显示 `—`，强调距下一档 |
| `in_tier` | 在档内、未封顶 | 三卡片 + 进度桥接 + 预计多赚 |
| `capped` | 已达最高档 | 「已封顶 · 享最高 X% 折扣」 |

### 3.3 前端兼容别名（已实现，可选）

前端 `_discountInfoFor()` 也兼容以下旧/简写字段，但**建议统一用上面标准名**：

| 标准字段 | 兼容别名 |
|----------|----------|
| `currentCumSales` | `cur` |
| `currentTier` | `curRate` |
| `nextTier` | `nextRate` |
| `salesToNextTier` | 可省略，由 `target - currentCumSales` 推导 |
| 下一档门槛 | `target`（元） |

### 3.4 已废弃：行级 `discount: 0.73` 数值

当前接口若只返回 `discount: 0`（number），前端会做一个**很差劲的兜底**（用 `sales` 猜进度）。  
**请后端务必返回 object，不要只返 number。**

---

## 4. 前端 UI 如何用这些字段

### 4.1 进行中（`in_tier` / `below_first`）

```
┌─────────┐     79%      ┌─────────┐
│ 本档    │ ═══════════► │ 下一档  │
│ 2.0%    │              │ 2.5%    │
│ ¥530.8万│              │ ¥600.0万│
└─────────┘              └─────────┘

距下一档    预计多赚      计算口径
69.2万      +2.7万        核销
```

前端计算（若后端未给 `profitGainAtNextTier`，前端会自己算）：

```text
profitGainAtNextTier = currentCumSales × (nextTier - currentTier) / 100
```

> 会议口径：`currentTier` / `nextTier` 按 **‰** 理解，`/100` 即千分比换算。  
> 例：3000 万基数、0.4‰ → 0.5‰：`30,000,000 × 0.1 / 1000 = 3,000`（需与业务方确认是否 `/1000` 而非 `/100`）。

**请以业务方累进规则为准**；后端算好后直接返 `profitGainAtNextTier`，前端优先展示后端值。

### 4.2 已封顶（`capped`）

- `nextTier = null`
- `currentProgress = 1.0`
- 展示「已封顶 · 享最高 {currentTier}% 折扣」

---

## 5. 数据库读取建议

宽表 `am_lighthouse_operating_*` **目前没有可用的 `discount` 列**，需要从折扣规则表计算。

### 5.1 相关表（库 `sel-mg`）

| 表 | 行数(约) | 用途 |
|----|---------|------|
| `light_tower_sp_disrules` | 54 | 规则主表：`supplier_id`, `supplier_name`, `merchant_name`, `state` |
| `light_tower_sp_disrules_mx_new` | 62 | 阶梯明细：`zk` JSON 阶梯、`zk_type`, `zk_mod`, `calculation_mode`, 生效时间 |
| `light_tower_sp_disrules_product` | 476 | 规则 ↔ `supplier_product_code` |
| `light_tower_sp_disrules_progressionlog` | 1,181 | 周期内累计进度：`discount`, `start_date`, `end_date` |

### 5.2 建议 JOIN 路径

```text
supply 一级行 name（如「内蒙古中石油」）
    │
    ├─► light_tower_sp_disrules.supplier_name / merchant_name  （名称匹配）
    │       └─► light_tower_sp_disrules_mx_new  （取当前生效规则 + 解析 zk 阶梯 JSON）
    │
    └─► light_tower_sp_disrules_progressionlog  （取当前周期累计 discount / 基数）
            ON disrules_id = light_tower_sp_disrules.id
            AND start_date <= period_end AND end_date >= period_start
```

`zk` 字段示例（阶梯 JSON，需解析）：

```json
[
  {"pirce_one": "5000000", "discount": "100"},
  {"pirce_one": "5000000", "pirce_two": "10000000", "discount": "98"}
]
```

`progressionlog` 样例：

```json
{
  "disrules_id": 120008,
  "zk_type": 1,
  "zk_mod": 2,
  "start_date": "2026-05-11",
  "end_date": "2026-05-29",
  "discount": "0.03"
}
```

### 5.3 与 supply 行对齐的 key

| 前端 supply 行 | 后端匹配建议 |
|----------------|--------------|
| `name` | `light_tower_sp_disrules.supplier_name` 或 `merchant_name` |
| `group` | 用于判断是否能源供给（`中石油`）；非能源行可不返 `discount` |

名称可能不完全一致（如「中国石油内蒙古」vs「内蒙古中石油」），建议：

1. 优先用 `supplier_id` / `merchant_id` 做主数据关联（若宽表或 ingest 能拿到）；
2. 否则做名称归一化（去空格、去括号、省份+品牌模糊匹配）。

### 5.4 累计基数 `currentCumSales` 取数

按 `zk_mod` / `base` 口径从宽表或 progressionlog 聚合（需业务确认）：

| `base` | 可能数据源 |
|--------|------------|
| `核销` | `daily_verify_amount` / `month_verify_amount` 周期 SUM |
| `引流` | `drainage_amount` 或 GMV 相关列 |
| `门槛` | `issue_sales_minus_refund` 等 |

---

## 6. 后端服务拆分建议

| 模块 | 职责 |
|------|------|
| `DiscountRuleRepo` | 读 `light_tower_sp_disrules*` 四张表，按 supplier 查当前生效规则 |
| `DiscountProgressRepo` | 读 `progressionlog` + 宽表聚合，算 `currentCumSales` |
| `DiscountCalculator` | 解析 `zk` JSON，定位 current/next tier，算 progress / gap / profitGain |
| `SupplyOverviewAssembler` | 在 `GET /lighthouse/overview` 组装 `supply[].discount` |

**性能**：讲话人接受几分钟 ETL 延迟，建议 **预计算缓存**（Redis 或 overview 接口内缓存），不要每次请求实时扫 4 张表 + 宽表聚合。

---

## 7. 计算伪代码

```python
def build_discount(supply_name: str, period: str, date: str) -> dict | None:
    rule = find_active_rule(supply_name, date)
    if rule is None:
        return None

    tiers = parse_zk_json(rule.zk)          # 阶梯列表，按门槛升序
    cum_sales = aggregate_base(rule, period, date)  # 元

    current_tier, next_tier = locate_tiers(tiers, cum_sales)
    if next_tier is None:
        return {
            "currentTier": current_tier.rate,
            "nextTier": None,
            "currentCumSales": cum_sales,
            "currentProgress": 1.0,
            "salesToNextTier": 0,
            "profitGainAtNextTier": 0,
            "status": "capped",
            "base": rule.base_label,  # 引流/核销/门槛
        }

    gap = max(0, next_tier.threshold - cum_sales)
    progress = cum_sales / next_tier.threshold if next_tier.threshold > 0 else 0
    profit_gain = cum_sales * (next_tier.rate - current_tier.rate) / 100  # 公式待业务确认

    status = "below_first" if current_tier.rate <= 0 else "in_tier"

    return {
        "currentTier": current_tier.rate,
        "nextTier": next_tier.rate,
        "currentCumSales": cum_sales,
        "currentProgress": min(1.0, progress),
        "salesToNextTier": gap,
        "profitGainAtNextTier": profit_gain,
        "status": status,
        "base": rule.base_label,
    }
```

---

## 8. 验收清单

### 8.1 接口

- [ ] `data.supply[]` 里中石油相关行带 `discount` **object**（不是 number）
- [ ] 无规则的行：`discount` 字段省略或 `null`（不要返空 object）
- [ ] `period=month` 时 `currentCumSales` 与业务 Excel 手算一致（抽 2~3 个省）

### 8.2 前端联调（无需改 UI）

- [ ] 供给方 → 内蒙古中石油：展开后默认显示折扣进度，有「预计多赚」金额
- [ ] 已封顶省：显示「已封顶」样式
- [ ] 无折扣行：无 `折扣` 标签

### 8.3 删除前端兜底

后端稳定后，前端删除：

- `native_lighthouse_page.dart` 中 `_kDiscount` 常量（约 13 条快照）
- `_discountInfoFor()` 里对 `_kDiscount` 的 fallback 分支

---

## 9. 当前前端临时状态（供后端知悉）

| 项 | 状态 |
|----|------|
| 折扣 UI | ✅ 已完成（三态 + 趋势切换） |
| 解析 `discount` object | ✅ 已实现 |
| 本地 `_kDiscount` 快照 | ⚠️ 仍兜底 13 条，等 BE-4 |
| 行级 `discount: 0` number | ⚠️ 前端有劣质兜底，应尽快改为 object |
| `profitGainAtNextTier` | 前端当前用 `cur × (next-cur) / 100` 自算，后端给了会优先用后端值 |

---

## 10. 参考文件

| 文件 | 内容 |
|------|------|
| `docs/lighthouse-database-fields.md` §9、附录 I.21–I.24 | 折扣表结构与样例 |
| `docs/lighthouse_refactor_plan.md` BE-4 | 原始任务卡 |
| `docs/灯塔数据接入对齐文档.md` | 全链路对齐 |
| `lib/features/lighthouse/native_lighthouse_page.dart` | `_discountInfoFor`、`_buildDiscountFlow` |
