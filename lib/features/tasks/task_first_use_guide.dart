import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/dunes_theme.dart';

const _guideVersion = 'v3';

enum TaskGuidePage {
  home,
  detailMain,
  detailSub,
  createMain,
  createSub,
  progress,
  evaluate,
  dailyReport,
  summary,
  assistant,
  assistantActiveTasks,
  meetingCreate,
  quickCreateMain,
  quickCreateSub,
}

class TaskGuideSpec {
  const TaskGuideSpec({
    required this.pageId,
    required this.badge,
    required this.title,
    required this.accent,
    required this.steps,
  });

  final String pageId;
  final String badge;
  final String title;
  final Color accent;
  final List<TaskGuideStepData> steps;
}

class TaskGuideStepData {
  const TaskGuideStepData({
    required this.icon,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String body;
  final List<String> actions;
}

TaskGuideSpec taskGuideSpec(TaskGuidePage page) {
  switch (page) {
    case TaskGuidePage.home:
      return const TaskGuideSpec(
        pageId: 'home',
        badge: '任务中心',
        title: '任务中心怎么用',
        accent: Color(0xFF7B5CD8),
        steps: [
          TaskGuideStepData(
            icon: Icons.view_agenda_outlined,
            title: '先分清两个列表',
            body: '这是任务入口页，不是详情，也不是日报。',
            actions: ['「今日」：看今天要做、待确认的子目标', '「主目标」：只看完整目标，点进去才看到子目标'],
          ),
          TaskGuideStepData(
            icon: Icons.add_box_outlined,
            title: '从右上角新建',
            body: '本页只能新建主目标，不能直接在列表里建子目标。',
            actions: ['点「新建主目标」', '填周期和验收标准后保存', '进入详情再拆子目标'],
          ),
          TaskGuideStepData(
            icon: Icons.edit_calendar_outlined,
            title: '日报在列表上方',
            body: '有待填日报时会出现入口，点进去填写，不是在这张列表里直接改进度。',
            actions: ['点「今日日报」进入填写页'],
          ),
        ],
      );
    case TaskGuidePage.detailMain:
      return const TaskGuideSpec(
        pageId: 'main_detail',
        badge: '主目标详情',
        title: '主目标详情怎么用',
        accent: Color(0xFF5B6FC4),
        steps: [
          TaskGuideStepData(
            icon: Icons.flag_outlined,
            title: '这是主目标，不是执行清单',
            body: '上方是目标本身：负责人、周期、验收标准和汇总进度。',
            actions: ['有子目标时，主目标进度由子目标平均得出，不能手改'],
          ),
          TaskGuideStepData(
            icon: Icons.add_task_outlined,
            title: '拆解从右上角开始',
            body: '子目标不会出现在任务中心默认列表，只在这个详情里管理。',
            actions: ['点「添加子目标」', '指定执行人和验收标准', '下方可点进某个子目标'],
          ),
          TaskGuideStepData(
            icon: Icons.check_circle_outlined,
            title: '办结要单独确认',
            body: '子目标都完成后，系统不会自动结束主目标。',
            actions: ['点「标记完成」确认办结主目标', '「任务评价」由创建人或审核人填写'],
          ),
        ],
      );
    case TaskGuidePage.detailSub:
      return const TaskGuideSpec(
        pageId: 'sub_detail',
        badge: '子目标详情',
        title: '子目标详情怎么用',
        accent: Color(0xFF2F8F7E),
        steps: [
          TaskGuideStepData(
            icon: Icons.task_outlined,
            title: '这是你要执行的事项',
            body: '子目标有自己的负责人、周期和验收标准，完成情况会汇总回主目标。',
            actions: ['顶部可点所属主目标名称返回主目标'],
          ),
          TaskGuideStepData(
            icon: Icons.tune_outlined,
            title: '用本页按钮更新',
            body: '进度、延期、办结都在这个详情里操作，不是在主目标列表里改。',
            actions: ['「更新进度」填写当前完成情况', '「延期」只能改结束时间', '「标记完成」才算办结'],
          ),
          TaskGuideStepData(
            icon: Icons.lock_outline,
            title: '删除权在创建人',
            body: '上级分配给你的子目标，你可以执行，但不能删除。',
            actions: ['没有删除按钮时，说明你不是创建人'],
          ),
        ],
      );
    case TaskGuidePage.createMain:
      return const TaskGuideSpec(
        pageId: 'create_main',
        badge: '新建主目标',
        title: '怎么建主目标',
        accent: Color(0xFFB7791F),
        steps: [
          TaskGuideStepData(
            icon: Icons.edit_note_outlined,
            title: '先写最终要达成什么',
            body: '这里创建的是主目标。保存后不会自动生成子目标。',
            actions: ['填写名称和描述', '选择负责人和分类'],
          ),
          TaskGuideStepData(
            icon: Icons.event_outlined,
            title: '周期和验收都是必填',
            body: '没有开始/结束时间，任务不会进入「今日」和日报。',
            actions: ['选择开始时间和结束时间', '写清验收标准：做到什么程度算完成'],
          ),
          TaskGuideStepData(
            icon: Icons.save_outlined,
            title: '保存后再拆',
            body: '点「保存」后进入主目标详情，再添加子目标。',
            actions: ['点右下角「保存」'],
          ),
        ],
      );
    case TaskGuidePage.createSub:
      return const TaskGuideSpec(
        pageId: 'create_sub',
        badge: '添加子目标',
        title: '怎么添加子目标',
        accent: Color(0xFF0F766E),
        steps: [
          TaskGuideStepData(
            icon: Icons.subdirectory_arrow_right,
            title: '这是挂在主目标下的事项',
            body: '不要写成另一个主目标。名称要能直接执行。',
            actions: ['填写子目标名称', '选择执行人（自己或下级）'],
          ),
          TaskGuideStepData(
            icon: Icons.event_repeat_outlined,
            title: '时间默认跟着主目标',
            body: '打开时会带入主目标的开始和结束日期，可按实际执行再改。',
            actions: ['确认开始/结束时间', '验收标准必须单独填写，不会自动带入'],
          ),
          TaskGuideStepData(
            icon: Icons.person_off_outlined,
            title: '分配后下级不能删',
            body: '被分配人可以更新进度和办结，只有创建人能删除。',
            actions: ['点「保存」完成添加'],
          ),
        ],
      );
    case TaskGuidePage.progress:
      return const TaskGuideSpec(
        pageId: 'update_progress',
        badge: '更新进度',
        title: '怎么更新进度',
        accent: Color(0xFF7B5CD8),
        steps: [
          TaskGuideStepData(
            icon: Icons.linear_scale,
            title: '这是进度弹窗，不是办结',
            body: '拖动进度不会自动把任务标成完成。',
            actions: ['拖动进度条到当前比例', '在「进展说明」写这次完成了什么'],
          ),
          TaskGuideStepData(
            icon: Icons.attach_file,
            title: '需要证据就上传附件',
            body: '保存后会在任务详情的「最近进展」里留下一条记录。',
            actions: ['可选上传文件', '点「保存」'],
          ),
        ],
      );
    case TaskGuidePage.evaluate:
      return const TaskGuideSpec(
        pageId: 'evaluate',
        badge: '任务评价',
        title: '怎么写任务评价',
        accent: Color(0xFF9C5FB5),
        steps: [
          TaskGuideStepData(
            icon: Icons.rate_review_outlined,
            title: '评价不等于改进度',
            body: '这里只写对结果和质量的意见，不会改完成时间。',
            actions: ['填写评价意见（必填）', '必要时上传依据', '点「提交」'],
          ),
        ],
      );
    case TaskGuidePage.dailyReport:
      return const TaskGuideSpec(
        pageId: 'daily_report',
        badge: '任务日报',
        title: '日报怎么填',
        accent: Color(0xFF23856D),
        steps: [
          TaskGuideStepData(
            icon: Icons.today_outlined,
            title: '一人一天一张日报',
            body: '这不是任务详情。这里按日期填写当天工作，并同步回任务进度。',
            actions: ['顶部可切换今天 / 可补填的昨天', '待填任务按颜色区分主目标和子目标'],
          ),
          TaskGuideStepData(
            icon: Icons.edit_note,
            title: '每条任务都要写「今日完成」',
            body: '只拖进度、不写完成内容，无法提交。',
            actions: ['调整当前进度', '填写今日完成', '「下一步」可以不填'],
          ),
          TaskGuideStepData(
            icon: Icons.send_outlined,
            title: '提交后才会同步',
            body: '点「提交日报」后，进度和完成说明会写入对应任务。',
            actions: ['阻塞、其他工作可填在页面下方', '可点「历史日报」查看已提交记录'],
          ),
        ],
      );
    case TaskGuidePage.summary:
      return const TaskGuideSpec(
        pageId: 'summary',
        badge: '任务汇总',
        title: '任务汇总怎么看',
        accent: Color(0xFF3D7A8C),
        steps: [
          TaskGuideStepData(
            icon: Icons.insights_outlined,
            title: '这是管理视图，不能代填',
            body: '用来看部门目标健康度和日报率，不是执行页。',
            actions: ['看顶部的按期完成、风险、逾期、日报率'],
          ),
          TaskGuideStepData(
            icon: Icons.account_tree_outlined,
            title: '按部门往下点',
            body: '路径是：部门 → 人员 → 主目标。点进去是只读详情。',
            actions: ['先选部门', '再点人员看他的目标', '需要改任务请回到任务中心'],
          ),
        ],
      );
    case TaskGuidePage.assistant:
      return const TaskGuideSpec(
        pageId: 'assistant',
        badge: '任务助手',
        title: '任务助手怎么用',
        accent: Color(0xFF2F8F7E),
        steps: [
          TaskGuideStepData(
            icon: Icons.chat_bubble_outline,
            title: '这里是通知流',
            body: '分配任务、会议建议、日报提醒都会推到这个会话，不是任务列表本身。',
            actions: ['点任务卡片进入详情', '点日报卡片进入填写页'],
          ),
          TaskGuideStepData(
            icon: Icons.notifications_active_outlined,
            title: '日报入口在顶部',
            body: '有待填日报时，「日报」旁边会出现红点。',
            actions: ['点「日报」填写当天日报', '点底部「进入任务」看进行中的子目标'],
          ),
        ],
      );
    case TaskGuidePage.assistantActiveTasks:
      return const TaskGuideSpec(
        pageId: 'assistant_active_tasks',
        badge: '进行中的任务',
        title: '进行中的任务怎么用',
        accent: Color(0xFF2563A9),
        steps: [
          TaskGuideStepData(
            icon: Icons.playlist_add_check,
            title: '只列出你正在执行的子目标',
            body: '主目标不会出现在这里。要看完整目标，请回工作台任务中心。',
            actions: ['点卡片进入子目标详情', '点「更新进度」直接改当前进度'],
          ),
        ],
      );
    case TaskGuidePage.meetingCreate:
      return const TaskGuideSpec(
        pageId: 'meeting_create',
        badge: '会议创建任务',
        title: '会议建议怎么变成任务',
        accent: Color(0xFFB45309),
        steps: [
          TaskGuideStepData(
            icon: Icons.account_tree_outlined,
            title: '必须先选定主目标',
            body: '会议建议不能悬空。要么新建主目标，要么挂到已有主目标下变成子目标。',
            actions: ['选「新建主目标」或「关联已有主目标」'],
          ),
          TaskGuideStepData(
            icon: Icons.rule_outlined,
            title: '补齐才能创建',
            body: '负责人和周期、验收标准都要填完。',
            actions: ['选执行人', '确认开始/结束时间', '填写验收标准后保存'],
          ),
        ],
      );
    case TaskGuidePage.quickCreateMain:
      return const TaskGuideSpec(
        pageId: 'quick_create_main',
        badge: '快速新建主目标',
        title: '快速新建主目标',
        accent: Color(0xFF7B5CD8),
        steps: [
          TaskGuideStepData(
            icon: Icons.flash_on_outlined,
            title: '这是精简创建，不是完整表单',
            body: '先起名并选周期，进去后再补验收标准和子目标。',
            actions: ['填写名称', '选择开始和结束时间', '保存后进入详情继续完善'],
          ),
        ],
      );
    case TaskGuidePage.quickCreateSub:
      return const TaskGuideSpec(
        pageId: 'quick_create_sub',
        badge: '快速新建子目标',
        title: '快速新建子目标',
        accent: Color(0xFF2F8F7E),
        steps: [
          TaskGuideStepData(
            icon: Icons.playlist_add,
            title: '必须挂到已有主目标',
            body: '先选所属主目标，再写这条要做的事。',
            actions: ['选择所属主目标', '填写事项名称和周期', '保存后出现在该主目标详情里'],
          ),
        ],
      );
  }
}

Future<void> showTaskFirstUseGuide(
  BuildContext context, {
  required int userId,
  required TaskGuidePage page,
  bool force = false,
}) async {
  final spec = taskGuideSpec(page);
  final prefs = await SharedPreferences.getInstance();
  final storageKey = 'task.guide.$_guideVersion.${spec.pageId}.$userId';
  if (!force && (prefs.getBool(storageKey) ?? false)) return;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => _TaskGuideDialog(key: ValueKey(spec.pageId), spec: spec),
  );
  await prefs.setBool(storageKey, true);
}

class TaskGuideHelpButton extends StatelessWidget {
  const TaskGuideHelpButton({
    super.key,
    required this.onPressed,
    this.color = DunesColors.text2,
  });

  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '使用指引',
      onPressed: onPressed,
      icon: Icon(Icons.help_outline, color: color),
    );
  }
}

