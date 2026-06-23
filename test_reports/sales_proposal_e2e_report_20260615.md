# 销售提案全流程 E2E 测试报告

| 项目 | 内容 |
|------|------|
| 测试时间 | 2026-06-15 |
| 测试账号 | 15268642022（王奕凡，userId=2） |
| 环境 | 本机 Docker + API 网关 `http://127.0.0.1:6090/api/v1` |
| 测试方式 | API 自动化（等价 App 内 XFlow 提交 + 审批待办完成） |

---

## 1. 结论摘要

| 项 | 结果 |
|----|------|
| 登录（15268642022 / 验证码 66666） | ✅ 通过 |
| 清库（删除历史草稿提案） | ✅ 已删除 8 条 DRAFT |
| 填写并提交销售提案 | ✅ 提案 #16 提交成功 |
| 三级审批链走通 | ✅ 3 步全部 APPROVED（旧链：直属上级→事业部→技术） |
| 审批链与产品设计对齐 | ✅ V50 迁移已应用（部门主管→邓艳丽→技术→归档留痕） |
| 提案终态 | ✅ `APPROVED` |
| Zeebe 自动编排（proposal-to-live） | ❌ BPMN 未部署，流程未自动启动 |
| 「我的」三处数量是否为假数据 | ⚠️ 见下文第 2 节 |

**整体结论**：销售提案 **表单提交 + 三级审批业务逻辑可用**；当前环境 **Zeebe 流程定义未部署**，App 点「提交审批」后不会自动生成待办，需修复 BPMN 部署或启用 `start-sync` 联调路径后，App 内才能无人工干预走通全流程。

---

## 2. 「我的」三个数量：是不是假的？

### 2.1 界面上的数字来源

`index.html` 里 **默认写死了演示数据**（例如「28 份」「12 待我审」「3」等），首次打开会显示这些占位值。

### 2.2 真实数据来源

进入「我的」并联网后，前端会调用：

- `GET /workbench/my-stats` — 统计接口（**读数据库**）
- `GET /xflow/proposals/mine` — 我的提案列表（**读数据库**）

`workbench_live.js` 中的 `refreshB2Menu()` 会用接口返回值刷新：

- **我发起的审批**（B14）：`initiatedByMe` / `approvalPending` / `approvalRejected`
- **我发起的提案**（P1）：`proposalTotal` 及各状态拆分
- **我审批的**（B1）：`pendingForMe` / `handledThisMonth`

因此：**不是永久假数据**；未拉接口前是 HTML 占位，拉接口后是 **PostgreSQL 真实统计**。

### 2.3 本次清库前后对比（王奕凡 userId=2）

| 阶段 | proposalTotal | proposalDrafts | proposalPending | proposalApproved | initiatedByMe | pendingForMe |
|------|---------------|----------------|-----------------|------------------|---------------|--------------|
| 清库前 | 8 | 8 | 0 | 0 | 0 | 0 |
| 清库后 | 0 | 0 | 0 | 0 | 0 | 0 |
| 全流程后 | 1 | 0 | 0 | 1 | 1 | 0 |

**已执行清库**：通过 `DELETE /xflow/proposals/{id}` 删除 8 条 DRAFT 提案（id 7–15）。

### 2.4 已知前端缺口

`loadB2Workbench()` 仅更新顶部 **quick-stats** 四格，**不会**自动刷新「我的事项」三条菜单文案；需 `WorkbenchLive.refreshMyProposals()` 才会更新那三个数字。若 App 内仍显示 28/12/3，多半是 **未触发 refreshB2Menu**，而非接口返回假数。

---

## 3. 测试用例执行记录

### 3.1 环境准备

1. 确认 `dunes-flow-go` 以 `ZEEBE_ENABLED=true` 运行（原容器为 `false`，已重建）。
2. Zeebe 容器 `flow-svc-zeebe-1` 已运行，但 **BPMN 未部署**（见 3.4）。

### 3.2 提交销售提案

**接口**：`POST /xflow/templates/sales-proposal/submit`

**主要字段**（与 App 表单一致）：

| 字段 | 值 |
|------|-----|
| title | E2E Auto Sales Proposal 20260615 |
| launchDate | 2026-07-15 |
| txType / goodType | 销售 / 虚拟商品 |
| tag1 | COUPON |
| provinces | 湖北省 |
| owner1 | userId=2（王奕凡） |
| owner1Level | B |
| techPlatform | 蓝鲸 |
| targetMonthlyScaleWan | 50 |
| needAdvanceFund | 否 |
| solutionDesc | E2E full flow test... |

