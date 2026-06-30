# 灯塔字段对照：前端需求 × 数据库映射

> 合并自原 `lighthouse-database-fields.md` 与 `lighthouse-table-schema-recommendation.md`。  
> 基于 `test.joypay.cn:3306/sel-mg` 实库 + Flutter 灯塔页实际消费字段整理。  
> 探查时间：2026-06-26 · 日表约 3246 行（2026-01-01 ~ 06-25）

**相关文档**

- 前端-only 清单：`docs/lighthouse-frontend-fields.md`
- API 契约：`docs/lighthouse-backend-field-contract.md`

**权威指导意见（GROUP BY 口径）**

- Excel：`excel汇总表计算分析final/step2output/二级页面总览指标版_v8.xlsx`
- 脚本：`excel汇总表计算分析final/step2output/build_l2_v8.py`
- 上游标签一：`relabel_summary_v3.py` → `汇总表_v3_标签一.xlsx`

---

## 1. 一句话结论

| 类别 | 状态 |
|------|------|
| **GROUP BY 口径** | 以 **v8 脚本** 为准（§2）：`标签一` / `标签二+供给分类` / `标签三+渠道分类` |
| **维度** | 须先跑 v8 同款 `map_*` + `classify()` 派生，再聚合；**不能** `GROUP BY product_name` |
| **指标** | v8 `*_BIZ` 列与宽表大部分对应；`WOA` 等 v8 占位 **=0** |
| **需要新建** | 宽表存派生结果：`tag1`,`tag2`,`supply_class`,`oil_type`,`channel_class`,`tag3` 等 |

---

## 2. v8 指导意见：一级列表 GROUP BY（`build_l2_v8.py`）

### 2.1 三个 Tab 一级行

| 前端 tab | API `name` | API `group` | v8 GROUP BY | 约行数 |
|----------|-----------|-------------|-------------|--------|
| product | **`标签一`** | **`product_line_group`**（§2.3） | `GROUP BY 标签一` | 14 |
| supply | **`标签二`** | **`供给分类`** | 展示：`标签二`+`供给分类`；内部分级含 `油品` | 70 |
| channel | **`标签三`** | **`渠道分类`** | `GROUP BY 渠道分类, 标签三` | 12 |

渠道详情 key：`标签三::渠道分类`（如 `产险::平安`）。

### 2.2 派生逻辑（sync 时必须实现，逻辑与 v8 脚本一致）

| 宽表建议列 | v8 字段 | 算法摘要 |
|-----------|---------|----------|
| `tag1` | 标签一 | `relabel_summary_v3.classify()` → 19 类产品线 |
| `tag2` | 标签二 | `COALESCE(省份_中石油, 省份, '(无省份)')` |
| `supply_class` | 供给分类 | `map_supply_class` → 中石油/中石化/民营油站/运营商 |
| `oil_type` | 油品 | `map_oil` → 汽油/柴油/全部（供给 Hero 筛选用） |
| `channel_class` | 渠道分类 | `map_channel_class(客户签约主体, 标签一, 项目名称)` |
| `tag3` | 标签三 | `map_tag3(渠道分类, 项目, 数据来源, 产品名, 客户名)` |
| `product_line_group` | 前端 product group | 标签一 → 能源/出行/运营商（§2.3） |

**标签一 19 类**：中石油/中石化 ×（现金券、满减券、权益券包、积分、不下车加油）、电子车队卡、能源 SaaS、小套-*（4 种）、星和动力、点播-AI豆商城、其他。v8 **丢弃卡数据**；权益金下发核销 → `小套-出行权益金`。

### 2.3 产品 tab 的 `group`（前端 `CATEGORY_OVERRIDE`）

| group | 包含的 `标签一` |
|-------|----------------|
| 能源 | 中石油*、中石化*、电子车队卡、能源 SaaS、星和动力 |
| 出行 | 小套-加油会员、小套-出行会员、小套-出行权益金 |
| 运营商 | 点播-AI豆商城、小套-明星来电 |
| Fintech | 前端占位 |

### 2.4 详情 sub-tab ↔ v8 Sheet

| sub-tab | v8 Sheet | GROUP BY |
|---------|----------|----------|
| 产品→supply | 4.产品×供给 | 标签一, 标签二 |
| 产品→channel | 5.产品×渠道 | 标签一, 标签三, 客户签约主体 |
| 产品→project / productName | 10 / 11 | 标签一, 项目名称 / 产品名称 |
| 供给→product | 6.供给×产品 | 供给分类, 油品, 标签二, 标签一 |
| 渠道→product | 8.渠道×产品 | 渠道分类, 标签三, 标签一 |

### 2.5 指标：v8 BIZ → 宽表 → API

| v8 | 源 | 宽表 | API |
|----|-----|------|-----|
| 销售额 | 销售额 | `sales_amount` | `sales` |
| 引流GMV | 引流金额 | `gmv` | `gmv` |
| GMV | 销售额 | `sales_amount` | `gmv2` |
| ITS / 折后ITS | 核销金额 / 销售额 | `verify_amount` / `sales_amount` | `its` / `itsAfter` |
| 利差 | 利差 | `spread_margin` | `spread` |
| WOA | **固定 0** | 填 0 | `woa` |
| 收入/业务成本/税务/SAAS | 含税字段 | `revenue` 等 | 同名 camelCase |
| 毛利润 | 派生公式 | `profit` | `profit` |

### 2.6 汇总表列 → 宽表缺口

| 汇总表列 | 宽表 |
|----------|------|
| 产品名称 | `product_name` ✅ |
| 项目名称 | `project_name` ⚠️ |
| 省份 / 省份_中石油 | `province_name` ❌ 需灌 |
| 客户签约主体 / 客户名称 | ❌ 需结算回传 |
| 标签一~三 / 供给分类 / 油品 | ❌ sync 派生写入 |

HTML v13 的 `DATA` 与 v8 Sheet 1/2/3 **同源**；不能 `GROUP BY product_name`（SKU）。

---

## 3. 数据源

### API 查哪张表

| period | 宽表 | 时间键 |
|--------|------|--------|
| day / week / month / quarter | `am_lighthouse_operating_daily` | `stat_date` |
| month（也可 rollup 月表） | `am_lighthouse_operating_monthly` | `stat_month` |
| year | `am_lighthouse_operating_yearly` | `stat_year` |

粒度：`(stat_date, product_code, supplier_product_code)` 一行。

### 主数据 JOIN 路径

```text
宽表 product_code
  → am_channel_product → am_channel_profile → am_channel_category
                       → oil_category / merchant_name / project_name

宽表 supplier_product_code
  → am_product → am_supplier → am_supplier_type
              → am_product_category (sector, tag_l1)

am_channel_product_source_rel
  （channel_product_id ↔ supplier_product_id）
```

---

## 4. 前端需要的全部字段

### 4.1 接口顶层

| 前端字段 | 类型 | 数据库来源 | 说明 |
|----------|------|-----------|------|
| `data.product` | array | 宽表聚合 | 产品一级列表 |
| `data.supply` | array | 宽表聚合 | 供给方一级列表 |
| `data.channel` | array | 宽表聚合 | 渠道一级列表 |
| `product_detail` | object | 宽表下钻聚合 | key = 产品名 |
| `supply_detail` | object | 宽表下钻聚合 | key = 供应商名 |
| `channel_detail` | object | 宽表下钻聚合 | key = `渠道名::分类` |
| `metrics` | object | — | 前端未使用，可返回 `{}` |

### 4.2 每行通用字段（三个 tab 都有）

| 前端 key | 中文 | 产品 | 供给方 | 渠道 | 是否必填 |
|----------|------|:----:|:------:|:----:|:--------:|
| `name` | 名称 | ✓ | ✓ | ✓ | **是** |
| `group` | 分类 | ✓ | ✓ | ✓ | **是** |
| `profit` | 毛利润 | ✓ | ✓ | ✓ | **是**（默认排序） |
| `sales` | 销售额/规模 | ✓ | ✓ | ✓ | **是** |
| `gmv` | 引流 GMV | ✓ | ✓ | ✓ | **是** |
| `cost` | 业务成本 | ✓ | ✓ | ✓ | 是 |
| `tax` | 税务成本 | ✓ | ✓ | ✓ | 是 |
| `revenue` | 收入 | ✓ | | | 缺则 fallback `sales` |
| `spread` | 利差 | ✓ | ✓ | ✓ | 是 |
| `woa` | WOA | ✓ | ✓ | ✓ | 是（**库无列**） |
| `rate` | 毛利率 | 本地算 | 本地算 | 本地算 | 不需返回 |

