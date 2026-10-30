# 饕智能查询升级计划（后端）

目标：用户用自然语言提问即可识别并查到结果，例如「张三的知识库有多少文档」「技术部本月会议纪要有多少」「李四上个月 IM 会话」「那王五呢」。

已定方案：**模型只解析意图，后端按权限执行并用模板回答**。模型仍然只接收用户问题（以及上一轮的结构化意图），不接收任何业务数据，原有安全约束不变。

涉及代码：`new_dune/qianji-go/cmd/qianji-svc/qianji_chat.go`（新增 `qianji_chat_intent.go`、`qianji_chat_people.go`），不需要数据库迁移。

## 1. 现状与根因

- `chatResolveScope` 只让模型输出板块分类；真正查询靠 `chatAnswer` 里的正则白名单。
- `chatHasUnsupportedQualifier` 会把姓名、部门等未知词判定为"不支持的筛选条件"，直接回复"暂不支持按姓名、部门、状态等条件筛选"，这就是"xxx 员工的知识库有多少"答不了的原因。
- 选"全部板块"时，问题里没写明板块名就回复"还不能确定要查询哪个板块"。
- 相对时间（本月、上月、今年 8 月）只接受明确年月。

下游大多已经支持按人筛选，并且由下游按当前用户 token 做组织权限校验。各接口的返回结构是 `{"success":true,"data":...}`。

下表是"人员表板块配置"，每个板块的按人、按部门查询方式都已核实：

| 板块 | 接口（base） | 按人 | 按部门 | 月份 | 指标字段 |
| --- | --- | --- | --- | --- | --- |
| 知识库 | `GET /api/v1/kb/supervise`（kb） | `q`，匹配 displayName 或 username | `departmentName` 包含匹配，或 `departmentId` | `from`/`to` 毫秒 | `documentCount`、`folderCount`、`uploadedCount`、`minutesCount` |
| IM会话 | `GET /api/v1/ai/sessions/supervise`（flow） | `q`，同上 | 同上 | `from`/`to` | `sessionCount`、`turnCount`、`lastMessageAt` |
| 会议纪要 | `GET /api/v1/ai/meeting-minutes?scope=supervise`（minutes） | `q`，匹配会议标题或组织者 | `departmentId` | 不支持 | 不按人聚合，用返回的 `total` 作为会议数 |
| 研发账号 | `GET /api/v1/qianji/cursor/supervise`（qianji 本地） | `q`，匹配姓名、邮箱或账号 ID | `departmentId` | 不涉及 | 用返回的 `total` 作为账号数 |
| 群响应 | `GET /api/v1/qianji/reply-sla/supervise`（qianji 本地） | `q` | `departmentId>0` | `month` | 每行的响应指标 |
| 日报 | `GET /api/v1/qianji/task-daily-reports/supervise`（qianji 本地） | `q` | `departmentId>0` | 仅 `reportDate`（单日） | 每行的 `status` |
| 使用热力 | `GET /api/v1/analytics/users`（flow） | `q`，匹配 display_name 或 username | `departmentId` | `from`/`to`，默认近 7 天 | `durationMs`、`pv`、`sessionCount`，单次最多 50 条 |
| 任务 | `GET /api/v1/qianji/tasks`（qianji 本地） | `q` 可匹配负责人姓名，但也会匹配任务标题 | 不支持 | `dateFrom`/`dateTo` | `total`、`active`、`completed` |
| 工作情况 | `GET /api/v1/efficiency/work-situation`（flow） | 后端按 `people[].name` 过滤 | 按 `departmentName` 过滤 | `month` | `kbDocuments`、`imSessions`、`meetings` 等 |
| 员工画像 | `GET /api/v1/work-profile/team`（flow） | 后端按 `people[].name` 过滤 | 按 `departmentName` 过滤 | `month` | `taskTotal`、`meetings`、`knowledgeDocuments` 等 |
| 差旅管理 | `GET /api/v1/travel-orders/summary`（flow） | `q`，匹配姓名或部门名 | 同一个 `q` | `from`/`to`（YYYY-MM-DD） | `costFen`、`trips`、`lastTrip` |

需要特别处理的几点：

