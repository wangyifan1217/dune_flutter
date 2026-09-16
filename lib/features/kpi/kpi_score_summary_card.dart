import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../profile/work_profile_kpi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 工作台「转发到 IM」的月度绩效汇总卡
//
// 旧版转发的是一张 Markdown 表格：六列硬塞进聊天气泡，「绩效等级 / 绩效系数」
// 两列被挤出右边只剩「辅（」半个字；全员 0.00 同色同重，领导翻开消息看不出
// 「整体怎么样、谁好谁差、分布如何」这三件事，只能一行一行横着扫。
//
// 这版把它当成一张给领导看的汇总卡：
//   · 顶部三格总览：人数 / 均分 / 项目绩效系数（整体绩效评价表 10 分制得分按档取 0.7–1.1）
//   · 等级分布条：优良中普改辅按人数分段上色，一眼看出结构
//   · 按这个人计分的板块分组（运营商/能源看任务，不看名册部门）：序号 · 姓名 / 岗位 · 得分 + 等级 + 系数
//   · 超过 [kKpiSummaryCollapsedRows] 人先收起，点「展开全部」
//
// 消息正文仍然是原来那段 Markdown（给会话列表预览、复制、老版本客户端兜底），
// 结构化数据走 payload['kpiSummary']；老消息没有结构化数据时，从 Markdown
// 表格里解析回来，历史转发也能直接变成卡片。
// ═══════════════════════════════════════════════════════════════════════════

const int kKpiSummaryCollapsedRows = 8;

/// 等级展示顺序（高 → 低）。
const List<String> kKpiGradeOrder = ['优', '良', '中', '普', '改', '辅'];

class KpiScoreSummaryRow {
  const KpiScoreSummaryRow({
    required this.rank,
    required this.name,
    this.department = '',
    this.position = '',
    this.score = 0,
    this.gradeCode = '',
    this.gradeLabel = '',
    this.coefficient = 0,
    this.pending = false,
    this.skipped = false,
    this.skipLabel = '',
    this.projectScore,
  });

  final int rank;
  final String name;
  final String department;
  final String position;
  final double score;
  final String gradeCode;
  final String gradeLabel;
  final double coefficient;
  final bool pending;
  final bool skipped;
  final String skipLabel;
  final double? projectScore;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'rank': rank,
    'name': name,
    'department': department,
    'position': position,
    'score': score,
    'grade': gradeCode,
    'gradeLabel': gradeLabel,
    'coefficient': coefficient,
    if (pending) 'pending': true,
    if (skipped) 'skipped': true,
    if (skipLabel.isNotEmpty) 'skipLabel': skipLabel,
    if (projectScore != null) 'projectScore': projectScore,
  };

  factory KpiScoreSummaryRow.fromJson(Map<String, dynamic> json, int index) {
    final label = '${json['gradeLabel'] ?? ''}'.trim();
    var code = '${json['grade'] ?? ''}'.trim();
    if (code.isEmpty) code = kpiGradeCodeFromLabel(label);
    return KpiScoreSummaryRow(
      rank: (json['rank'] as num?)?.toInt() ?? index + 1,
      name: '${json['name'] ?? ''}'.trim(),
      department: '${json['department'] ?? ''}'.trim(),
      position: '${json['position'] ?? ''}'.trim(),
      score: (json['score'] as num?)?.toDouble() ?? 0,
      gradeCode: code,
      gradeLabel: label,
      coefficient: (json['coefficient'] as num?)?.toDouble() ?? 0,
      pending: json['pending'] == true,
      skipped: json['skipped'] == true,
      skipLabel: '${json['skipLabel'] ?? ''}'.trim(),
      projectScore: _positiveSummaryNum(json['projectScore']),
    );
  }
}

class KpiScoreSummaryData {
  const KpiScoreSummaryData({
    required this.title,
    required this.rows,
    this.projectScore,
    this.projectCoefficient,
  });

  final String title;
  final List<KpiScoreSummaryRow> rows;

