# XFlow 销售提案配置化发布与回滚手册

## 灰度顺序

1. **先发后端（flow-go）**
   - 包含 `GET /api/v1/workbench/config`。
   - 包含提案 `template_key` 去硬编码与 `proposal.template_key` 兼容回退逻辑。
2. **执行 DB migration**
   - `V69__workbench_menu_page_config_and_proposal_template_key.sql`
   - `V70__sales_proposal_excel_upload_page_mode.sql`（默认 `pageMode=excel-upload`）
3. **admin-web 发布模板配置**
   - 在模板设计器 `layoutJson.detailConfig.recognitionConfig` 维护识别规则。
   - 在工作台菜单 `/business/proposals/new` 的 `pageConfig.templateKey` 配置目标模板。
4. **最后发 Flutter**
   - B2 快捷入口优先消费 `workbench/config.templateBindings`。
   - 缺失配置时自动降级到 `sales-proposal`。

## 验证清单

- B2 “我的”页不再出现合同入口。
- B2 快捷入口点击“销售提案”在 `pageMode=excel-upload` 时进入 **提案上传页（XFU）**。
- `pageMode=xflow-form` 时仍进入 XF 动态表单（回退路径）。
- 服务端返回 `workbench/config`，包含 `menuTree`、`templateBindings` 与 `pageBindings`。
- 修改 `pageConfig.templateKey` / `pageConfig.pageMode` 后，前端重进页面可切换模板或页面模式。
- 模板 `detailConfig.recognitionConfig` 修改后，`/xflow/templates/{key}/detail-config` 可看到同步结果。
- 提案草稿、推送代发起、发起审批、驳回重提链路均可通过。

## 回滚预案

1. **配置回滚（优先）**
   - 将 `/business/proposals/new` 的 `pageConfig.pageMode` 改回 `xflow-form`（恢复手填表单）。
   - 或将 `pageConfig.templateKey` 改回 `sales-proposal`。
2. **前端降级（无需重发）**
   - 即使 `workbench/config` 异常，Flutter 自动 fallback 到 `sales-proposal`。
3. **后端紧急回滚**
   - 回滚到旧版本时，`proposalTemplateKey()` 内置缺列兼容与默认值，不会阻断线上提交流程。

## 观察指标

- `workbench/config` 5xx 比例。
- XF 页面打开成功率、模板加载成功率。
- 提案提交成功率（含重提）。
- 审批链路成功率（待审、通过、驳回闭环）。