class _TaskGuideDialog extends StatefulWidget {
  const _TaskGuideDialog({super.key, required this.spec});

  final TaskGuideSpec spec;

  @override
  State<_TaskGuideDialog> createState() => _TaskGuideDialogState();
}

class _TaskGuideDialogState extends State<_TaskGuideDialog> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant _TaskGuideDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec.pageId != widget.spec.pageId) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final step = spec.steps[_index];
    final last = _index == spec.steps.length - 1;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: spec.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      spec.badge,
                      style: TextStyle(
                        color: spec.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_index + 1}/${spec.steps.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: DunesColors.text3,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('跳过'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                spec.title,
                style: const TextStyle(
                  fontSize: 13,
                  color: DunesColors.text3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: spec.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(step.icon, size: 24, color: spec.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      step.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.text,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                step.body,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: DunesColors.text2,
                ),
              ),
              if (step.actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: spec.accent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final action in step.actions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: spec.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  action,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.45,
                                    color: DunesColors.text,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  for (var i = 0; i < spec.steps.length; i++) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: i == _index ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? spec.accent
                            : const Color(0xFFD9DCE3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    if (i < spec.steps.length - 1) const SizedBox(width: 5),
                  ],
                  const Spacer(),
                  if (_index > 0)
                    TextButton(
                      onPressed: () => setState(() => _index--),
                      child: const Text('上一步'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: spec.accent),
                    onPressed: () {
                      if (last) {
                        Navigator.pop(context);
                      } else {
                        setState(() => _index++);
                      }
                    },
                    child: Text(last ? '开始使用' : '下一步'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
