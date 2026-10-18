import '../auth/auth_session.dart';
import '../lighthouse/lighthouse_service.dart';
import '../tasks/task_api.dart';
import '../tasks/task_models.dart';
import 'nova_personal_plan.dart';

/// 欢迎页和浮层的两个入口。普通聊天不走这里。
enum NovaPersonalCapability { tasks, lighthouse }

class NovaPersonalPrompt {
  const NovaPersonalPrompt({
    required this.capability,
    required this.title,
    required this.subtitle,
    required this.prompt,
  });

  final NovaPersonalCapability capability;
  final String title;
  final String subtitle;
  final String prompt;
}

const novaPersonalPrompts = <NovaPersonalPrompt>[
  NovaPersonalPrompt(
    capability: NovaPersonalCapability.tasks,
    title: '管理我的任务',
    subtitle: '查看本人负责、协同、参与和创建的任务',
    prompt: '帮我看看和我相关的任务',
  ),
  NovaPersonalPrompt(
    capability: NovaPersonalCapability.lighthouse,
    title: '查询灯塔数据',
    subtitle: '看今天的经营总览，只读',
    prompt: '今天灯塔整体怎么样？',
  ),
];

/// 用现有任务、灯塔接口取数。不调用模型，也不改普通对话。
class NovaPersonalReply {
  const NovaPersonalReply(this.text, {this.preview});

  final String text;
  final NovaTaskPreview? preview;
}

/// Bounds client-provided context before it crosses the API boundary.
List<({String role, String text})> novaPersonalContextTurns(
  List<({String role, String text})> history,
) {
  final turns = history
      .where(
        (turn) =>
            (turn.role == 'user' || turn.role == 'assistant') &&
            turn.text.trim().isNotEmpty,
      )
      .toList(growable: false);
  final recent = turns.length > 8 ? turns.sublist(turns.length - 8) : turns;
  return [
    for (final turn in recent)
      (
        role: turn.role,
        text: turn.text.trim().length > 600
            ? '${turn.text.trim().substring(0, 600)}…'
            : turn.text.trim(),
      ),
  ];
}

class NovaTaskPreview {
  const NovaTaskPreview({
    required this.kind,
    required this.summary,
    this.taskId,
    this.body = const {},
  });

  /// progress、complete、create
  final String kind;
  final String summary;
  final int? taskId;
  final Map<String, dynamic> body;
}

/// 用户在输入框明确选了任务或灯塔，但这句话对不上该能力时的说明。
String novaPinnedCapabilityGuide(NovaPersonalCapability capability) {
  switch (capability) {
    case NovaPersonalCapability.tasks:
      return '现在只处理任务。可以说「看看和我相关的任务」，或「创建任务：标题，验收：…，截止：2026-10-23」。';
    case NovaPersonalCapability.lighthouse:
      return '现在只查询灯塔。可以说「今天灯塔整体怎么样」，或「本月毛利前十的产品」。';
  }
}

class NovaPersonalQuery {
  static Future<NovaPersonalReply> run({
    required AuthSession session,
    required NovaPersonalCapability capability,
    String prompt = '',
  }) {
    final text = prompt.trim();
    switch (capability) {
      case NovaPersonalCapability.tasks:
        return _tasks(session);
      case NovaPersonalCapability.lighthouse:
        if (_isRank(text)) return _rank(session);
        if (_isCompare(text)) return _compare(session);
        return _lighthouse(session);
    }
  }

  /// 返回 null 表示这句话仍走原来的聊天。
  static Future<NovaPersonalReply?> tryFollowUp({
    required AuthSession session,
    required NovaPersonalCapability? mode,
    required String text,
    required bool previewPending,
  }) async {
    final value = text.trim();
    if (value.isEmpty) return null;
    final command = value.toLowerCase().replaceAll(RegExp(r'[\s，。！？!?、]'), '');
    if (previewPending && const {'确认', '确认执行'}.contains(command)) {
      return const NovaPersonalReply('请点下方的「确认执行」。对话里打出确认两个字不会写入。');
    }
    if (previewPending && const {'取消', '取消执行', '先不做', '算了'}.contains(command)) {
      return const NovaPersonalReply('已取消，没有写入。');
    }
    if (previewPending) {
      return const NovaPersonalReply('还有一条变更没确认。点确认执行或取消后，再继续说别的。');
    }
    final effective = mode ?? novaPersonalCapabilityFor(value);
    if (effective == NovaPersonalCapability.tasks) {
      if (_isTaskList(value) && !_looksLikeTaskWrite(value)) {
        return _tasks(session);
      }
      final intent = parseNovaTaskIntent(value);
      if (intent != null) return _prepareTask(session, intent);
      if (_looksLikeTaskWrite(value)) {
        return const NovaPersonalReply(
          '办结请说「办结 任务名」。改进度请说「把任务名进度改成 40」。创建请说「创建任务：标题，验收：…，截止：2026-10-23」。点确认执行后才会写入。',
        );
      }
      return null;
    }
    if (effective == NovaPersonalCapability.lighthouse) {
      return null;
    }
    return null;
  }