### 4.3 各 tab 额外指标

| 前端 key | 中文 | 产品 | 供给方 | 渠道 |
|----------|------|:----:|:------:|:----:|
| `gmv2` | GMV | ✓ | | |
| `its` | ITS | ✓ | | |
| `itsAfter` | 折后 ITS | ✓ | | |
| `totalCost` | 成本 | ✓ | | |
| `saasFee` | SAAS 服务费 | | ✓ | ✓ |
| `projectCost` | 项目成本 | | ✓ | ✓ |
| `deferred` | 抵扣延期分润 | | ✓ | ✓ |
| `discount` | 折扣进度 | | ✓ | |

### 4.4 详情 sub-tab

| sub-tab key | 行内字段 | 说明 |
|-------------|---------|------|
| `supply` / `channel` / `project` / `productName` | `name`, `group` + 同上指标 | 与一级行结构相同 |

---

## 5. 前端字段 ↔ 数据库完整对照（对齐 HTML v13）

> **状态图例**：✅ 可直接映射 · ⚠️ 有列但不对 · ❌ 缺列 · 🗺️ 需业务映射 · 🔄 API 计算 · 📦 其他表

### 5.1 维度字段 — 对齐设计稿

| 前端 tab | 前端 `name` | 前端 `group` | **应对齐 HTML 的 DB 列（待建）** | 宽表现有列（不够用） | 灌数来源 |
|----------|------------|-------------|----------------------------------|---------------------|----------|
| **product** | **`标签一`** | **`product_line_group`** | `tag1` / `product_line_group` | ~~product_name~~ |
| **supply** | **`标签二`** | **`供给分类`** | `tag2` / `supply_class` | ~~merchant_name~~ |
| **channel** | **`标签三`** | **`渠道分类`** | `tag3` / `channel_class` | ~~channel_name~~ |
| sub-tab SKU | 券名 | — | `product_name` | ✅ | 宽表 SKU 层 |
| 油品筛选 | 汽油/柴油 | — | `oil_category` | ❌ | `am_channel_product` |

### 5.2 指标字段

| 前端 key | DB 列 | 状态 | 产品 | 供给方 | 渠道 |
|----------|-------|------|:----:|:------:|:----:|
| `profit` | `profit` | ✅ | ✓ | ✓ | ✓ |
| `sales` | `sales_amount` | ✅ | ✓ | ✓ | ✓ |
| `gmv` | `gmv` | ✅ ⚠️ | ✓ | ✓ | ✓ |
| `gmv2` | `verify_amount` | ✅ ⚠️ | ✓ | | |
| `its` / `itsAfter` | `its` / `discounted_its` | ✅ | ✓ | | |
| `spread` | `spread_margin` | ✅ | ✓ | ✓ | ✓ |
| `revenue` / `totalCost` | `revenue` / `total_cost` | ✅ | ✓ | | |
| `cost` / `tax` | `business_cost` / `tax_cost` | ✅ | ✓ | ✓ | ✓ |
| `saasFee` / `projectCost` / `deferred` | 对应列 | ✅ ⚠️ | | ✓ | ✓ |
| `woa` | **`woa`** | ❌ | ✓ | ✓ | ✓ |
| `discount` | 📦 规则表 | 📦 | | ✓ | |
| `rate` | — | 🔄 | ✓ | ✓ | ✓ |

---

## 6. 需要新建什么

### 6.1 P0 — v8 派生维度列（宽表三表同步）

| 新建列 | v8 字段 | 用途 |
|--------|---------|------|
| `tag1` | 标签一 | product tab `name` |
| `product_line_group` | （派生） | product tab `group` |
| `tag2` | 标签二 | supply tab `name` |
| `supply_class` | 供给分类 | supply tab `group` |
| `oil_type` | 油品 | 供给汽油/柴油筛选 |
| `channel_class` | 渠道分类 | channel tab `group` |
| `tag3` | 标签三 | channel tab `name` |
| `customer_sign_entity` | 客户签约主体 | 详情 Sheet 5/7 |
| `customer_name` | 客户名称 | `map_tag3` 入参 |
| `province_cnpc` | 省份_中石油 | `map_supply_class` / `tag2` |

### 6.2 P0 — 实体快照列

`channel_id`, `channel_code`, `supplier_id`, `supplier_code`, `supplier_name`, `channel_product_id`, `supplier_product_id`, `supplier_product_name`, `oil_category`；并 **灌数 `province_name`**（已有列）。

### 6.3 P1 — 指标

`woa`；可选 `discount_progress`。

### 6.4 已有无需 ALTER

三级分类 18 列 + 全部金额指标列。

### 6.5 不能当 HTML 维度用的列

| 列 | 原因 |
|----|------|
| `product_name` | SKU，不是产品线 |
| `category_l1_name` | 成品油零售 ≠ 能源/出行 |
| `merchant_name` | ≠ 内蒙古中石油 |
| `channel_name`（主数据） | 整渠道=平安，分不出产险/银行 |

---

## 7. 推荐 DDL

```sql
ALTER TABLE `am_lighthouse_operating_daily`
  ADD COLUMN `product_line_name`    varchar(128) DEFAULT NULL COMMENT '业务产品线' AFTER `product_name`,
  ADD COLUMN `product_line_group`   varchar(64)  DEFAULT NULL COMMENT '能源/出行/运营商/Fintech' AFTER `product_line_name`,
  ADD COLUMN `supply_display_name`  varchar(128) DEFAULT NULL COMMENT '供给方展示名' AFTER `merchant_name`,
  ADD COLUMN `supply_biz_group`     varchar(64)  DEFAULT NULL COMMENT '中石油/民营油站/运营商' AFTER `supply_display_name`,
  ADD COLUMN `channel_segment_name` varchar(128) DEFAULT NULL COMMENT '渠道业务段' AFTER `supply_biz_group`,
  ADD COLUMN `channel_parent_name`  varchar(64)  DEFAULT NULL COMMENT '渠道父级' AFTER `channel_segment_name`,
  ADD COLUMN `channel_id` bigint(20) DEFAULT NULL AFTER `channel_parent_name`,
  ADD COLUMN `channel_code` varchar(64) DEFAULT NULL AFTER `channel_id`,
  ADD COLUMN `supplier_id` bigint(20) DEFAULT NULL AFTER `channel_code`,
  ADD COLUMN `supplier_code` varchar(64) DEFAULT NULL AFTER `supplier_id`,
  ADD COLUMN `supplier_name` varchar(256) DEFAULT NULL AFTER `supplier_code`,
  ADD COLUMN `channel_product_id` bigint(20) DEFAULT NULL AFTER `supplier_name`,
  ADD COLUMN `supplier_product_id` bigint(20) DEFAULT NULL AFTER `channel_product_id`,
  ADD COLUMN `supplier_product_name` varchar(256) DEFAULT NULL AFTER `supplier_product_id`,
  ADD COLUMN `oil_category` varchar(20) DEFAULT NULL AFTER `supplier_product_name`,
  ADD COLUMN `woa` decimal(20,4) DEFAULT NULL AFTER `coupon_spread_margin`;
-- monthly / yearly 同样执行
```

---

## 8. 后端聚合（对齐 v8）

| tab | GROUP BY name | GROUP BY group |
|-----|---------------|----------------|
| product | `tag1` | `product_line_group` |
| supply | `tag2` | `supply_class` |
| channel | `tag3` | `channel_class` |

```sql
SELECT tag1 AS name, product_line_group AS `group`, SUM(profit) AS profit, ...
FROM am_lighthouse_operating_daily WHERE is_del = 0 AND tag1 IS NOT NULL
GROUP BY tag1, product_line_group ORDER BY profit DESC;
-- 渠道详情 key: CONCAT(tag3, '::', channel_class)
```

