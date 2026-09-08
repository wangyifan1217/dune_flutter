import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';

class KpiGrade {
  const KpiGrade({
    required this.code,
    required this.label,
    required this.coefficient,
  });

  final String code;
  final String label;
  final double coefficient;
}

/// 优 95≤X≤100 1.1；良 85≤X<95 1；中 80≤X<85 0.9；普 75≤X<80 0.8；改 70≤X<75 0.7；辅 X<70 0.6.
KpiGrade kpiGradeOf(double score) {
  if (score >= 95) {
    return const KpiGrade(code: '优', label: '优（优秀）', coefficient: 1.1);
  }
  if (score >= 85) {
    return const KpiGrade(code: '良', label: '良（达到预期）', coefficient: 1);
  }
  if (score >= 80) {
    return const KpiGrade(code: '中', label: '中（低于预期）', coefficient: 0.9);
  }
  if (score >= 75) {
    return const KpiGrade(code: '普', label: '普（待提升）', coefficient: 0.8);
  }
  if (score >= 70) {
    return const KpiGrade(code: '改', label: '改（重点改进）', coefficient: 0.7);
  }
  return const KpiGrade(code: '辅', label: '辅（专项改进）', coefficient: 0.6);
}

String formatKpiCoefficient(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}

class WorkProfileKpiMetric {
  const WorkProfileKpiMetric({
    required this.key,
    required this.label,
    required this.status,
    this.points,
    this.momPct,
    this.current,
    this.previous,
    this.note = '',
  });

  final String key;
  final String label;
  final String status;
  final double? points;
  final double? momPct;
  final double? current;
  final double? previous;
  final String note;

  factory WorkProfileKpiMetric.fromJson(Map<String, dynamic> json) {
    return WorkProfileKpiMetric(
      key: '${json['key'] ?? ''}',
      label: '${json['label'] ?? ''}',
      status: '${json['status'] ?? ''}',
      points: (json['points'] as num?)?.toDouble(),
      momPct: (json['momPct'] as num?)?.toDouble(),
      current: (json['current'] as num?)?.toDouble(),
      previous: (json['previous'] as num?)?.toDouble(),
      note: '${json['note'] ?? ''}',
    );
  }

  String get line {
    final pts = points == null
        ? (status == 'none'
            ? '无数'
            : status == 'manual'
                ? '未自动'
                : '—')
        : points!.toStringAsFixed(1);
    final mom = momPct == null
        ? ''
        : ' ${momPct! >= 0 ? '+' : ''}${momPct!.toStringAsFixed(1)}%';
    return '$label $pts$mom';
  }
}

class WorkProfileKpiTask {
  const WorkProfileKpiTask({
    required this.taskId,
    required this.taskName,
    required this.province,
    required this.bucketLabel,
    required this.weightPct,
    required this.taskTotal,
    required this.curRevenue,
    required this.prevRevenue,
    required this.curProfit,
    required this.prevProfit,
    this.curUsers,
    this.prevUsers,
    this.autoWeightPct,
    this.weightOverridden = false,
    this.autoTaskTotal,
    this.scoreAdj = 0,
    this.scoreAdjusted = false,
    this.remark = '',
    this.matchSummary = '',
    this.productName = '',
    this.productGroup = '',
    this.channelName = '',
    this.channelGroup = '',
    this.supplyGroup = '',
    this.metrics = const [],
  });

  final int taskId;
  final String taskName;
  final String province;
  final String bucketLabel;
  final double weightPct;
  final double taskTotal;
  final double curRevenue;
  final double prevRevenue;
  final double curProfit;
  final double prevProfit;
  final double? curUsers;
  final double? prevUsers;
  final double? autoWeightPct;
  final bool weightOverridden;
  final double? autoTaskTotal;
  final double scoreAdj;
  final bool scoreAdjusted;
  final String remark;
  final String matchSummary;
  final String productName;
  final String productGroup;
  final String channelName;
  final String channelGroup;
  final String supplyGroup;
  final List<WorkProfileKpiMetric> metrics;