  /// 研发整体绩效评价表加权总分（满分 10）。行政 / 财务 / 业务板块没有。
  final double? projectScore;
  final double? projectCoefficient;

  List<KpiScoreSummaryRow> get scoredRows => [
    for (final r in rows)
      if (!r.pending && !r.skipped) r,
  ];

  int get pendingCount => rows.where((r) => r.pending && !r.skipped).length;

  int get skippedCount => rows.where((r) => r.skipped).length;

  double? get averageScore {
    final scored = scoredRows;
    if (scored.isEmpty) return null;
    return scored.fold<double>(0, (s, r) => s + r.score) / scored.length;
  }

  double? get topScore {
    final scored = scoredRows;
    if (scored.isEmpty) return null;
    return scored.map((r) => r.score).reduce((a, b) => a > b ? a : b);
  }

  /// 已评分人员个人绩效系数的算术平均，未录入 / 不考核的人不计入。
  double? get departmentCoefficient {
    final scored = scoredRows;
    if (scored.isEmpty) return null;
    return scored.fold<double>(0, (s, r) => s + r.coefficient) / scored.length;
  }

  /// 已评分的人里全部是 0 分 —— 多半还没开始录入，卡片上给一句提示。
  bool get allScoresZero =>
      scoredRows.isNotEmpty && scoredRows.every((r) => r.score.abs() < 1e-9);

  /// 等级 → 人数（只数已评分的人），按 [kKpiGradeOrder] 排序。
  List<MapEntry<String, int>> get gradeCounts {
    final counts = <String, int>{};
    for (final r in scoredRows) {
      final code = r.gradeCode.isEmpty ? '—' : r.gradeCode;
      counts[code] = (counts[code] ?? 0) + 1;
    }
    final keys = counts.keys.toList()
      ..sort((a, b) {
        final ia = kKpiGradeOrder.indexOf(a);
        final ib = kKpiGradeOrder.indexOf(b);
        return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
      });
    return [for (final k in keys) MapEntry(k, counts[k]!)];
  }

  /// 按部门分组，组的先后按组内最高名次（名单本身已按得分排好）。
  List<MapEntry<String, List<KpiScoreSummaryRow>>> get byDepartment {
    final groups = <String, List<KpiScoreSummaryRow>>{};
    for (final r in rows) {
      final dept = r.department.isEmpty ? '未分部门' : r.department;
      groups.putIfAbsent(dept, () => []).add(r);
    }
    return groups.entries.toList();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'rows': [for (final r in rows) r.toJson()],
    if (projectScore != null) 'projectScore': projectScore,
    if (projectCoefficient != null) 'projectCoefficient': projectCoefficient,
  };