**结果**：

- `proposalId = 16`
- `status = PENDING`
- `mode = zeebe`

### 3.3 审批流程（设计 vs 实际）

截图中的展示链路：

```
发起人提交 → 部门主管 → 财务总监·邓艳丽 → 技术审批 → 归档留痕 → 审批通过
```

**数据库模板 `sales-proposal` 当前 4 个阶段**（`xflow_template_stage`，V50 迁移后）：

| 步骤 | 阶段名 | 类型 | 实际审批人 |
|------|--------|------|------------|
| 1 | 部门主管 | DIRECT_SUP | 朱子姝（id=1，13329736325） |
| 2 | 财务总监 | USER | 邓艳丽（id=13，13164111149） |
| 3 | 技术审批 | ROLE=TECH | 缪承恭（id=5，蓝鲸标签）等 |
| 4 | 归档留痕 | SYSTEM | 系统自动（不产生待办） |

**展示层**：`layout_json.approvalFlow` 补充「发起人提交」「审批通过」首尾节点，与 App 示意图一致。

**人工待办**：`start-sync` 验证 approval #2 生成 3 步待办（朱子姝 → 邓艳丽 → 缪承恭），`SYSTEM` 阶段已跳过。

### 3.4 Zeebe 阻塞点

提交后 `flow-go` 日志：

```
start zeebe process failed processId=proposal-to-live
error: process definition with process ID 'proposal-to-live' not found
```

因此：

- 无 `approval` 记录、无 `todo` 待办自动生成
- 审批人 inbox 为空

**补救（本次测试采用）**：`POST /approvals/start-sync` 手动启动同步审批链（`templateKey=sales-proposal`），生成 approval #1 及 3 个待办。

**生产/App 修复建议**：部署 `flow-svc/bpmn/` 下至少：

- `approval-route.bpmn`
- `proposal-to-live.bpmn`

到 Zeebe（26500），并确认 `flow-go` 连上 Zeebe。

### 3.5 三级审批执行

| 步骤 | 审批人手机 | 待办 todoId | 操作 | 结果 |
|------|------------|-------------|------|------|
| 1 直属上级 | 13329736325 | 1 | APPROVED | ✅ |
| 2 事业部 | 18627190358 | 2 | APPROVED | ✅ |
| 3 技术 | 18271680648 | 3 | APPROVED | ✅ |

### 3.6 终态校验

| 检查项 | 结果 |
|--------|------|
| `proposal.status` | `APPROVED` |
| `approval.status` | `APPROVED`（current_step=3） |
| `workbench/my-stats` | proposalApproved=1, initiatedByMe=1, handledThisMonth=1 |
| 待办 inbox | 全部完成，openTodos=0 |

---

## 4. 缺陷与建议

| 优先级 | 问题 | 建议 |
|--------|------|------|
| P0 | Zeebe 未部署 `proposal-to-live`，App 提交后无待办 | 启动时自动 deploy BPMN，或文档化 zbctl/CI 部署步骤 |
| ~~P1~~ | ~~审批链与 UI 示意图不一致~~ | ✅ 已通过 `V50__sales_proposal_approval_chain.sql` 修复 |
| ~~P2~~ | ~~B2 三条菜单数字未联动~~ | ✅ `loadB2Workbench` 已调用 `refreshMyProposals` |
| ~~P2~~ | ~~index.html 静态占位 28/12~~ | ✅ 「我发起的提案」默认改为 0 |

---

## 5. 附录：关键 API

```http
POST /auth/sms/token          { "phone":"15268642022", "code":"66666" }
GET  /workbench/my-stats
GET  /xflow/proposals/mine
POST /xflow/templates/sales-proposal/submit
POST /approvals/start-sync    { "businessType":"PROPOSAL", "businessId":16, "initiatorId":2, "templateKey":"sales-proposal" }
POST /todos/{id}/complete     { "decision":"APPROVED", "comment":"..." }
DELETE /xflow/proposals/{id}  （仅 DRAFT / PENDING_INITIATE）
```

---

*报告由自动化脚本 + 数据库校验生成。*
