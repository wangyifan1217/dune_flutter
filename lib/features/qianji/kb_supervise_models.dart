class KbSuperviseRow {
  const KbSuperviseRow({
    required this.userId,
    required this.displayName,
    required this.username,
    required this.departmentId,
    required this.departmentName,
    required this.folderCount,
    required this.documentCount,
  });

  final int userId;
  final String displayName;
  final String username;
  final int? departmentId;
  final String departmentName;
  final int folderCount;
  final int documentCount;

  String get personLabel {
    final name = displayName.trim();
    if (name.isNotEmpty) return name;
    final u = username.trim();
    if (u.isNotEmpty) return u;
    return '用户$userId';
  }

  factory KbSuperviseRow.fromJson(Map<String, dynamic> json) {
    return KbSuperviseRow(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      displayName: '${json['displayName'] ?? ''}',
      username: '${json['username'] ?? ''}',
      departmentId: (json['departmentId'] as num?)?.toInt(),
      departmentName: '${json['departmentName'] ?? ''}',
      folderCount: (json['folderCount'] as num?)?.toInt() ?? 0,
      documentCount: (json['documentCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class KbSuperviseListPageResult {
  const KbSuperviseListPageResult({
    required this.items,
    required this.totalCount,
  });

  final List<KbSuperviseRow> items;
  final int totalCount;
}

class KbSuperviseDeptStat {
  const KbSuperviseDeptStat({
    required this.departmentId,
    required this.departmentName,
    required this.folderCount,
    required this.documentCount,
    required this.userCount,
  });

  final int? departmentId;
  final String departmentName;
  final int folderCount;
  final int documentCount;
  final int userCount;

  factory KbSuperviseDeptStat.fromJson(Map<String, dynamic> json) {
    return KbSuperviseDeptStat(
      departmentId: (json['departmentId'] as num?)?.toInt(),
      departmentName: '${json['departmentName'] ?? '未分配部门'}',
      folderCount: (json['folderCount'] as num?)?.toInt() ?? 0,
      documentCount: (json['documentCount'] as num?)?.toInt() ?? 0,
      userCount: (json['userCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class KbSuperviseDeptStatsResult {
  const KbSuperviseDeptStatsResult({
    required this.departments,
    required this.totalFolders,
    required this.totalDocuments,
    required this.superviseAll,
  });

  final List<KbSuperviseDeptStat> departments;
  final int totalFolders;
  final int totalDocuments;
  final bool superviseAll;

  factory KbSuperviseDeptStatsResult.fromJson(Map<String, dynamic> json) {
    final content =
        (json['content'] as List?) ?? (json['items'] as List?) ?? const [];
    return KbSuperviseDeptStatsResult(
      departments: content
          .whereType<Map>()
          .map(
            (e) => KbSuperviseDeptStat.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
      totalFolders: (json['totalFolders'] as num?)?.toInt() ?? 0,
      totalDocuments: (json['totalDocuments'] as num?)?.toInt() ?? 0,
      superviseAll: json['superviseAll'] == true,
    );
  }
}