  static KpiScoreSummaryData? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final rawRows = json['rows'];
    if (rawRows is! List) return null;
    final rows = <KpiScoreSummaryRow>[];
    for (var i = 0; i < rawRows.length; i++) {
      final row = rawRows[i];
      if (row is! Map) continue;
      final parsed = KpiScoreSummaryRow.fromJson(
        Map<String, dynamic>.from(row),
        i,
      );
      if (parsed.name.isNotEmpty) rows.add(parsed);
    }
    if (rows.isEmpty) return null;
    return KpiScoreSummaryData(
      title: '${json['title'] ?? ''}'.trim(),
      rows: rows,
      projectScore: _positiveSummaryNum(json['projectScore']),
      projectCoefficient: _positiveSummaryNum(json['projectCoefficient']),
    );
  }

  /// 聊天消息 → 汇总卡数据。优先读结构化 payload，其次解析 Markdown 表格。
  /// 不是绩效汇总消息时返回 null，调用方照旧按 Markdown 渲染。
  static KpiScoreSummaryData? fromMessage(
    Map<String, dynamic>? payload,
    String text,
  ) {
    if (payload == null) return null;
    final flag = payload['kpiScoreSummary'];
    if (flag != true && '$flag'.toLowerCase() != 'true') return null;
    return fromJson(payload['kpiSummary']) ?? parseMarkdown(text);
  }

  /// 解析 [kpiScoreSummaryMarkdown] 生成的表格（兼容「业务绩效汇总」旧标题）。
  static KpiScoreSummaryData? parseMarkdown(String text) {
    var title = '';
    List<String>? header;
    final rows = <KpiScoreSummaryRow>[];
    final pipe = RegExp(r'(?<!\\)\|');
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.startsWith('#')) {
        if (title.isEmpty) title = line.replaceFirst(RegExp(r'^#+\s*'), '');
        continue;
      }
      if (!line.startsWith('|')) continue;
      final cells = line
          .split(pipe)
          .map((c) => c.trim().replaceAll(r'\|', '|'))
          .toList();
      // 首尾两个 | 切出来的空串去掉。
      if (cells.isNotEmpty && cells.first.isEmpty) cells.removeAt(0);
      if (cells.isNotEmpty && cells.last.isEmpty) cells.removeLast();
      if (cells.isEmpty) continue;
      if (cells.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c))) continue;
      if (header == null) {
        header = cells;
        continue;
      }
      String at(String name) {
        final i = header!.indexOf(name);
        if (i < 0 || i >= cells.length) return '';
        final v = cells[i];
        return v == '—' ? '' : v;
      }

      final rawName = at('姓名');
      final m = RegExp(r'^(\d+)\.\s*(.*)$').firstMatch(rawName);
      final name = (m?.group(2) ?? rawName).trim();
      if (name.isEmpty) continue;
      final gradeLabel = at('绩效等级');
      rows.add(
        KpiScoreSummaryRow(
          rank: int.tryParse(m?.group(1) ?? '') ?? rows.length + 1,
          name: name,
          department: at('部门'),
          position: at('岗位'),
          score: double.tryParse(at('绩效得分')) ?? 0,
          gradeCode: kpiGradeCodeFromLabel(gradeLabel),
          gradeLabel: gradeLabel,
          coefficient: double.tryParse(at('绩效系数')) ?? 0,
        ),
      );
    }
    if (header == null || !header!.contains('姓名') || rows.isEmpty) {
      return null;
    }
    return KpiScoreSummaryData(title: title, rows: rows);
  }
}

/// 「辅（专项改进）」→「辅」。
String kpiGradeCodeFromLabel(String label) {
  final v = label.trim();
  if (v.isEmpty) return '';
  final cut = v.indexOf(RegExp(r'[（(]'));
  return (cut > 0 ? v.substring(0, cut) : v.substring(0, 1)).trim();
}

/// 工作台名单 → 转发用的结构化汇总（与 [kpiScoreSummaryMarkdown] 同顺序同口径）。
KpiScoreSummaryData kpiScoreSummaryData(
  WorkProfileKpiScore score, {
  List<WorkProfileKpiPerson>? people,
}) {
  final list = kpiPeopleByScoreDesc(people ?? score.people);
  final monthTitle = kpiScoreMonthTitle(score.month);
  final team = kpiSummaryProjectTeamOf(score, people: list);
  return KpiScoreSummaryData(
    title: monthTitle.isEmpty ? '月度绩效考评汇总' : '$monthTitle 月度绩效考评汇总',
    projectScore: team?.projectScore,
    projectCoefficient: team?.coefficient,
    rows: [
      for (var i = 0; i < list.length; i++)
        KpiScoreSummaryRow(
          rank: i + 1,
          name: list[i].userName.trim(),
          department: kpiPersonShareDepartment(list[i]),
          position: list[i].position.trim(),
          score: list[i].mainScore,
          gradeCode: list[i].resolvedGrade.code,
          gradeLabel: list[i].resolvedGrade.label,
          coefficient: list[i].resolvedGrade.coefficient,
          pending: list[i].isPending,
          skipped: list[i].isSkipped,
          skipLabel: list[i].isSkipped ? list[i].skipLabel : '',
          projectScore: kpiSummaryProjectTeamOf(
            score,
            people: [list[i]],
          )?.projectScore,
        ),
    ],
  );
}

