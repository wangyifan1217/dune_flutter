# Lighthouse 后端设计方案 (Go)

> 目的：把 Dart 端 `native_lighthouse_page.dart` 当前对后端的所有数据需求，落成可直接对接数据库实现的 Go 服务规范。
> 配套：Gin + sqlx + shopspring/decimal + viper + zap，与现有 Heunion 后端栈一致。

---

## 1. 现状盘点

### 1.1 Dart 已经在用的接口
单接口：

```
GET /api/v1/lighthouse/overview?period={day|week|month|quarter|year}&date=YYYY-MM-DD&fuel={全部|汽油}
Authorization: Bearer <token>
```

返回结构（Dart `LighthouseDataBundle.fromJson`）：

```json
{
  "data": {
    "product": [Row, Row, ...],
    "supply":  [Row, Row, ...],
    "channel": [Row, Row, ...]
  },
  "product_detail": { "汽油92": { "supply":[Row], "channel":[Row] } },
  "supply_detail":  { "北京中石油": { "product":[Row], "channel":[Row] } },
  "channel_detail": { "DICT平台": { "product":[Row], "supply":[Row] } },
  "metrics": {
    "lastSyncedAt": "2026-06-21T09:18:00+08:00",
    "hero": { ... 见 1.3 },
    "periods": { ... 见 1.5 }
  }
}
```

### 1.2 Row 字段全集

| Dart key | 中文 | 单位 | 业务含义 | 是否必填 |
|---|---|---|---|---|
| `name` | — | string | 实体名（汽油92 / 北京中石油 / DICT 等） | ✓ |
| `group` | 分组 | string | 中石油 / 中石化 / 民营 / 平安 / DICT / ... | ✓ |
| `sales` | 销售额 | 元 | GMV 减去优惠 | ✓ |
| `gmv` | 引流 GMV | 元 | 引流口径金额 | ✓ |
| `gmv2` | GMV | 元 | 普通 GMV | ✓ |
| `its` | ITS | 元 | 折前 ITS（理论成本） | ✓ |
| `itsAfter` | 折后 ITS | 元 | 折后 ITS | ✓ |
| `revenue` | 收入 | 元 | 真实结算收入 | ✓ |
| `totalCost` | 总成本 | 元 | totalCost = cost + tax + 其他 | ✓ |
| `cost` | 业务成本 | 元 | 油品采购、给油站结算 | ✓ |
| `tax` | 税务成本 | 元 | 增值税 + 附加 | ✓ |
| `spread` | 利差 | 元 | sales - itsAfter | ✓ |
| `profit` | 毛利润 | 元 | sales - totalCost | ✓ |
| `woa` | WOA | 元 | 油站合规返点等 | **当前有 bug，全 0** |
| `saasFee` | SaaS 费 | 元 | 平台服务费 | 仅 supply / channel |
| `projectCost` | 项目成本 | 元 | 项目分摊费用 | 仅 supply / channel |
| `deferred` | 延期分润 | 元 | 抵扣 / 延期分润 | 仅 supply / channel |
| `discount` | 折扣进度 | object | **仅 supply 维度阶梯省份**，见 1.4 | 当前缺 |
| `deltaPct` | 环比 % | float | 当前周期 vs 上周期 % 变化 | 当前缺 |
| `trend` | 趋势 | object | revenue/cost/profit 时间序列 | 当前缺 |
| `hunU` | HUN-U | 元 | U 类口径金额 | 当前缺 |
| `hunN` | HUN-N | 元 | N 类口径金额 | 当前缺 |
| `hunH` | HUN-H | 元 | H 类口径金额 | 当前缺 |

### 1.3 Hero 块

Dart 顶部 hero panel 期望：

```json
"hero": {
  "label": "本月 06.01 — 06.30",
  "short": "本月",
  "deltaVs": "vs 上月",
  "sales":   { "value": 350000000, "deltaPct": 12.5 },
  "profit":  { "value": 18500000,  "deltaPct": 8.3 },
  "gmv":     { "value": 410000000, "deltaPct": 15.2 }
}
```

### 1.4 折扣进度（discount）

Dart 当前硬编码 `_kDiscountRows`（21 个中石油省级，已达标 18 + 临门 3）。需要后端给出：

