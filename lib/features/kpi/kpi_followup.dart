import '../profile/work_profile_kpi.dart';

class KpiFollowupCounts {
  const KpiFollowupCounts({
    this.expected = 0,
    this.scored = 0,
    this.unscored = 0,
    this.unpublished = 0,
    this.publishedUnacked = 0,
    this.acked = 0,
  });

  final int expected;
  final int scored;
  final int unscored;
  final int unpublished;
  final int publishedUnacked;
  final int acked;

  factory KpiFollowupCounts.fromJson(Map<String, dynamic> json) {
    return KpiFollowupCounts(
      expected: (json['expected'] as num?)?.toInt() ?? 0,
      scored: (json['scored'] as num?)?.toInt() ?? 0,
      unscored: (json['unscored'] as num?)?.toInt() ?? 0,
      unpublished: (json['unpublished'] as num?)?.toInt() ?? 0,
      publishedUnacked: (json['publishedUnacked'] as num?)?.toInt() ?? 0,
      acked: (json['acked'] as num?)?.toInt() ?? 0,
    );
  }
}

class KpiFollowupGroup {
  const KpiFollowupGroup({
    this.departmentId = 0,
    required this.name,
    this.track = '',
    this.expected = 0,
    this.scored = 0,
    this.unscored = 0,
    this.unpublished = 0,
    this.publishedUnacked = 0,
    this.acked = 0,
    this.projectScore = 0,
    double projectCoefficient = 0,
    this.unscoredNames = const [],
  }) : _projectCoefficient = projectCoefficient;

  final int departmentId;
  final String name;
  final String track;
  final int expected;
  final int scored;
  final int unscored;
  final int unpublished;
  final int publishedUnacked;
  final int acked;
  final double projectScore;
  final double _projectCoefficient;
  final List<String> unscoredNames;

  /// 项目绩效系数（0.7–1.1）：10 分制项目得分按档重新算，其余沿用后端给的系数。
  double get projectCoefficient =>
      kpiProjectCoefficient(projectScore, fallback: _projectCoefficient);

  bool get isLighthouse => track == 'lighthouse';

  factory KpiFollowupGroup.fromJson(Map<String, dynamic> json) {
    return KpiFollowupGroup(
      departmentId: (json['departmentId'] as num?)?.toInt() ?? 0,
      name: '${json['name'] ?? ''}',
      track: '${json['track'] ?? ''}',
      expected: (json['expected'] as num?)?.toInt() ?? 0,
      scored: (json['scored'] as num?)?.toInt() ?? 0,
      unscored: (json['unscored'] as num?)?.toInt() ?? 0,
      unpublished: (json['unpublished'] as num?)?.toInt() ?? 0,
      publishedUnacked: (json['publishedUnacked'] as num?)?.toInt() ?? 0,
      acked: (json['acked'] as num?)?.toInt() ?? 0,
      projectScore: (json['projectScore'] as num?)?.toDouble() ?? 0,
      projectCoefficient:
          (json['projectCoefficient'] as num?)?.toDouble() ?? 0,
      unscoredNames: _stringList(json['unscoredNames']),
    );
  }
}

class KpiFollowupLeader {
  const KpiFollowupLeader({
    this.userId = 0,
    required this.userName,
    this.done = false,
    this.expected = 0,
    this.scored = 0,
    this.unscored = 0,
    this.unscoredNames = const [],
  });

  final int userId;
  final String userName;
  final bool done;
  final int expected;
  final int scored;
  final int unscored;
  final List<String> unscoredNames;

  factory KpiFollowupLeader.fromJson(Map<String, dynamic> json) {
    return KpiFollowupLeader(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      userName: '${json['userName'] ?? ''}',
      done: json['done'] == true,
      expected: (json['expected'] as num?)?.toInt() ?? 0,
      scored: (json['scored'] as num?)?.toInt() ?? 0,
      unscored: (json['unscored'] as num?)?.toInt() ?? 0,
      unscoredNames: _stringList(json['unscoredNames']),
    );
  }
}