---

## 9. 灌数 sync

```sql
-- 1) 实体快照（JOIN 主数据）
UPDATE am_lighthouse_operating_daily lh
JOIN am_channel_product cp ON cp.product_code = lh.product_code AND cp.is_del = 0
JOIN am_channel_profile ch ON ch.id = cp.channel_id AND ch.is_del = 0
JOIN am_product ap ON ap.product_code = lh.supplier_product_code AND ap.is_del = 0
JOIN am_supplier s ON s.id = ap.supplier_id AND s.is_del = 0
SET lh.channel_id = ch.id, lh.channel_code = ch.channel_code,
    lh.supplier_id = s.id, lh.supplier_code = s.supplier_code,
    lh.supplier_name = s.supplier_name, lh.oil_category = cp.oil_category,
    lh.channel_product_id = cp.id, lh.supplier_product_id = ap.id,
    lh.supplier_product_name = ap.product_name
WHERE lh.is_del = 0;

-- 2) 业务维度（需映射表 / 规则，示例）
-- channel_segment_name ← 从 project_name 解析，如「平安（产险新车道保证金）」→ 产险
-- channel_parent_name    ← 平安
-- product_line_name      ← 从 product_code 查 am_lighthouse_product_line_map
-- supply_display_name  ← CONCAT(province_name, 供应商品牌)
```

---

## 9. `discount` 字段来源（可不建列）

宽表无列时，API 查以下表计算进度：

| 表 | 用途 |
|----|------|
| `light_tower_sp_disrules` | 折扣规则主表（supplier_id, merchant_id） |
| `light_tower_sp_disrules_mx_new` | 规则明细（阶梯 JSON） |
| `light_tower_sp_disrules_product` | 规则 ↔ 供应商产品 |
| `light_tower_sp_disrules_progressionlog` | 阶梯进度 |

---

## 10. 实施清单

| 优先级 | 动作 |
|--------|------|
| **P0** | 建 **业务维度 6 列** 或映射表（产品线 / 供给方展示名 / 渠道 segment） |
| **P0** | 从 Excel/业务方拿到 SKU→产品线、项目→渠道 segment 映射（HTML 数据源） |
| **P0** | 建实体快照列 + 灌 `province_name` |
| **P1** | ADD `woa`、确认指标口径 |
| **P2** | `discount` 查规则表；三级分类列灌数 |

---

## 11. 待业务确认

| 项 | 说明 |
|----|------|
| 产品线映射表 | 哪个 SKU/产品类型 →「中石油现金券」等 13 条线 |
| 渠道 segment | `project_name` 解析规则 vs 独立字典 |
| 供给方展示名 | 省份+品牌拼接规则（内蒙古中石油） |
| `gmv` / `gmv2` / `deferred` / `woa` | 指标口径 |

---

## 12. 三表字段对齐

| 检查项 | daily | monthly | yearly |
|--------|:-----:|:-------:|:------:|
| 三级分类 18 列 | ✅ | ✅ | ✅ |
| **业务维度 6 列** | **待建** | **待建** | **待建** |
| 实体快照 + `oil_category` | **待建** | **待建** | **待建** |
| `woa` | **待建** | **待建** | **待建** |
| 时间键 | `stat_date` | `stat_month` | `stat_year` |
| 核销汇总 | `daily_verify_amount` | `month_verify_amount` | `year_verify_amount` |

---

## 附录 A. 资管库连接与探查说明（给后续 AI 分析用）

> **探查时间**：2026-06-26 · 库名 `sel-mg` · 共 263 张表（全库），灯塔相关约 24 张。

### A.1 连接信息

```text
Host:     test.joypay.cn
Port:     3306
Database: sel-mg
Username: jpadmin
Password: <由团队提供，勿写入 git；后端用环境变量 LIGHTHOUSE_DB_DSN>
Charset:  utf8mb4
Timezone: Asia/Shanghai

JDBC URL 示例:
jdbc:mysql://test.joypay.cn:3306/sel-mg?useUnicode=true&characterEncoding=UTF-8&zeroDateTimeBehavior=convertToNull&serverTimezone=Asia/Shanghai&useSSL=false&rewriteBatchedStatements=true

Go DSN 示例:
jpadmin:<password>@tcp(test.joypay.cn:3306)/sel-mg?charset=utf8mb4&parseTime=true&loc=Asia%2FShanghai
```

Python 探查：

```python
import pymysql
conn = pymysql.connect(host='test.joypay.cn', port=3306, user='jpadmin',
                       password='<password>', database='sel-mg', charset='utf8mb4')
```

---

## 附录 B. 数据链路总览

```text
业务平台回传
    │
    ▼
am_biz_settlement_ingest_batch          ← 批次（sync_no, stat_date）
    ├── am_biz_settlement_ingest_product   ← 渠道产品日指标（1 行/批次）
    ├── am_biz_settlement_ingest_supplier  ← 供应商产品维度（可多条/批次）
    └── am_biz_settlement_ingest_line      ← 费用项明细（按 bill_type_l3_code）
            │
            │  am_biz_settlement_lighthouse_field_mapping（账单类型→宽表列）
            ▼
am_lighthouse_operating_daily             ← 灯塔宽表（API 主读）
    │ rollup
    ├── am_lighthouse_operating_monthly
    └── am_lighthouse_operating_yearly

主数据（维度补全 / v8 派生入参）:
    am_channel_product ──► am_channel_profile ──► am_channel_category
                      └── am_channel_product_source_rel ──► am_product ──► am_supplier
                                                                 └── am_product_category
    am_config_category（PROJECT_NAME 等项目字典）
    light_tower_sp_disrules*（供给方折扣进度，可选）
```

**v8 GROUP BY 不在宽表原生列里**，需从上游字段 + 主数据 **派生** `tag1/tag2/tag3/...` 后再聚合（见 §2）。

---

## 附录 C. 表清单（灯塔相关）

| 层级 | 表名 | 行数(约) | 角色 |
|------|------|---------|------|
| **API 读** | `am_lighthouse_operating_daily` | 3,127 | 日宽表，粒度 `(stat_date, product_code, supplier_product_code)` |
| **API 读** | `am_lighthouse_operating_monthly` | 174 | 月宽表，`stat_month` |
| **API 读** | `am_lighthouse_operating_yearly` | 174 | 年宽表，`stat_year` |
| 日志 | `am_lighthouse_operating_sync_log` | 2 | 日/月/年同步日志 |
| 日志 | `am_biz_settlement_lighthouse_sync_log` | 0 | 结算→灯塔同步日志 |
| **写入源** | `am_biz_settlement_ingest_batch` | 1,641 | 回传批次 |
| **写入源** | `am_biz_settlement_ingest_product` | 1,641 | 产品日指标（灌宽表上游） |
| **写入源** | `am_biz_settlement_ingest_supplier` | 3,031 | 供应商维度 |
| **写入源** | `am_biz_settlement_ingest_line` | 3,625 | 费用项→宽表列映射源 |
| 配置 | `am_biz_settlement_lighthouse_field_mapping` | 26 | `bill_type_l3_code` → 宽表列 |
| 主数据 | `am_channel_product` | 2,016 | 渠道产品（`product_code`） |
| 主数据 | `am_channel_profile` | 231 | 渠道（`channel_name`） |
| 主数据 | `am_channel_category` | 13 | 渠道分类树 |
| 主数据 | `am_channel_product_source_rel` | — | 渠道产品↔供应商产品 |
| 主数据 | `am_product` | 1,237 | 供应商产品（`supplier_product_code`） |
| 主数据 | `am_product_category` | 16 | 产品分类树 |
| 主数据 | `am_supplier` | 213 | 供应商主体 |
| 主数据 | `am_supplier_type` | 14 | 供应商类型树 |
| 主数据 | `am_merchant` | 37 | 商户 |
| 主数据 | `am_config_category` | — | 项目/配置字典 |
| 折扣 | `light_tower_sp_disrules` | 54 | 折扣规则主表 |
| 折扣 | `light_tower_sp_disrules_mx_new` | 62 | 规则明细 |
| 折扣 | `light_tower_sp_disrules_product` | 476 | 规则↔产品 |
| 折扣 | `light_tower_sp_disrules_progressionlog` | 1,181 | 阶梯进度 |