```json
"discount": {
  "province":  "海南",
  "mode":      "阶梯·引流",
  "subtag":    null,              // "高率待核" / "双月" / "季度" / null
  "cur":       3352000,           // 当月基数（元）
  "target":    4000000,           // 下一档下限（元）；null = 封顶 / 固定
  "curRate":   2.0,               // 当前率（%）
  "nextRate":  3.0,               // 下一档率（%）；null = 封顶 / 固定
  "tierLabel": null,              // "第3档" / null
  "rebate":    67040              // 本期返点（元）
}
```

派生计算（前端做，**不要在后端重复**）：
- `gap = max(0, target - cur)`
- `progress = clamp(cur / target, 0, 1)`
- `incrementalGain = target × (nextRate - curRate) / 100`
- `isAlmost = gap > 0 && gap < 700000`（临门一脚判定阈值）

### 1.5 周期切换

Dart 当前请求 `period=day|week|month|quarter|year`，后端按周期返回不同 `period_bucket`：

| period | bucket 含义 | 当前周期 vs 上周期 |
|---|---|---|
| `day` | 当前自然日 | 今日 vs 昨日 |
| `week` | 当前周（周一开始） | 本周 vs 上周 |
| `month` | 当前自然月 | 本月 vs 上月 |
| `quarter` | 当前自然季 | 本季 vs 上季 |
| `year` | 当前自然年 | 本年 vs 上年 |

时区固定 **Asia/Shanghai (UTC+8)**，前端已经按 CST 计算并显示，后端写入 / 查询都用 CST 日期 bucket。

---

## 2. 当前后端缺口

| # | 缺口 | 影响 | 优先级 |
|---|---|---|---|
| BE-1 | `woa` 全 0（计算/数据源问题） | 列表"指标"开关里 WOA 显示空 | P0 |
| BE-2 | 没有 `deltaPct`（环比） | list item 右侧"↑5.3%"现在是 mock | P0 |
| BE-3 | 没有 `trend` 时间序列 | 列表展开后趋势图全是 mock 数据 | P0 |
| BE-4 | 没有 `discount` 字段 | 折扣 section 硬编码 21 个省，时效性差 | P1 |
| BE-5 | 没有 `hunU/N/H` 拆分 | HUN 进度条全是 mock 派生（按 name hash） | P1 |
| BE-6 | `projectCost / deferred` 仅在部分维度有 | 数据完整性问题 | P1 |
| BE-7 | 没有 hero block | 顶部 hero "对比上月" 是 mock | P2 |

---

## 3. Go 服务结构

```
internal/lighthouse/
├── handler.go          // Gin handler: GET /overview
├── service.go          // 业务编排
├── repo.go             // sqlx 查询
├── model.go            // Go struct (与 Dart 端 JSON 对齐)
├── period.go           // 周期解析 (period + date → bucket range)
├── trend.go            // 趋势 JSON 序列化助手
└── discount.go         // 折扣进度组装
```

---

## 4. Go 数据模型

