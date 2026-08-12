class SessionSuperviseRow {
  const SessionSuperviseRow({
    required this.userId,
    required this.displayName,
    required this.username,
    required this.departmentId,
    required this.departmentName,
    required this.sessionCount,
    required this.turnCount,
    required this.lastMessageAt,
  });

  final int userId;
  final String displayName;
  final String username;
  final int? departmentId;
  final String departmentName;
  final int sessionCount;
  final int turnCount;
  final DateTime? lastMessageAt;

  String get personLabel {
    final name = displayName.trim();
    if (name.isNotEmpty) return name;
    final u = username.trim();
    if (u.isNotEmpty) return u;
    return '用户$userId';
  }

  factory SessionSuperviseRow.fromJson(Map<String, dynamic> json) {
    return SessionSuperviseRow(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      displayName: '${json['displayName'] ?? ''}',
      username: '${json['username'] ?? ''}',
      departmentId: (json['departmentId'] as num?)?.toInt(),
      departmentName: '${json['departmentName'] ?? ''}',
      sessionCount: (json['sessionCount'] as num?)?.toInt() ?? 0,
      turnCount: (json['turnCount'] as num?)?.toInt() ?? 0,
      lastMessageAt: DateTime.tryParse('${json['lastMessageAt'] ?? ''}'),
    );
  }
}

class SessionSuperviseListPageResult {
  const SessionSuperviseListPageResult({
    required this.items,
    required this.totalCount,
  });

  final List<SessionSuperviseRow> items;
  final int totalCount;
}

class SessionSuperviseSessionItem {
  const SessionSuperviseSessionItem({
    required this.conversationId,
    required this.title,
    required this.turnCount,
    required this.lastMessageAt,
  });

  final int conversationId;
  final String title;
  final int turnCount;
  final DateTime? lastMessageAt;

  factory SessionSuperviseSessionItem.fromJson(Map<String, dynamic> json) {
    return SessionSuperviseSessionItem(
      conversationId: (json['conversationId'] as num?)?.toInt() ?? 0,
      title: '${json['title'] ?? ''}'.trim(),
      turnCount: (json['turnCount'] as num?)?.toInt() ?? 0,
      lastMessageAt: DateTime.tryParse('${json['lastMessageAt'] ?? ''}'),
    );
  }
}

class SessionSuperviseDeptStat {
  const SessionSuperviseDeptStat({
    required this.departmentId,
    required this.departmentName,
    required this.sessionCount,
    required this.userCount,
  });

  final int? departmentId;
  final String departmentName;
  final int sessionCount;
  final int userCount;

  factory SessionSuperviseDeptStat.fromJson(Map<String, dynamic> json) {
    return SessionSuperviseDeptStat(
      departmentId: (json['departmentId'] as num?)?.toInt(),
      departmentName: '${json['departmentName'] ?? '未分配部门'}',
      sessionCount: (json['sessionCount'] as num?)?.toInt() ?? 0,
      userCount: (json['userCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class SessionSuperviseDeptStatsResult {
  const SessionSuperviseDeptStatsResult({
    required this.departments,
    required this.totalSessions,
    required this.superviseAll,
  });

  final List<SessionSuperviseDeptStat> departments;
  final int totalSessions;
  final bool superviseAll;

  factory SessionSuperviseDeptStatsResult.fromJson(Map<String, dynamic> json) {
    final content =
        (json['content'] as List?) ?? (json['items'] as List?) ?? const [];
    return SessionSuperviseDeptStatsResult(
      departments: content
          .whereType<Map>()
          .map(
            (e) => SessionSuperviseDeptStat.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false),
      totalSessions: (json['totalSessions'] as num?)?.toInt() ?? 0,
      superviseAll: json['superviseAll'] == true,
    );
  }
}
