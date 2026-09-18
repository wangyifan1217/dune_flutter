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

String formatKpiNum(double? v) {
  if (v == null) return '—';
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}

String formatKpiProjectScore(double v) {
  final s = v.toStringAsFixed(2);
  if (s.endsWith('00')) return v.toStringAsFixed(0);
  if (s.endsWith('0')) return v.toStringAsFixed(1);
  return s;
}

/// 项目绩效系数分档（整体绩效评价表，10 分制项目得分）。
class KpiProjectTier {
  const KpiProjectTier({required this.range, required this.coefficient});

  final String range;
  final double coefficient;
}

const kpiProjectTiers = <KpiProjectTier>[
  KpiProjectTier(range: '≤6', coefficient: 0.7),
  KpiProjectTier(range: '6–7', coefficient: 0.8),
  KpiProjectTier(range: '7–8', coefficient: 0.9),
  KpiProjectTier(range: '8–9', coefficient: 1),
  KpiProjectTier(range: '9–10', coefficient: 1.1),
];

/// X≤6→0.7；6<X≤7→0.8；7<X≤8→0.9；8<X≤9→1；9<X≤10→1.1。
double kpiProjectCoefficientOfScore(double score) {
  if (score <= 6) return 0.7;
  if (score <= 7) return 0.8;
  if (score <= 8) return 0.9;
  if (score <= 9) return 1;
  return 1.1;
}

/// 项目得分 → 项目绩效系数。
/// ≤1.1 视为表里直接填的系数；1.1–10 按分档表；百分制板块得分沿用已有系数。
double kpiProjectCoefficient(double projectScore, {double fallback = 0}) {
  if (projectScore <= 0) return fallback > 0 ? fallback : 0;
  if (projectScore <= 1.1) return projectScore;
  if (projectScore <= 10) return kpiProjectCoefficientOfScore(projectScore);
  if (fallback > 0) return fallback;
  return kpiGradeOf(projectScore).coefficient;
}

/// 项目得分是不是 10 分制（能对上分档表）。
bool kpiProjectScoreOnTenScale(double projectScore) =>
    projectScore > 1.1 && projectScore <= 10;

String formatKpiProjectCoefficient(double v) => v.toStringAsFixed(1);

String formatKpiAckedAt(String raw) {
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) return '';
  final t = parsed.toLocal();
  return '${t.year}年${t.month}月${t.day}日';
}

class WorkProfileKpiMetric {
  const WorkProfileKpiMetric({
    required this.key,
    required this.label,
    required this.status,
    this.kind = '',
    this.base = 0,
    this.maxPoints = 0,
    this.weight = 0,
    this.points,
    this.momPct,
    this.current,
    this.previous,
    this.note = '',
  });

  final String key;
  final String label;
  final String status;
  final String kind;
  final double base;
  final double maxPoints;
  final double weight;
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
      kind: '${json['kind'] ?? ''}',
      base: (json['base'] as num?)?.toDouble() ?? 0,
      maxPoints: (json['maxPoints'] as num?)?.toDouble() ?? 0,
      weight: (json['weight'] as num?)?.toDouble() ?? 0,
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
    this.bucket = '',
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
  final String bucket;
  final List<WorkProfileKpiMetric> metrics;

  bool get isRubric => metrics.any((m) => m.kind == 'rubric');