---

## 附录 D. 核心表结构

### D.1 `am_lighthouse_operating_daily`（81 列）

**粒度**：`(stat_date, product_code, supplier_product_code)`  
**日期范围**：2026-01-01 ~ 2026-06-25  
**唯一索引**：`uk_lighthouse_operating_daily_ps(stat_date, product_code, supplier_product_code)`

| 分组 | 列名 | 类型 | 说明 | 非空行数/3127 |
|------|------|------|------|--------------|
| 时间 | `stat_date` | date | 统计日 | 3127 |
| 产品分类 | `category_l1/l2/l3_name/code` | varchar | 产品三级分类 | l1: **26** |
| 渠道分类 | `channel_category_l1/l2/l3_name/code` | varchar | 渠道三级分类 | **0**（未灌） |
| 供给分类 | `supplier_category_l1/l2/l3_name/code` | varchar | 供应商三级分类 | **0**（未灌） |
| 维度 | `product_name` | varchar(256) | SKU 名称 | 265 |
| 维度 | `product_code` | varchar(64) | 渠道产品编码 | 3127 |
| 维度 | `supplier_product_code` | varchar(64) | 供应商产品编码 | — |
| 维度 | `project_name` | varchar(256) | 项目名称 | **259** |
| 维度 | `merchant_name` | varchar(256) | 商户名（≠供给方展示名） | 88 |
| 维度 | `province_name` | varchar(64) | 省份 | **2858** |
| 维度 | `project_id`, `merchant_id` | bigint | ID | **0** |
| 指标 | `sales_amount` | decimal | 销售额 | 2822 |
| 指标 | `gmv` | decimal | GMV/引流 | 2973 |
| 指标 | `verify_amount` | decimal | 核销额 | 145 |
| 指标 | `daily_verify_amount` | decimal | 当日核销 | — |
| 指标 | `actual_trade_scale` | decimal | 实际交易规模 | — |
| 指标 | `its`, `discounted_its` | decimal | ITS / 折后ITS | 101 / 102 |
| 指标 | `spread_margin` | decimal | 利差 | 101 |
| 指标 | `revenue` | decimal | 收入 | 251 |
| 指标 | `business_cost`, `tax_cost` | decimal | 业务/税务成本 | 14 / 1 |
| 指标 | `saas_service_fee` | decimal | SaaS | **0** |
| 指标 | `project_cost` | decimal | 项目成本 | — |
| 指标 | `deduct_deferred_profit_share` | decimal | 抵扣延期分润 | — |
| 指标 | `total_cost`, `profit` | decimal | 成本/利润 | profit: 254 |
| 结算灌入 | `e_coupon_sales/purchase` | decimal | 电子券销售/采购款 | — |
| 结算灌入 | `channel_side_u/n/h` | decimal | 渠道侧 U/N/H | — |
| 结算灌入 | `supplier_side_u/n/h` | decimal | 供给侧 U/N/H | — |
| 结算灌入 | `platform_service_fee`, `payable_rebate` | decimal | 平台费/支付手续费 | — |
| 审计 | `settlement_changed`, `data_revision` | | 结算变更标记 | — |
| 审计 | `is_del` | tinyint | 0=正常 | — |

**monthly / yearly 时间范围**：monthly `2026-01`~`2026-06`（174 行）；yearly `2026`（174 行）。

**宽表 `project_name` 样例**（渠道 segment 解析参考）：

| project_name | 行数 |
|--------------|------|
| 压测项目 | 150 |
| 平安(共享平台) | 26 |
| 平安（产险新车道保证金） | 20 |
| 平安（亿力-卓悦银行新车道保证金） | 12 |
| 平安(天琨-优惠买单) | 8 |
| 支付宝多渠道 | 6 |

**宽表目前没有 v8 派生列**（`tag1`, `tag2`, `supply_class`, `channel_class`, `tag3` 等），需 ADD 或在 API 层实时算。

---

### D.2 `am_biz_settlement_ingest_batch`（12 列）

**行数**：1,641 · **含 `raw_payload`(mediumtext)**，可能存 v8 缺失字段（客户签约主体等）

| 列名 | 类型 | 说明 |
|------|------|------|
| `id` | bigint | PK |
| `sync_no` | varchar(64) | 同步批次号 |
| `stat_date` | date | 统计日 |
| `sync_source` | varchar(32) | `DIGITALG` / `CX_CARD_DATA` / `CX_BENEFIT` |
| `ingest_status` | varchar(32) | 入库状态 |
| `validate_note` | varchar(1000) | 校验备注 |
| **`raw_payload`** | mediumtext | **原始 JSON，待解析是否有客户签约主体/省份_中石油** |
| `create_time`, `update_time`, `is_del` | | 审计 |

**ingest_product.sync_source 分布**：`DIGITALG` 1623 · `CX_CARD_DATA` 17 · `CX_BENEFIT` 1

---

### D.3 `am_biz_settlement_ingest_product`（54 列）— 灌宽表上游

**粒度**：约 1 行 / 批次 / 渠道产品 / 日  
**行数**：1,641

| 列名 | 类型 | v8 / 前端用途 |
|------|------|--------------|
| `batch_id` | bigint | 关联 batch |
| `stat_date` | date | 统计日 |
| `product_code` | varchar(128) | = 宽表 `product_code` |
| `product_name` | varchar(256) | SKU；`classify()` 入参 |
| `project_name` | varchar(256) | `map_tag3` / 渠道解析入参 |
| `project_id` | bigint | → `am_config_category` |
| `channel_product_id` | bigint | → `am_channel_product.id` |
| `sector` | varchar(128) | 板块（现多为「成品油零售」或 NULL） |
| `tag_l1` | varchar(128) | 标签一（**现全 NULL**，v8 的「标签一」需 `classify()` 派生） |
| `product_category_name` | varchar(128) | 产品三级分类名 |
| `sync_source` | varchar(32) | 数据来源（DIGITALG / CX_CARD_DATA / CX_BENEFIT） |
| `gmv` | decimal | 引流相关 |
| `drainage_amount` | decimal | = v8「引流金额」 |
| `its`, `discounted_its` | decimal | ITS |
| `daily_verify_amount`, `total_verify_face_value` | decimal | 核销 |
| `revenue`, `cost`, `profit` | decimal | 收入/成本/利润 |
| `business_cost`, `tax_cost`, `spread_margin` | decimal | 成本/税务/利差 |
| `total_user_count`, `new_user_count`, `retain_user_count` | bigint | 用户量 |
| `lighthouse_sync_status` | varchar | PENDING/SYNCED/FAILED |

**完整 54 列清单**（按表顺序）：

`id`, `batch_id`, `stat_date`, `product_id`, `product_code`, `sync_source`, `parent_packet_product_id`, `parent_packet_channel_product_id`, `packet_item_num`, `product_name`, `project_name`, `project_id`, `channel_product_id`, `coupon_pack_name`, `sector`, `revenue_type`, `tag_l1`, `product_category_name`, `gmv`, `its`, `discounted_its`, `coupon_spread_margin`, `order_quantity`, `issue_sales_minus_refund`, `daily_verify_amount`, `total_verify_face_value`, `drainage_amount`, `total_refueling_amount`, `ty_amount_pay`, `actual_amount_pay`, `payable_rebate`, `promotion_fee_with_tax`, `promotion_fee_without_tax`, `promotion_fee_tax`, `supplier_fee_concat`, `revenue`, `cost`, `profit`, `channel_marketing_cost`, `supplier_marketing_cost`, `tax_cost`, `business_cost`, `spread_margin`, `total_user_count`, `new_user_count`, `retain_user_count`, `lighthouse_sync_status`, `lighthouse_sync_time`, `lighthouse_sync_note`, `create_by`, `create_time`, `update_by`, `update_time`, `is_del`

