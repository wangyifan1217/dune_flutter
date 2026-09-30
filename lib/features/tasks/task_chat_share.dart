import 'task_models.dart';

/// IM 中转发的普通任务名片。payload 中的字段只用于绘制转发时快照；
/// 打开详情时始终由服务端通过 shareRef 校验会话授权并返回最新数据。
class TaskChatShare {
  const TaskChatShare({
    required this.shareRef,
    required this.taskId,
    required this.title,
    required this.status,
    required this.priority,
    required this.ownerName,
    required this.progressPct,
    required this.overdue,
    required this.subtaskCount,
    required this.sharedAt,
    this.startAt,
    this.dueAt,
    this.isMain = true,
  });

  final String shareRef;
  final int taskId;
  final String title;
  final String status;
  final String priority;
  final String ownerName;
  final int progressPct;
  final bool overdue;
  final int subtaskCount;
  final DateTime? startAt;
  final DateTime? dueAt;
  final DateTime sharedAt;
  final bool isMain;

  factory TaskChatShare.fromTask(
    TaskItem task, {
    required String shareRef,
    required DateTime sharedAt,
  }) => TaskChatShare(
    shareRef: shareRef,
    taskId: task.id,
    title: task.title,
    status: task.status,
    priority: task.priority,
    ownerName: task.ownerName,
    progressPct: task.progressPct,
    overdue: task.overdue,
    subtaskCount: task.subtaskCount,
    startAt: task.startAt,
    dueAt: task.dueAt,
    sharedAt: sharedAt,
    isMain: task.isMain,
  );

  Map<String, dynamic> toMessagePayload() => {
    'taskShareCard': {
      'version': 1,
      'shareRef': shareRef,
      'taskId': taskId,
      'title': title,
      'status': status,
      'priority': priority,
      'ownerName': ownerName,
      'progressPct': progressPct,
      'overdue': overdue,
      'subtaskCount': subtaskCount,
      if (startAt != null) 'startAt': startAt!.toIso8601String(),
      if (dueAt != null) 'dueAt': dueAt!.toIso8601String(),
      'sharedAt': sharedAt.toIso8601String(),
      'isMain': isMain,
    },
  };

  TaskChatShare withShareRef(String value) => TaskChatShare(
    shareRef: value,
    taskId: taskId,
    title: title,
    status: status,
    priority: priority,
    ownerName: ownerName,
    progressPct: progressPct,
    overdue: overdue,
    subtaskCount: subtaskCount,
    startAt: startAt,
    dueAt: dueAt,
    sharedAt: sharedAt,
    isMain: isMain,
  );

  static TaskChatShare? fromPayload(Map<String, dynamic>? payload) {
    final raw = payload?['taskShareCard'];
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final shareRef = '${map['shareRef'] ?? ''}'.trim();
    final taskId = _asInt(map['taskId']);
    if (shareRef.isEmpty || taskId <= 0) return null;
    return TaskChatShare(
      shareRef: shareRef,
      taskId: taskId,
      title: '${map['title'] ?? ''}'.trim().isEmpty
          ? '任务 #$taskId'
          : '${map['title']}'.trim(),
      status: '${map['status'] ?? 'active'}',
      priority: '${map['priority'] ?? 'medium'}',
      ownerName: '${map['ownerName'] ?? ''}'.trim(),
      progressPct: _asInt(map['progressPct']).clamp(0, 100).toInt(),
      overdue: map['overdue'] == true,
      subtaskCount: _asInt(map['subtaskCount']),
      startAt: DateTime.tryParse('${map['startAt'] ?? ''}'),
      dueAt: DateTime.tryParse('${map['dueAt'] ?? ''}'),
      sharedAt: DateTime.tryParse('${map['sharedAt'] ?? ''}') ?? DateTime.now(),
      isMain: map['isMain'] != false,
    );
  }
}

class TaskChatShareBundle {
  const TaskChatShareBundle({
    required this.ownerName,
    required this.sharedAt,
    required this.shares,
  });

  final String ownerName;
  final DateTime sharedAt;
  final List<TaskChatShare> shares;

  Map<String, dynamic> toMessagePayload() => {
    'taskShareBundle': {
      'version': 1,
      'ownerName': ownerName,
      'sharedAt': sharedAt.toIso8601String(),
      'items': [for (final share in shares) share.toMessagePayload()],
    },
  };

  static TaskChatShareBundle? fromPayload(Map<String, dynamic>? payload) {
    final raw = payload?['taskShareBundle'];
    if (raw is! Map) return null;
    final bundle = Map<String, dynamic>.from(raw);
    final rawItems = bundle['items'];
    if (rawItems is! List) return null;
    final shares = rawItems
        .whereType<Map>()
        .map(
          (item) => TaskChatShare.fromPayload(Map<String, dynamic>.from(item)),
        )
        .whereType<TaskChatShare>()
        .toList(growable: false);
    if (shares.length < 2) return null;
    return TaskChatShareBundle(
      ownerName: '${bundle['ownerName'] ?? ''}'.trim(),
      sharedAt:
          DateTime.tryParse('${bundle['sharedAt'] ?? ''}') ?? DateTime.now(),
      shares: shares,
    );
  }
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

String taskShareStatusLabel(String status, {bool overdue = false}) {
  if (overdue && status != 'completed') return '已逾期';
  return switch (status) {
    'completed' => '已完成',
    'pending_approval' => '待审核',
    'pending_assignment' => '待接收',
    'rejected' => '已驳回',
    'cancelled' => '已取消',
    _ => '进行中',
  };
}

String taskSharePriorityLabel(String priority) => switch (priority) {
  'urgent' => '紧急',
  'high' => '高优先级',
  'low' => '低优先级',
  _ => '普通优先级',
};
