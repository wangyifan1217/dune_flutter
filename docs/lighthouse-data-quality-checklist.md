# 灯塔测试库数据质量排查清单

> **探查时间**：2026-06-26  
> **接口**：`GET /api/v1/lighthouse/overview?period=month&date=2026-06-26`  
> **环境**：`sel-mg` 测试库 · 网关 `localhost:6090`  
> **用途**：前端已接真接口；本文汇总当前返回中「恒 0 / 口径待定 / 疑似脏数据」三类问题，供后端与 DBA 排查。

---

## 1. 结论摘要

| 类型 | 结论 |
|------|------|
| **预期内** | `projectCost` / `saasFee` / `deferred` 全 0；`gmv2` 暂等于 `sales`；部分 `its`/`itsAfter` 接近引流/销售（上游灌数） |
| **需确认** | Hero `metrics.deltaPct = 0`；行级 `deltaPct` 字段未返 |
| **疑似错误** | 孤儿利润重复桶、负销售额、内蒙古行 revenue/cost 为负、未分类行利润率异常、大量 cost/tax 为 0 导致毛利率虚高 |

三个 tab（product / supply / channel）**sales 合计均为 1,110,250** 属于正常对账（同一宽表不同 GROUP BY），不是重复请求。

---

## 2. 预期内：接了字段但值为 0 或口径未定

### 2.1 全 tab 恒为 0

| API 字段 | 宽表列（文档） | 前端展示位置 | 当前状态 |
|----------|----------------|--------------|----------|
| `projectCost` | 项目成本列 | supply / channel 指标 chip | **4/4 product、20/20 supply、8/8 channel 全 0** |
| `saasFee` | SAAS 服务费列 | supply / channel 指标 chip | 同上 |
| `deferred` | 抵扣延期分润 | supply / channel 指标 chip | **几乎全 0**（仅 1 行 = 95） |

**后端已说明**：源表暂无数据，非前端问题。

### 2.2 有值但口径待定 / 测试灌数

| API 字段 | 现象 | 说明 |
|----------|------|------|
| `gmv2` | 有 sales 的行 **100% 满足 gmv2 ≈ sales** | 后端临时映射，口径未定 |
| `its` | **product 2/4、supply 17/20、channel 7/8** 行 ITS 与 gmv 相差 <5% | 测试库 `its` 列可能仍按引流灌数 |
| `itsAfter` | **product 2/4、supply 17/20、channel 8/8** 行折 ITS 与 sales 相差 <5% | 测试库 `discounted_its` 可能仍按销售灌数 |
| `woa` | 部分行为 0（product 1/4、supply 4/20、channel 1/8） | 宽表 `woa` 列待建/待灌（文档 P1） |

### 2.3 Hero metrics

| 字段 | 当前值 | 说明 |
|------|--------|------|
| `deltaPct` | `0`（`deltaDir: up`） | 字段存在；环比计算结果是否为 0 待业务确认 |
| `rate` | `76.76` | 与行汇总 profit/sales 一致，但偏高，可能与 cost/tax 大量为 0 有关 |

---

## 3. 字段缺失（非 0，是未返回）

| 字段 | 位置 | 现状 |
|------|------|------|
| `deltaPct` | `product[]` / `supply[]` / `channel[]` 行级 | **0/32 行有该字段**；前端已隐藏假环比，等后端补 |

---

## 4. 疑似脏数据（建议优先排查）

### 4.1 同一笔「孤儿利润」重复出现在两个维度

以下两行 **gmv / profit / revenue 完全一致**，sales 均为 0：

| tab | name | group | sales | gmv | profit | revenue | cost |
|-----|------|-------|------:|----:|-------:|--------:|-----:|
| product | 其他 | 其他 | 0 | 1,500,000 | 45,000 | 75,000 | 0 |
| supply | (无省份) | 运营商 | 0 | 1,500,000 | 45,000 | 75,000 | 0 |

**怀疑**：未归类批次在 product 与 supply 维度各聚合一次，或 `province_name` / 产品线映射缺失导致重复桶。

### 4.2 单行指标严重失衡

| tab | name | 异常 | 样例数值 |
|-----|------|------|----------|
| supply | **内蒙古** | profit >> sales；**revenue、cost 为负** | sales=2,100 · profit=53,061 · revenue=**-6,312** · cost=**-59,990** |
| channel | **未分类** | 利润率 >10000% | sales=400 · profit=45,392 · revenue=75,396 |
| product | 中石油权益券包 | **负销售额** | sales=**-10** · profit=100.6 |
| supply | 四川省 | **负销售额** | sales=**-72** |

### 4.3 成本/税务缺失 → 毛利率虚高

| 检查项 | product | supply | channel |
|--------|---------|--------|---------|
| cost=0 且 profit>1,000 | 0/4 | **10/20** | **4/8** |
| tax=0 且 profit>10,000 | 1/4 | **5/20** | **3/8** |
| profit > revenue | 2/4 | 1/20 | 1/8 |
| profit > sales | 0/4 | **4/20** | **3/8** |

Hero 汇总：salesTotal=1,110,250 · profit 合计≈852,244 · **rate≈76.76%**，与 cost/tax 大量为 0 一致。