  /// 按模型给出的工具调用去查。金额只来自接口。
  static Future<NovaPersonalReply> executePlan(
    AuthSession session,
    NovaPersonalPlan plan,
  ) async {
    switch (plan.tool) {
      case 'none':
        final missing = plan.missing.trim();
        return NovaPersonalReply(missing.isEmpty ? '这句话还缺查询条件。' : missing);
      case 'task_list':
        return _tasks(session, query: plan.taskQuery, due: plan.due);
      case 'task_write':
        return _prepareTask(session, _intentFromPlan(plan));
      case 'lighthouse_summary':
        return _lighthouse(
          session,
          period: plan.period,
          date: plan.date,
          offset: plan.offset,
        );
      case 'lighthouse_list':
        return _rankedList(session, plan);
      case 'lighthouse_compare':
        if (plan.subjects.isEmpty) {
          return _compare(session, period: plan.period);
        }
        return _compareSubjects(session, plan);
      default:
        return const NovaPersonalReply('这句话还缺查询条件。');
    }
  }

  static Future<String> execute(
    AuthSession session,
    NovaTaskPreview preview,
  ) async {
    final api = TaskApi(session);
    if (preview.kind == 'create') {
      final created = await api.createMain(preview.body);
      return '已创建任务「${created.title}」。';
    }
    final id = preview.taskId;
    if (id == null || id <= 0) return '没有找到要修改的任务，没有写入。';
    final updated = await api.patchTask(id, preview.body);
    if (updated.hasPendingChange) {
      return '已提交，待审批。任务「${updated.title}」还没有直接改完。';
    }
    if (preview.kind == 'complete') {
      return '已办结「${updated.title}」。';
    }
    return '已写入「${updated.title}」的进度 ${updated.progressPct}%。进度到 100% 不会自动办结。';
  }

  static Future<NovaPersonalReply> _tasks(
    AuthSession session, {
    String query = '',
    String due = '',
  }) async {
    final page = await TaskApi(session).listTasksPage(
      scope: 'self',
      q: query.trim().isEmpty ? null : query.trim(),
      size: query.trim().isEmpty ? 8 : 20,
    );
    final now = DateTime.now();
    final related = page.items
        .where((task) => isNovaSelfTask(task, session.userId))
        .where((task) => _dueMatches(task, due, now))
        .toList(growable: false);
    return NovaPersonalReply(
      formatNovaSelfTasks(
        items: related,
        total: related.length,
        userId: session.userId,
        mayHaveMore: page.hasMore,
      ),
    );
  }

  static Future<NovaPersonalReply> _lighthouse(
    AuthSession session, {
    String period = 'day',
    String date = '',
    int offset = 0,
  }) async {
    if (!session.effectiveLighthouseAccess) {
      return const NovaPersonalReply('暂无灯塔权限。这不是空数据。');
    }
    final day = date.trim().isNotEmpty
        ? date.trim()
        : novaShanghaiDay(DateTime.now());
    final service = LighthouseService(session: session);
    try {
      final summary = await service.fetchSummary(
        period: period,
        date: period == 'day' ? day : null,
        offset: offset == 0 ? null : offset,
      );
      return NovaPersonalReply(formatNovaLighthouseSummary(summary, day: day));
    } catch (error) {
      final text = error.toString();
      if (text.contains('暂无权限') || text.contains('403')) {
        return const NovaPersonalReply('暂无灯塔权限。这不是空数据。');
      }
      return NovaPersonalReply('灯塔数据暂时没有读到：$text');
    } finally {
      service.dispose();
    }
  }

