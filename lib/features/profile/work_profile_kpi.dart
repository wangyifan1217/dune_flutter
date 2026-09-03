import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';

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
  final List<WorkProfileKpiMetric> metrics;

  factory WorkProfileKpiTask.fromJson(Map<String, dynamic> json) {
    return WorkProfileKpiTask(
      taskId: (json['taskId'] as num?)?.toInt() ?? 0,
      taskName: '${json['taskName'] ?? ''}',
      province: '${json['province'] ?? ''}',
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
    this.categories = const [],
  });

  final int userId;
  final String userName;
  final double mainScore;
  final double bonus;
  final double telecomWeight;
  final double energyWeight;
  final double telecomScore;
  final double energyScore;
  final List<WorkProfileKpiCategory> categories;

  factory WorkProfileKpiPerson.fromJson(Map<String, dynamic> json) {
    return WorkProfileKpiPerson(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      userName: '${json['userName'] ?? ''}',
      mainScore: (json['mainScore'] as num?)?.toDouble() ?? 0,
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