```go
package lighthouse

import "time"

// 顶层 wrap (Gin 统一 envelope 由 router 中间件处理)
type OverviewResponse struct {
    Data           TabData              `json:"data"`
    ProductDetail  map[string]Detail    `json:"product_detail"`
    SupplyDetail   map[string]Detail    `json:"supply_detail"`
    ChannelDetail  map[string]Detail    `json:"channel_detail"`
    Metrics        Metrics              `json:"metrics"`
}

type TabData struct {
    Product []Row `json:"product"`
    Supply  []Row `json:"supply"`
    Channel []Row `json:"channel"`
}

// Row — 主列表 + 详情共用（详情里 product/supply/channel 子列表的元素也是 Row）
type Row struct {
    Name        string    `json:"name"`
    Group       string    `json:"group"`
    Sales       float64   `json:"sales"`
    GMV         float64   `json:"gmv"`
    GMV2        float64   `json:"gmv2"`
    ITS         float64   `json:"its"`
    ITSAfter    float64   `json:"itsAfter"`
    Revenue     float64   `json:"revenue"`
    TotalCost   float64   `json:"totalCost"`
    Cost        float64   `json:"cost"`
    Tax         float64   `json:"tax"`
    Spread      float64   `json:"spread"`
    Profit      float64   `json:"profit"`
    WOA         float64   `json:"woa"`
    SaaSFee     float64   `json:"saasFee,omitempty"`
    ProjectCost float64   `json:"projectCost,omitempty"`
    Deferred    float64   `json:"deferred,omitempty"`

    // HUN 三段（仅 supply / channel）
    HunU float64 `json:"hunU,omitempty"`
    HunN float64 `json:"hunN,omitempty"`
    HunH float64 `json:"hunH,omitempty"`

    // 环比
    DeltaPct float64 `json:"deltaPct"`

    // 趋势 (period 内的时间序列)
    Trend *Trend `json:"trend,omitempty"`

    // 折扣进度 (仅 supply 维度阶梯省份)
    Discount *Discount `json:"discount,omitempty"`
}

type Trend struct {
    RangeLabel string    `json:"rangeLabel"` // "06.01 — 06.30"
    Revenue    []float64 `json:"revenue"`    // N 个点（period 决定 N）
    Cost       []float64 `json:"cost"`
    Profit     []float64 `json:"profit"`
}

type Discount struct {
    Province  string   `json:"province"`
    Mode      string   `json:"mode"`             // "阶梯·引流" | "固定" | ...
    Subtag    *string  `json:"subtag,omitempty"` // "高率待核" / "双月" / null
    Cur       float64  `json:"cur"`              // 当月基数
    Target    *float64 `json:"target,omitempty"` // 下一档下限；null = 封顶/固定
    CurRate   float64  `json:"curRate"`
    NextRate  *float64 `json:"nextRate,omitempty"`
    TierLabel *string  `json:"tierLabel,omitempty"` // "第3档"
    Rebate    float64  `json:"rebate"`
}

type Detail struct {
    Product []Row `json:"product,omitempty"`
    Supply  []Row `json:"supply,omitempty"`
    Channel []Row `json:"channel,omitempty"`
}

type Metrics struct {
    LastSyncedAt time.Time `json:"lastSyncedAt"` // 序列化为 RFC3339 with +08:00
    Hero         HeroBlock `json:"hero"`
    Periods      map[string]PeriodMeta `json:"periods,omitempty"` // optional metadata
}

type HeroBlock struct {
    Label   string         `json:"label"`   // "本月 06.01 — 06.30"
    Short   string         `json:"short"`   // "本月"
    DeltaVs string         `json:"deltaVs"` // "vs 上月"
    Sales   MetricWithDelta `json:"sales"`
    Profit  MetricWithDelta `json:"profit"`
    GMV     MetricWithDelta `json:"gmv"`
}

type MetricWithDelta struct {
    Value    float64 `json:"value"`
    DeltaPct float64 `json:"deltaPct"`
}

type PeriodMeta struct {
    Label string `json:"label"`
    Range string `json:"range"`
}
```

---

## 5. 数据库 Schema (PostgreSQL)

按 ETL 物化原则：一张主表存所有维度的聚合，detail / trend 独立表关联。

### 5.1 物化主表

```sql
CREATE TABLE lighthouse_aggregate (
    period_type      VARCHAR(16)   NOT NULL,    -- 'day'|'week'|'month'|'quarter'|'year'
    period_bucket    DATE          NOT NULL,    -- CST 桶起始日, e.g. '2026-06-01'
    dim_type         VARCHAR(16)   NOT NULL,    -- 'product'|'supply'|'channel'
    name             VARCHAR(128)  NOT NULL,
    group_name       VARCHAR(64),
    fuel             VARCHAR(32)   NOT NULL DEFAULT 'all',

    -- 度量
    sales        NUMERIC(18,2) NOT NULL DEFAULT 0,
    gmv          NUMERIC(18,2) NOT NULL DEFAULT 0,
    gmv2         NUMERIC(18,2) NOT NULL DEFAULT 0,
    its          NUMERIC(18,2) NOT NULL DEFAULT 0,
    its_after    NUMERIC(18,2) NOT NULL DEFAULT 0,
    revenue      NUMERIC(18,2) NOT NULL DEFAULT 0,
    total_cost   NUMERIC(18,2) NOT NULL DEFAULT 0,
    cost         NUMERIC(18,2) NOT NULL DEFAULT 0,
    tax          NUMERIC(18,2) NOT NULL DEFAULT 0,
    spread       NUMERIC(18,2) NOT NULL DEFAULT 0,
    profit       NUMERIC(18,2) NOT NULL DEFAULT 0,
    woa          NUMERIC(18,2) NOT NULL DEFAULT 0,
    saas_fee     NUMERIC(18,2),
    project_cost NUMERIC(18,2),
    deferred     NUMERIC(18,2),

    -- HUN 拆分 (仅 supply/channel)
    hun_u NUMERIC(18,2),
    hun_n NUMERIC(18,2),
    hun_h NUMERIC(18,2),

    -- 环比
    delta_pct NUMERIC(8,4),

    -- 趋势 JSON: {"rangeLabel":"...", "revenue":[...], "cost":[...], "profit":[...]}
    trend JSONB,

    synced_at TIMESTAMPTZ NOT NULL,

    PRIMARY KEY (period_type, period_bucket, dim_type, name, fuel)
);

CREATE INDEX idx_lh_agg_listing
    ON lighthouse_aggregate (period_type, period_bucket, dim_type, fuel, profit DESC);

CREATE INDEX idx_lh_agg_group
    ON lighthouse_aggregate (period_type, period_bucket, dim_type, group_name);
```

