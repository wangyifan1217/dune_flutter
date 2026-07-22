class CursorSuperviseRow {
  const CursorSuperviseRow({
    required this.bindingId,
    required this.userId,
    required this.displayName,
    required this.username,
    required this.departmentId,
    required this.departmentName,
    required this.cursorAccountId,
    required this.email,
    required this.accountLabel,
    required this.membershipType,
    required this.isPro,
    required this.remainingDays,
    required this.totalUsagePercent,
    required this.autoUsagePercent,
    required this.apiUsagePercent,
  });

  final int bindingId;
  final int userId;
  final String displayName;
  final String username;
  final int? departmentId;
  final String departmentName;
  final String cursorAccountId;
  final String email;
  final String accountLabel;
  final String membershipType;
  final bool isPro;
  final int? remainingDays;
  final int? totalUsagePercent;
  final int? autoUsagePercent;
  final int? apiUsagePercent;

  String get personLabel {
    final name = displayName.trim();
    if (name.isNotEmpty) return name;
    final u = username.trim();
    if (u.isNotEmpty) return u;
    return '用户$userId';
  }

  String get accountText {
    final a = accountLabel.trim();
    if (a.isNotEmpty) return a;
    final e = email.trim();
    if (e.isNotEmpty) return e;
    return cursorAccountId;
  }

  String get membershipLabel {
    final m = membershipType.trim();
    if (m.isNotEmpty) return m;
    return isPro ? 'Pro' : '—';
  }

  factory CursorSuperviseRow.fromJson(Map<String, dynamic> json) {
    return CursorSuperviseRow(
      bindingId: (json['bindingId'] as num?)?.toInt() ?? 0,
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      displayName: '${json['displayName'] ?? ''}',
      username: '${json['username'] ?? ''}',
      departmentId: (json['departmentId'] as num?)?.toInt(),
      departmentName: '${json['departmentName'] ?? ''}',
      cursorAccountId: '${json['cursorAccountId'] ?? ''}',
      email: '${json['email'] ?? ''}',
      accountLabel: '${json['accountLabel'] ?? ''}',
      membershipType: '${json['membershipType'] ?? ''}',
      isPro: json['isPro'] == true,
      remainingDays: (json['remainingDays'] as num?)?.toInt(),
      totalUsagePercent: (json['totalUsagePercent'] as num?)?.toInt(),
      autoUsagePercent: (json['autoUsagePercent'] as num?)?.toInt(),
      apiUsagePercent: (json['apiUsagePercent'] as num?)?.toInt(),
    );
  }
}

class CursorSuperviseListPageResult {
  const CursorSuperviseListPageResult({
    required this.items,
    required this.totalCount,
  });

  final List<CursorSuperviseRow> items;
  final int totalCount;
}

class CursorSuperviseDeptStat {
  const CursorSuperviseDeptStat({
    required this.departmentId,
    required this.departmentName,
    required this.accountCount,
  });

  final int? departmentId;
  final String departmentName;
  final int accountCount;

  factory CursorSuperviseDeptStat.fromJson(Map<String, dynamic> json) {
    return CursorSuperviseDeptStat(
      departmentId: (json['departmentId'] as num?)?.toInt(),
      departmentName: '${json['departmentName'] ?? '未分配部门'}',
      accountCount: (json['accountCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class CursorSuperviseDeptStatsResult {
  const CursorSuperviseDeptStatsResult({
    required this.departments,
    required this.totalAccounts,
    required this.superviseAll,
  });

  final List<CursorSuperviseDeptStat> departments;
  final int totalAccounts;
  final bool superviseAll;

  factory CursorSuperviseDeptStatsResult.fromJson(Map<String, dynamic> json) {
    final content =
        (json['content'] as List?) ?? (json['items'] as List?) ?? const [];
    return CursorSuperviseDeptStatsResult(
      departments: content
          .whereType<Map>()
          .map(
            (e) =>
                CursorSuperviseDeptStat.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
      totalAccounts: (json['totalAccounts'] as num?)?.toInt() ?? 0,
      superviseAll: json['superviseAll'] == true,
    );
  }
}

class CursorSuperviseDailySpendItem {
  const CursorSuperviseDailySpendItem({
    required this.day,
    required this.dayMs,
    required this.model,
    required this.spendCents,
    required this.spendDollars,
    required this.totalTokens,
    required this.tokensMillions,
  });

  final String day;
  final int dayMs;
  final String model;
  final int spendCents;
  final double spendDollars;
  final String totalTokens;
  final double tokensMillions;

  String get spendDollarLabel => '\$${spendDollars.toStringAsFixed(2)}';

  String get tokensMLabel {
    if (tokensMillions <= 0) return '0M';
    if (tokensMillions >= 10) {
      return '${tokensMillions.toStringAsFixed(1)}M';
    }
    return '${tokensMillions.toStringAsFixed(2)}M';
  }

  factory CursorSuperviseDailySpendItem.fromJson(Map<String, dynamic> json) {
    return CursorSuperviseDailySpendItem(
      day: '${json['day'] ?? ''}',
      dayMs: (json['dayMs'] as num?)?.toInt() ?? 0,
      model: '${json['model'] ?? json['category'] ?? ''}',
      spendCents: (json['spendCents'] as num?)?.toInt() ?? 0,
      spendDollars: (json['spendDollars'] as num?)?.toDouble() ??
          (((json['spendCents'] as num?)?.toDouble() ?? 0) / 100.0),
      totalTokens: '${json['totalTokens'] ?? '0'}',
      tokensMillions: (json['tokensMillions'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CursorSuperviseDailySpendResult {
  const CursorSuperviseDailySpendResult({
    required this.bindingId,
    required this.cursorAccountId,
    required this.displayName,
    required this.email,
    required this.items,
  });

  final int bindingId;
  final String cursorAccountId;
  final String displayName;
  final String email;
  final List<CursorSuperviseDailySpendItem> items;

  factory CursorSuperviseDailySpendResult.fromJson(Map<String, dynamic> json) {
    final content =
        (json['content'] as List?) ??
        (json['dailySpend'] as List?) ??
        const [];
    return CursorSuperviseDailySpendResult(
      bindingId: (json['bindingId'] as num?)?.toInt() ?? 0,
      cursorAccountId: '${json['cursorAccountId'] ?? ''}',
      displayName: '${json['displayName'] ?? ''}',
      email: '${json['email'] ?? ''}',
      items: content
          .whereType<Map>()
          .map(
            (e) => CursorSuperviseDailySpendItem.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false),
    );
  }
}