  static bool _isTaskList(String text) {
    if (!text.contains('任务')) return false;
    return text.contains('看看') ||
        text.contains('相关') ||
        text.contains('我的') ||
        text.contains('有哪些') ||
        text.contains('列表') ||
        text.contains('查询');
  }

  static bool _looksLikeTaskWrite(String text) {
    return text.contains('创建') ||
        text.contains('新建') ||
        text.contains('办结') ||
        text.contains('完成任务') ||
        text.contains('进度');
  }

  static bool _isRank(String text) =>
      text.contains('前十') || text.contains('排名');

  static bool _isCompare(String text) =>
      text.contains('比上周') || text.contains('对比');

  static Future<NovaPersonalReply> _rank(AuthSession session) async {
    if (!session.effectiveLighthouseAccess) {
      return const NovaPersonalReply('暂无灯塔权限。这不是空数据。');
    }
    final service = LighthouseService(session: session);
    try {
      final raw = await service.fetchDimension(tab: 'product', period: 'month');
      return NovaPersonalReply(formatNovaProductRank(raw));
    } catch (error) {
      return NovaPersonalReply('灯塔排名暂时没有读到：$error');
    } finally {
      service.dispose();
    }
  }

  static Future<NovaPersonalReply> _rankedList(
    AuthSession session,
    NovaPersonalPlan plan,
  ) async {
    if (!session.effectiveLighthouseAccess) {
      return const NovaPersonalReply('暂无灯塔权限。这不是空数据。');
    }
    final service = LighthouseService(session: session);
    try {
      final raw = await service.fetchDimension(
        tab: plan.tab,
        period: plan.period,
        date: plan.period == 'day' ? plan.date : null,
        offset: plan.offset == 0 ? null : plan.offset,
      );
      final rows = _rowMaps(raw);
      if (plan.subjects.isNotEmpty) {
        final hits = matchNovaSubjectProfits(
          subjects: plan.subjects,
          rows: rows,
        );
        return NovaPersonalReply(
          formatNovaSubjectCompare(
            hits: hits,
            dayLabel: _dayLabel(plan),
            source: '灯塔${_tabLabel(plan.tab)}列表',
          ),
        );
      }
      return NovaPersonalReply(
        formatNovaProductRank(
          {'rows': rows},
          limit: plan.rank == 0 ? 10 : plan.rank,
          objectLabel: _tabLabel(plan.tab),
          periodLabel: _periodLabel(plan.period),
        ),
      );
    } catch (error) {
      if ('$error'.contains('暂无权限') || '$error'.contains('403')) {
        return const NovaPersonalReply('暂无灯塔权限。这不是空数据。');
      }
      return NovaPersonalReply('灯塔列表暂时没有读到：$error');
    } finally {
      service.dispose();
    }
  }

  static Future<NovaPersonalReply> _compareSubjects(
    AuthSession session,
    NovaPersonalPlan plan,
  ) async {
    if (!session.effectiveLighthouseAccess) {
      return const NovaPersonalReply('暂无灯塔权限。这不是空数据。');
    }
    final service = LighthouseService(session: session);
    try {
      final raw = await service.fetchDimension(
        tab: plan.tab,
        period: plan.period,
        date: plan.period == 'day' ? plan.date : null,
        offset: plan.offset == 0 ? null : plan.offset,
      );
      final rows = _rowMaps(raw);
      final groups = <String>{};
      for (final row in rows) {
        final group = (row['group'] ?? '').toString().trim();
        if (group.isNotEmpty) groups.add(group);
      }
      final groupProfits = <String, double>{};
      for (final subject in plan.subjects) {
        String? group;
        for (final name in groups) {
          if (name == subject || name.contains(subject)) {
            group = name;
            break;
          }
        }
        if (group == null) continue;
        final summary = await service.fetchSummary(
          period: plan.period,
          date: plan.period == 'day' ? plan.date : null,
          offset: plan.offset == 0 ? null : plan.offset,
          tab: plan.tab,
          group: group,
        );
        final metrics = _metricsOf(summary);
        final profit = _numOf(metrics, const [
          'profit',
          'grossProfit',
          'gross_profit',
        ]);
        if (profit != null) groupProfits[group] = profit;
      }
      final hits = matchNovaSubjectProfits(
        subjects: plan.subjects,
        rows: rows,
        groupProfits: groupProfits,
      );
      return NovaPersonalReply(
        formatNovaSubjectCompare(
          hits: hits,
          dayLabel: _dayLabel(plan),
          source: '灯塔${_tabLabel(plan.tab)}',
        ),
      );
    } catch (error) {
      if ('$error'.contains('暂无权限') || '$error'.contains('403')) {
        return const NovaPersonalReply('暂无灯塔权限。这不是空数据。');
      }
      return NovaPersonalReply('灯塔对比暂时没有读到：$error');
    } finally {
      service.dispose();
    }
  }