- **资金借调**：`q` 匹配的是单号、借款主体和付款主体，**不是人名**，所以不能按人查询。
- **会议纪要**：`q` 同时匹配会议标题，"张三"可能命中标题里含"张三"的会议。回答里要注明"按组织者或标题匹配"。另外 dept-stats 接口不支持按月筛选。
- **任务**：`q` 同时匹配任务标题，统计负责人时会被标题干扰。要精确按负责人统计，需要在 qianji 本地先用 `flow.SearchUsers` 查到 userId，再按 `owner_user_id` 过滤。另外，现有 `chatAnswer` 只支持"我的"任务；查他人任务还必须限制在 `subordinateOwnerIDs` 范围内，否则会越权。
- **日报、群响应**：`departmentId=-1`（未分配部门）没有实现，不要使用。
- **部门名换算成 ID**：用户 token 没有可用的部门列表接口。推荐用返回行里的 `departmentName` 做包含匹配。如果一定要用 ID，可以由 qianji 调用服务端的 `ListDepartments`，但要注意按权限范围控制。

## 2. 结构化意图

```go
type chatIntent struct {
    Scope      string `json:"scope"`      // 白名单内的中文板块名；未知为 ""
    Action     string `json:"action"`     // count | list | overview
    Person     string `json:"person,omitempty"`     // 姓名，≤ 20 字，仅汉字/字母/数字/·
    Department string `json:"department,omitempty"` // 部门名，≤ 30 字
    Month      string `json:"month,omitempty"`      // YYYY-MM，后端统一换算
    Status     string `json:"status,omitempty"`     // 已完成/进行中/已结清/未结清/逾期
    Side       string `json:"side,omitempty"`       // 应收/应付
    Category   string `json:"category,omitempty"`   // 渠道/供给
    Mine       bool   `json:"mine,omitempty"`       // "我的"
}
```

校验规则（模型和规则输出都要过）：

- 各字段只接受枚举或长度、字符集受限的值，其余丢弃。
- `Month` 用 `time.Parse("2006-01")` 校验。
- 名字里不能出现"全部、所有、公司、我们"这类泛指词。

## 3. 意图解析：模型优先，规则兜底

**模型解析**：替换 `chatResolveScope`，沿用现有的 `chatLLM*` 配置和 6 秒超时。

- system 提示写明三件事：板块枚举、字段说明、今天的日期（用于把"本月、上月"换算成 YYYY-MM），只输出 JSON，不要回答问题。
- user 消息只放用户问题本身。
- 多轮追问时，额外附上一轮的意图 JSON（不含任何结果），用来支持"那李四呢""上个月呢""已完成的呢"这类追问。
- 用户在界面上手动限定了板块（`scope != 全部板块`）时，强制覆盖模型给出的 `Scope`。

**规则兜底**：模型未配置、超时或输出不合法时使用，同时作为单测基线。

- 板块同义词：文档/知识库 → 知识库；会话/聊天/IM → IM会话；会议/纪要 → 会议纪要；出差/机票/酒店 → 差旅管理；借调/借款 → 资金借调；热力/活跃/使用时长 → 使用热力；流水/余额/现金 → 资金流向；应收/应付/账单 → 月结；账号/cursor → 研发账号；提案 → 提案时效；画像 → 员工画像；效能/工作情况 → 工作情况。
- 部门：`^(.{1,12}?(部|中心|组|团队|事业部|办公室|分公司))`。
- 人员：`([\p{Han}A-Za-z]{2,4})的` 后紧跟板块词，并排除"我、我们、本月、上月、全部、公司"等。
- 动作：列表/有哪些/明细/名单/排名/谁 → `list`；概览/汇总/情况/怎么样 → `overview`；其他情况 → `count`。
- 时间：本月、这个月、上月、上个月、今年 N 月、YYYY 年 N 月、YYYY-MM，都由后端按东八区当前时间换算。

## 4. 执行

1. **按人或按部门**（`Person` 或 `Department` 非空）：走新的"人员表"执行器。
   - 按板块配置调用列表接口：`q=Person`，`size=200`，按需带上 `from`/`to`。
   - 部门筛选在后端完成：`departmentName` 包含 `Department` 的行才保留。这样不需要先把部门名换算成 ID，仍然只在下游返回的权限范围内筛选。
   - 回答模板：
     - 匹配到 0 人：「在你的权限范围内没有找到「张三」，请确认姓名或权限。」
     - 匹配到 1 人：「知识库 · 张三（技术部）：12 份文档、3 个知识库、上传 5 份。」
     - 匹配到多人：「知识库 · 匹配到 3 人：」后跟最多 5 行 `• 姓名 · 部门 · 指标`。
     - 按部门：「知识库 · 技术部共 18 人，合计 230 份文档。」后跟前 5 名。
   - 不支持按人筛选的板块（资金流向、月结、资金借调）明确回复「该板块暂不支持按人员或部门查询」，不允许忽略条件后返回全量数据。
   - 会议纪要、研发账号直接取接口返回的 `total`。工作情况、员工画像在后端拿到 `people[]` 后按姓名或部门过滤。