  String get rubricKey {
    final fromBucket = bucket.trim();
    if (fromBucket.isNotEmpty) return fromBucket;
    if (metrics.isEmpty) return '';
    return metrics.first.key.trim();
  }

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
      bucket: '${json['bucket'] ?? ''}',
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
          .map(
            (e) => WorkProfileKpiMetric.fromJson(Map<String, dynamic>.from(e)),
          )
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
    this.departmentName = '',
    this.parentDepartmentName = '',
    this.position = '',
    required this.mainScore,
    required this.bonus,
    required this.telecomWeight,
    required this.energyWeight,
    required this.telecomScore,
    required this.energyScore,
    this.grade = '',
    this.gradeLabel = '',
    this.coefficient = 0,
    this.scoreSource = '',
    this.scoreStatus = '',
    this.templateKey = '',
    this.canWrite = false,
    this.scoredBy = 0,
    this.scoredByName = '',
    this.ackedAt = '',
    this.canAck = false,
    this.publishedAt = '',
    this.needsPublish = false,
    this.supervisorId = 0,
    this.supervisorName = '',
    this.skipReason = '',
    this.skipNote = '',
    this.categories = const [],
  });

  final int userId;
  final String userName;
  final String departmentName;
  final String parentDepartmentName;
  final String position;
  final double mainScore;
  final String grade;
  final String gradeLabel;
  final double coefficient;
  final double bonus;
  final double telecomWeight;
  final double energyWeight;
  final double telecomScore;
  final double energyScore;
  final String scoreSource;
  final String scoreStatus;
  final String templateKey;
  final bool canWrite;
  final int scoredBy;
  final String scoredByName;
  final String ackedAt;
  final bool canAck;
  final String publishedAt;
  final bool needsPublish;
  final int supervisorId;
  final String supervisorName;
  final String skipReason;
  final String skipNote;
  final List<WorkProfileKpiCategory> categories;

  bool get isRubric => scoreSource == 'rubric';
  bool get isPending => scoreStatus == 'pending';
  bool get isSkipped =>
      scoreStatus == 'skipped' || skipReason.trim().isNotEmpty;
  bool get isAcked => ackedAt.trim().isNotEmpty;
  bool get isUnpublished => isRubric && !isPending && !isSkipped && needsPublish;

  String get skipLabel => kpiSkipLabel(skipReason, skipNote);

  KpiGrade get resolvedGrade {
    if (isSkipped) {
      return KpiGrade(code: '', label: skipLabel, coefficient: 0);
    }
    if (gradeLabel.trim().isNotEmpty) {
      return KpiGrade(
        code: grade.trim().isEmpty ? kpiGradeOf(mainScore).code : grade.trim(),
        label: gradeLabel.trim(),
        coefficient: coefficient > 0
            ? coefficient
            : kpiGradeOf(mainScore).coefficient,
      );
    }
    return kpiGradeOf(mainScore);
  }

  factory WorkProfileKpiPerson.fromJson(Map<String, dynamic> json) {
    return WorkProfileKpiPerson(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      userName: '${json['userName'] ?? ''}',
      departmentName: '${json['departmentName'] ?? ''}',
      parentDepartmentName: '${json['parentDepartmentName'] ?? ''}',
      position: '${json['position'] ?? ''}',
      mainScore: (json['mainScore'] as num?)?.toDouble() ?? 0,
      grade: '${json['grade'] ?? ''}',
      gradeLabel: '${json['gradeLabel'] ?? ''}',
      coefficient: (json['coefficient'] as num?)?.toDouble() ?? 0,
      bonus: (json['bonus'] as num?)?.toDouble() ?? 0,
      telecomWeight: (json['telecomWeight'] as num?)?.toDouble() ?? 0,
      energyWeight: (json['energyWeight'] as num?)?.toDouble() ?? 0,
      telecomScore: (json['telecomScore'] as num?)?.toDouble() ?? 0,
      energyScore: (json['energyScore'] as num?)?.toDouble() ?? 0,
      scoreSource: '${json['scoreSource'] ?? ''}',
      scoreStatus: '${json['scoreStatus'] ?? ''}',
      templateKey: '${json['templateKey'] ?? ''}',
      canWrite: json['canWrite'] == true,
      scoredBy: (json['scoredBy'] as num?)?.toInt() ?? 0,
      scoredByName: '${json['scoredByName'] ?? ''}',
      ackedAt: '${json['ackedAt'] ?? ''}',
      canAck: json['canAck'] == true,
      publishedAt: '${json['publishedAt'] ?? ''}',
      needsPublish: json['needsPublish'] == true,
      supervisorId: (json['supervisorId'] as num?)?.toInt() ?? 0,
      supervisorName: '${json['supervisorName'] ?? ''}',
      skipReason: '${json['skipReason'] ?? ''}',
      skipNote: '${json['skipNote'] ?? ''}',
      categories: (json['categories'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (e) =>
                WorkProfileKpiCategory.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
    );
  }
}

class WorkProfileKpiTeam {
  const WorkProfileKpiTeam({
    required this.departmentId,
    required this.departmentName,
    required this.projectScore,
    required this.coefficient,
    this.memberAvg = 0,
    this.deptScore = 0,
  });

  final int departmentId;
  final String departmentName;
  final double projectScore;
  final double coefficient;
  final double memberAvg;
  final double deptScore;

  /// 项目绩效系数（0.7–1.1），按 [kpiProjectCoefficient] 从项目得分重新算。
  double get projectCoefficient =>
      kpiProjectCoefficient(projectScore, fallback: coefficient);

  factory WorkProfileKpiTeam.fromJson(Map<String, dynamic> json) {
    return WorkProfileKpiTeam(
      departmentId: (json['departmentId'] as num?)?.toInt() ?? 0,
      departmentName: '${json['departmentName'] ?? ''}',
      projectScore: (json['projectScore'] as num?)?.toDouble() ?? 0,
      coefficient: (json['coefficient'] as num?)?.toDouble() ?? 0,
      memberAvg: (json['memberAvg'] as num?)?.toDouble() ?? 0,
      deptScore: (json['deptScore'] as num?)?.toDouble() ?? 0,
    );
  }
}

class WorkProfileKpiScore {
  const WorkProfileKpiScore({
    required this.month,
    required this.prevMonth,
    this.people = const [],
    this.teams = const [],
    this.unmapped = const [],
  });

  final String month;
  final String prevMonth;
  final List<WorkProfileKpiPerson> people;
  final List<WorkProfileKpiTeam> teams;
  final List<Map<String, dynamic>> unmapped;

  WorkProfileKpiPerson? get me => people.isEmpty ? null : people.first;

  WorkProfileKpiTeam? teamForDept(String name) {
    final needle = name.trim();
    if (needle.isEmpty) return null;
    for (final team in teams) {
      if (team.departmentName == needle) return team;
    }
    return null;
  }

  factory WorkProfileKpiScore.fromJson(Map<String, dynamic> json) {
    return WorkProfileKpiScore(
      month: '${json['month'] ?? ''}',
      prevMonth: '${json['prevMonth'] ?? ''}',
      people: (json['people'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (e) => WorkProfileKpiPerson.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
      teams: (json['teams'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => WorkProfileKpiTeam.fromJson(Map<String, dynamic>.from(e)))
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
  if (task.isRubric) {
    final desc = task.matchSummary.trim();
    if (desc.isNotEmpty) return desc;
    return task.bucketLabel.trim();
  }
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
  return [...people]..sort(kpiPersonScoreCompare);
}

int kpiPersonScoreCompare(WorkProfileKpiPerson a, WorkProfileKpiPerson b) {
  if (a.isSkipped != b.isSkipped) return a.isSkipped ? 1 : -1;
  if (a.isPending != b.isPending) return a.isPending ? 1 : -1;
  final byScore = b.mainScore.compareTo(a.mainScore);
  if (byScore != 0) return byScore;
  return a.userName.compareTo(b.userName);
}

const kKpiSkipReasons = [
  MapEntry('probation', '试用期'),
  MapEntry('resigned', '离职'),
  MapEntry('absent', '未出勤'),
];

String kpiSkipLabel(String reason, [String note = '']) {
  switch (reason.trim()) {
    case 'probation':
    case '试用期':
      return '试用期';
    case 'resigned':
    case '离职':
      return '离职';
    case 'absent':
    case '未出勤':
      return '未出勤';
    default:
      final extra = note.trim();
      return extra.isEmpty ? '不考核' : extra;
  }
}

/// 研发量表名单按沙丘组织分组的展示顺序。
const kKpiRdGroupOrder = ['AI研发', '产业研发', '出行', '能源', '大宗电商'];

/// 运营商领导层置顶顺序。
const kKpiTelecomLeaders = ['石淼', '徐峥', '李同池'];

/// 能源领导层置顶顺序。
const kKpiEnergyLeaders = ['王一凡', '吕宙'];

const kKpiTelecomGroupOrder = ['出行会员', '加油会员', '出行金', '明星来电', '点播加油权益'];

const kKpiEnergyGroupOrder = ['中石油', '中石化', '民营加油', '平安', '石油科技'];

const kKpiOfficeGroupOrder = ['行政', '财务'];

final _kpiRdLeaderTitle = RegExp(r'总监|架构师');
final _kpiOfficeLeaderTitle = RegExp(r'总监|经理|助理|主管');

String kpiCanonicalRdGroup(String departmentName) {
  final name = departmentName.trim();
  if (name.isEmpty) return '未分组';
  if (name == '出行组' || name == '出行部') return '出行';
  return name;
}

String kpiCanonicalMarketGroup(WorkProfileKpiTask task) {
  final dims = parseKpiLighthouseDims(task);
  final channel = (dims['channel'] ?? '').trim();
  if (channel.contains('平安')) return '平安';
  final product = [
    dims['product'] ?? '',
    dims['supply'] ?? '',
    task.productName,
    task.taskName,
  ].map((e) => e.trim()).firstWhere((e) => e.isNotEmpty, orElse: () => '');
  if (product.contains('中石化')) return '中石化';
  if (product.contains('民营')) return '民营加油';
  if (product.contains('石油科技')) return '石油科技';
  if (product.contains('中石油')) return '中石油';
  if (product.contains('出行会员')) return '出行会员';
  if (product.contains('加油会员')) return '加油会员';
  if (product.contains('明星来电')) return '明星来电';
  if (product.contains('出行金')) return '出行金';
  if (product.contains('点播')) return '点播加油权益';
  final title = kpiLighthouseSliceTitle(task).trim();
  if (title.isEmpty || kpiLighthouseBucketDim(title)) return '未分组';
  return title;
}

String kpiCanonicalOfficeGroup(String departmentName) {
  final name = departmentName.trim();
  if (name.isEmpty) return '未分组';
  if (name.contains('财务')) return '财务';
  if (name.contains('行政') || name.contains('人事')) return '行政';
  return name;
}

bool kpiIsOfficeDept(String departmentName) {
  final name = departmentName.trim();
  return name.contains('行政') || name.contains('人事') || name.contains('财务');
}

/// 业务名单：通讯录挂在「能源板块 / 通信板块」时跟板块。
String kpiOrgMarketSector(
  String departmentName, [
  String parentDepartmentName = '',
]) {
  for (final raw in [departmentName, parentDepartmentName]) {
    final name = raw.trim();
    if (name.contains('能源板块')) return 'energy';
    if (name.contains('通信板块')) return 'telecom';
  }
  return '';
}

/// 没挂板块时按灯塔任务落到能源 / 运营商（吕宙在运营中心）。
String kpiTaskMarketSector(WorkProfileKpiPerson person) {
  final hasEnergy = person.categories.any((c) => c.category == 'energy');
  final hasTelecom = person.categories.any((c) => c.category == 'telecom');
  if (hasEnergy && !hasTelecom) return 'energy';
  if (hasTelecom && !hasEnergy) return 'telecom';
  if (hasEnergy && hasTelecom) {
    return person.energyWeight >= person.telecomWeight ? 'energy' : 'telecom';
  }
  if (person.energyWeight > 0 && person.energyWeight >= person.telecomWeight) {
    return 'energy';
  }
  if (person.telecomWeight > 0) return 'telecom';
  return '';
}

String kpiPrimarySectorOf(WorkProfileKpiPerson person) {
  final hasOffice =
      person.categories.any((c) => c.category == 'office') ||
      person.templateKey == 'office_summary' ||
      kpiIsOfficeDept(person.departmentName);
  if (hasOffice) return 'office';
  final hasRd =
      person.categories.any((c) => c.category == 'rd') ||
      person.scoreSource == 'rubric';
  if (hasRd) return 'rd';
  final market = kpiOrgMarketSector(
    person.departmentName,
    person.parentDepartmentName,
  );
  if (market.isNotEmpty) return market;
  final fromTasks = kpiTaskMarketSector(person);
  if (fromTasks.isNotEmpty) return fromTasks;
  return 'none';
}

/// 转发汇总的业务部门列用通讯录板块，不再按任务产品切到运营商 / 能源。
String kpiPersonShareDepartment(WorkProfileKpiPerson person) {
  switch (kpiPrimarySectorOf(person)) {
    case 'telecom':
      final name = person.departmentName.trim();
      return name.isEmpty ? '通信板块' : name;
    case 'energy':
      final name = person.departmentName.trim();
      return name.isEmpty ? '能源板块' : name;
    case 'rd':
      final dept = person.departmentName.trim();
      return dept.isEmpty ? '研发' : dept;
    case 'office':
      final dept = person.departmentName.trim();
      return dept.isEmpty ? '职能' : dept;
    default:
      return person.departmentName.trim();
  }
}

WorkProfileKpiTask? kpiPrimarySectorTask(
  WorkProfileKpiPerson person,
  String sector,
) {
  WorkProfileKpiTask? best;
  var bestScore = double.negativeInfinity;
  for (final cat in person.categories) {
    if (cat.category != sector) continue;
    for (final task in cat.tasks) {
      if (best == null || task.taskTotal > bestScore) {
        best = task;
        bestScore = task.taskTotal;
      }
    }
  }
  return best;
}

String kpiPersonProjectGroup(WorkProfileKpiPerson person, String sector) {
  if (sector == 'rd') return kpiCanonicalRdGroup(person.departmentName);
  if (sector == 'office') return kpiCanonicalOfficeGroup(person.departmentName);
  final task = kpiPrimarySectorTask(person, sector);
  if (task == null) return '未分组';
  return kpiCanonicalMarketGroup(task);
}

int kpiLeaderPriority(
  WorkProfileKpiPerson person, {
  required String sector,
  required List<WorkProfileKpiPerson> peers,
}) {
  final view = sector == 'all' ? kpiPrimarySectorOf(person) : sector;
  if (view == 'telecom') {
    final i = kKpiTelecomLeaders.indexOf(person.userName);
    if (i >= 0) return i;
  } else if (view == 'energy') {
    final i = kKpiEnergyLeaders.indexOf(person.userName);
    if (i >= 0) return i;
  } else if (view == 'rd') {
    final title = person.position.trim();
    if (title.contains('总监')) return 100;
    if (_kpiRdLeaderTitle.hasMatch(title)) return 101;
    if (person.userId > 0 &&
        peers.any(
          (p) => p.userId != person.userId && p.supervisorId == person.userId,
        )) {
      return 102;
    }
  } else if (view == 'office') {
    final title = person.position.trim();
    if (_kpiOfficeLeaderTitle.hasMatch(title)) return 100;
    if (person.userId > 0 &&
        peers.any(
          (p) => p.userId != person.userId && p.supervisorId == person.userId,
        )) {
      return 102;
    }
  }
  return 1000;
}

bool kpiIsLeader(
  WorkProfileKpiPerson person, {
  required String sector,
  required List<WorkProfileKpiPerson> peers,
}) {
  return kpiLeaderPriority(person, sector: sector, peers: peers) < 1000;
}

List<WorkProfileKpiPerson> kpiPeopleLeadersFirst(
  List<WorkProfileKpiPerson> people, {
  required String sector,
}) {
  final rest = kpiPeopleByScoreDesc(people);
  final leaders = <WorkProfileKpiPerson>[];
  final others = <WorkProfileKpiPerson>[];
  for (final person in rest) {
    if (kpiIsLeader(person, sector: sector, peers: people)) {
      leaders.add(person);
    } else {
      others.add(person);
    }
  }
  leaders.sort((a, b) {
    final byRank = kpiLeaderPriority(
      a,
      sector: sector,
      peers: people,
    ).compareTo(kpiLeaderPriority(b, sector: sector, peers: people));
    if (byRank != 0) return byRank;
    return kpiPersonScoreCompare(a, b);
  });
  return [...leaders, ...others];
}

List<MapEntry<String, List<WorkProfileKpiPerson>>> kpiRdPeopleByGroup(
  List<WorkProfileKpiPerson> people,
) {
  return _kpiBucketPeople(
    people,
    groupOf: (person) => kpiCanonicalRdGroup(person.departmentName),
    order: kKpiRdGroupOrder,
  );
}

List<MapEntry<String, List<WorkProfileKpiPerson>>> kpiPeopleByProjectGroup(
  List<WorkProfileKpiPerson> people, {
  required String sector,
}) {
  final grouped = switch (sector) {
    'rd' => kpiRdPeopleByGroup(people),
    'office' => _kpiBucketPeople(
      people,
      groupOf: (person) => kpiCanonicalOfficeGroup(person.departmentName),
      order: kKpiOfficeGroupOrder,
    ),
    _ => _kpiBucketPeople(
      people,
      groupOf: (person) => kpiPersonProjectGroup(person, sector),
      order: sector == 'telecom' ? kKpiTelecomGroupOrder : kKpiEnergyGroupOrder,
    ),
  };
  return [
    for (final entry in grouped)
      MapEntry(entry.key, kpiPeopleLeadersFirst(entry.value, sector: sector)),
  ];
}

List<String> kpiProjectGroupFilterOptions(
  List<WorkProfileKpiPerson> people, {
  required String sector,
}) {
  return [
    for (final entry in kpiPeopleByProjectGroup(people, sector: sector))
      entry.key,
  ];
}

class KpiPublishGroup {
  const KpiPublishGroup({
    required this.name,
    this.scored = const [],
    this.pending = const [],
  });

  final String name;
  final List<WorkProfileKpiPerson> scored;
  final List<WorkProfileKpiPerson> pending;

  int get expected => scored.length + pending.length;
}

class KpiAppeal {
  const KpiAppeal({
    this.id = 0,
    this.month = '',
    this.userId = 0,
    this.userName = '',
    this.departmentName = '',
    this.kind = 'data',
    this.kindLabel = '',
    this.comment = '',
    this.status = 'open',
    this.createdAt = '',
    this.handledAt = '',
  });

  final int id;
  final String month;
  final int userId;
  final String userName;
  final String departmentName;
  final String kind;
  final String kindLabel;
  final String comment;
  final String status;
  final String createdAt;
  final String handledAt;

  bool get isRubric => kind == 'rubric';
  bool get isOpen => status != 'done';

  String get resolvedKindLabel {
    if (kindLabel.trim().isNotEmpty) return kindLabel.trim();
    return isRubric ? '评价结果' : '绩效数据';
  }

  factory KpiAppeal.fromJson(Map<String, dynamic> json) {
    return KpiAppeal(
      id: (json['id'] as num?)?.toInt() ?? 0,
      month: '${json['month'] ?? ''}',
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      userName: '${json['userName'] ?? ''}',
      departmentName: '${json['departmentName'] ?? ''}',
      kind: '${json['kind'] ?? 'data'}',
      kindLabel: '${json['kindLabel'] ?? ''}',
      comment: '${json['comment'] ?? ''}',
      status: '${json['status'] ?? 'open'}',
      createdAt: '${json['createdAt'] ?? ''}',
      handledAt: '${json['handledAt'] ?? ''}',
    );
  }
}

String kpiAppealTitle({required bool isRubric}) =>
    isRubric ? '申诉评价结果' : '申诉绩效数据';

List<KpiAppeal> kpiAppealsFromData(Object? data) {
  if (data is List) {
    return [
      for (final row in data)
        if (row is Map) KpiAppeal.fromJson(Map<String, dynamic>.from(row)),
    ];
  }
  if (data is Map) {
    return kpiAppealsFromData(data['items']);
  }
  return const [];
}

bool kpiPersonInSector(WorkProfileKpiPerson person, String sector) {
  if (sector == 'all') return true;
  return kpiPrimarySectorOf(person) == sector;
}

List<KpiPublishGroup> kpiPublishGroupsForSector(
  List<WorkProfileKpiPerson> people, {
  required String sector,
}) {
  final eligible = [
    for (final person in people)
      if (person.isRubric &&
          person.canWrite &&
          kpiPersonInSector(person, sector))
        person,
  ];
  if (eligible.isEmpty) return const [];
  return [
    for (final entry in kpiPeopleByProjectGroup(eligible, sector: sector))
      KpiPublishGroup(
        name: entry.key,
        scored: [
          for (final person in entry.value)
            if (!person.isPending) person,
        ],
        pending: [
          for (final person in entry.value)
            if (person.isPending) person,
        ],
      ),
  ];
}

String kpiDefaultPublishSector(
  List<WorkProfileKpiPerson> people,
  String sector,
) {
  if (sector != 'all' &&
      kpiPublishGroupsForSector(people, sector: sector).isNotEmpty) {
    return sector;
  }
  for (final id in const ['rd', 'office', 'telecom', 'energy']) {
    if (kpiPublishGroupsForSector(people, sector: id).isNotEmpty) return id;
  }
  return sector == 'all' ? 'rd' : sector;
}

List<MapEntry<String, List<WorkProfileKpiPerson>>> _kpiBucketPeople(
  List<WorkProfileKpiPerson> people, {
  required String Function(WorkProfileKpiPerson person) groupOf,
  required List<String> order,
}) {
  final buckets = <String, List<WorkProfileKpiPerson>>{};
  for (final person in people) {
    buckets.putIfAbsent(groupOf(person), () => []).add(person);
  }
  final keys = buckets.keys.toList()
    ..sort((a, b) {
      final ia = order.indexOf(a);
      final ib = order.indexOf(b);
      final ra = ia < 0 ? order.length : ia;
      final rb = ib < 0 ? order.length : ib;
      if (ra != rb) return ra.compareTo(rb);
      if (a == '未分组') return 1;
      if (b == '未分组') return -1;
      return a.compareTo(b);
    });
  return [for (final key in keys) MapEntry(key, buckets[key]!)];
}

/// 列表、汇总、导出统一：人名前面带当前名单里的序号。
String kpiIndexedPersonName(int index, String name) {
  final n = name.trim();
  return '${index + 1}. ${n.isEmpty ? '—' : n}';
}

/// 最终得分与等级的 Markdown，便于页面展示和转发 IM。
/// [people] 不传时用全员；传入时按当前筛选名单生成，部门切换后汇总与转发一致。
String kpiScoreSummaryMarkdown(
  WorkProfileKpiScore score, {
  List<WorkProfileKpiPerson>? people,
}) {
  final list = kpiPeopleByScoreDesc(people ?? score.people);
  final monthTitle = kpiScoreMonthTitle(score.month);
  final title = monthTitle.isEmpty ? '月度绩效考评汇总' : '$monthTitle 月度绩效考评汇总';
  final buf = StringBuffer()
    ..writeln('## $title')
    ..writeln()
    ..writeln('共 **${list.length}** 人')
    ..writeln()
    ..writeln('| 部门 | 姓名 | 岗位 | 绩效得分 | 绩效等级 | 绩效系数 |')
    ..writeln('| --- | --- | --- | ---: | --- | ---: |');
  for (var i = 0; i < list.length; i++) {
    final person = list[i];
    String cell(String raw) {
      final v = raw.trim().replaceAll('|', '\\|');
      return v.isEmpty ? '—' : v;
    }

    final grade = person.resolvedGrade;
    final scoreCell = person.isPending || person.isSkipped
        ? '—'
        : person.mainScore.toStringAsFixed(2);
    final gradeCell = person.isSkipped
        ? person.skipLabel
        : (person.isPending ? '待录入' : grade.label);
    final coefCell = person.isPending || person.isSkipped
        ? '—'
        : '${grade.coefficient}';
    buf.writeln(
      '| ${cell(kpiPersonShareDepartment(person))} | ${cell(kpiIndexedPersonName(i, person.userName))} | ${cell(person.position)} '
      '| $scoreCell | ${cell(gradeCell)} | $coefCell |',
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
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
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
    final q = month.trim().isEmpty
        ? ''
        : '?month=${Uri.encodeQueryComponent(month.trim())}';
    final resp = await dunesHttpGet(
      session,
      '/kpi/my-score$q',
      client: _client,
    );
    final data = _unwrap(resp);
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    return WorkProfileKpiScore.fromJson(map);
  }

  Future<WorkProfileKpiScore> ackRubricScore({required String month}) async {
    final q = '?month=${Uri.encodeQueryComponent(month.trim())}';
    final resp = await dunesHttpPost(
      session,
      '/kpi/rubric-ack$q',
      client: _client,
    );
    final data = _unwrap(resp);
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    return WorkProfileKpiScore.fromJson(map);
  }

  Future<KpiAppeal> submitAppeal({
    required String month,
    required String comment,
  }) async {
    final resp = await dunesHttpPost(
      session,
      '/kpi/appeal',
      body: jsonEncode({'month': month.trim(), 'comment': comment.trim()}),
      client: _client,
    );
    final data = _unwrap(resp);
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    return KpiAppeal.fromJson(map);
  }

  Future<List<KpiAppeal>> listMyAppeals({required String month}) async {
    final q = '?month=${Uri.encodeQueryComponent(month.trim())}';
    final resp = await dunesHttpGet(
      session,
      '/kpi/my-appeals$q',
      client: _client,
    );
    return kpiAppealsFromData(_unwrap(resp));
  }
}