### 5.2 详情表

```sql
CREATE TABLE lighthouse_detail (
    period_type   VARCHAR(16)  NOT NULL,
    period_bucket DATE         NOT NULL,
    parent_dim    VARCHAR(16)  NOT NULL,    -- 'product' | 'supply' | 'channel'
    parent_name   VARCHAR(128) NOT NULL,
    child_dim     VARCHAR(16)  NOT NULL,    -- 'supply' | 'channel' | 'product'
    child_name    VARCHAR(128) NOT NULL,
    child_group   VARCHAR(64),
    fuel          VARCHAR(32)  NOT NULL DEFAULT 'all',

    -- 所有度量列 (同主表) ...
    sales NUMERIC(18,2) NOT NULL DEFAULT 0,
    profit NUMERIC(18,2) NOT NULL DEFAULT 0,
    gmv   NUMERIC(18,2) NOT NULL DEFAULT 0,
    cost  NUMERIC(18,2) NOT NULL DEFAULT 0,
    tax   NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- ... 完整 17 列

    PRIMARY KEY (period_type, period_bucket, parent_dim, parent_name, child_dim, child_name, fuel)
);

CREATE INDEX idx_lh_detail_lookup
    ON lighthouse_detail (period_type, period_bucket, parent_dim, parent_name, fuel);
```

### 5.3 折扣进度表

```sql
CREATE TABLE lighthouse_discount (
    period_type   VARCHAR(16)  NOT NULL,
    period_bucket DATE         NOT NULL,
    province      VARCHAR(64)  NOT NULL,    -- 业务实体名（"海南中石油" / "中油BP" / ...）
    mode          VARCHAR(32)  NOT NULL,    -- "阶梯·引流" | "阶梯·门槛" | "阶梯·核销" | "阶梯·年累计" | "固定"
    subtag        VARCHAR(32),              -- "高率待核" | "双月" | "季度" | null
    cur_base      NUMERIC(18,2) NOT NULL,
    next_target   NUMERIC(18,2),            -- null = 封顶/固定
    cur_rate      NUMERIC(6,3)  NOT NULL,
    next_rate     NUMERIC(6,3),
    tier_label    VARCHAR(16),
    rebate        NUMERIC(18,2) NOT NULL,

    PRIMARY KEY (period_type, period_bucket, province)
);
```

折扣阶梯规则表（不变的业务规则，独立维护）：

```sql
CREATE TABLE discount_rule (
    province     VARCHAR(64) NOT NULL,
    mode         VARCHAR(32) NOT NULL,
    tier_no      INT         NOT NULL,
    tier_low     NUMERIC(18,2) NOT NULL,
    tier_high    NUMERIC(18,2),
    rate_pct     NUMERIC(6,3) NOT NULL,
    PRIMARY KEY (province, mode, tier_no)
);
```

---

## 6. Service / Handler 骨架

### 6.1 Period 解析