/// 当前名单对应的项目绩效：行政/财务看汇总表第一行，研发看整体绩效评价表，
/// 运营商/能源看板块整体。名单跨组且分数不一致时不合成一个数。
WorkProfileKpiTeam? kpiSummaryProjectTeamOf(
  WorkProfileKpiScore score, {
  List<WorkProfileKpiPerson>? people,
}) {
  final list = people ?? score.people;
  WorkProfileKpiTeam? first;
  var missing = false;
  var found = false;
  for (final person in list) {
    if (person.isSkipped) continue;
    final team = kpiSummaryProjectTeamForPerson(score, person);
    if (team == null) {
      missing = true;
      continue;
    }
    found = true;
    first ??= team;
    if ((team.projectScore - first.projectScore).abs() >= 0.005) {
      return null;
    }
  }
  if (!found || missing) return null;
  return first;
}

String kpiSummaryTeamKey(WorkProfileKpiPerson person) {
  switch (kpiPrimarySectorOf(person)) {
    case 'telecom':
      return '运营商';
    case 'energy':
      return '能源';
    case 'office':
      return kpiCanonicalOfficeGroup(person.departmentName);
    case 'rd':
      return kpiCanonicalRdGroup(person.departmentName);
    default:
      final name = person.departmentName.trim();
      return name;
  }
}

WorkProfileKpiTeam? kpiSummaryProjectTeamForPerson(
  WorkProfileKpiScore score,
  WorkProfileKpiPerson person,
) {
  final key = kpiSummaryTeamKey(person);
  if (key.isEmpty || key == '未分组') return null;
  final sector = kpiPrimarySectorOf(person);
  WorkProfileKpiTeam? best;
  for (final team in score.teams) {
    if (team.projectScore <= 0) continue;
    if (!kpiSummaryTeamMatches(team, key, sector)) continue;
    if (best == null) {
      best = team;
      continue;
    }
    if ((sector == 'telecom' || sector == 'energy') &&
        team.departmentId == 0 &&
        best.departmentId != 0) {
      best = team;
    }
  }
  return best;
}

bool kpiSummaryTeamMatches(
  WorkProfileKpiTeam team,
  String key,
  String sector,
) {
  final name = team.departmentName.trim();
  if (name.isEmpty) return false;
  switch (sector) {
    case 'telecom':
    case 'energy':
      return name == key && team.departmentId == 0;
    case 'office':
      return name == key || kpiCanonicalOfficeGroup(name) == key;
    case 'rd':
      return name == key || kpiCanonicalRdGroup(name) == key;
    default:
      return name == key;
  }
}

double? _positiveSummaryNum(Object? raw) {
  if (raw is! num) return null;
  final v = raw.toDouble();
  if (v <= 0) return null;
  return v;
}

/// 等级色与工作台绩效列表、绩效助手结果卡保持一致。
(Color, Color) kpiSummaryGradeColors(String code) {
  switch (code) {
    case '优':
      return (DunesColors.green, DunesColors.greenSoft);
    case '良':
      return (DunesColors.brandPurple, DunesColors.brandPurpleSoft);
    case '中':
      return (DunesColors.blue, DunesColors.blueSoft);
    case '普':
      return (DunesColors.amber, DunesColors.amberSoft);
    case '改':
    case '辅':
      return (DunesColors.coral, DunesColors.coralSoft);
  }
  return (DunesColors.text2, DunesColors.bgSoft);
}

String _fmtScore(double v) => v.toStringAsFixed(v.abs() >= 100 ? 0 : 1);

String _fmtProject(double v) => formatKpiProjectScore(v);

String _fmtCoef(double v) {
  if (v <= 0) return '—';
  final s = v.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'0$'), '');
}

class ChatKpiScoreSummaryCard extends StatefulWidget {
  const ChatKpiScoreSummaryCard({super.key, required this.data});

  final KpiScoreSummaryData data;

  @override
  State<ChatKpiScoreSummaryCard> createState() =>
      _ChatKpiScoreSummaryCardState();
}

