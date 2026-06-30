# 灯塔前端字段清单

> 本文件梳理 Flutter 原生「灯塔」板块当前实际消费的全部字段，作为前后端联调的字段契约。
>
> 主要代码位置：
> - `lib/features/lighthouse/lighthouse_data.dart` — 顶层响应解析（`LighthouseDataBundle.fromJson`）
> - `lib/features/lighthouse/lighthouse_service.dart` — 请求后端 API
> - `lib/features/lighthouse/native_lighthouse_page.dart` — 主 UI、字段消费、指标常量
>
> **数据库对照与待建字段**：见 `docs/lighthouse-database-fields.md`

---

## 1. 接口层

### 请求

```text
GET http://localhost:6090/api/v1/lighthouse/overview?period=month
Authorization: Bearer <token>
```

- 基地址：`http://localhost:6090/api/v1`（可通过 `LIGHTHOUSE_API_BASE` 的 dart-define 覆盖）
- 路径：`/lighthouse/overview`
- `period` 可选值：`day` / `week` / `month` / `quarter` / `year`

### 响应顶层

`LighthouseDataBundle.fromJson` 解析的顶层结构：

| 字段 | 类型 | 是否实际使用 | 说明 |
|------|------|:-----------:|------|
| `data` | object | 是 | 一级列表数据，含 `product` / `supply` / `channel` 三个数组 |
| `product_detail` | object | 是 | 产品详情字典 |
| `supply_detail` | object | 是 | 供给方详情字典 |
| `channel_detail` | object | 是 | 渠道详情字典 |
| `metrics` | object | **否** | 已解析但页面未使用，指标配置写死在前端，可先返回 `{}` |

也支持外层包一层：

```json
{ "success": true, "data": { /* 上述顶层结构 */ } }
```

---

## 2. 一级列表字段

`data.product` / `data.supply` / `data.channel` 均为数组，每行（row）结构如下。

### 所有 tab 通用字段

| 字段 | 类型 | 用途 |
|------|------|------|
| `name` | string | 名称、详情页 key |
| `group` | string | 分类筛选、标签颜色、渠道详情 key |
| `profit` | number | 默认排序、右侧主数字 |
| `sales` | number | Hero、列表 meta、毛利率分母 |
| `gmv` | number | Hero、列表 meta |
| `cost` | number | Hero、列表 meta |
| `tax` | number | 列表 meta |
| `revenue` | number | Hero；缺失时 fallback 到 `sales` |
| `spread` | number | 列表 meta |
| `woa` | number | 列表 meta |

### 各 tab 指标字段全集（`_kMetricByTab`）

- **product**：`sales`, `gmv`, `gmv2`, `its`, `itsAfter`, `spread`, `woa`, `revenue`, `totalCost`, `cost`, `tax`
- **supply**：`sales`, `gmv`, `cost`, `tax`, `spread`, `saasFee`, `woa`, `projectCost`, `deferred`, `discount`
- **channel**：`sales`, `gmv`, `cost`, `tax`, `spread`, `saasFee`, `woa`, `projectCost`, `deferred`

### 前端本地计算（无需后端返回）

| 字段 | 计算方式 |
|------|----------|
| `rate` | `profit / sales * 100`（毛利率） |

---

## 3. 详情页字段

### 详情字典 key 规则

| 类型 | 字典 | key 格式 |
|------|------|----------|
| 产品 | `product_detail` | `产品名称` |
| 供给方 | `supply_detail` | `供给方名称` |
| 渠道 | `channel_detail` | `渠道名称::渠道分类` |

### 详情实体对象

与一级行相同的指标字段，外加 4 个 sub-tab 数组：

| 详情类型 | sub-tab 字段 |
|----------|--------------|
| 产品详情 | `supply`、`channel`、`project`、`productName`（SKU） |
| 供给方详情 | `product`、`channel`、`project`、`productName` |
| 渠道详情 | `product`、`supply`、`project`、`productName` |

### sub-tab 数组内每行

| 字段 | 用途 |
|------|------|
| `name` | 名称 |
| `group` | 分类标签 |
| 各指标字段 | 同一级列表（`sales`、`gmv`、`cost`、`profit` 等） |

---

## 4. 前端写死的配置（不从后端读）

以下为代码常量，不在接口返回里：

| 配置 | 说明 |
|------|------|
| `_kMetricByTab` | 每个 tab 可选指标全集 |
| `_kInitialMetrics` | 每个 tab 默认显示哪些指标 |
| `_kResetMetrics` | 点「默认」重置为 `['sales', 'cost', 'gmv']` |
| `_kHeroMetrics` | Hero 区显示哪些格子和标签 |
| `_kDetailMiniMetrics` | 详情页 mini 指标格 |
| `_kDetailSubTabs` | 详情页 4 个 sub-tab |
| `_kCategoryOverride` | 产品 tab 固定分类列表（全部 / 能源 / 出行 / 运营商 / Fintech） |
| 供给方油品筛选 | 前端比例：汽油 70% / 柴油 30%（非后端字段） |

---

## 5. 后端最小必填字段

每行（一级列表 + sub-tab）至少需要：

```json
{
  "name": "xxx",
  "group": "xxx",
  "sales": 0,
  "gmv": 0,
  "cost": 0,
  "profit": 0
}
```

详情实体再加对应 sub-tab 数组（可以为空 `[]`）。

---

## 6. 完整指标字段对照表

| 字段 key | 中文 | 产品 | 供给方 | 渠道 | 备注 |
|----------|------|:----:|:------:|:----:|------|
| `profit` | 毛利润 | ✓ | ✓ | ✓ | 默认排序字段 |
| `sales` | 销售额 / 规模 | ✓ | ✓ | ✓ | |
| `gmv` | 引流 GMV | ✓ | ✓ | ✓ | |
| `gmv2` | GMV | ✓ | | | 产品专用 |
| `its` | ITS | ✓ | | | |
| `itsAfter` | 折后 ITS | ✓ | | | |
| `spread` | 利差 | ✓ | ✓ | ✓ | |
| `woa` | WOA | ✓ | ✓ | ✓ | |
| `revenue` | 收入 | ✓ | | | 缺失时 fallback `sales` |
| `totalCost` | 成本 | ✓ | | | |
| `cost` | 业务成本 | ✓ | ✓ | ✓ | |
| `tax` | 税务成本 | ✓ | ✓ | ✓ | |
| `projectCost` | 项目成本 | | ✓ | ✓ | |
| `saasFee` | SAAS 服务费 | | ✓ | ✓ | |
| `deferred` | 抵扣延期分润 | | ✓ | ✓ | |
| `discount` | 折扣进度 | | ✓ | | 供给方专用 |
| `rate` | 毛利率 | 本地算 | 本地算 | 本地算 | 无需后端返回 |

---

## 7. 一句话总结

后端返回的 JSON 顶层要有 `data` + 三个 `*_detail`；每行至少 `name`、`group`、`sales`、`gmv`、`cost`、`profit`；指标字段按 tab 补齐第 6 节对照表；`metrics` 顶层字段目前前端未使用，可先返回 `{}`。