```go
package lighthouse

import "time"

var cstLoc = time.FixedZone("CST", 8*3600)

// 当前 period bucket (CST 时区)
func ResolveBucket(period string, dateStr string) (time.Time, error) {
    now := time.Now().In(cstLoc)
    if dateStr != "" {
        t, err := time.ParseInLocation("2006-01-02", dateStr, cstLoc)
        if err != nil {
            return time.Time{}, err
        }
        now = t
    }
    switch period {
    case "day":
        return time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, cstLoc), nil
    case "week":
        // 周一 0 点
        w := int(now.Weekday())
        if w == 0 { w = 7 }
        d := now.AddDate(0, 0, -(w - 1))
        return time.Date(d.Year(), d.Month(), d.Day(), 0, 0, 0, 0, cstLoc), nil
    case "month":
        return time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, cstLoc), nil
    case "quarter":
        m := ((int(now.Month())-1)/3)*3 + 1
        return time.Date(now.Year(), time.Month(m), 1, 0, 0, 0, 0, cstLoc), nil
    case "year":
        return time.Date(now.Year(), 1, 1, 0, 0, 0, 0, cstLoc), nil
    default:
        return time.Time{}, fmt.Errorf("unknown period: %s", period)
    }
}
```

### 6.2 Handler

```go
package lighthouse

import (
    "context"
    "net/http"

    "github.com/gin-gonic/gin"
    "golang.org/x/sync/errgroup"
)

type Handler struct {
    svc *Service
}

func (h *Handler) GetOverview(c *gin.Context) {
    period := c.DefaultQuery("period", "month")
    date := c.Query("date")
    fuel := c.DefaultQuery("fuel", "all")

    bucket, err := ResolveBucket(period, date)
    if err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
        return
    }

    ctx := c.Request.Context()
    resp, err := h.svc.LoadOverview(ctx, period, bucket, fuel)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": err.Error()})
        return
    }
    c.JSON(http.StatusOK, gin.H{"success": true, "data": resp})
}
```

### 6.3 Service (并发拉取 5 块数据)

```go
type Service struct {
    repo *Repo
}

func (s *Service) LoadOverview(
    ctx context.Context,
    period string,
    bucket time.Time,
    fuel string,
) (*OverviewResponse, error) {
    var (
        resp OverviewResponse
        hero HeroBlock
    )
    resp.ProductDetail = make(map[string]Detail)
    resp.SupplyDetail  = make(map[string]Detail)
    resp.ChannelDetail = make(map[string]Detail)

    g, gctx := errgroup.WithContext(ctx)

    g.Go(func() error {
        return s.repo.FetchHero(gctx, period, bucket, &hero)
    })
    g.Go(func() error {
        rows, err := s.repo.FetchTab(gctx, period, bucket, "product", fuel)
        resp.Data.Product = rows
        return err
    })
    g.Go(func() error {
        rows, err := s.repo.FetchTab(gctx, period, bucket, "supply", fuel)
        // 给 supply 行 attach discount
        if err == nil {
            err = s.repo.AttachDiscount(gctx, period, bucket, rows)
        }
        resp.Data.Supply = rows
        return err
    })
    g.Go(func() error {
        rows, err := s.repo.FetchTab(gctx, period, bucket, "channel", fuel)
        resp.Data.Channel = rows
        return err
    })
    g.Go(func() error {
        return s.repo.FetchDetails(gctx, period, bucket, fuel, &resp)
    })

    if err := g.Wait(); err != nil {
        return nil, err
    }

    resp.Metrics.LastSyncedAt = time.Now().In(cstLoc)
    resp.Metrics.Hero = hero
    return &resp, nil
}
```

### 6.4 Repo 查询示例