**注意**：ingest 表 **没有**「客户签约主体」「客户名称」「省份_中石油」——这些若 v8 需要，要从 batch 的 `raw_payload` 解析或扩展回传字段。

---

### D.4 `am_biz_settlement_ingest_supplier`（24 列）

**粒度**：供应商产品 × 渠道产品 × 日（可多条）  
**行数**：3,031

| 列名 | 用途 |
|------|------|
| `product_row_id` | → ingest_product.id |
| `product_code` | 渠道产品编码 |
| `supplier_product_code` | 供应商产品编码 |
| `supplier_product_name` | SKU 名（供应商侧） |
| `merchant_name` | 商户/供给相关名（如「广西中石油」） |
| `supplier_id` | → `am_supplier.id` |
| `project_name` | 项目快照 |
| `rebate_mode`, `is_yuantong` | 返利/元通标记 |

---

### D.5 `am_biz_settlement_ingest_line`（36 列）

**粒度**：费用项明细（CHANNEL 或 SUPPLIER slice）  
**行数**：3,625

关键列：

| 列名 | 用途 |
|------|------|
| `slice_type` | `CHANNEL` / `SUPPLIER` |
| `bill_type_l3_code` | 账单三级编码 → 查 `field_mapping` 灌宽表 |
| `lighthouse_amount` | 灌入宽表对应列的金额 |
| `lighthouse_tax_amount` | 税额 |
| `counterparty_entity` | 对方主体（潜在「客户签约主体」来源） |
| `match_status` | MATCHED / UNMATCHED |

---

### D.6 `am_biz_settlement_lighthouse_field_mapping`（26 行）

`bill_type_l3_code` → `target_column`（宽表 snake_case 列）：

| target_column | 含义 |
|---------------|------|
| `e_coupon_sales` | 电子券销售款（渠道） |
| `e_coupon_purchase` | 电子券采购款（供应商） |
| `saas_service_fee` | SaaS 服务费 |
| `deduct_deferred_profit_share` | 抵扣延期分润 |
| `deferred_deduct_profit_share` | 延期抵扣分润（第二口径） |
| `receivable_commission` | 机构返佣 |
| `receivable_rebate` | 返佣 |
| `platform_service_fee` | 平台服务费 |
| `payable_rebate` | 支付手续费 |
| `channel_side_u/n/h` | 渠道侧 U/N/H |
| `supplier_side_u/n/h` | 供给侧 U/N/H |

---

### D.7 主数据表（维度补全）

#### `am_channel_product`（2,016 行 · 41 列）

| 列名 | 用途 |
|------|------|
| `id` | PK |
| `product_code` | 与宽表 JOIN 键 |
| `product_name` | 渠道侧产品名 |
| `channel_id` | → `am_channel_profile` |
| `merchant_id`, `merchant_name`, `merchant_code` | 商户 |
| `project_id`, `project_name` | 项目 |
| `oil_category` | `GASOLINE` / `DIESEL` |
| `product_category_name` | 产品大类 |
| `sync_source`, `external_id` | 平台同步 |
| `denomination`, `discount_rate`, `unit_price` | 面额/折扣 |
| `rebate_mode`, `ind_rebate_coupon`, `is_deduct_coupon` | 返利/抵扣 |
| `supplier_id` | 关联供应商 |

#### `am_channel_profile`（231 行 · 22 列）

| 列名 | 填充率 | 用途 |
|------|--------|------|
| `channel_code`, `channel_name`, `channel_short_name` | 高 | 渠道名（如「平安」） |
| `entity_id`, `entity_name` | | 签约实体 |
| `partner_subject_id` | | 合作主体 |
| `parent_channel_id` | | 父渠道 |
| `channel_category_id` | **0/231** | → `am_channel_category`（未维护） |
| `channel_type` | | 渠道类型 |

#### `am_product`（1,237 行 · 36 列）

| 列名 | 用途 |
|------|------|
| `product_code` | = 宽表 `supplier_product_code` |
| `product_name` | 供应商产品名 |
| `supplier_id` | → `am_supplier` |
| `category_id` | → `am_product_category` |
| `province_code` | 省份编码 |
| `oil_category` | 油品 |
| `project_name`, `project_id` | 项目 |
| `proposal_code`, `proposal_name` | 方案 |
| `rebate_mode`, `is_yuantong` | 返利/元通 |

#### `am_supplier`（213 行 · 32 列）

| 列名 | 填充率 | 用途 |
|------|--------|------|
| `supplier_code`, `supplier_name`, `short_name` | 高 | 供应商主体 |
| `province_code` | | 省份 |
| `sign_subject_id`, `sign_subject_name` | | **签约主体（潜在「客户签约主体」来源）** |
| `partner_subject_id` | | 合作主体 |
| `type_path` | **3/213** | → `am_supplier_type` 路径（分类未维护） |
| `attribute_json` | | 扩展属性 JSON |

#### `am_channel_product_source_rel`

| 列名 | 用途 |
|------|------|
| `channel_product_id` | → `am_channel_product.id` |
| `supplier_product_id` | → `am_product.id` |
| `supplier_id`, `supplier_name` | 货源供应商 |

#### `am_product_category`（16 行）— 示例

```text
电子券(DZQ) → 现金券(XJQ)、优惠券、白嫖券、星和动力平台券…
交通卡(CXK)、电子卡、会员(HY) → 星和动力会员…
```

`sector` / `tag_l1` 列 **现均为 NULL**，不能替代 v8「标签一」。

#### `am_config_category`

`category_type='PROJECT_NAME'` 存项目字典（如「平安项目」「陕西联通」），与 ingest/宽表 `project_name` 文本快照对应。

---

### D.8 折扣规则表（供给方 `discount` 可选）

| 表 | 行数 | 说明 |
|----|------|------|
| `light_tower_sp_disrules` | 54 | `supplier_id`, `merchant_id`, `state` |
| `light_tower_sp_disrules_mx_new` | 62 | 阶梯规则 JSON `zk`，`zk_type`, `zk_mod` |
| `light_tower_sp_disrules_product` | 476 | `supplier_product_code` |
| `light_tower_sp_disrules_progressionlog` | 1,181 | 周期内 `discount` 进度 |

---

## 附录 E. JOIN 路径与覆盖率（daily 3127 行）

```sql
-- 宽表 ← 渠道产品 ← 渠道
lh.product_code = cp.product_code
cp.channel_id = ch.id

-- 宽表 ← 供应商产品 ← 供应商
lh.supplier_product_code = ap.product_code
ap.supplier_id = s.id

-- 货源关联
cp.id = rel.channel_product_id AND rel.is_active = 1
```

| JOIN | 命中行 / 总行 |
|------|--------------|
| → `am_channel_product` | 228 / 3246 |
| → `am_product` | 2427 / 3246 |
| → `source_rel` | 227 / 3246 |
| `channel_category_id` 有值 | 0 / 3246 |

---

## 附录 F. v8 派生列 ← 资管字段对照（实现清单）

| v8 派生列 | 优先数据来源 | 资管表.列 | 现状 |
|-----------|-------------|-----------|------|
| **标签一** `tag1` | `classify(旧标签, 产品名称, 数据来源, 折扣模式)` | ingest.`product_name`, `sync_source`；或 product_category | **需实现**，ingest.`tag_l1` 全 NULL |
| **标签二** `tag2` | `COALESCE(省份_中石油, 省份)` | daily.`province_name` + 归一规则 | province 2858/3127 有值；缺「省份_中石油」列 |
| **供给分类** | `map_supply_class` | daily.`province_name` + 产品名 | 需派生 |
| **油品** | `map_oil` | `am_channel_product.oil_category` + 产品名 | oil_category 在主数据 |
| **渠道分类** | `map_channel_class` | **缺** `客户签约主体`；可用 ingest_line.`counterparty_entity` 或扩展回传 | **缺口** |
| **标签三** | `map_tag3` | daily.`project_name` + sync_source + product_name | project_name 259 行有值，可部分解析 |
| **product_line_group** | 标签一 → 能源/出行/运营商 | 规则表 | 需配置 |