  factory WorkProfileKpiTask.fromJson(Map<String, dynamic> json) {
    return WorkProfileKpiTask(
      taskId: (json['taskId'] as num?)?.toInt() ?? 0,
      taskName: '${json['taskName'] ?? ''}',
      province: '${json['province'] ?? ''}',
      productName: '${json['productName'] ?? ''}',
      productGroup: '${json['productGroup'] ?? ''}',
      channelName: '${json['channelName'] ?? ''}',
      channelGroup: '${json['channelGroup'] ?? ''}',
      supplyGroup: '${json['supplyGroup'] ?? ''}',
      bucketLabel: '${json['bucketLabel'] ?? json['categoryLabel'] ?? ''}',
      weightPct: (json['weightPct'] as num?)?.toDouble() ?? 0,
      taskTotal: (json['taskTotal'] as num?)?.toDouble() ?? 0,
      curRevenue: (json['curRevenue'] as num?)?.toDouble() ?? 0,
      prevRevenue: (json['prevRevenue'] as num?)?.toDouble() ?? 0,
      curProfit: (json['curProfit'] as num?)?.toDouble() ?? 0,
      prevProfit: (json['prevProfit'] as num?)?.toDouble() ?? 0,
      curUsers: (json['curUsers'] as num?)?.toDouble(),
      prevUsers: (json['prevUsers'] as num?)?.toDouble(),
      autoWeightPct: (json['autoWeightPct'] as num?)?.toDouble(),
      weightOverridden: json['weightOverridden'] == true,
      autoTaskTotal: (json['autoTaskTotal'] as num?)?.toDouble(),
      scoreAdj: (json['scoreAdj'] as num?)?.toDouble() ?? 0,
      scoreAdjusted: json['scoreAdjusted'] == true,
      remark: '${json['remark'] ?? ''}',
      matchSummary: '${json['matchSummary'] ?? ''}',
      metrics: (json['metrics'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => WorkProfileKpiMetric.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }
}

class WorkProfileKpiCategory {
  const WorkProfileKpiCategory({
    required this.category,
    required this.categoryLabel,
    required this.categoryWeight,
    required this.score,
    this.tasks = const [],
  });

  final String category;
  final String categoryLabel;
  final double categoryWeight;
  final double score;
  final List<WorkProfileKpiTask> tasks;

  factory WorkProfileKpiCategory.fromJson(Map<String, dynamic> json) {
    return WorkProfileKpiCategory(
      category: '${json['category'] ?? ''}',
      categoryLabel: '${json['categoryLabel'] ?? ''}',
      categoryWeight: (json['categoryWeight'] as num?)?.toDouble() ?? 0,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      tasks: (json['tasks'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => WorkProfileKpiTask.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }
}

class WorkProfileKpiPerson {
  const WorkProfileKpiPerson({
    required this.userId,
    required this.userName,
    required this.mainScore,
    required this.bonus,
    required this.telecomWeight,
    required this.energyWeight,
    required this.telecomScore,
    required this.energyScore,
    this.grade = '',
    this.gradeLabel = '',
    this.coefficient = 0,
    this.categories = const [],
  });

  final int userId;
  final String userName;
  final double mainScore;
  final String grade;
  final String gradeLabel;
  final double coefficient;
  final double bonus;
  final double telecomWeight;
  final double energyWeight;
  final double telecomScore;
  final double energyScore;
  final List<WorkProfileKpiCategory> categories;

  KpiGrade get resolvedGrade {
    if (gradeLabel.trim().isNotEmpty) {
      return KpiGrade(
        code: grade.trim().isEmpty ? kpiGradeOf(mainScore).code : grade.trim(),
        label: gradeLabel.trim(),
        coefficient: coefficient > 0 ? coefficient : kpiGradeOf(mainScore).coefficient,
      );
    }
    return kpiGradeOf(mainScore);
  }

  factory WorkProfileKpiPerson.fromJson(Map<String, dynamic> json) {
    return WorkProfileKpiPerson(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      userName: '${json['userName'] ?? ''}',
      mainScore: (json['mainScore'] as num?)?.toDouble() ?? 0,
      grade: '${json['grade'] ?? ''}',
      gradeLabel: '${json['gradeLabel'] ?? ''}',
      coefficient: (json['coefficient'] as num?)?.toDouble() ?? 0,
      bonus: (json['bonus'] as num?)?.toDouble() ?? 0,
      telecomWeight: (json['telecomWeight'] as num?)?.toDouble() ?? 0,
      energyWeight: (json['energyWeight'] as num?)?.toDouble() ?? 0,
      telecomScore: (json['telecomScore'] as num?)?.toDouble() ?? 0,
      energyScore: (json['energyScore'] as num?)?.toDouble() ?? 0,
      categories: (json['categories'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => WorkProfileKpiCategory.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }
}

class WorkProfileKpiScore {
  const WorkProfileKpiScore({
    required this.month,
    required this.prevMonth,
    this.people = const [],
    this.unmapped = const [],
  });

  final String month;
  final String prevMonth;
  final List<WorkProfileKpiPerson> people;
  final List<Map<String, dynamic>> unmapped;

  WorkProfileKpiPerson? get me => people.isEmpty ? null : people.first;

  factory WorkProfileKpiScore.fromJson(Map<String, dynamic> json) {
    return WorkProfileKpiScore(
      month: '${json['month'] ?? ''}',
      prevMonth: '${json['prevMonth'] ?? ''}',
      people: (json['people'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => WorkProfileKpiPerson.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      unmapped: (json['unmapped'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false),
    );
  }
}

bool kpiLighthouseWildcardDim(String value, {bool keepNationwide = false}) {
  final v = value.trim();
  if (v.isEmpty || v == '*' || v == '全部' || v.toLowerCase() == 'none') {
    return true;
  }
  if (v == '全国') return !keepNationwide;
  return false;
}

bool kpiLighthouseBucketDim(String value) {
  final v = value.replaceAll('板块', '').trim();
  return v == '能源' || v == '通信' || v == '运营商';
}

Map<String, String> parseKpiLighthouseDims(WorkProfileKpiTask task) {
  final out = <String, String>{};
  void put(String key, String? value, {bool keepNationwide = false}) {
    final v = (value ?? '').trim();
    if (v.isEmpty || out.containsKey(key)) return;
    if (kpiLighthouseWildcardDim(v, keepNationwide: keepNationwide)) return;
    out[key] = v;
  }

  put('product', task.productName);
  put('group', task.productGroup);
  put('province', task.province, keepNationwide: true);
  put('channel', task.channelName);
  put('channel', task.channelGroup);
  put('supply', task.supplyGroup);

  var raw = task.matchSummary.trim();
  if (raw.startsWith('灯塔规则')) {
    raw = raw.replaceFirst(RegExp(r'^灯塔规则\s*'), '');
  }
  for (final part in raw.split(RegExp(r'[；;]'))) {
    final idx = part.indexOf('=');
    if (idx <= 0) continue;
    final key = part.substring(0, idx).trim();
    final value = part.substring(idx + 1).trim();
    if (key.startsWith('产品分组') || key == '分组') {
      put('group', value);
    } else if (key.startsWith('产品')) {
      put('product', value);
    } else if (key.startsWith('省份')) {
      put('province', value, keepNationwide: true);
    } else if (key.startsWith('渠道')) {
      put('channel', value);
    } else if (key.startsWith('供给')) {
      put('supply', value);
    }
  }
  return out;
}

String kpiLighthouseSliceTitle(WorkProfileKpiTask task) {
  final dims = parseKpiLighthouseDims(task);
  for (final key in ['product', 'group', 'channel', 'supply']) {
    final value = dims[key]?.trim() ?? '';
    if (value.isEmpty) continue;
    if (key == 'group' && kpiLighthouseBucketDim(value)) continue;
    return value;
  }
  final group = dims['group']?.trim() ?? '';
  if (group.isNotEmpty) return group;
  final name = task.taskName.trim();
  return name.isEmpty ? '灯塔数据' : name;
}

String kpiLighthouseSliceSubtitle(WorkProfileKpiTask task) {
  final dims = parseKpiLighthouseDims(task);
  final title = kpiLighthouseSliceTitle(task);
  final bits = <String>[];
  void add(String? value, {bool skipBucket = false}) {
    final v = (value ?? '').trim();
    if (v.isEmpty || v == title || bits.contains(v)) return;
    if (skipBucket && kpiLighthouseBucketDim(v)) return;
    bits.add(v);
  }

  final province = (dims['province'] ?? task.province).trim();
  add(province.isEmpty ? '全国' : province);
  add(dims['channel']);
  add(dims['supply']);
  add(dims['group'], skipBucket: true);
  return bits.isEmpty ? '全国' : bits.join(' · ');
}

String kpiScoreMonthTitle(String month) {
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(month.trim());
  if (match == null) return month.trim();
  return '${match.group(1)}年${int.parse(match.group(2)!)}月';
}

List<WorkProfileKpiPerson> kpiPeopleByScoreDesc(
  List<WorkProfileKpiPerson> people,
) {
  return [...people]..sort((a, b) {
      final byScore = b.mainScore.compareTo(a.mainScore);
      if (byScore != 0) return byScore;
      return a.userName.compareTo(b.userName);
    });
}

/// 全员最终得分与等级的 Markdown，便于页面展示和转发 IM。
String kpiScoreSummaryMarkdown(WorkProfileKpiScore score) {
  final people = kpiPeopleByScoreDesc(score.people);
  final monthTitle = kpiScoreMonthTitle(score.month);
  final title = monthTitle.isEmpty ? '业务绩效汇总' : '$monthTitle 业务绩效汇总';
  final buf = StringBuffer()
    ..writeln('## $title')
    ..writeln()
    ..writeln('共 **${people.length}** 人')
    ..writeln()
    ..writeln('| 姓名 | 最终得分 | 等级 |')
    ..writeln('| --- | ---: | --- |');
  for (final person in people) {
    final name = person.userName.trim().replaceAll('|', '\\|');
    buf.writeln(
      '| $name | ${person.mainScore.toStringAsFixed(2)} | ${person.resolvedGrade.label} |',
    );
  }
  return buf.toString().trimRight();
}

class WorkProfileModuleHint {
  const WorkProfileModuleHint({
    required this.type,
    required this.status,
    this.summary = '',
  });

  final String type;
  final String status;
  final String summary;
}

class WorkProfileKpiService {
  WorkProfileKpiService({required this.session, http.Client? client})
      : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;

  dynamic _unwrap(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('绩效请求失败：HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['success'] == false) {
      throw Exception((decoded['message'] ?? '绩效请求失败').toString());
    }
    if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
    return decoded;
  }

  Future<List<WorkProfileModuleHint>> fetchProfileModules() async {
    final resp = await dunesHttpGet(
      session,
      '/work-profile/me',
      client: _client,
    );
    final data = _unwrap(resp);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final rawModules = map['modules'];
    if (rawModules is! List) return const [];
    return rawModules
        .whereType<Map>()
        .map(
          (row) => WorkProfileModuleHint(
            type: '${row['type'] ?? ''}',
            status: '${row['status'] ?? ''}',
            summary: '${row['summary'] ?? ''}',
          ),
        )
        .where((e) => e.type.isNotEmpty)
        .toList(growable: false);
  }

  Future<WorkProfileKpiScore> fetchMyScore({String month = ''}) async {
    final q = month.trim().isEmpty ? '' : '?month=${Uri.encodeQueryComponent(month.trim())}';
    final resp = await dunesHttpGet(
      session,
      '/kpi/my-score$q',
      client: _client,
    );
    final data = _unwrap(resp);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    return WorkProfileKpiScore.fromJson(map);
  }
}