class _ChatKpiScoreSummaryCardState extends State<ChatKpiScoreSummaryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final collapsible = data.rows.length > kKpiSummaryCollapsedRows;
    final visibleRanks = <int>{
      for (final r
          in (collapsible && !_expanded
              ? data.rows.take(kKpiSummaryCollapsedRows)
              : data.rows))
        r.rank,
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DunesColors.borderSoft),
        boxShadow: [
          BoxShadow(
            color: DunesColors.brandPurpleDeep.withValues(alpha: 0.07),
            blurRadius: 14,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(data),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: _overview(data),
          ),
          if (data.gradeCounts.isNotEmpty && !data.allScoresZero)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: _gradeDistribution(data),
            ),
          if (data.allScoresZero)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: _notice('名单里的得分都还是 0，可能尚未评分'),
            ),
          const SizedBox(height: 8),
          for (final group in data.byDepartment)
            if (group.value.any((r) => visibleRanks.contains(r.rank)))
              _departmentBlock(
                group.key,
                group.value,
                visibleRanks: visibleRanks,
              ),
          if (collapsible)
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                height: 38,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: DunesColors.borderSoft, width: 0.7),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded ? '收起' : '展开全部 ${data.rows.length} 人',
                      style: DunesTypography.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.brandPurpleDeep,
                        height: 1.0,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: DunesColors.brandPurpleDeep,
                    ),
                  ],
                ),
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _header(KpiScoreSummaryData data) {
    final title = data.title.isEmpty ? '月度绩效考评汇总' : data.title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: DunesColors.brandPurple,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '沙丘绩效 · 汇总',
                style: DunesTypography.sans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: DunesColors.brandPurpleDeep,
                  letterSpacing: 0.3,
                  height: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: DunesColors.text,
              letterSpacing: -0.2,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _overview(KpiScoreSummaryData data) {
    final avg = data.averageScore;
    final project = data.projectScore == null
        ? data.projectCoefficient
        : kpiProjectCoefficient(
            data.projectScore!,
            fallback: data.projectCoefficient ?? 0,
          );

    Widget cell(String caption, String value, {String unit = '', String? sub}) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              caption,
              style: DunesTypography.sans(
                fontSize: 10,
                color: DunesColors.text3,
                letterSpacing: 0.3,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.mono(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                      letterSpacing: -0.6,
                      height: 1.0,
                    ),
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 2),
                  Text(
                    unit,
                    style: DunesTypography.sans(
                      fontSize: 10.5,
                      color: DunesColors.text3,
                      height: 1.0,
                    ),
                  ),
                ],
              ],
            ),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 9.5,
                  color: DunesColors.amber,
                  height: 1.0,
                ),
              ),
            ],
          ],
        ),
      );
    }

    Widget divider() => Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: DunesColors.brandPurpleLine.withValues(alpha: 0.35),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF8F5FD), DunesColors.brandPurpleSoft],
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          cell(
            '人数',
            '${data.rows.length}',
            unit: '人',
            sub: [
              if (data.pendingCount > 0) '${data.pendingCount} 人待录入',
              if (data.skippedCount > 0) '${data.skippedCount} 人不考核',
            ].isEmpty
                ? null
                : [
                    if (data.pendingCount > 0) '${data.pendingCount} 人待录入',
                    if (data.skippedCount > 0) '${data.skippedCount} 人不考核',
                  ].join(' · '),
          ),
          divider(),
          cell('均分', avg == null ? '—' : _fmtScore(avg)),
          divider(),
          cell(
            '项目绩效系数',
            project == null || project <= 0
                ? '—'
                : formatKpiProjectCoefficient(project),
            sub: data.projectScore != null &&
                    kpiProjectScoreOnTenScale(data.projectScore!)
                ? '项目得分 ${_fmtProject(data.projectScore!)}'
                : null,
          ),
        ],
      ),
    );
  }

  Widget _gradeDistribution(KpiScoreSummaryData data) {
    final counts = data.gradeCounts;
    final total = counts.fold<int>(0, (s, e) => s + e.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '等级分布',
              style: DunesTypography.sans(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: DunesColors.text2,
                height: 1.0,
              ),
            ),
            const Spacer(),
            Text(
              '已评 $total 人',
              style: DunesTypography.sans(
                fontSize: 10,
                color: DunesColors.text3,
                height: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 7,
            child: Row(
              children: [
                for (var i = 0; i < counts.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: counts[i].value,
                    child: Container(
                      color: kpiSummaryGradeColors(counts[i].key).$1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 10,
          runSpacing: 5,
          children: [
            for (final e in counts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: kpiSummaryGradeColors(e.key).$1,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${e.key} ${e.value}人',
                    style: DunesTypography.sans(
                      fontSize: 10.5,
                      color: DunesColors.text2,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _notice(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: DunesColors.amberSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 12,
            color: DunesColors.amber,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: DunesTypography.sans(
                fontSize: 10.5,
                color: DunesColors.amber,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _departmentBlock(
    String department,
    List<KpiScoreSummaryRow> rows, {
    required Set<int> visibleRanks,
  }) {
    final scored = [
      for (final r in rows)
        if (!r.pending && !r.skipped) r,
    ];
    final avg = scored.isEmpty
        ? null
        : scored.fold<double>(0, (s, r) => s + r.score) / scored.length;
    final projectScores = <double>{
      for (final r in rows)
        if (r.projectScore != null) r.projectScore!,
    };
    final project = projectScores.length == 1 ? projectScores.first : null;
    final coef = scored.isEmpty
        ? null
        : scored.fold<double>(0, (s, r) => s + r.coefficient) / scored.length;
    final shown = [
      for (final r in rows)
        if (visibleRanks.contains(r.rank)) r,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
          color: DunesColors.bgSoft,
          child: Row(
            children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: DunesColors.brandPurple,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  department,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                [
                  '${rows.length} 人',
                  if (avg != null) '均分 ${_fmtScore(avg)}',
                  if (project != null)
                    '项目绩效系数 ${formatKpiProjectCoefficient(kpiProjectCoefficient(project))}',
                  if (project == null && coef != null) '系数 ${_fmtCoef(coef)}',
                ].join(' · '),
                style: DunesTypography.sans(
                  fontSize: 10.5,
                  color: DunesColors.text3,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < shown.length; i++)
          _personRow(shown[i], last: i == shown.length - 1),
      ],
    );
  }

  Widget _personRow(KpiScoreSummaryRow r, {required bool last}) {
    final (gradeFg, gradeBg) = kpiSummaryGradeColors(r.gradeCode);
    final topThree = r.rank <= 3 && !r.pending && !r.skipped && r.score > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(
                bottom: BorderSide(color: DunesColors.borderSoft, width: 0.6),
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: topThree
                  ? DunesColors.brandPurple
                  : DunesColors.bgSoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${r.rank}',
              style: DunesTypography.mono(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: topThree ? Colors.white : DunesColors.text3,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                    height: 1.25,
                  ),
                ),
                if (r.position.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    r.position,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 10.5,
                      color: DunesColors.text3,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (r.skipped)
            Text(
              r.skipLabel.isEmpty ? '不考核' : r.skipLabel,
              style: DunesTypography.sans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: DunesColors.text2,
                height: 1.0,
              ),
            )
          else if (r.pending)
            Text(
              '待录入',
              style: DunesTypography.sans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: DunesColors.amber,
                height: 1.0,
              ),
            )
          else ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  r.score.toStringAsFixed(2),
                  style: DunesTypography.mono(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                    letterSpacing: -0.4,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '系数 ${_fmtCoef(r.coefficient)}',
                  style: DunesTypography.sans(
                    fontSize: 10,
                    color: DunesColors.text3,
                    height: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 9),
            Tooltip(
              message: r.gradeLabel.isEmpty ? r.gradeCode : r.gradeLabel,
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: gradeBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: gradeFg.withValues(alpha: 0.25)),
                ),
                child: Text(
                  r.gradeCode.isEmpty ? '—' : r.gradeCode,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: gradeFg,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