### F.1 汇总表/v8 列 → 宽表列（指标 sync）

| v8 BIZ 源（Excel 汇总明细） | ingest_product 列 | daily 宽表列 |
|---------------------------|-------------------|-------------|
| 销售额 | （issue_sales 等） | `sales_amount` |
| 引流金额 | `drainage_amount` | `gmv` |
| 核销金额 | `daily_verify_amount` | `verify_amount` |
| 收入_含税 | `revenue` | `revenue` |
| 业务成本_含税 | `business_cost` | `business_cost` |
| 利差 | `spread_margin` | `spread_margin` |
| 平台服务费_含税 | ingest_line → mapping | `saas_service_fee` |

---

## 附录 G. 给后续 AI 的分析任务建议

1. **复刻 v8 派生**：把 `build_l2_v8.py` 中 `map_supply_class` / `map_channel_class` / `map_tag3` / `relabel_summary_v3.classify` 移植到后端 sync 或 SQL UDF。
2. **补缺口字段**：宽表 ADD `tag1, tag2, supply_class, oil_type, channel_class, tag3, customer_sign_entity, product_line_group`；或 API 层实时计算。
3. **客户签约主体**：确认是否在 ingest `raw_payload` JSON 里；若无则扩展回传协议。
4. **标签一**：ingest.`tag_l1` 未使用；必须用 `classify()` 逻辑从产品名+来源推导，不能读 `category_l1_name`（成品油零售）。
5. **指标完整性**：宽表 `saas_service_fee` 全 0，需确认 ingest_line 匹配率与 mapping 配置。
6. **验证**：对同一 `stat_date` 范围，SQL 聚合结果应 ≈ v8 Excel Sheet 1/2/3 行数与毛利润合计。

### G.1 快速验证 SQL

```sql
-- 宽表日粒度总量
SELECT stat_date,
  SUM(sales_amount) sales, SUM(gmv) gmv, SUM(profit) profit,
  COUNT(*) rows, COUNT(DISTINCT product_code) products
FROM am_lighthouse_operating_daily
WHERE is_del = 0 AND stat_date BETWEEN '2026-06-01' AND '2026-06-25'
GROUP BY stat_date ORDER BY stat_date;

-- ingest 与宽表行数对比
SELECT stat_date, COUNT(*) FROM am_biz_settlement_ingest_product WHERE is_del=0 GROUP BY stat_date ORDER BY 1 DESC LIMIT 10;
SELECT stat_date, COUNT(*) FROM am_lighthouse_operating_daily WHERE is_del=0 GROUP BY stat_date ORDER BY 1 DESC LIMIT 10;
```

---

## 附录 H. 相关文件索引

| 文件 | 路径 |
|------|------|
| v8 聚合脚本 | `excel汇总表计算分析final/step2output/build_l2_v8.py` |
| v8 输出 Excel | `excel汇总表计算分析final/step2output/二级页面总览指标版_v8.xlsx` |
| 标签一推导 | `excel汇总表计算分析final/step2output/relabel_summary_v3.py` |
| HTML 设计稿 | `lighthouse_v13.html`（内嵌 DATA，与 v8 Sheet 1/2/3 同源） |
| 前端字段 | `docs/lighthouse-frontend-fields.md` |
| API 契约 | `docs/lighthouse-backend-field-contract.md` |

---

## 附录 I. 全表数据样例（test 环境 · 2026-06-26 探查）

> 附录 C 所列 **24 张表** 各 1～2 行真实样例。完整 JSON 探查脚本见文末 I.25。

| # | 表名 | 行数 | 本节 |
|---|------|------|------|
| 1 | `am_lighthouse_operating_daily` | 3,127 | I.1 |
| 2 | `am_lighthouse_operating_monthly` | 174 | I.2 |
| 3 | `am_lighthouse_operating_yearly` | 174 | I.3 |
| 4 | `am_lighthouse_operating_sync_log` | 2 | I.4 |
| 5 | `am_biz_settlement_lighthouse_sync_log` | **0** | I.5 |
| 6 | `am_biz_settlement_ingest_batch` | 1,641 | I.6 |
| 7 | `am_biz_settlement_ingest_product` | 1,641 | I.7 |
| 8 | `am_biz_settlement_ingest_supplier` | 3,031 | I.8 |
| 9 | `am_biz_settlement_ingest_line` | 3,625 | I.9 |
| 10 | `am_biz_settlement_lighthouse_field_mapping` | 26 | I.10 |
| 11 | `am_channel_product` | 2,019 | I.11 |
| 12 | `am_channel_profile` | 231 | I.12 |
| 13 | `am_channel_category` | 18 | I.13 |
| 14 | `am_channel_product_source_rel` | 5,129 | I.14 |
| 15 | `am_product` | 1,237 | I.15 |
| 16 | `am_product_category` | 18 | I.16 |
| 17 | `am_supplier` | 213 | I.17 |
| 18 | `am_supplier_type` | 15 | I.18 |
| 19 | `am_merchant` | 37 | I.19 |
| 20 | `am_config_category` | 541 | I.20 |
| 21 | `light_tower_sp_disrules` | 54 | I.21 |
| 22 | `light_tower_sp_disrules_mx_new` | 62 | I.22 |
| 23 | `light_tower_sp_disrules_product` | 476 | I.23 |
| 24 | `light_tower_sp_disrules_progressionlog` | 1,181 | I.24 |

---

### I.1 `am_lighthouse_operating_daily` — API 日宽表

**粒度**：`(stat_date, product_code, supplier_product_code)`

```json
{
  "id": 3244,
  "stat_date": "2026-06-21",
  "product_code": "PINGAN_NXZSY300YDZQGXPT1",
  "supplier_product_code": "300元(移动)",
  "product_name": "宁夏中石油300元电子券（共享平台1）",
  "project_name": "平安(共享平台)",
  "merchant_name": "宁夏中石油",
  "province_name": null,
  "category_l1_name": "成品油零售",
  "channel_category_l1_name": null,
  "supplier_category_l1_name": null,
  "gmv": 900.0,
  "sales_amount": 900.0,
  "verify_amount": 1200.0,
  "its": 900.0,
  "spread_margin": 891.0,
  "revenue": 891.0,
  "e_coupon_sales": 891.0,
  "platform_service_fee": 4.8,
  "profit": 886.2,
  "create_by": "biz-settlement-lighthouse-sync"
}
```

---

### I.2 `am_lighthouse_operating_monthly` — 月宽表

**粒度**：`(stat_month, product_code, supplier_product_code)`

```json
{
  "id": 176,
  "stat_month": "2026-06",
  "product_code": "PINGAN_NMGZSY100YTHDZQYT-CX26",
  "supplier_product_code": "202606154_FkL3Dg",
  "product_name": "内蒙古中石油100元特惠电子券（宇天-产险26）",
  "project_name": "平安（宇天-产险保证金）",
  "merchant_name": "广东中石油",
  "gmv": 10000.0,
  "sales_amount": 9000.0,
  "verify_amount": 8500.0,
  "profit": 300.0,
  "e_coupon_sales": 95.0,
  "platform_service_fee": 95.0
}
```

---

### I.3 `am_lighthouse_operating_yearly` — 年宽表

**粒度**：`(stat_year, product_code, supplier_product_code)` · 列同 monthly，时间键为 `stat_year`

```json
{
  "id": 175,
  "stat_year": 2026,
  "product_code": "PINGAN_NMGZSY100YTHDZQYT-CX26",
  "product_name": "内蒙古中石油100元特惠电子券（宇天-产险26）",
  "project_name": "平安（宇天-产险保证金）",
  "gmv": 10000.0,
  "sales_amount": 9000.0,
  "profit": 300.0
}
```

---

### I.4 `am_lighthouse_operating_sync_log` — 宽表同步日志

```json
{
  "id": 2,
  "sync_type": "DAILY",
  "start_date": "2026-05-31",
  "end_date": "2026-06-02",
  "rows_upserted": 63,
  "status": "SUCCESS",
  "message": "同步完成 rows=63, range=2026-05-31~2026-06-02, chunks=1",
  "cost_ms": 3404,
  "create_time": "2026-06-03 02:30:04"
}
```

