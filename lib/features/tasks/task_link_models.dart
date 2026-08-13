/// 任务 × 会议纪要 × 知识库绑定的数据模型（qianji-go /tasks/{id}/links 等接口）。
library;

class TaskLink {
  const TaskLink({
    required this.id,
    required this.taskId,
    required this.kind,
    this.meetingId,
    this.kbDocumentId,
    this.title = '',
    this.decisionExcerpt = '',
    this.matchReason = '',
    this.linkKind = 'manual_add',
  });

  final int id;
  final int taskId;
  final String kind; // meeting | kb
  final int? meetingId;
  final int? kbDocumentId;
  final String title;
  final String decisionExcerpt;
  final String matchReason;
  final String linkKind; // auto_sync | manual_add | user_create

  bool get isMeeting => kind == 'meeting';
  bool get isAuto => linkKind == 'auto_sync';

  factory TaskLink.fromJson(Map<String, dynamic> json) {
    return TaskLink(
      id: (json['id'] as num?)?.toInt() ?? 0,
      taskId: (json['taskId'] as num?)?.toInt() ?? 0,
      kind: '${json['kind'] ?? ''}',
      meetingId: (json['meetingId'] as num?)?.toInt(),
      kbDocumentId: (json['kbDocumentId'] as num?)?.toInt(),
      title: '${json['title'] ?? ''}',
      decisionExcerpt: '${json['decisionExcerpt'] ?? ''}',
      matchReason: '${json['matchReason'] ?? ''}',
      linkKind: '${json['linkKind'] ?? 'manual_add'}',
    );
  }

  /// 撤销删除时按原关联重新添加。
  Map<String, dynamic> toCreateJson() => {
        'kind': kind,
        if (meetingId != null) 'meetingId': meetingId,
        if (kbDocumentId != null) 'kbDocumentId': kbDocumentId,
        'title': title,
        'decisionExcerpt': decisionExcerpt,
      };
}

class TaskBindRun {
  const TaskBindRun({
    required this.status,
    this.detail = '',
    this.updatedAt,
  });

  final String status; // running | done | failed
  final String detail;
  final DateTime? updatedAt;

  /// 匹配中，且状态足够新鲜（防止编排端异常时永远转圈）。
  bool get isRunningFresh {
    if (status != 'running') return false;
    final at = updatedAt;
    if (at == null) return false;
    return DateTime.now().difference(at.toLocal()).inMinutes < 3;
  }

  static TaskBindRun? fromJson(dynamic json) {
    if (json is! Map) return null;
    return TaskBindRun(
      status: '${json['status'] ?? ''}',
      detail: '${json['detail'] ?? ''}',
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
    );
  }
}

class TaskLinksResult {
  const TaskLinksResult({required this.links, this.bindRun});

  final List<TaskLink> links;
  final TaskBindRun? bindRun;
}

class TaskLinkCandidateMeeting {
  const TaskLinkCandidateMeeting({
    required this.meetingId,
    required this.title,
    this.meetingDate = '',
    this.summary = '',
    this.kbDocumentId = 0,
    this.score = 0,
    this.linked = false,
  });

  final int meetingId;
  final String title;
  final String meetingDate;
  final String summary;
  final int kbDocumentId;
  final int score;
  final bool linked;

  factory TaskLinkCandidateMeeting.fromJson(Map<String, dynamic> json) {
    return TaskLinkCandidateMeeting(
      meetingId: (json['meetingId'] as num?)?.toInt() ?? 0,
      title: '${json['title'] ?? ''}',
      meetingDate: '${json['meetingDate'] ?? ''}',
      summary: '${json['summary'] ?? ''}',
      kbDocumentId: (json['kbDocumentId'] as num?)?.toInt() ?? 0,
      score: (json['score'] as num?)?.toInt() ?? 0,
      linked: json['linked'] == true,
    );
  }
}

class TaskLinkCandidateDoc {
  const TaskLinkCandidateDoc({
    required this.kbDocumentId,
    required this.title,
    this.meetingId = 0,
    this.score = 0,
    this.linked = false,
  });

  final int kbDocumentId;
  final String title;
  final int meetingId;
  final int score;
  final bool linked;

  factory TaskLinkCandidateDoc.fromJson(Map<String, dynamic> json) {
    return TaskLinkCandidateDoc(
      kbDocumentId: (json['kbDocumentId'] as num?)?.toInt() ?? 0,
      title: '${json['title'] ?? ''}',
      meetingId: (json['meetingId'] as num?)?.toInt() ?? 0,
      score: (json['score'] as num?)?.toInt() ?? 0,
      linked: json['linked'] == true,
    );
  }
}

class TaskLinkCandidates {
  const TaskLinkCandidates({
    this.meetings = const [],
    this.docs = const [],
  });

  final List<TaskLinkCandidateMeeting> meetings;
  final List<TaskLinkCandidateDoc> docs;
}

class MeetingTaskSuggestion {
  const MeetingTaskSuggestion({
    required this.id,
    required this.meetingId,
    required this.suggestedTitle,
    this.suggestedDescription = '',
    this.decisionExcerpt = '',
  });

  final int id;
  final int meetingId;
  final String suggestedTitle;
  final String suggestedDescription;
  final String decisionExcerpt;

  factory MeetingTaskSuggestion.fromJson(Map<String, dynamic> json) {
    return MeetingTaskSuggestion(
      id: (json['id'] as num?)?.toInt() ?? 0,
      meetingId: (json['meetingId'] as num?)?.toInt() ?? 0,
      suggestedTitle: '${json['suggestedTitle'] ?? ''}',
      suggestedDescription: '${json['suggestedDescription'] ?? ''}',
      decisionExcerpt: '${json['decisionExcerpt'] ?? ''}',
    );
  }
}

class MeetingSyncedTask {
  const MeetingSyncedTask({
    required this.linkId,
    required this.taskId,
    required this.taskTitle,
    this.taskStatus = '',
    this.progressPct = 0,
  });

  final int linkId;
  final int taskId;
  final String taskTitle;
  final String taskStatus;
  final int progressPct;

  factory MeetingSyncedTask.fromJson(Map<String, dynamic> json) {
    return MeetingSyncedTask(
      linkId: (json['linkId'] as num?)?.toInt() ?? 0,
      taskId: (json['taskId'] as num?)?.toInt() ?? 0,
      taskTitle: '${json['taskTitle'] ?? ''}',
      taskStatus: '${json['taskStatus'] ?? ''}',
      progressPct: (json['progressPct'] as num?)?.toInt() ?? 0,
    );
  }
}

class MeetingTaskBindData {
  const MeetingTaskBindData({
    this.suggestions = const [],
    this.syncedTasks = const [],
    this.bindRun,
  });

  final List<MeetingTaskSuggestion> suggestions;
  final List<MeetingSyncedTask> syncedTasks;
  final TaskBindRun? bindRun;

  bool get isEmpty =>
      suggestions.isEmpty && syncedTasks.isEmpty && bindRun == null;
}
