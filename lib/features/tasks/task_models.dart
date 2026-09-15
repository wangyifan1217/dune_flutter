class TaskItem {
  const TaskItem({
    required this.id,
    this.parentId,
    required this.title,
    this.description = '',
    this.priority = 'medium',
    this.category = '',
    required this.ownerUserId,
    required this.creatorUserId,
    this.departmentId,
    this.status = 'active',
    this.progressPct = 0,
    this.weight = 1,
    this.startAt,
    this.dueAt,
    this.acceptanceCriteria = '',
    this.source = 'assigned',
    this.approverUserId,
    this.approvalComment = '',
    this.evalLevel = '',
    this.evalComment = '',
    this.evalBy,
    this.evalAt,
    this.evalByName = '',
    this.subtaskCount = 0,
    this.ownerName = '',
    this.ownerAvatarPreset = '',
    this.ownerAvatarObjectKey = '',
    this.ownerAvatarUrl = '',
    this.creatorName = '',
    this.approverName = '',
    this.parentTitle = '',
    this.sourceMeetingTitle = '',
    this.overdue = false,
    this.coOwnerUserIds = const [],
    this.aiState = '',
    this.completedAt,
    this.completedAtInferred = false,
    this.assessmentIncluded = false,
    this.assessmentWeight = 1,
    this.openItemCount = 0,
    this.itemsReadyToClose = false,
    this.displayStatus = '',
  });

  final int id;
  final int? parentId;
  final String title;
  final String description;
  final String priority;
  final String category;
  final int ownerUserId;
  final int creatorUserId;
  final int? departmentId;
  final String status;
  final int progressPct;
  final double weight;
  final DateTime? startAt;
  final DateTime? dueAt;
  final String acceptanceCriteria;
  final String source;
  final int? approverUserId;
  final String approvalComment;
  final String evalLevel;
  final String evalComment;
  final int? evalBy;
  final DateTime? evalAt;
  final String evalByName;
  final int subtaskCount;
  final String ownerName;
  final String ownerAvatarPreset;
  final String ownerAvatarObjectKey;
  final String ownerAvatarUrl;
  final String creatorName;
  final String approverName;
  final String parentTitle;
  final String sourceMeetingTitle;
  final bool overdue;
  final List<int> coOwnerUserIds;

  /// 服务端展示态：analyzing = AI 分析中，binding = AI 匹配知识库中。
  final String aiState;
  final DateTime? completedAt;
  final bool completedAtInferred;
  final bool assessmentIncluded;
  final double assessmentWeight;
  final int openItemCount;
  final bool itemsReadyToClose;
  final String displayStatus;

  bool get isMain => parentId == null;
  bool get isPending => status == 'pending_approval';
  bool get hasEval =>
      evalBy != null ||
      evalLevel.trim().isNotEmpty ||
      evalComment.trim().isNotEmpty;

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseTime(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return TaskItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      parentId: (json['parentId'] as num?)?.toInt(),
      title: '${json['title'] ?? ''}',
      description: '${json['description'] ?? ''}',
      priority: '${json['priority'] ?? 'medium'}',
      category: '${json['category'] ?? ''}',
      ownerUserId: (json['ownerUserId'] as num?)?.toInt() ?? 0,
      creatorUserId: (json['creatorUserId'] as num?)?.toInt() ?? 0,
      departmentId: (json['departmentId'] as num?)?.toInt(),
      status: '${json['status'] ?? 'active'}',
      progressPct: (json['progressPct'] as num?)?.toInt() ?? 0,
      weight: (json['weight'] as num?)?.toDouble() ?? 1,
      startAt: parseTime(json['startAt']),
      dueAt: parseTime(json['dueAt']),
      acceptanceCriteria: '${json['acceptanceCriteria'] ?? ''}',
      source: '${json['source'] ?? 'assigned'}',
      approverUserId: (json['approverUserId'] as num?)?.toInt(),
      approvalComment: '${json['approvalComment'] ?? ''}',
      evalLevel: '${json['evalLevel'] ?? ''}',
      evalComment: '${json['evalComment'] ?? ''}',
      evalBy: (json['evalBy'] as num?)?.toInt(),
      evalAt: parseTime(json['evalAt']),
      evalByName: '${json['evalByName'] ?? ''}',
      subtaskCount: (json['subtaskCount'] as num?)?.toInt() ?? 0,
      ownerName: '${json['ownerName'] ?? ''}',
      ownerAvatarPreset: '${json['ownerAvatarPreset'] ?? ''}',
      ownerAvatarObjectKey: '${json['ownerAvatarObjectKey'] ?? ''}',
      ownerAvatarUrl: '${json['ownerAvatarUrl'] ?? ''}',
      creatorName: '${json['creatorName'] ?? ''}',
      approverName: '${json['approverName'] ?? ''}',
      parentTitle: '${json['parentTitle'] ?? ''}',
      sourceMeetingTitle: '${json['sourceMeetingTitle'] ?? ''}',
      overdue: json['overdue'] == true,
      coOwnerUserIds:
          (json['coOwnerUserIds'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList(growable: false) ??
          const [],
      aiState: '${json['aiState'] ?? ''}',
      completedAt: parseTime(json['completedAt']),
      completedAtInferred: json['completedAtInferred'] == true,
      assessmentIncluded: json['assessmentIncluded'] == true,
      assessmentWeight: (json['assessmentWeight'] as num?)?.toDouble() ?? 1,
      openItemCount: (json['openItemCount'] as num?)?.toInt() ?? 0,
      itemsReadyToClose: json['itemsReadyToClose'] == true,
      displayStatus: '${json['displayStatus'] ?? ''}',
    );
  }
}

class TaskAttachment {
  const TaskAttachment({
    required this.id,
    required this.taskId,
    required this.fileName,
    this.objectKey = '',
    this.url = '',
    this.bucket = 'xflow-proposals',
    this.sizeBytes = 0,
    this.mimeType = '',
  });

  final int id;
  final int taskId;
  final String fileName;
  final String objectKey;
  final String url;
  final String bucket;
  final int sizeBytes;
  final String mimeType;

  factory TaskAttachment.fromJson(Map<String, dynamic> json) {
    return TaskAttachment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      taskId: (json['taskId'] as num?)?.toInt() ?? 0,
      fileName: '${json['fileName'] ?? ''}',
      objectKey: '${json['objectKey'] ?? ''}',
      url: '${json['url'] ?? ''}',
      bucket: '${json['bucket'] ?? 'xflow-proposals'}',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      mimeType: '${json['mimeType'] ?? ''}',
    );
  }

  Map<String, dynamic> toCreateJson() => {
    'fileName': fileName,
    'objectKey': objectKey,
    'url': url,
    'bucket': bucket,
    'sizeBytes': sizeBytes,
    'mimeType': mimeType,
  };
}