---

### I.5 `am_biz_settlement_lighthouse_sync_log` — 结算→灯塔同步日志

**当前 test 库无数据（0 行）**。预期字段：`batch_id`, `sync_status`, `rows_affected`, `error_message`, `create_time`。

---

### I.6 `am_biz_settlement_ingest_batch` — 回传批次

```json
{
  "id": 3388,
  "sync_no": "850eeafd-de42-40e4-a764-1ea01e7c05a7",
  "stat_date": "2026-06-20",
  "sync_source": "DIGITALG",
  "ingest_status": "VALIDATED",
  "raw_payload": "{ \"channelProduct\": { \"productCode\": \"PINGAN_NXZSY300YDZQGXPT1\", ... }, \"supplierProducts\": [] }"
}
```

`raw_payload.channelProduct` 含指标 + `settlementLines[]`（见 I.6b）。

**I.6b raw_payload 片段**（batch 3388，对应 daily id=3243）：

```json
{
  "productCode": "PINGAN_NXZSY300YDZQGXPT1",
  "productName": "宁夏中石油300元电子券（共享平台1）",
  "projectName": "平安(共享平台)",
  "gmv": 600.0,
  "drainageAmount": 787.0,
  "profit": 591.6,
  "settlementLines": [
    {
      "billTypeL3Code": "ar_xsk_dzqxsk",
      "feeItemName": "电子券销售款",
      "lighthouseAmountWithTax": 594.0,
      "counterpartyEntity": "上海安壹通电子商务有限公司",
      "ourEntity": "上海卓悦优泰新能源科技有限公司"
    },
    {
      "billTypeL3Code": "ap_fwf_ptfwf",
      "feeItemName": "平台服务费",
      "lighthouseAmountWithTax": 2.4,
      "counterpartyEntity": "上海安壹通电子商务有限公司"
    }
  ]
}
```

---

### I.7 `am_biz_settlement_ingest_product` — 渠道产品日指标

```json
{
  "id": 3387,
  "batch_id": 3388,
  "stat_date": "2026-06-20",
  "product_code": "PINGAN_NXZSY300YDZQGXPT1",
  "product_name": "宁夏中石油300元电子券（共享平台1）",
  "project_name": "平安(共享平台)",
  "project_id": 2067525367968018433,
  "channel_product_id": 2067512790981033986,
  "sync_source": "DIGITALG",
  "sector": "成品油零售",
  "tag_l1": null,
  "gmv": 600.0,
  "drainage_amount": 787.0,
  "revenue": 594.0,
  "profit": 591.6,
  "lighthouse_sync_status": "FAILED",
  "lighthouse_sync_note": "Duplicate entry '2026-06-20-PINGAN_NXZSY300YDZQGXPT1' for key 'uk_lighthouse_daily_product_date'"
}
```

---

### I.8 `am_biz_settlement_ingest_supplier` — 供应商产品维度

同一 product_row 可挂多条 supplier（宽表按 `supplier_product_code` 拆行）：

```json
[
  {
    "id": 3420,
    "product_row_id": 3387,
    "stat_date": "2026-06-20",
    "product_code": "商务合作2",
    "supplier_product_code": "商务合作2",
    "supplier_product_name": "宁夏中石油300元汽油券",
    "merchant_name": "宁夏中石油",
    "project_name": "平安(共享平台)",
    "rebate_mode": null,
    "sort_no": 1
  },
  {
    "id": 3421,
    "product_row_id": 3387,
    "product_code": "yy300元汽油电子券(平安)",
    "supplier_product_code": "yy300元汽油电子券(平安)",
    "supplier_product_name": "宁夏中石油300元电子券（产险01）",
    "merchant_name": "宁夏中石油",
    "rebate_mode": "独立返券",
    "sort_no": 2
  }
]
```

---

### I.9 `am_biz_settlement_ingest_line` — 费用项明细

```json
{
  "id": 7131,
  "batch_id": 3388,
  "product_row_id": 3387,
  "slice_type": "CHANNEL",
  "fee_item_name": "电子券销售款",
  "bill_type_l3_code": "ar_xsk_dzqxsk",
  "counterparty_entity": "上海安壹通电子商务有限公司",
  "our_entity": "上海卓悦优泰新能源科技有限公司",
  "settlement_ratio": 0.99,
  "lighthouse_amount": 594.0,
  "match_status": "UNMATCHED"
}
```

---

### I.10 `am_biz_settlement_lighthouse_field_mapping` — 账单类型→宽表列

全表 26 行，示例 2 条：

| bill_type_l3_code | bill_type_l3_name | target_column | remark |
|-------------------|-------------------|---------------|--------|
| ap_cgk_dzqcgk | 电子券采购款 | e_coupon_purchase | 供应商-category_code |
| ar_ysfl_ysfl | 应收返利 | receivable_rebate | 渠道-category_code |
| ar_xsk_dzqxsk | 电子券销售款 | e_coupon_sales | 渠道-category_code |
| ap_fwf_ptfwf | 平台服务费 | platform_service_fee | 渠道-category_code |

---

### I.11 `am_channel_product` — 渠道产品主数据

**与宽表 JOIN 样例**（`product_code = PINGAN_NXZSY300YDZQGXPT1`）：

```json
{
  "id": 2067512790981033986,
  "product_code": "PINGAN_NXZSY300YDZQGXPT1",
  "product_name": "宁夏中石油300元电子券（共享平台1）",
  "channel_id": 2067525367968018433,
  "project_name": "平安(共享平台)",
  "oil_category": "GASOLINE",
  "merchant_name": "宁夏中石油300元电子券（共享平台）",
  "sync_source": "DIGITALG",
  "status": "active"
}
```

**其他来源样例**（CX_MEMBER 同步，无项目/油品）：

```json
{
  "product_code": "黑龙江-ZK96",
  "product_name": "黑龙江-ZK96",
  "channel_id": 2070328655612407810,
  "project_name": null,
  "oil_category": null,
  "sync_source": "CX_MEMBER"
}
```

---

### I.12 `am_channel_profile` — 渠道主数据

```json
[
  {
    "id": 2067525367968018433,
    "channel_code": "PINGAN",
    "channel_name": "平安",
    "channel_short_name": "平安",
    "sync_source": "DIGITALG",
    "channel_category_id": null
  },
  {
    "id": 2070328655612407810,
    "channel_code": "ZYJK",
    "channel_name": "中移金卡",
    "sync_source": "CX_MEMBER",
    "channel_category_id": null
  }
]
```

---

### I.13 `am_channel_category` — 渠道分类树

```json
[
  {
    "id": 2064619075901272066,
    "parent_id": 0,
    "category_code": "PRODUCT_BIG_CATEGORY_ROOT",
    "category_name": "产品大类",
    "level": 1
  },
  {
    "id": 2058731432590536706,
    "parent_id": 1779249170639119,
    "category_code": "ZGSY",
    "category_name": "中国石油",
    "level": 2,
    "is_del": 1
  }
]
```

> 注意：`am_channel_profile.channel_category_id` 全 NULL，分类树暂未挂到渠道。

---

### I.14 `am_channel_product_source_rel` — 渠道产品↔供应商产品

```json
{
  "id": 2069679722366771202,
  "channel_product_id": 2067512762224885761,
  "supplier_id": 2069236265220804609,
  "supplier_product_id": 2067583488856477697,
  "real_supplier_code": "ZSYTJQ",
  "supplier_name": "宁夏中石油",
  "is_active": 1,
  "priority": 1,
  "sync_source": "DIGITALG"
}
```

---

### I.15 `am_product` — 供应商产品主数据

**与宽表 `supplier_product_code` 对应**：

```json
{
  "id": 2067583488856477697,
  "product_code": "300元(移动)",
  "product_name": "宁夏中石油300元汽油券（移动）",
  "supplier_id": 2069236265220804609,
  "oil_category": "GASOLINE",
  "rebate_mode": "INDEPENDENT_COUPON",
  "sync_source": "DIGITALG"
}
```

**权益类样例**：