  static Future<NovaPersonalReply> _compare(
    AuthSession session, {
    String period = 'week',
  }) async {
    if (!session.effectiveLighthouseAccess) {
      return const NovaPersonalReply('暂无灯塔权限。这不是空数据。');
    }
    final service = LighthouseService(session: session);
    try {
      final current = await service.fetchSummary(period: period);
      final previous = await service.fetchSummary(period: period, offset: -1);
      return NovaPersonalReply(
        formatNovaWeekCompare(
          current,
          previous,
          periodLabel: _periodLabel(period),
        ),
      );
    } catch (error) {
      return NovaPersonalReply('灯塔对比暂时没有读到：$error');
    } finally {
      service.dispose();
    }
  }

  static NovaTaskIntent _intentFromPlan(NovaPersonalPlan plan) {
    switch (plan.taskAction) {
      case 'complete':
        if (plan.taskName.trim().isEmpty) {
          return const NovaTaskIntent._(
            kind: 'create',
            question: '办结需要任务名称。可以说「办结 任务名」。',
          );
        }
        return NovaTaskIntent._(kind: 'complete', name: plan.taskName.trim());
      case 'progress':
        final pct = plan.progress;
        if (plan.taskName.trim().isEmpty ||
            pct == null ||
            pct < 0 ||
            pct > 100) {
          return const NovaTaskIntent._(
            kind: 'create',
            question: '改进度需要任务名和 0 到 100 的进度。可以说「把任务名进度改成 40」。',
          );
        }
        return NovaTaskIntent._(
          kind: 'progress',
          name: plan.taskName.trim(),
          progress: pct,
        );
      case 'create':
        return parseNovaTaskIntent(
              '创建任务：${plan.title}，验收：${plan.acceptance}，截止：${plan.due}',
            ) ??
            const NovaTaskIntent._(
              kind: 'create',
              question: '创建任务需要标题、验收标准和截止日期。',
            );
      default:
        return NovaTaskIntent._(
          kind: 'create',
          question: plan.missing.trim().isEmpty
              ? '还缺少要修改的任务。'
              : plan.missing.trim(),
        );
    }
  }

  static bool _dueMatches(TaskItem task, String due, DateTime now) {
    final value = due.trim();
    if (value.isEmpty) return true;
    final at = task.dueAt?.toLocal();
    if (at == null) return false;
    if (value == 'today' || value == '今天') {
      return at.year == now.year && at.month == now.month && at.day == now.day;
    }
    if (value == 'week' || value == '本周') {
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 7));
      return !at.isBefore(start) && at.isBefore(end);
    }
    return true;
  }

  static String _periodLabel(String period) {
    switch (period) {
      case 'week':
        return '本周';
      case 'month':
        return '本月';
      default:
        return '今日';
    }
  }

  static String _tabLabel(String tab) {
    switch (tab) {
      case 'product':
        return '产品';
      case 'channel':
        return '渠道';
      default:
        return '供给';
    }
  }

  static String _dayLabel(NovaPersonalPlan plan) {
    if (plan.period == 'day' && plan.date.isNotEmpty) {
      return '${plan.date}（Asia/Shanghai，按天）';
    }
    return '${_periodLabel(plan.period)}（Asia/Shanghai）';
  }

  static Future<NovaPersonalReply> _prepareTask(
    AuthSession session,
    NovaTaskIntent intent,
  ) async {
    if (intent.kind == 'create') {
      final preview = intent.preview;
      if (preview != null) {
        return NovaPersonalReply(
          '${preview.summary}\n开始时间按今天。点确认执行后才会创建。',
          preview: preview,
        );
      }
      return NovaPersonalReply(intent.question ?? '还缺少创建任务需要的内容。');
    }
    final page = await TaskApi(
      session,
    ).listTasksPage(scope: 'self', q: intent.name, size: 20);
    final related = page.items
        .where((task) => isNovaSelfTask(task, session.userId))
        .where((task) => task.title.contains(intent.name))
        .toList(growable: false);
    if (related.isEmpty) {
      return NovaPersonalReply('没有找到名称里包含「${intent.name}」的本人任务，没有写入。');
    }
    if (related.length > 1) {
      final names = related.map((task) => task.title).join('、');
      return NovaPersonalReply('有多条任务都对得上：$names。请说得更完整一些。');
    }
    final task = related.first;
    if (intent.kind == 'progress' &&
        task.parentId == null &&
        task.subtaskCount > 0) {
      return const NovaPersonalReply(
        '这条主任务已经有子任务，进度由子任务汇总，不能直接改进度。办结需要单独说「办结 任务名」。',
      );
    }
    final before = intent.kind == 'complete'
        ? '状态 ${task.displayStatus.isEmpty ? task.status : task.displayStatus}'
        : '进度 ${task.progressPct}%';
    final after = intent.kind == 'complete' ? '办结' : '进度 ${intent.progress}%';
    return NovaPersonalReply(
      '将要修改「${task.title}」\n修改前：$before\n修改后：$after\n点确认执行后才会写入。',
      preview: NovaTaskPreview(
        kind: intent.kind,
        summary: '${task.title}：$before → $after',
        taskId: task.id,
        body: intent.kind == 'complete'
            ? const {'forceComplete': true}
            : {'progressPct': intent.progress, 'progressNote': '来自小饕确认'},
      ),
    );
  }
}

