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
    this.overdue = false,
    this.coOwnerUserIds = const [],
    this.aiState = '',
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
  final bool overdue;
  final List<int> coOwnerUserIds;

  /// 服务端展示态：analyzing = AI 分析中，binding = AI 匹配知识库中。
  final String aiState;

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
      overdue: json['overdue'] == true,
      coOwnerUserIds:
          (json['coOwnerUserIds'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList(growable: false) ??
          const [],
      aiState: '${json['aiState'] ?? ''}',
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
    this.mainOverdue = 0,
    this.avgProgress = 0,
    this.pendingApproval = 0,
    this.rejected = 0,
  });

  final int departmentId;
  final String departmentName;
  final int mainTotal;
  final int mainCompleted;
  final int mainOverdue;
  final double avgProgress;
  final int pendingApproval;
  final int rejected;

  factory HrbpDeptStat.fromJson(Map<String, dynamic> json) {
    return HrbpDeptStat(
      departmentId: (json['departmentId'] as num?)?.toInt() ?? 0,
      departmentName: '${json['departmentName'] ?? ''}',
      mainTotal: (json['mainTotal'] as num?)?.toInt() ?? 0,
      mainCompleted: (json['mainCompleted'] as num?)?.toInt() ?? 0,
      mainOverdue: (json['mainOverdue'] as num?)?.toInt() ?? 0,
      avgProgress: (json['avgProgress'] as num?)?.toDouble() ?? 0,
      pendingApproval: (json['pendingApproval'] as num?)?.toInt() ?? 0,
      rejected: (json['rejected'] as num?)?.toInt() ?? 0,
    );
  }
}

String taskStatusLabel(String status) {
  switch (status) {
    case 'pending_approval':
      return '待审核';
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