```go
type Repo struct {
    db *sqlx.DB
}

func (r *Repo) FetchTab(
    ctx context.Context,
    period string,
    bucket time.Time,
    dim string,
    fuel string,
) ([]Row, error) {
    const q = `
        SELECT
          name,
          group_name AS "group",
          sales, gmv, gmv2, its, its_after AS "itsAfter",
          revenue, total_cost AS "totalCost", cost, tax,
          spread, profit, woa,
          saas_fee     AS "saasFee",
          project_cost AS "projectCost",
          deferred,
          hun_u AS "hunU", hun_n AS "hunN", hun_h AS "hunH",
          delta_pct AS "deltaPct",
          trend
        FROM lighthouse_aggregate
        WHERE period_type   = $1
          AND period_bucket = $2
          AND dim_type      = $3
          AND fuel          = $4
        ORDER BY profit DESC
        LIMIT 100;
    `
    var rows []Row
    if err := r.db.SelectContext(ctx, &rows, q, period, bucket, dim, fuel); err != nil {
        return nil, err
    }
    return rows, nil
}

func (r *Repo) AttachDiscount(
    ctx context.Context,
    period string,
    bucket time.Time,
    rows []Row,
) error {
    const q = `
        SELECT province, mode, subtag, cur_base AS "cur",
               next_target AS "target", cur_rate AS "curRate",
               next_rate AS "nextRate", tier_label AS "tierLabel",
               rebate
        FROM lighthouse_discount
        WHERE period_type = $1 AND period_bucket = $2;
    `
    type discRow struct {
        Province string `db:"province"`
        Discount
    }
    var list []discRow
    if err := r.db.SelectContext(ctx, &list, q, period, bucket); err != nil {
        return err
    }
    byProv := make(map[string]*Discount, len(list))
    for i := range list {
        byProv[list[i].Province] = &list[i].Discount
    }
    for i := range rows {
        if d, ok := byProv[rows[i].Name]; ok {
            rows[i].Discount = d
        }
    }
    return nil
}
```

### 6.5 Trend JSONB 反序列化

让 `Row.Trend` 直接走 sqlx 的 `Valuer` / `Scanner`：

```go
import "database/sql/driver"

func (t *Trend) Scan(src any) error {
    if src == nil { return nil }
    bytes, ok := src.([]byte)
    if !ok { return fmt.Errorf("expected []byte") }
    return json.Unmarshal(bytes, t)
}

func (t Trend) Value() (driver.Value, error) {
    return json.Marshal(t)
}
```

Row 字段声明改一下，让 sqlx 自动 Scan：

```go
Trend *Trend `db:"trend" json:"trend,omitempty"`
```

---

## 7. ETL 任务（每日 / 实时增量）

按 dart 端"几分钟延迟可接受"的需求，建议：

```
[OLTP 流水表]
    └─ (每 5 分钟) ─→ [stg_lighthouse_raw_<period>]
                            └─ (每 5 分钟) ─→ [lighthouse_aggregate]
                                                   └─ JSONB trend 字段实时维护
[折扣规则表 discount_rule]
    └─ (每月初冻结) ─→ [lighthouse_discount]
```

聚合 SQL 示例（month, product 维度）：

```sql
INSERT INTO lighthouse_aggregate (
    period_type, period_bucket, dim_type, name, group_name, fuel,
    sales, gmv, gmv2, its, its_after,
    revenue, total_cost, cost, tax, spread, profit, woa,
    hun_u, hun_n, hun_h,
    delta_pct, trend, synced_at
)
SELECT
    'month',
    DATE_TRUNC('month', t.tx_date)::date,
    'product',
    p.name,
    p.group_name,
    'all',
    SUM(t.sales), SUM(t.gmv), SUM(t.gmv2),
    SUM(t.its), SUM(t.its_after),
    SUM(t.revenue), SUM(t.total_cost), SUM(t.cost), SUM(t.tax),
    SUM(t.spread), SUM(t.profit), SUM(t.woa),
    SUM(t.hun_u), SUM(t.hun_n), SUM(t.hun_h),
    -- 环比
    CASE WHEN prev.profit > 0
         THEN (SUM(t.profit) - prev.profit) / prev.profit * 100
         ELSE NULL END,
    -- trend JSON: 当月每日 3 序列
    JSONB_BUILD_OBJECT(
        'rangeLabel', TO_CHAR(MIN(t.tx_date), 'MM.DD') || ' — ' || TO_CHAR(MAX(t.tx_date), 'MM.DD'),
        'revenue',    JSONB_AGG(daily.revenue ORDER BY daily.d),
        'cost',       JSONB_AGG(daily.cost    ORDER BY daily.d),
        'profit',     JSONB_AGG(daily.profit  ORDER BY daily.d)
    ),
    NOW()
FROM tx_oltp t
JOIN product p ON p.id = t.product_id
LEFT JOIN LATERAL (
    SELECT profit
    FROM lighthouse_aggregate
    WHERE period_type = 'month'
      AND period_bucket = DATE_TRUNC('month', t.tx_date - INTERVAL '1 month')::date
      AND dim_type = 'product'
      AND name = p.name
) prev ON true
LEFT JOIN (
    SELECT product_id, tx_date AS d,
           SUM(revenue) AS revenue,
           SUM(cost) AS cost,
           SUM(profit) AS profit
    FROM tx_oltp
    GROUP BY product_id, tx_date
) daily ON daily.product_id = t.product_id
GROUP BY p.name, p.group_name, DATE_TRUNC('month', t.tx_date), prev.profit
ON CONFLICT (period_type, period_bucket, dim_type, name, fuel)
DO UPDATE SET
    sales      = EXCLUDED.sales,
    gmv        = EXCLUDED.gmv,
    -- ... 全字段
    delta_pct  = EXCLUDED.delta_pct,
    trend      = EXCLUDED.trend,
    synced_at  = EXCLUDED.synced_at;
```