bool isNovaSelfTask(TaskItem task, int userId) {
  return task.ownerUserId == userId ||
      task.creatorUserId == userId ||
      task.approverUserId == userId ||
      task.coOwnerUserIds.contains(userId) ||
      task.participantUserIds.contains(userId);
}

String formatNovaSelfTasks({
  required List<TaskItem> items,
  required int total,
  required int userId,
  bool mayHaveMore = false,
}) {
  if (items.isEmpty) {
    return '没有查到和你相关的任务。范围是你负责、协同、参与或创建的任务，不含下级的任务。';
  }
  final lines = <String>[
    mayHaveMore ? '下面是和你本人相关的任务，后面还有更多。' : '和你本人相关的任务有 $total 条。',
    '范围：本人负责、协同、参与、创建。不含下级任务。',
  ];
  for (final task in items) {
    final due = task.dueAt?.toLocal();
    final dueText = due == null ? '未设截止' : '${due.month}月${due.day}日';
    final status = task.displayStatus.trim().isNotEmpty
        ? task.displayStatus.trim()
        : task.status;
    lines.add(
      '· ${task.title}（${_taskRole(task, userId)}，$status，进度 ${task.progressPct}%，$dueText）',
    );
  }
  lines.add('可以说：办结 任务名，或把任务名进度改成 40。我会先给出变更，等你点确认后再写入。进度到 100% 不会自动办结。');
  return lines.join('\n');
}

String _taskRole(TaskItem task, int userId) {
  if (task.ownerUserId == userId) return '负责人';
  if (task.creatorUserId == userId) return '创建人';
  if (task.coOwnerUserIds.contains(userId)) return '协同';
  if (task.participantUserIds.contains(userId)) return '参与';
  return '相关';
}

String formatNovaLighthouseSummary(
  Map<String, dynamic> summary, {
  required String day,
}) {
  final metrics = summary['metrics'] is Map
      ? Map<String, dynamic>.from(summary['metrics'] as Map)
      : summary;
  final lines = <String>[
    '查询对象：灯塔整体',
    '日期范围：$day（Asia/Shanghai，按天）',
    '数据来源：灯塔当日摘要',
  ];
  final updated = _firstText(summary, const [
    'updatedAt',
    'dataUpdatedAt',
    'asOf',
    'version',
  ]);
  lines.add(updated.isEmpty ? '更新时间：摘要未返回' : '更新时间：$updated');
  final shown = <String>[];
  for (final entry in const [
    ('writeOffAmount', '核销额'),
    ('salesAmount', '销售额'),
    ('sales', '销售额'),
    ('profit', '利润'),
    ('grossProfit', '毛利'),
    ('gmv', 'GMV'),
  ]) {
    final value = metrics[entry.$1];
    if (value is! num) continue;
    shown.add('${entry.$2} ${_amount(value.toDouble())}');
    if (shown.length >= 4) break;
  }
  if (shown.isEmpty) {
    lines.add('这次摘要没有返回可展示的核心指标。不能把失败当成 0。');
  } else {
    lines.add(shown.join('，'));
    lines.add('金额和单位来自灯塔查询，没有另行估算。');
    lines.add('还可以说：本月毛利前十的产品，或本周比上周。');
  }
  return lines.join('\n');
}