```json
{
  "product_code": "314000-江苏派若米电子商务有限公司",
  "product_name": "314000-江苏派若米电子商务有限公司",
  "sync_source": "CX_BENEFIT",
  "category_id": null
}
```

---

### I.16 `am_product_category` — 产品分类树

```json
[
  {
    "id": 2058742011468480514,
    "category_code": "CPYLS",
    "category_name": "成品油零售",
    "level": 1,
    "sector": null,
    "tag_l1": null
  },
  {
    "id": 2039640010633732098,
    "parent_id": 2016797948985278466,
    "category_code": "DZQ_XHDLPTQB",
    "category_name": "星和动力平台券包",
    "level": 2
  }
]
```

> `sector` / `tag_l1` 均为 NULL，**不能**替代 v8「标签一」。

---

### I.17 `am_supplier` — 供应商主体

```json
[
  {
    "id": 2069236265220804609,
    "supplier_code": "ZSYTJQ_640000",
    "supplier_name": "宁夏中石油",
    "short_name": "宁夏中石油",
    "sign_subject_name": null,
    "type_path": null,
    "sync_source": "DIGITALG"
  },
  {
    "id": 2070081661818679297,
    "supplier_code": "test-zqpz-yglcp",
    "supplier_name": "测试供应商-周期配置-有关联产品",
    "sign_subject_name": "上海卓悦",
    "type_path": "2069626326070878209,2070080996237160450,2070081113178550273",
    "province_code": "430000"
  }
]
```

---

### I.18 `am_supplier_type` — 供应商类型树

```json
[
  {
    "id": 2044259948174520321,
    "parent_id": 2044251960755892226,
    "type_code": "QYX_HZ",
    "type_name": "合作",
    "level": 2
  },
  {
    "id": 2044252174514401282,
    "type_code": "QYX_FR",
    "type_name": "分润",
    "level": 2
  }
]
```

> `am_supplier.type_path` 仅 3/213 有值，分类关联基本未维护。

---

### I.19 `am_merchant` — 商户

```json
[
  {
    "id": 2067497616779182081,
    "merchant_code": "GSZSY",
    "merchant_name": "甘肃中石油",
    "province_code": "620000",
    "sync_source": "DIGITALG"
  },
  {
    "id": 2067503128686067714,
    "merchant_code": "DEMO-MCH-001",
    "merchant_name": "Demo Merchant",
    "sync_source": "DIGITALG"
  }
]
```

---

### I.20 `am_config_category` — 项目/配置字典

```json
[
  {
    "id": 6441659025766481941,
    "category_type": "PROJECT_NAME",
    "category_code": "天琨-优惠买单",
    "category_name": "天琨-优惠买单",
    "remark": "migrated from bank flow project fields"
  },
  {
    "id": 228,
    "category_type": "PROJECT_NAME",
    "category_code": "1",
    "category_name": "平安项目"
  }
]
```

与宽表/ingest 的 `project_name` 文本快照对应（如「平安(共享平台)」「平安（天琨-银行新车道保证金）」）。

---

### I.21 `light_tower_sp_disrules` — 折扣规则主表

```json
[
  {
    "id": 540001,
    "name": "月阶梯-核销",
    "supplier_id": 480001,
    "supplier_name": "中油BP",
    "merchant_id": 1007450917293883412,
    "merchant_name": "中油BP",
    "state": 1
  },
  {
    "id": 510002,
    "name": "月阶梯（超额累进）-引流金额（黑龙江）",
    "supplier_id": 90010,
    "supplier_name": "黑龙江中石油",
    "merchant_name": "黑龙江中石油"
  }
]
```

---

### I.22 `light_tower_sp_disrules_mx_new` — 规则明细（阶梯 JSON）

```json
{
  "id": 1350193,
  "disrules_id": 540001,
  "name": "月阶梯-核销",
  "supplier_name": "中油BP",
  "zk_type": 1,
  "zk_mod": 1,
  "calculation_mode": 2,
  "zk": "[{\"pirce_one\":\"5000000\",\"discount\":\"100\"},{\"pirce_one\":\"5000000\",\"pirce_two\":\"10000000\",\"discount\":\"98\"}, ...]",
  "start_time": "2025-11-01 00:00:00",
  "end_time": "2027-12-31 23:59:59"
}
```

---

### I.23 `light_tower_sp_disrules_product` — 规则↔供应商产品

```json
[
  {
    "id": 1350007,
    "disrules_id": 540001,
    "supplier_name": "中油BP",
    "supplier_product_code": "19468"
  },
  {
    "id": 1350008,
    "disrules_id": 120008,
    "supplier_name": "广东中石油",
    "supplier_product_code": "202512344_4KvkRd"
  }
]
```

---

### I.24 `light_tower_sp_disrules_progressionlog` — 阶梯进度

```json
{
  "id": 1830034,
  "disrules_id": 120008,
  "disrules_mx_id": 120007,
  "zk_type": 1,
  "zk_mod": 2,
  "start_date": "2026-05-11 19:21:19",
  "end_date": "2026-05-29 23:59:59",
  "discount": "0.03",
  "task_status": 1
}
```

前端供给方 `discount` 字段可从此表 + 规则表计算。

---

### I.25 表间关联样例（同一条业务链）

以 **2026-06-20 · PINGAN_NXZSY300YDZQGXPT1** 为例：

```text
ingest_batch (3388, sync_no=850eeafd...)
  └─ ingest_product (3387)  product_code=PINGAN_NXZSY300YDZQGXPT1, profit=591.6
       ├─ ingest_supplier (3420) supplier_product=商务合作2 / 宁夏中石油300元汽油券
       ├─ ingest_supplier (3421) supplier_product=yy300元汽油电子券(平安)
       └─ ingest_line (7131)    ar_xsk_dzqxsk → e_coupon_sales=594
              counterparty=上海安壹通电子商务有限公司

ingest_product.channel_product_id → channel_product (2067512790981033986)
  └─ channel_profile → channel_name=平安, channel_code=PINGAN
  └─ source_rel → supplier_name=宁夏中石油

ingest_supplier → product (300元(移动)) → supplier (宁夏中石油)

lighthouse_operating_daily (3243)
  stat_date=2026-06-20, supplier_product_code=300元(移动)
  gmv=600, profit=591.6, e_coupon_sales=594, platform_service_fee=2.4
```

### I.26 v8 派生示意（同 SKU）

| v8 列 | 从样例推导 |
|-------|-----------|
| 标签一 | classify(NULL, 宁夏中石油300元电子券…, DIGITALG) → **需脚本** |
| 标签二 | 从产品名解析 → **宁夏** |
| 标签三 | project_name + channel_name → **平安** |
| 渠道分类 | counterparty「上海安壹通」+ 项目「平安(共享平台)」→ **产险/平安** 类 |
| 销售额 | 600 ← sales_amount |
| 毛利润 | 591.6 ← profit |

**同一 SKU 行不会直接出现在 HTML 一级列表**——须 GROUP BY 标签一/二/三后聚合。

### I.27 复现探查 SQL

```sql
-- 任意表取 2 行样例
SELECT * FROM am_lighthouse_operating_daily WHERE is_del=0 ORDER BY id DESC LIMIT 2;

-- 同链路 JOIN
SELECT lh.stat_date, lh.product_code, ip.id ingest_id, ib.sync_no,
       il.bill_type_l3_code, il.lighthouse_amount, cp.channel_id, ch.channel_name
FROM am_lighthouse_operating_daily lh
JOIN am_biz_settlement_ingest_product ip
  ON ip.product_code=lh.product_code AND ip.stat_date=lh.stat_date AND ip.is_del=0
JOIN am_biz_settlement_ingest_batch ib ON ib.id=ip.batch_id
LEFT JOIN am_biz_settlement_ingest_line il ON il.product_row_id=ip.id AND il.is_del=0
LEFT JOIN am_channel_product cp ON cp.product_code=lh.product_code AND cp.is_del=0
LEFT JOIN am_channel_profile ch ON ch.id=cp.channel_id
WHERE lh.product_code='PINGAN_NXZSY300YDZQGXPT1' AND lh.is_del=0
LIMIT 10;
```
