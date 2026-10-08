# APP 深夜模式检查（2026-10-08）

## 范围与方法

扫描 lib/features 全部 Dart 文件及公共主题、排版；检查固定浅色表面、文字/图标颜色、强制 light 主题、输入装饰、Canvas 绘制及主题切换。候选计数仅供审查，不等于缺陷数量：透明色、阴影、品牌按钮、二维码白底、PDF 纸张、图片预览暗背景及用于尺寸测量的文字可有意固定。

没有逐页访问真实账号、全部权限分支和服务端业务数据；本报告不能作为所有实际页面均可读的保证。

## 本轮修复

- 用户资料：APP 深夜模式使用暗底与分组卡片，增大头像，分离发起群聊入口，突出发消息；保留资料、聊天设置、搜索及头像预览回调。
- 资料/群信息共用底色：去除写死的浅灰底，随主题变化。
- 资料长字段：约束尾部内容，部门/职位长文本可换行，不挤出屏幕；状态长文本在夜间资料头部省略并提供完整提示。
- 群信息开关：白色圆点保持白色，修复深夜下被 surface 转换变暗的问题。
- 工作画像雷达：标签、网格与轮廓响应主题，切换主题触发重绘；数据与计算不变。
- 日报详情：内容卡片、标题和正文接入主题，消除突兀白块。
- PDF：工具栏跟随主题；白色文档纸张上使用明确的深色失败提示，保留文档原色。
- 公共等宽文字：补充中文字体 fallback；夜间聊天/资料副标题改为更易读的正文字体。

## 核对后保留

- 对账表格的两处固定文字颜色只参与 TextPainter 尺寸测量，不直接画到页面。
- 审批表单的 hintStyle 经过 DunesColors.inputDecoration 转换。
- 灯塔、更新页等局部 light Theme 已带深夜模式条件，不强制覆盖深夜。
- 二维码保留白底以便扫描；文档纸张和媒体画布保留原色。
- 灯塔未修改源码。

## 验证

资料日间/深夜、发消息/建群、头像预览、共用开关、画像主题切换、IM 正文/@/链接、NOVA/机器人 markdown、灯塔日期弹层及 PC 原布局回归。19 项针对性测试通过。截图使用测试联系人，不含线上资料。

旧 native_user_work_profile_page_test 在原始 HEAD 源码运行同样为 3 通过、9 失败（包括 Material 祖先和模型断言），不将其计入本轮通过结果。

## 全目录扫描清单

共扫描 582 个业务 Dart 文件，覆盖 42 个模块。

| 模块 | 文件数 | 原始颜色候选 |
| --- | ---: | ---: |
| administrative_notice | 4 | 9 |
| ai_summary | 8 | 1 |
| am_sso | 2 | 0 |
| approval | 3 | 0 |
| approval_assistant | 4 | 1 |
| auth | 13 | 4 |
| broadcast | 2 | 4 |
| chat | 90 | 66 |
| contacts | 6 | 4 |
| contract_register | 4 | 10 |
| conversation | 25 | 20 |
| ctrip | 8 | 0 |
| desktop | 10 | 3 |
| drive | 13 | 18 |
| im | 1 | 0 |
| kb | 9 | 2 |
| kpi | 9 | 25 |
| kpi_assistant | 2 | 0 |
| lighthouse | 36 | 87 |
| meeting | 24 | 12 |
| native | 2 | 5 |
| nova | 40 | 41 |
| payment_invoice | 5 | 4 |
| payroll | 3 | 2 |
| profile | 12 | 29 |
| proposal_intake | 15 | 23 |
| push | 8 | 2 |
| qianji | 66 | 61 |
| qianji_admin | 3 | 36 |
| reconciliation | 16 | 10 |
| robots | 16 | 8 |
| search | 4 | 3 |
| shell | 5 | 8 |
| task_assistant | 5 | 1 |
| tasks | 35 | 43 |
| travel_import | 3 | 12 |
| update | 9 | 5 |
| wechat | 3 | 0 |
| weekly_summary | 3 | 16 |
| workbench | 5 | 2 |
| xflow | 43 | 32 |
| xrxs | 8 | 0 |