String _firstText(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty && text != 'null') return text;
  }
  return '';
}

String _amount(double value) {
  final abs = value.abs();
  if (abs >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(2)}亿';
  }
  if (abs >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
  return value.toStringAsFixed(0);
}

class NovaTaskIntent {
  const NovaTaskIntent._({
    required this.kind,
    this.name = '',
    this.progress = 0,
    this.question,
    this.preview,
  });

  final String kind;
  final String name;
  final int progress;
  final String? question;
  final NovaTaskPreview? preview;
}

NovaPersonalCapability? novaPersonalCapabilityFor(String text) {
  final value = text.trim();
  if (value.isEmpty) return null;
  if (value.contains('灯塔') ||
      value.contains('前十') ||
      value.contains('排名') ||
      value.contains('比上周')) {
    return NovaPersonalCapability.lighthouse;
  }
  if (value.contains('任务') || value.contains('办结') || value.contains('完成任务')) {
    return NovaPersonalCapability.tasks;
  }
  if (value.contains('进度') && RegExp(r'改成|调到|设为|到\s*\d').hasMatch(value)) {
    return NovaPersonalCapability.tasks;
  }
  return null;
}

String normalizeNovaTaskCommand(String text) {
  var value = text.trim();
  final lead = RegExp(r'^(?:请|帮我|我想|我要)\s*');
  while (lead.hasMatch(value)) {
    value = value.replaceFirst(lead, '');
  }
  value = value.replaceFirst(RegExp(r'^创建(?:一个|一条|个)?任务'), '创建任务');
  value = value.replaceFirst(RegExp(r'^新建(?:一个|一条|个)?任务'), '创建任务');
  return value.trim();
}

NovaTaskIntent? parseNovaTaskIntent(String text) {
  final value = normalizeNovaTaskCommand(text);
  final complete = RegExp(r'^(?:办结|完成任务)\s*[《「]?\s*(.+?)\s*[》」]?\s*$');
  final completeMatch = complete.firstMatch(value);
  if (completeMatch != null) {
    final name = completeMatch.group(1)!.trim();
    if (name.isEmpty) return null;
    return NovaTaskIntent._(kind: 'complete', name: name);
  }
  final progress = RegExp(
    r'^(?:把)?\s*[《「]?\s*(.+?)\s*[》」]?\s*(?:的)?进度(?:改成|调到|设为|到)\s*(\d{1,3})\s*%?\s*$',
  );
  final progressMatch = progress.firstMatch(value);
  if (progressMatch != null) {
    final name = progressMatch.group(1)!.trim();
    final pct = int.tryParse(progressMatch.group(2)!);
    if (name.isEmpty || pct == null || pct < 0 || pct > 100) return null;
    return NovaTaskIntent._(kind: 'progress', name: name, progress: pct);
  }
  if (!value.startsWith('创建任务')) return null;
  final title = _field(value, '创建任务');
  final accept = _field(value, '验收');
  final dueText = _field(value, '截止');
  if (title.isEmpty || accept.isEmpty || dueText.isEmpty) {
    return NovaTaskIntent._(
      kind: 'create',
      question: '创建任务需要标题、验收标准和截止日期。例如：创建任务：周报，验收：周五前提交，截止：2026-10-23',
    );
  }
  final due = _parseDue(dueText);
  if (due == null) {
    return NovaTaskIntent._(
      kind: 'create',
      question: '截止日期请写成 2026-10-23，或明天、后天。',
    );
  }
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  return NovaTaskIntent._(
    kind: 'create',
    preview: NovaTaskPreview(
      kind: 'create',
      summary: '创建「$title」\n验收：$accept\n开始：${_day(start)}\n截止：${_day(due)}',
      body: {
        'title': title,
        'acceptanceCriteria': accept,
        'startAt': start.toUtc().toIso8601String(),
        'dueAt': due.toUtc().toIso8601String(),
      },
    ),
  );
}