class KpiFollowupPerson {
  const KpiFollowupPerson({
    required this.userId,
    required this.userName,
    this.departmentName = '',
    this.supervisorName = '',
    this.position = '',
  });

  final int userId;
  final String userName;
  final String departmentName;
  final String supervisorName;
  final String position;

  String get subtitle {
    final parts = [
      if (departmentName.trim().isNotEmpty) departmentName.trim(),
      if (supervisorName.trim().isNotEmpty) supervisorName.trim(),
    ];
    return parts.join(' · ');
  }

  factory KpiFollowupPerson.fromJson(Map<String, dynamic> json) {
    return KpiFollowupPerson(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      userName: '${json['userName'] ?? ''}',
      departmentName: '${json['departmentName'] ?? ''}',
      supervisorName: '${json['supervisorName'] ?? ''}',
      position: '${json['position'] ?? ''}',
    );
  }
}

class KpiFollowupMembers {
  const KpiFollowupMembers({
    this.unpublished = const [],
    this.publishedUnacked = const [],
    this.acked = const [],
  });

  final List<KpiFollowupPerson> unpublished;
  final List<KpiFollowupPerson> publishedUnacked;
  final List<KpiFollowupPerson> acked;

  factory KpiFollowupMembers.fromJson(Map<String, dynamic> json) {
    return KpiFollowupMembers(
      unpublished: _people(json['unpublished']),
      publishedUnacked: _people(json['publishedUnacked']),
      acked: _people(json['acked']),
    );
  }
}

class KpiFollowupBoard {
  const KpiFollowupBoard({
    required this.month,
    this.summary = const KpiFollowupCounts(),
    this.sectors = const [],
  });

  final String month;
  final KpiFollowupCounts summary;
  final List<KpiFollowupSector> sectors;

  factory KpiFollowupBoard.fromJson(Map<String, dynamic> json) {
    final summaryRaw = json['summary'];
    return KpiFollowupBoard(
      month: '${json['month'] ?? ''}',
      summary: summaryRaw is Map
          ? KpiFollowupCounts.fromJson(Map<String, dynamic>.from(summaryRaw))
          : const KpiFollowupCounts(),
      sectors: (json['sectors'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => KpiFollowupSector.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }
}

class KpiFollowupSector {
  const KpiFollowupSector({
    required this.key,
    required this.name,
    this.summary = const KpiFollowupCounts(),
    this.groups = const [],
    this.leaders = const [],
    this.members = const KpiFollowupMembers(),
  });

  final String key;
  final String name;
  final KpiFollowupCounts summary;
  final List<KpiFollowupGroup> groups;
  final List<KpiFollowupLeader> leaders;
  final KpiFollowupMembers members;

  bool get isLighthouse =>
      groups.isNotEmpty && groups.every((g) => g.isLighthouse);

  factory KpiFollowupSector.fromJson(Map<String, dynamic> json) {
    final summaryRaw = json['summary'];
    final membersRaw = json['members'];
    return KpiFollowupSector(
      key: '${json['key'] ?? ''}',
      name: '${json['name'] ?? ''}',
      summary: summaryRaw is Map
          ? KpiFollowupCounts.fromJson(Map<String, dynamic>.from(summaryRaw))
          : const KpiFollowupCounts(),
      groups: (json['groups'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => KpiFollowupGroup.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      leaders: (json['leaders'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => KpiFollowupLeader.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      members: membersRaw is Map
          ? KpiFollowupMembers.fromJson(Map<String, dynamic>.from(membersRaw))
          : const KpiFollowupMembers(),
    );
  }
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if ('$item'.trim().isNotEmpty) '$item'.trim(),
  ];
}

List<KpiFollowupPerson> _people(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map)
        KpiFollowupPerson.fromJson(Map<String, dynamic>.from(item)),
  ];
}