### 4.4 趋势 `trend.profit` 出现负值点

| tab | name | 负值点（约） |
|-----|------|-------------|
| product | 中石油现金券 | -2.4 |
| product | 中石油权益券包 | -4.0 |
| supply | 广东省 | -4.0 |
| channel | 共享平台 | -2.4 |

可能是日级退款/冲正；也可能是日聚合符号或口径错误，建议对 `stat_date` 下钻核对。

---

## 5. 建议 SQL（宽表 `am_lighthouse_operating_monthly` / `daily`）

> 列名以 `lighthouse-database-fields.md` 为准；下表 API 字段 → 宽表列按文档映射。

### 5.1 孤儿利润（有利润无销售）

```sql
SELECT stat_month, product_name, project_name, province_name,
       sales_amount, gmv, revenue, cost, profit, its, discounted_its
FROM am_lighthouse_operating_monthly
WHERE stat_month = '2026-06'
  AND (sales_amount IS NULL OR sales_amount = 0)
  AND profit > 0
ORDER BY profit DESC;
```

### 5.2 负值行

```sql
SELECT stat_month, product_name, province_name, supplier_name,
       sales_amount, revenue, cost, profit
FROM am_lighthouse_operating_monthly
WHERE stat_month = '2026-06'
  AND (sales_amount < 0 OR revenue < 0 OR cost < 0 OR profit < 0);
```

### 5.3 内蒙古 / 未归类 下钻

```sql
-- 内蒙古 supply 行异常
SELECT *
FROM am_lighthouse_operating_monthly
WHERE stat_month = '2026-06'
  AND (province_name LIKE '%内蒙古%' OR supplier_name LIKE '%内蒙古%');

-- 150万 gmv + 4.5万 profit 桶
SELECT product_name, project_name, province_name,
       SUM(gmv) AS gmv, SUM(sales_amount) AS sales, SUM(profit) AS profit
FROM am_lighthouse_operating_monthly
WHERE stat_month = '2026-06'
GROUP BY product_name, project_name, province_name
HAVING SUM(gmv) = 1500000 AND SUM(profit) = 45000;
```

### 5.4 ITS 灌数核对

```sql
SELECT product_name,
       SUM(gmv) AS gmv,
       SUM(daily_verify_amount) AS verify,  -- 或 month_verify_amount
       SUM(its) AS its,
       SUM(discounted_its) AS its_after,
       SUM(sales_amount) AS sales
FROM am_lighthouse_operating_monthly
WHERE stat_month = '2026-06'
GROUP BY product_name
HAVING SUM(its) > 0
ORDER BY ABS(SUM(its) - SUM(gmv)) / NULLIF(SUM(gmv), 0) DESC
LIMIT 20;
```

### 5.5 成本/税务缺失

```sql
SELECT province_name, product_name,
       sales_amount, revenue, cost, tax_cost, profit
FROM am_lighthouse_operating_monthly
WHERE stat_month = '2026-06'
  AND profit > 1000
  AND (cost IS NULL OR cost = 0);
```

---

## 6. 前端当前行为（供联调参考）

| 场景 | 前端处理 |
|------|----------|
| 恒 0 字段 | 如实展示 0（未做隐藏） |
| 行级无 `deltaPct` | 不显示环比箭头 |
| `discount` | 仅 supply 中石油/中石化行有对象；已删本地快照 |
| 趋势 `trend` | 读 API 真曲线；无 trend 显示「暂无趋势数据」 |
| 油品筛选 | 带 `fuel` 参数重新请求，不再本地乘系数 |

---

## 7. 排查优先级

| 优先级 | 项 | 负责 |
|--------|-----|------|
| **P0** | 内蒙古 revenue/cost 负值、孤儿利润重复桶（其他 / 无省份） | 后端 + DBA |
| **P0** | 负销售额（权益券包、四川省） | 后端 ingest |
| **P1** | cost/tax 大量为 0 → 毛利率 76% 是否可信 | 后端口径 |
| **P1** | `its` / `discounted_its` 与 gmv/sales 对齐 | 上游灌数 |
| **P2** | `projectCost` / `saasFee` / `deferred` / `woa` 源列灌数 | 后端 ETL |
| **P2** | `gmv2` 口径、`deltaPct` 行级/hero 环比 | 后端 API |
| **P3** | trend 日点负 profit 是否为合理冲正 | 业务确认 |

---

## 8. 复现方式

```bash
# 登录
curl -s -X POST http://localhost:6090/api/v1/auth/sms/token \
  -H 'Content-Type: application/json' \
  -d '{"phone":"13329736325","code":"666666","channel":"app"}'

# 拉 overview
curl -s "http://localhost:6090/api/v1/lighthouse/overview?period=month" \
  -H "Authorization: Bearer <token>"
```

关键样例行：`product.其他`、`supply.(无省份)`、`supply.内蒙古`、`channel.未分类`。

---

## 9. 相关文档

| 文件 | 内容 |
|------|------|
| `docs/lighthouse-database-fields.md` | 宽表列 ↔ API 字段映射 |
| `docs/灯塔数据接入对齐文档.md` | 全链路对接 |
| `docs/lighthouse-discount-backend-spec.md` | 折扣 progress 字段 |