---

## 8. 配置 (viper)

```yaml
# config.yaml
lighthouse:
  listen_addr: ":6090"
  db_url: "postgres://lighthouse:***@db:5432/heunion?sslmode=disable"
  jwt_secret: "..."
  default_period: "month"
  query_timeout_ms: 3000

logging:
  level: "info"
```

---

## 9. 测试用例（最小）

```go
func TestResolveBucket_Month(t *testing.T) {
    b, _ := ResolveBucket("month", "2026-06-15")
    if b.Day() != 1 || b.Month() != time.June {
        t.Fatalf("bad bucket: %v", b)
    }
}

func TestLoadOverview_HappyPath(t *testing.T) {
    db := setupTestDB(t)
    seedFixtures(t, db)
    svc := &Service{repo: &Repo{db: db}}
    resp, err := svc.LoadOverview(context.Background(), "month", time.Date(2026, 6, 1, 0, 0, 0, 0, cstLoc), "all")
    require.NoError(t, err)
    require.NotEmpty(t, resp.Data.Product)
    require.NotZero(t, resp.Data.Product[0].Profit)
    // ...
}
```

---

## 10. 部署 / 路由

```go
// cmd/lighthouse/main.go
func main() {
    cfg := loadConfig()
    db := mustOpenDB(cfg.Lighthouse.DBURL)
    repo := &lighthouse.Repo{DB: db}
    svc  := &lighthouse.Service{Repo: repo}
    h    := &lighthouse.Handler{Svc: svc}

    r := gin.New()
    r.Use(middleware.Recovery(), middleware.JWT(cfg.Lighthouse.JWTSecret))

    v1 := r.Group("/api/v1")
    v1.GET("/lighthouse/overview", h.GetOverview)

    r.Run(cfg.Lighthouse.ListenAddr)
}
```

---

## 11. 落地路径建议

按优先级 phase 实施：

**Phase 1 (P0, 1 周)** — 把当前 mock 替换为真数据
1. 起 Postgres + `lighthouse_aggregate` 表
2. ETL 写一个简单聚合任务（dim=product/supply/channel, period=month）
3. Go service 起来，handler 接通主表查询
4. 补 `woa` 字段（BE-1）
5. 补 `deltaPct`（BE-2）

**Phase 2 (P0, 1 周)** — 趋势 + 详情
6. ETL 加 `trend` JSONB 聚合（每日 sub-series）
7. `lighthouse_detail` 表 + ETL，Service 拼 `*_detail`
8. 增加 day / week / quarter / year 周期

**Phase 3 (P1, 1 周)** — 折扣 + HUN
9. `discount_rule` + `lighthouse_discount` 表
10. ETL 按规则匹配当月基数生成 discount 行
11. `hun_u/n/h` 字段补齐 (BE-5)

**Phase 4 (P2)** — Hero + 优化
12. Hero block 字段
13. 缓存层（Redis 缓存 5 分钟）
14. 灰度对比 / 监控

---

## 12. 与 Dart 端的契约规则

后端 PR 评审清单（每次改字段时核对）：

- [ ] 新增字段在 `Row` struct 加 `json` tag，名字与 dart `r['xxx']` 完全一致（**camelCase**）
- [ ] 可选字段用指针 + `omitempty`
- [ ] 时间字段统一 RFC3339 + `+08:00`
- [ ] 金额字段统一 float64（元），不要 cent 不要字符串
- [ ] 折扣 / 趋势这类对象字段用嵌套 struct + `*` 指针，避免空 object
- [ ] 任何字段命名变化都要在本文档登记