class TaskDetail {
  const TaskDetail({
    required this.task,
    this.subtasks = const [],
    this.logs = const [],
    this.evalLogs = const [],
    this.attachments = const [],
  });

  final TaskItem task;
  final List<TaskItem> subtasks;
  final List<TaskProgressLog> logs;
  final List<TaskEvalLog> evalLogs;
  final List<TaskAttachment> attachments;
}

class TaskProgressLog {
  const TaskProgressLog({
    required this.id,
    required this.taskId,
    required this.userId,
    required this.progressPct,
    this.note = '',
    required this.createdAt,
    this.userName = '',
    this.taskTitle = '',
    this.isSubtask = false,
    this.attachments = const [],
    this.canDelete = false,
  });

  final int id;
  final int taskId;
  final int userId;
  final int progressPct;
  final String note;
  final DateTime createdAt;
  final String userName;
  final String taskTitle;
  final bool isSubtask;
  final List<TaskAttachment> attachments;
  final bool canDelete;

  factory TaskProgressLog.fromJson(Map<String, dynamic> json) {
    return TaskProgressLog(
      id: (json['id'] as num?)?.toInt() ?? 0,
      taskId: (json['taskId'] as num?)?.toInt() ?? 0,
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      progressPct: (json['progressPct'] as num?)?.toInt() ?? 0,
      note: '${json['note'] ?? ''}',
      createdAt:
          DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
      userName: '${json['userName'] ?? ''}',
      taskTitle: '${json['taskTitle'] ?? ''}',
      isSubtask: json['isSubtask'] == true,
      attachments: (json['attachments'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => TaskAttachment.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      canDelete: json['canDelete'] == true,
    );
  }
}

class TaskEvalLog {
  const TaskEvalLog({
    required this.id,
    required this.taskId,
    required this.userId,
    required this.level,
    this.comment = '',
    required this.createdAt,
    this.userName = '',
    this.taskTitle = '',
    this.isSubtask = false,
    this.attachments = const [],
    this.canDelete = false,
  });

  final int id;
  final int taskId;
  final int userId;
  final String level;
  final String comment;
  final DateTime createdAt;
  final String userName;
  final String taskTitle;
  final bool isSubtask;
  final List<TaskAttachment> attachments;
  final bool canDelete;

  factory TaskEvalLog.fromJson(Map<String, dynamic> json) {
    return TaskEvalLog(
      id: (json['id'] as num?)?.toInt() ?? 0,
      taskId: (json['taskId'] as num?)?.toInt() ?? 0,
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      level: '${json['level'] ?? ''}',
      comment: '${json['comment'] ?? ''}',
      createdAt:
          DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
      userName: '${json['userName'] ?? ''}',
      taskTitle: '${json['taskTitle'] ?? ''}',
      isSubtask: json['isSubtask'] == true,
      attachments: (json['attachments'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => TaskAttachment.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      canDelete: json['canDelete'] == true,
    );
  }
}

class TaskAssignee {
  const TaskAssignee({
    required this.id,
    required this.displayName,
    this.departmentName = '',
    this.avatarPreset = '',
    this.avatarObjectKey = '',
    this.avatarUrl = '',
  });

  final int id;
  final String displayName;
  final String departmentName;
  final String avatarPreset;
  final String avatarObjectKey;
  final String avatarUrl;

  factory TaskAssignee.fromJson(Map<String, dynamic> json) {
    return TaskAssignee(
      id: (json['id'] as num?)?.toInt() ?? 0,
      displayName: '${json['displayName'] ?? ''}',
      departmentName: '${json['departmentName'] ?? ''}',
      avatarPreset: '${json['avatarPreset'] ?? ''}',
      avatarObjectKey: '${json['avatarObjectKey'] ?? ''}',
      avatarUrl: '${json['avatarUrl'] ?? ''}',
    );
  }
}

class TaskListPage {
  const TaskListPage({
    required this.items,
    this.hasMore = false,
    this.total = 0,
    this.active = 0,
    this.completed = 0,
  });

  final List<TaskItem> items;
  final bool hasMore;
  final int total;
  final int active;
  final int completed;

  factory TaskListPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((e) => TaskItem.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : const <TaskItem>[];
    return TaskListPage(
      items: items,
      hasMore: json['hasMore'] == true,
      total: (json['total'] as num?)?.toInt() ?? items.length,
      active: (json['active'] as num?)?.toInt() ?? 0,
      completed: (json['completed'] as num?)?.toInt() ?? 0,
    );
  }
}

class HrbpDeptStat {
  const HrbpDeptStat({
    required this.departmentId,
    this.departmentName = '',
    this.mainTotal = 0,
    this.mainCompleted = 0,
    this.mainOnTimeCompleted = 0,
    this.mainOverdue = 0,
    this.inProgressRisk = 0,
    this.avgProgress = 0,
    this.pendingApproval = 0,
    this.rejected = 0,
    this.dailyReportExpected = 0,
    this.dailyReportSubmitted = 0,
    this.dailyReportRate = 0,
  });

  final int departmentId;
  final String departmentName;
  final int mainTotal;
  final int mainCompleted;
  final int mainOnTimeCompleted;
  final int mainOverdue;
  final int inProgressRisk;
  final double avgProgress;
  final int pendingApproval;
  final int rejected;
  final int dailyReportExpected;
  final int dailyReportSubmitted;
  final double dailyReportRate;

  factory HrbpDeptStat.fromJson(Map<String, dynamic> json) {
    return HrbpDeptStat(
      departmentId: (json['departmentId'] as num?)?.toInt() ?? 0,
      departmentName: '${json['departmentName'] ?? ''}',
      mainTotal: (json['mainTotal'] as num?)?.toInt() ?? 0,
      mainCompleted: (json['mainCompleted'] as num?)?.toInt() ?? 0,
      mainOnTimeCompleted: (json['mainOnTimeCompleted'] as num?)?.toInt() ?? 0,
      mainOverdue: (json['mainOverdue'] as num?)?.toInt() ?? 0,
      inProgressRisk: (json['inProgressRisk'] as num?)?.toInt() ?? 0,
      avgProgress: (json['avgProgress'] as num?)?.toDouble() ?? 0,
      pendingApproval: (json['pendingApproval'] as num?)?.toInt() ?? 0,
      rejected: (json['rejected'] as num?)?.toInt() ?? 0,
      dailyReportExpected: (json['dailyReportExpected'] as num?)?.toInt() ?? 0,
      dailyReportSubmitted:
          (json['dailyReportSubmitted'] as num?)?.toInt() ?? 0,
      dailyReportRate: (json['dailyReportRate'] as num?)?.toDouble() ?? 0,
    );
  }

  /// 主目标是否都已办结（与填报进度是否 100% 无关）。
  bool get allClosed => mainTotal > 0 && mainCompleted >= mainTotal;

  String get summaryLine {
    final parts = <String>['$mainTotal 个主目标', '$mainCompleted 已办结'];
    if (mainOverdue > 0) parts.add('$mainOverdue 已逾期未办结');
    return parts.join(' · ');
  }
}

String taskFillProgressLabel(int progressPct) => '填报 $progressPct%';

/// 逾期且未办结时的说明；进度拉满仍可能返回文案。
String? taskUnfinishedOverdueHint({
  required bool overdue,
  required bool completed,
  required int progressPct,
}) {
  if (!overdue || completed) return null;
  if (progressPct >= 100) {
    return '已过截止日，尚未办结。进度填满不等于已经完成。';
  }
  return '已过截止日，尚未办结。';
}

String formatTaskYmd(DateTime? d) {
  if (d == null) return '';
  final local = d.toLocal();
  final m = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$m-$day';
}

String? taskCreateRangeLabel(DateTime? startAt, DateTime? dueAt) {
  if (startAt == null && dueAt == null) return null;
  if (startAt != null && dueAt != null) {
    return '${formatTaskYmd(startAt)} ~ ${formatTaskYmd(dueAt)}';
  }
  if (startAt != null) return '起 ${formatTaskYmd(startAt)}';
  return '止 ${formatTaskYmd(dueAt!)}';
}

/// 新建任务周期，开始时间和结束时间必填。
String? taskCreateRangeError(
  DateTime? startAt,
  DateTime? dueAt, {
  bool required = true,
}) {
  if (startAt == null || dueAt == null) {
    return required ? '请选择开始时间和结束时间' : null;
  }
  final start = DateTime(startAt.year, startAt.month, startAt.day);
  final due = DateTime(dueAt.year, dueAt.month, dueAt.day);
  if (due.isBefore(start)) return '结束时间不能早于开始时间';
  return null;
}

String? taskPostponeError({
  required DateTime? startAt,
  required DateTime? currentDue,
  required DateTime? newDue,
}) {
  if (newDue == null) return '请选择新的截止日';
  final dueDay = DateTime(newDue.year, newDue.month, newDue.day);
  if (startAt != null) {
    final startDay = DateTime(startAt.year, startAt.month, startAt.day);
    if (dueDay.isBefore(startDay)) return '结束时间不能早于开始时间';
  }
  if (currentDue != null) {
    final cur = DateTime(currentDue.year, currentDue.month, currentDue.day);
    if (!dueDay.isAfter(cur)) return '新的截止日必须晚于当前截止日';
  }
  return null;
}

String taskStatusLabel(String status) {
  switch (status) {
    case 'not_started':
      return '待开始';
    case 'pending_approval':
      return '待确认';
    case 'completed':
      return '已完成';
    case 'cancelled':
      return '已取消';
    case 'rejected':
      return '已驳回';
    case 'draft':
      return '草稿';
    default:
      return '进行中';
  }
}

String taskKindLabel(TaskItem task) => task.isMain ? '主目标' : '子目标';

String taskDisplayStatusLabel(TaskItem task) {
  final raw = task.displayStatus.trim();
  if (raw.isNotEmpty) return taskStatusLabel(raw);
  return taskStatusLabel(task.status);
}

String taskPriorityLabel(String priority) {
  switch (priority) {
    case 'low':
      return '低';
    case 'high':
      return '高';
    case 'urgent':
      return '紧急';
    default:
      return '中';
  }
}

/// 描述若只是标题复写，详情不再重复展示。
String taskDistinctDescription(TaskItem task) {
  final desc = task.description.trim();
  if (desc.isEmpty || desc == task.title.trim()) return '';
  return desc;
}

/// 列表卡补充信息：会议来源或描述首句。
String? taskCardContextLine(TaskItem task) {
  final meeting = task.sourceMeetingTitle.trim();
  if (meeting.isNotEmpty) return '来自《$meeting》';
  final desc = taskDistinctDescription(task);
  if (desc.isEmpty) return null;
  final line = desc.split('\n').first.trim();
  if (line.isEmpty) return null;
  if (line.length <= 36) return line;
  return '${line.substring(0, 36)}…';
}

class TaskDailyReportItem {
  const TaskDailyReportItem({
    this.id = 0,
    this.reportId = 0,
    required this.taskId,
    this.mainTaskId = 0,
    this.progressPct = 0,
    this.workDone = '',
    this.nextAction = '',
    this.taskTitle = '',
    this.mainTitle = '',
    this.isItem = false,
  });

  final int id;
  final int reportId;
  final int taskId;
  final int mainTaskId;
  final int progressPct;
  final String workDone;
  final String nextAction;
  final String taskTitle;
  final String mainTitle;
  final bool isItem;

  factory TaskDailyReportItem.fromJson(Map<String, dynamic> json) {
    return TaskDailyReportItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      reportId: (json['reportId'] as num?)?.toInt() ?? 0,
      taskId: (json['taskId'] as num?)?.toInt() ?? 0,
      mainTaskId: (json['mainTaskId'] as num?)?.toInt() ?? 0,
      progressPct: (json['progressPct'] as num?)?.toInt() ?? 0,
      workDone: '${json['workDone'] ?? ''}',
      nextAction: '${json['nextAction'] ?? ''}',
      taskTitle: '${json['taskTitle'] ?? ''}',
      mainTitle: '${json['mainTitle'] ?? ''}',
      isItem: json['isItem'] == true,
    );
  }
}

class TaskDailyReport {
  const TaskDailyReport({
    this.id = 0,
    this.userId = 0,
    required this.reportDate,
    this.summary = '',
    this.blockers = '',
    this.nextPlan = '',
    this.status = '',
    this.submittedAt,
    this.source = '',
    this.items = const [],
    this.comments = const [],
  });

  final int id;
  final int userId;
  final String reportDate;
  final String summary;
  final String blockers;
  final String nextPlan;
  final String status;
  final DateTime? submittedAt;
  final String source;
  final List<TaskDailyReportItem> items;
  final List<TaskDailyReportComment> comments;

  bool get submitted => status == 'submitted';

  factory TaskDailyReport.fromJson(Map<String, dynamic> json) {
    DateTime? parseTime(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return TaskDailyReport(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      reportDate: '${json['reportDate'] ?? ''}',
      summary: '${json['summary'] ?? ''}',
      blockers: '${json['blockers'] ?? ''}',
      nextPlan: '${json['nextPlan'] ?? ''}',
      status: '${json['status'] ?? ''}',
      submittedAt: parseTime(json['submittedAt']),
      source: '${json['source'] ?? ''}',
      items:
          (json['items'] as List?)
              ?.whereType<Map>()
              .map(
                (e) =>
                    TaskDailyReportItem.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList(growable: false) ??
          const [],
      comments:
          (json['comments'] as List?)
              ?.whereType<Map>()
              .map(
                (e) => TaskDailyReportComment.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList(growable: false) ??
          const [],
    );
  }
}

class TaskDailyReportComment {
  const TaskDailyReportComment({
    required this.id,
    required this.reportId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.userName = '',
  });

  final int id;
  final int reportId;
  final int userId;
  final String body;
  final DateTime createdAt;
  final String userName;

  factory TaskDailyReportComment.fromJson(Map<String, dynamic> json) {
    return TaskDailyReportComment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      reportId: (json['reportId'] as num?)?.toInt() ?? 0,
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      body: '${json['body'] ?? ''}',
      createdAt:
          DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
      userName: '${json['userName'] ?? ''}',
    );
  }
}

class TaskDailyReportBundle {
  const TaskDailyReportBundle({
    this.report,
    this.candidates = const [],
    this.canSubmit = false,
    this.canBackfill = false,
    this.businessDate = '',
    this.backfillUntil = '',
  });

  final TaskDailyReport? report;
  final List<TaskItem> candidates;
  final bool canSubmit;
  final bool canBackfill;
  final String businessDate;
  final String backfillUntil;

  factory TaskDailyReportBundle.fromJson(Map<String, dynamic> json) {
    return TaskDailyReportBundle(
      report: json['report'] is Map
          ? TaskDailyReport.fromJson(
              Map<String, dynamic>.from(json['report'] as Map),
            )
          : null,
      candidates:
          (json['candidates'] as List?)
              ?.whereType<Map>()
              .map((e) => TaskItem.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false) ??
          const [],
      canSubmit: json['canSubmit'] == true,
      canBackfill: json['canBackfill'] == true,
      businessDate: '${json['businessDate'] ?? ''}',
      backfillUntil: '${json['backfillUntil'] ?? ''}',
    );
  }
}
