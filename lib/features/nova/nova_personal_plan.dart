import 'dart:convert';

/// 模型只许返回这份结构。金额不从这里读，查询结果由接口填写。
class NovaPersonalPlan {
  const NovaPersonalPlan({
    required this.tool,
    this.period = 'day',
    this.date = '',
    this.offset = 0,
    this.tab = 'supply',
    this.subjects = const [],
    this.rank = 0,
    this.taskQuery = '',
    this.taskAction = '',
    this.taskName = '',
    this.progress,
    this.title = '',
    this.acceptance = '',
    this.due = '',
    this.missing = '',
  });

  /// lighthouse_summary、lighthouse_list、lighthouse_compare、task_list、task_write、none
  final String tool;
  final String period;
  final String date;
  final int offset;
  final String tab;
  final List<String> subjects;
  final int rank;
  final String taskQuery;
  final String taskAction;
  final String taskName;
  final int? progress;
  final String title;
  final String acceptance;
  final String due;
  final String missing;
}

const novaLighthouseTabs = <String>{'supply', 'product', 'channel'};

DateTime novaShanghaiNow(DateTime now) =>
    now.toUtc().add(const Duration(hours: 8));

String novaShanghaiDay(DateTime now) {
  final day = novaShanghaiNow(now);
  final y = day.year.toString().padLeft(4, '0');
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String novaPersonalPlanPrompt({
  required bool tasks,
  required DateTime now,
}) {
  final today = novaShanghaiDay(now);
  final shared = '''
今天是 $today（Asia/Shanghai）。
只输出一个 JSON 对象，不要写解释，不要写金额。
对不上就用 {"tool":"none","missing":"缺什么"}。
禁止查询人效、资金池、净TA、运营成本。tab 只能是 supply、product、channel。
period 只能是 day、week、month。offset 只能是 0 或 -1。
''';
  if (tasks) {
    return '''
$shared
你在处理任务。可选：
{"tool":"task_list","taskQuery":"名称关键词，可空","due":"today 或 week 或空"}
{"tool":"task_write","taskAction":"create","title":"","acceptance":"","due":"YYYY-MM-DD"}
{"tool":"task_write","taskAction":"progress","taskName":"","progress":40}
{"tool":"task_write","taskAction":"complete","taskName":""}
创建、改进度、办结只生成待确认内容，不要声称已经写入。
''';
  }
  return '''
$shared
你在查询灯塔。可选：
{"tool":"lighthouse_summary","period":"day","date":"$today","offset":0}
{"tool":"lighthouse_list","tab":"product","period":"month","rank":10}
{"tool":"lighthouse_compare","period":"day","date":"$today","tab":"supply","subjects":["中石化","中石油"]}
{"tool":"lighthouse_compare","period":"week","offset":0,"subjects":[]}
subjects 为空且要和上一期比时，用 lighthouse_compare 且 subjects 为空。
两个公司或分组比利润时，把名称放进 subjects，不要改去查整体。
''';
}

NovaPersonalPlan? parseNovaPersonalPlan(
  String raw, {
  required bool tasks,
  DateTime? now,
}) {
  final json = _jsonObject(raw);
  if (json == null) return null;
  final tool = (json['tool'] ?? '').toString().trim();
  if (tool.isEmpty) return null;
  final metric = (json['metric'] ?? '').toString().trim();
  if (_blockedMetric(metric) || _blockedMetric(tool)) return null;
  final tab = _tab(json['tab']);
  if (tab == null) return null;
  final period = _period(json['period']);
  final offset = json['offset'] == -1 ? -1 : 0;
  final date = _date(json['date'], period: period, now: now ?? DateTime.now());
  final subjects = _subjects(json['subjects']);
  final rank = _rank(json['rank']);
  final missing = (json['missing'] ?? '').toString().trim();
  if (tool == 'none') {
    return NovaPersonalPlan(tool: 'none', missing: missing);
  }
  if (tasks) {
    if (tool != 'task_list' && tool != 'task_write') return null;
    final action = (json['taskAction'] ?? '').toString().trim();
    final progress = int.tryParse('${json['progress'] ?? ''}');
    return NovaPersonalPlan(
      tool: tool,
      taskQuery: (json['taskQuery'] ?? '').toString().trim(),
      taskAction: action,
      taskName: (json['taskName'] ?? '').toString().trim(),
      progress: progress,
      title: (json['title'] ?? '').toString().trim(),
      acceptance: (json['acceptance'] ?? '').toString().trim(),
      due: (json['due'] ?? '').toString().trim(),
      missing: missing,
    );
  }
  if (tool != 'lighthouse_summary' &&
      tool != 'lighthouse_list' &&
      tool != 'lighthouse_compare') {
    return null;
  }
  return NovaPersonalPlan(
    tool: tool,
    period: period,
    date: date,
    offset: offset,
    tab: tab,
    subjects: subjects,
    rank: rank,
    missing: missing,
  );
}

class NovaSubjectProfit {
  const NovaSubjectProfit({
    required this.subject,
    required this.label,
    this.profit,
  });

  final String subject;
  final String label;
  final double? profit;

  bool get found => profit != null;
}

List<NovaSubjectProfit> matchNovaSubjectProfits({
  required List<String> subjects,
  required List<Map<String, dynamic>> rows,
  Map<String, double> groupProfits = const {},
}) {
  return [
    for (final subject in subjects)
      _matchOne(subject, rows, groupProfits),
  ];
}

String formatNovaSubjectCompare({
  required List<NovaSubjectProfit> hits,
  required String dayLabel,
  required String source,
}) {
  final lines = <String>[
    '查询对象：${hits.map((hit) => hit.subject).join('、')}',
    '日期范围：$dayLabel',
    '指标：利润',
    '数据来源：$source',
  ];
  final missing = hits.where((hit) => !hit.found).map((hit) => hit.subject);
  if (missing.isNotEmpty) {
    lines.add('灯塔里没有「${missing.join('、')}」。没有拿别的名称充数。');
  }
  final found = hits.where((hit) => hit.found).toList(growable: false);
  for (final hit in found) {
    lines.add('${hit.label} ${_amount(hit.profit!)}');
  }
  if (found.length == 2) {
    final delta = found[0].profit! - found[1].profit!;
    lines.add(
      '差额（${found[0].label} − ${found[1].label}）${_amount(delta)}',
    );
  }
  if (found.isNotEmpty) {
    lines.add('金额来自灯塔查询，没有另行估算。');
  }
  return lines.join('\n');
}

Map<String, dynamic>? _jsonObject(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
  final fenced = fence.firstMatch(text);
  if (fenced != null) text = fenced.group(1)!.trim();
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final decoded = jsonDecode(text.substring(start, end + 1));
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

bool _blockedMetric(String value) {
  const blocked = ['人效', '资金池', '净TA', '净ta', '运营成本', 'people', 'netTa', 'fund'];
  return blocked.any(value.contains);
}

String? _tab(Object? raw) {
  final value = (raw ?? 'supply').toString().trim();
  if (value.isEmpty) return 'supply';
  if (!novaLighthouseTabs.contains(value)) return null;
  return value;
}

String _period(Object? raw) {
  final value = (raw ?? 'day').toString().trim();
  if (value == 'week' || value == 'month') return value;
  return 'day';
}

String _date(Object? raw, {required String period, required DateTime now}) {
  final value = (raw ?? '').toString().trim();
  if (period != 'day') return '';
  if (value.isEmpty || value == 'today' || value == '今天') {
    return novaShanghaiDay(now);
  }
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return novaShanghaiDay(now);
  return value;
}

List<String> _subjects(Object? raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final item in raw) {
    final text = item.toString().trim();
    if (text.isEmpty || out.contains(text)) continue;
    out.add(text);
    if (out.length >= 4) break;
  }
  return out;
}

int _rank(Object? raw) {
  final value = int.tryParse('$raw') ?? 0;
  if (value <= 0) return 0;
  if (value > 20) return 20;
  return value;
}

NovaSubjectProfit _matchOne(
  String subject,
  List<Map<String, dynamic>> rows,
  Map<String, double> groupProfits,
) {
  String? group;
  for (final row in rows) {
    final rowGroup = (row['group'] ?? '').toString().trim();
    if (rowGroup.isNotEmpty && _sameName(subject, rowGroup)) {
      group = rowGroup;
      break;
    }
  }
  if (group != null && groupProfits.containsKey(group)) {
    return NovaSubjectProfit(
      subject: subject,
      label: group,
      profit: groupProfits[group],
    );
  }
  final direct = groupProfits[subject];
  if (direct != null) {
    return NovaSubjectProfit(subject: subject, label: subject, profit: direct);
  }
  final named = <Map<String, dynamic>>[];
  for (final row in rows) {
    final rowGroup = (row['group'] ?? '').toString().trim();
    final name = (row['name'] ?? row['title'] ?? '').toString().trim();
    if (group != null && rowGroup == group) {
      named.add(row);
      continue;
    }
    if (_sameName(subject, name)) named.add(row);
  }
  if (named.isEmpty) {
    return NovaSubjectProfit(subject: subject, label: subject);
  }
  var sum = 0.0;
  var any = false;
  for (final row in named) {
    final profit = _numOf(row, const ['grossProfit', 'profit', 'gross_profit']);
    if (profit == null) continue;
    sum += profit;
    any = true;
  }
  final label = group ??
      (named.length == 1
          ? (named.first['name'] ?? subject).toString()
          : subject);
  return NovaSubjectProfit(
    subject: subject,
    label: label,
    profit: any ? sum : null,
  );
}

bool _sameName(String subject, String candidate) {
  if (subject.isEmpty || candidate.isEmpty) return false;
  return candidate == subject || candidate.contains(subject);
}

double? _numOf(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if (value is num) return value.toDouble();
  }
  return null;
}

String _amount(double value) {
  final abs = value.abs();
  if (abs >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(2)}亿';
  }
  if (abs >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
  return value.toStringAsFixed(0);
}