String formatNovaProductRank(
  Map<String, dynamic> raw, {
  int limit = 10,
  String objectLabel = '产品',
  String periodLabel = '本月',
}) {
  final rows = _rowMaps(raw);
  final ranked = <({String name, double profit})>[];
  for (final row in rows) {
    final name = (row['name'] ?? row['title'] ?? '').toString().trim();
    final profit = _numOf(row, const ['grossProfit', 'profit', 'gross_profit']);
    if (name.isEmpty || profit == null) continue;
    ranked.add((name: name, profit: profit));
  }
  ranked.sort((a, b) => b.profit.compareTo(a.profit));
  final take = limit <= 0 ? 10 : limit;
  final top = ranked.take(take).toList(growable: false);
  if (top.isEmpty) {
    return '$periodLabel$objectLabel排名没有读到毛利。这不是 0。查询对象：$objectLabel。期间：$periodLabel。数据来源：灯塔$objectLabel列表。';
  }
  final lines = <String>[
    '查询对象：$objectLabel',
    '日期范围：$periodLabel（Asia/Shanghai）',
    '指标：毛利',
    '数据来源：灯塔$objectLabel列表，按毛利从高到低取前 ${top.length} 名',
  ];
  for (var i = 0; i < top.length; i++) {
    lines.add('${i + 1}. ${top[i].name}  ${_amount(top[i].profit)}');
  }
  lines.add('排序使用灯塔返回的毛利，没有另行估算。');
  return lines.join('\n');
}

String formatNovaWeekCompare(
  Map<String, dynamic> current,
  Map<String, dynamic> previous, {
  String periodLabel = '本周',
}) {
  final nowMetrics = _metricsOf(current);
  final prevMetrics = _metricsOf(previous);
  final range = periodLabel == '本周'
      ? '本周对比上周（Asia/Shanghai，同一口径）'
      : '$periodLabel对比上一期（Asia/Shanghai，同一口径）';
  final lines = <String>[
    '查询对象：灯塔整体',
    '日期范围：$range',
    '数据来源：灯塔周摘要',
    '未结束的本周按目前已有数据对比，差额由查询结果相减，没有另行归因。',
  ];
  var shown = 0;
  final seen = <String>{};
  for (final entry in const [
    ('profit', '利润'),
    ('grossProfit', '毛利'),
    ('sales', '销售额'),
    ('salesAmount', '销售额'),
    ('writeOffAmount', '核销额'),
  ]) {
    final a = nowMetrics[entry.$1];
    final b = prevMetrics[entry.$1];
    if (a is! num || b is! num) continue;
    if (!seen.add(entry.$2)) continue;
    final delta = a.toDouble() - b.toDouble();
    lines.add(
      '${entry.$2}：$periodLabel ${_amount(a.toDouble())}，上一期 ${_amount(b.toDouble())}，差额 ${_amount(delta)}',
    );
    shown++;
    if (shown >= 3) break;
  }
  if (shown == 0) {
    lines.add('两次摘要都没有可对比的核心指标。不能把缺数当成没有变化。');
  }
  return lines.join('\n');
}

Map<String, dynamic> _metricsOf(Map<String, dynamic> summary) {
  final metrics = summary['metrics'];
  if (metrics is Map) return Map<String, dynamic>.from(metrics);
  return summary;
}

List<Map<String, dynamic>> _rowMaps(dynamic node) {
  if (node is List) {
    return node
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
  if (node is Map) {
    for (final key in const ['rows', 'items', 'list', 'product', 'data']) {
      final found = _rowMaps(node[key]);
      if (found.isNotEmpty) return found;
    }
  }
  return const [];
}

double? _numOf(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if (value is num) return value.toDouble();
  }
  return null;
}

String _field(String text, String label) {
  final match = RegExp(
    '$label[：:]\\s*(.+?)(?=\\s*(?:验收|截止)[：:]|\$)',
  ).firstMatch(text);
  return match?.group(1)?.trim().replaceAll(RegExp(r'[，,]\s*$'), '') ?? '';
}

DateTime? _parseDue(String text) {
  final now = DateTime.now();
  if (text == '明天') return DateTime(now.year, now.month, now.day + 1, 23, 59);
  if (text == '后天') return DateTime(now.year, now.month, now.day + 2, 23, 59);
  final match = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$').firstMatch(text);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  return DateTime(year, month, day, 23, 59);
}

String _day(DateTime time) =>
    '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