2. **其他意图**：把意图转成现有规则能识别的标准问句，再交给 `chatAnswer`，最大程度复用现有逻辑和测试。例如：
   - `{知识库, count, month 2026-08}` 转成 `2026-08 知识库有多少文档？`
   - `{任务, count, status 进行中, mine}` 转成 `我的进行中任务有多少？`
   - `{月结, list, side 应收, category 渠道, status 逾期}` 转成 `渠道应收逾期账单列表`
3. **全部板块且识别不出板块**：不再要求用户先选板块，改为回复「没太明白想查哪一块」，并附上 3 条建议问法。

## 5. 持久化与历史重放

- 复用现有的 `query_text` 列：新路径存 `intent:` 加意图 JSON，旧数据保持原样。
- 重放时，以 `intent:` 开头的记录直接按意图执行，不再调用模型，结果稳定且不受模型波动影响；其余记录仍走 `chatAnswer`。
- 每次重放前照旧调用 `scopeAllowed`，权限撤销后的隐藏逻辑不变。

## 6. 接口契约（前端已兼容，字段可选）

- `POST /qianji/chat/{id}/turns` 的返回新增 `suggestions: string[]`，作为追问建议。例如问了张三的知识库后，建议「张三的 IM 会话有多少」「张三本月的会议纪要」。不返回这个字段时，前端用各板块默认的建议。
- `GET /qianji/chat` 的列表项新增 `title`，取该会话第一条问题，最多 30 字。不返回时，前端显示「对话 {id}」。
- `scope` 返回实际识别出的板块，前端据此显示板块标签和"打开原页面"按钮。
- **删除对话（前后端已接入）**：`DELETE /qianji/chat/{id}`。
  - 在 `routeQianjiChat` 里，`len(parts) == 1` 且方法为 DELETE 时执行 `DELETE FROM qianji_chat_conversation WHERE id=$1 AND user_id=$2`。`qianji_chat_turn` 已经设置了 `ON DELETE CASCADE`，各轮问答会一并删除，不需要新增迁移。
  - 影响行数为 0 时返回 404，成功时返回 `{"success":true,"data":null}`。前端对空响应体也做了兼容。
  - 当前代码在 exists 校验之后，只要 `parts[1] != "turns"` 就返回 404。所以新分支要插在 exists 校验之后、这个判断之前。
  - 单测要覆盖三种情况：删除自己的对话成功；删除他人的对话返回 404；对 `/{id}` 发 GET 仍返回 404。

## 7. 实施步骤

1. 按第 1 节的表实现"人员表板块配置"。第一期先做知识库、IM 会话、使用热力、工作情况、员工画像、差旅管理，这几个按人查询的语义是干净的；会议纪要、研发账号、群响应、日报放第二期；任务的负责人统计单独排期。
2. 新增 `qianji_chat_intent.go`：意图结构、校验、规则解析、模型解析，以及意图转标准问句。
3. 新增 `qianji_chat_people.go`：人员表执行器和回答模板。
4. 修改 `routeQianjiChat`：
   - POST 改为：先解析意图，再执行，然后存储意图。
   - GET 改为：按意图重放历史；会话列表增加 `title`。
5. 单测（沿用 `httptest` 和 `sqlmock` 的写法）：
   - 规则解析：覆盖人员、部门、相对月份、追问继承。
   - 模型输出不合法时回退到规则。
   - 模型请求中只包含问题和上一轮意图。
   - 按人查询时透传用户 token 和 `q`，并且只在权限范围内统计。
   - 0 人、1 人、多人三种回答模板。
   - 不支持的板块拒绝人员筛选，不允许忽略条件后返回全量数据。
   - `intent:` 历史的重放，以及权限撤销后的隐藏。
6. 更新 `qianji_chat_deployment.md`：说明模型现在会接收上一轮意图（不含任何结果），以及按人和按部门查询的能力边界。

## 8. 风险

- 同名同姓：匹配到多人时列出部门供用户区分，不自动合并。
- 单次返回条数的上限：权限范围超过上限时，部门合计会不完整。使用热力单次最多 50 条，其他接口暂按 200 条。回复里要注明"按前 N 人统计"，或者改为分页累加。
- 匹配范围不一致：会议纪要、任务、差旅的 `q` 不止匹配人名，回答要写清楚是按什么匹配的，避免把数字误读为"某人的精确统计"。
- 模型延迟：解析意图会增加一次约 1 到 3 秒的调用。问题里写明了板块并且规则能完整解析时，直接跳过模型。
