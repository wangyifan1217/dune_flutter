class AppUsageHeatmap {
  const AppUsageHeatmap({
    required this.from,
    required this.to,
    required this.activeUsers,
    required this.sessionCount,
    required this.durationMs,
    required this.superviseAll,
    required this.dates,
    required this.modules,
    required this.matrix,
    required this.pages,
    required this.departments,
  });

  final String from;
  final String to;
  final List<String> dates;
  final int activeUsers;
  final int sessionCount;
  final int durationMs;
  final bool superviseAll;
  final List<AppUsageModule> modules;
  final List<AppUsageHeatRow> matrix;
  final List<AppUsagePageStay> pages;
  final List<AppUsageDept> departments;

  factory AppUsageHeatmap.fromJson(Map<String, dynamic> json) {
    return AppUsageHeatmap(
      from: '${json['from'] ?? ''}',
      to: '${json['to'] ?? ''}',
      dates: (json['dates'] as List?)?.map((e) => '$e').toList() ?? const [],
      activeUsers: (json['activeUsers'] as num?)?.toInt() ?? 0,
      sessionCount: (json['sessionCount'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      superviseAll: json['superviseAll'] == true,
      modules: _list(json['modules'], AppUsageModule.fromJson),
      matrix: _list(json['matrix'], AppUsageHeatRow.fromJson),
      pages: _list(json['pages'], AppUsagePageStay.fromJson),
      departments: _list(json['departments'], AppUsageDept.fromJson),
    );
  }
}

class AppUsageHeatRow {
  const AppUsageHeatRow({
    required this.moduleKey,
    required this.moduleName,
    required this.values,
  });

  final String moduleKey;
  final String moduleName;
  final List<int> values;

  factory AppUsageHeatRow.fromJson(Map<String, dynamic> json) {
    return AppUsageHeatRow(
      moduleKey: '${json['moduleKey'] ?? ''}',
      moduleName: '${json['moduleName'] ?? ''}',
      values: (json['values'] as List?)
              ?.map((e) => (e as num?)?.toInt() ?? 0)
              .toList() ??
          const [],
    );
  }
}

class AppUsageModule {
  const AppUsageModule({
    required this.moduleKey,
    required this.moduleName,
    required this.uv,
    required this.pv,
    required this.durationMs,
  });

  final String moduleKey;
  final String moduleName;
  final int uv;
  final int pv;
  final int durationMs;

  factory AppUsageModule.fromJson(Map<String, dynamic> json) {
    return AppUsageModule(
      moduleKey: '${json['moduleKey'] ?? ''}',
      moduleName: '${json['moduleName'] ?? json['moduleKey'] ?? ''}',
      uv: (json['uv'] as num?)?.toInt() ?? 0,
      pv: (json['pv'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class AppUsagePageStay {
  const AppUsagePageStay({
    required this.screenId,
    required this.screenName,
    required this.moduleKey,
    required this.uv,
    required this.pv,
    required this.durationMs,
  });

  final String screenId;
  final String screenName;
  final String moduleKey;
  final int uv;
  final int pv;
  final int durationMs;

  factory AppUsagePageStay.fromJson(Map<String, dynamic> json) {
    return AppUsagePageStay(
      screenId: '${json['screenId'] ?? ''}',
      screenName: '${json['screenName'] ?? json['screenId'] ?? ''}',
      moduleKey: '${json['moduleKey'] ?? ''}',
      uv: (json['uv'] as num?)?.toInt() ?? 0,
      pv: (json['pv'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class AppUsageDept {
  const AppUsageDept({
    this.departmentId,
    required this.departmentName,
    required this.userCount,
    required this.durationMs,
  });

  final int? departmentId;
  final String departmentName;
  final int userCount;
  final int durationMs;

  factory AppUsageDept.fromJson(Map<String, dynamic> json) {
    return AppUsageDept(
      departmentId: (json['departmentId'] as num?)?.toInt(),
      departmentName: '${json['departmentName'] ?? '未分配部门'}',
      userCount: (json['userCount'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class AppUsageUserRow {
  const AppUsageUserRow({
    required this.userId,
    required this.displayName,
    this.departmentId,
    required this.departmentName,
    required this.durationMs,
    required this.pv,
    required this.sessionCount,
    this.lastSeenAt,
    this.topModule = '',
    this.topModuleName = '',
  });

  final int userId;
  final String displayName;
  final int? departmentId;
  final String departmentName;
  final int durationMs;
  final int pv;
  final int sessionCount;
  final String? lastSeenAt;
  final String topModule;
  final String topModuleName;

  factory AppUsageUserRow.fromJson(Map<String, dynamic> json) {
    return AppUsageUserRow(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      displayName: '${json['displayName'] ?? '用户'}',
      departmentId: (json['departmentId'] as num?)?.toInt(),
      departmentName: '${json['departmentName'] ?? ''}',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      pv: (json['pv'] as num?)?.toInt() ?? 0,
      sessionCount: (json['sessionCount'] as num?)?.toInt() ?? 0,
      lastSeenAt: json['lastSeenAt']?.toString(),
      topModule: '${json['topModule'] ?? ''}',
      topModuleName: '${json['topModuleName'] ?? ''}',
    );
  }
}

class AppUsageUsersPage {
  const AppUsageUsersPage({
    required this.items,
    required this.total,
    required this.superviseAll,
  });

  final List<AppUsageUserRow> items;
  final int total;
  final bool superviseAll;
}

class AppUsageUserDetail {
  const AppUsageUserDetail({
    required this.userId,
    required this.displayName,
    required this.departmentName,
    required this.durationMs,
    required this.sessionCount,
    required this.pv,
    this.topModule = '',
    this.topModuleName = '',
    required this.pages,
    required this.days,
  });

  final int userId;
  final String displayName;
  final String departmentName;
  final int durationMs;
  final int sessionCount;
  final int pv;
  final String topModule;
  final String topModuleName;
  final List<AppUsagePageStay> pages;
  final List<AppUsageDayStay> days;

  factory AppUsageUserDetail.fromJson(Map<String, dynamic> json) {
    return AppUsageUserDetail(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      displayName: '${json['displayName'] ?? '用户'}',
      departmentName: '${json['departmentName'] ?? ''}',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      sessionCount: (json['sessionCount'] as num?)?.toInt() ?? 0,
      pv: (json['pv'] as num?)?.toInt() ?? 0,
      topModule: '${json['topModule'] ?? ''}',
      topModuleName: '${json['topModuleName'] ?? ''}',
      pages: _list(json['pages'], AppUsagePageStay.fromJson),
      days: _list(json['days'], AppUsageDayStay.fromJson),
    );
  }
}

class AppUsageDayStay {
  const AppUsageDayStay({
    required this.date,
    required this.durationMs,
    required this.pv,
  });

  final String date;
  final int durationMs;
  final int pv;

  factory AppUsageDayStay.fromJson(Map<String, dynamic> json) {
    return AppUsageDayStay(
      date: '${json['date'] ?? ''}',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      pv: (json['pv'] as num?)?.toInt() ?? 0,
    );
  }
}

List<T> _list<T>(
  dynamic raw,
  T Function(Map<String, dynamic> json) map,
) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => map(Map<String, dynamic>.from(e)))
      .toList(growable: false);
}

String formatUsageStay(int durationMs) {
  if (durationMs <= 0) return '0分';
  final minutes = (durationMs / 60000).round();
  if (minutes < 60) return '$minutes分';
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  if (rem == 0) return '$hours小时';
  return '$hours小时$rem分';
}

double usageAvgMinutes(int durationMs, int users) {
  if (users <= 0 || durationMs <= 0) return 0;
  return durationMs / users / 60000;
}
