class EfficiencyMetric {
  const EfficiencyMetric({
    required this.key,
    required this.label,
    required this.value,
    required this.unit,
    this.deltaPct,
    this.note = '',
  });

  final String key;
  final String label;
  final double value;
  final String unit;
  final double? deltaPct;
  final String note;

  factory EfficiencyMetric.fromJson(Map<String, dynamic> json) {
    return EfficiencyMetric(
      key: '${json['key'] ?? ''}',
      label: '${json['label'] ?? ''}',
      value: (json['value'] as num?)?.toDouble() ?? 0,
      unit: '${json['unit'] ?? ''}',
      deltaPct: (json['deltaPct'] as num?)?.toDouble(),
      note: '${json['note'] ?? ''}',
    );
  }
}

class EfficiencyStage {
  const EfficiencyStage({
    required this.key,
    required this.label,
    required this.total,
    required this.completed,
    required this.rate,
  });

  final String key;
  final String label;
  final int total;
  final int completed;
  final double rate;

  factory EfficiencyStage.fromJson(Map<String, dynamic> json) {
    return EfficiencyStage(
      key: '${json['key'] ?? ''}',
      label: '${json['label'] ?? ''}',
      total: (json['total'] as num?)?.toInt() ?? 0,
      completed: (json['completed'] as num?)?.toInt() ?? 0,
      rate: (json['rate'] as num?)?.toDouble() ?? 0,
    );
  }
}

class EfficiencyEvidence {
  const EfficiencyEvidence({
    required this.kind,
    required this.label,
    required this.count,
    required this.severity,
    required this.ref,
  });

  final String kind;
  final String label;
  final int count;
  final String severity;
  final String ref;

  factory EfficiencyEvidence.fromJson(Map<String, dynamic> json) {
    return EfficiencyEvidence(
      kind: '${json['kind'] ?? ''}',
      label: '${json['label'] ?? ''}',
      count: (json['count'] as num?)?.toInt() ?? 0,
      severity: '${json['severity'] ?? ''}',
      ref: '${json['ref'] ?? ''}',
    );
  }
}

class EfficiencySource {
  const EfficiencySource({
    required this.key,
    required this.label,
    required this.available,
    this.note = '',
  });

  final String key;
  final String label;
  final bool available;
  final String note;

  factory EfficiencySource.fromJson(Map<String, dynamic> json) {
    return EfficiencySource(
      key: '${json['key'] ?? ''}',
      label: '${json['label'] ?? ''}',
      available: json['available'] == true,
      note: '${json['note'] ?? ''}',
    );
  }
}

class EfficiencySnapshot {
  const EfficiencySnapshot({
    required this.scope,
    required this.month,
    required this.title,
    required this.peopleCount,
    required this.hasDepartmentView,
    required this.privacyProtected,
    required this.metricVersion,
    required this.generatedAt,
    required this.metrics,
    required this.stages,
    required this.bottlenecks,
    required this.sources,
    this.quality = const [],
    this.funnel = const [],
    this.trends = const [],
    this.timeline = const [],
    this.insights = const [],
    this.chains = const [],
    this.latestAnalysis,
    this.schedule,
  });

  final String scope;
  final String month;
  final String title;
  final int peopleCount;
  final bool hasDepartmentView;
  final bool privacyProtected;
  final String metricVersion;
  final DateTime? generatedAt;
  final List<EfficiencyMetric> metrics;
  final List<EfficiencyStage> stages;
  final List<EfficiencyStage> funnel;
  final List<EfficiencyTrendPoint> trends;
  final List<EfficiencyTimelineItem> timeline;
  final List<EfficiencyEvidence> bottlenecks;
  final List<EfficiencyEvidence> quality;
  final List<EfficiencySource> sources;
  final List<String> insights;
  final List<EfficiencyWorkChain> chains;
  final EfficiencyAnalysis? latestAnalysis;
  final EfficiencyScheduleInfo? schedule;

  factory EfficiencySnapshot.fromJson(Map<String, dynamic> json) {
    List<T> parseList<T>(String key, T Function(Map<String, dynamic>) parser) {
      return (json[key] as List? ?? const [])
          .whereType<Map>()
          .map((row) => parser(Map<String, dynamic>.from(row)))
          .toList(growable: false);
    }

    return EfficiencySnapshot(
      scope: '${json['scope'] ?? 'personal'}',
      month: '${json['month'] ?? ''}',
      title: '${json['title'] ?? ''}',
      peopleCount: (json['peopleCount'] as num?)?.toInt() ?? 1,
      hasDepartmentView: json['hasDepartmentView'] == true,
      privacyProtected: json['privacyProtected'] == true,
      metricVersion: '${json['metricVersion'] ?? ''}',
      generatedAt: DateTime.tryParse('${json['generatedAt'] ?? ''}'),
      metrics: parseList('metrics', EfficiencyMetric.fromJson),
      stages: parseList('stages', EfficiencyStage.fromJson),
      funnel: parseList('funnel', EfficiencyStage.fromJson),
      trends: parseList('trends', EfficiencyTrendPoint.fromJson),
      timeline: parseList('timeline', EfficiencyTimelineItem.fromJson),
      bottlenecks: parseList('bottlenecks', EfficiencyEvidence.fromJson),
      quality: parseList('quality', EfficiencyEvidence.fromJson),
      sources: parseList('sources', EfficiencySource.fromJson),
      insights: (json['insights'] as List? ?? const [])
          .map((value) => '$value')
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false),
      chains: parseList('chains', EfficiencyWorkChain.fromJson),
      latestAnalysis: json['latestAnalysis'] is Map
          ? EfficiencyAnalysis.fromJson(
              Map<String, dynamic>.from(json['latestAnalysis'] as Map),
            )
          : null,
      schedule: json['schedule'] is Map
          ? EfficiencyScheduleInfo.fromJson(
              Map<String, dynamic>.from(json['schedule'] as Map),
            )
          : null,
    );
  }
}

class EfficiencyTrendPoint {
  const EfficiencyTrendPoint({
    required this.month,
    required this.taskCompletionRate,
    required this.onTimeRate,
    required this.proposalDoneRate,
    required this.approvalCycleHours,
  });

  final String month;
  final double taskCompletionRate;
  final double onTimeRate;
  final double proposalDoneRate;
  final double approvalCycleHours;

  factory EfficiencyTrendPoint.fromJson(Map<String, dynamic> json) {
    return EfficiencyTrendPoint(
      month: '${json['month'] ?? ''}',
      taskCompletionRate: (json['taskCompletionRate'] as num?)?.toDouble() ?? 0,
      onTimeRate: (json['onTimeRate'] as num?)?.toDouble() ?? 0,
      proposalDoneRate: (json['proposalDoneRate'] as num?)?.toDouble() ?? 0,
      approvalCycleHours: (json['approvalCycleHours'] as num?)?.toDouble() ?? 0,
    );
  }
}

class EfficiencyWorkChain {
  const EfficiencyWorkChain({
    required this.meetingTitle,
    required this.brokenAt,
    this.taskCount = 0,
    this.hasMinutes = false,
  });

  final String meetingTitle;
  final String brokenAt;
  final int taskCount;
  final bool hasMinutes;

  factory EfficiencyWorkChain.fromJson(Map<String, dynamic> json) {
    return EfficiencyWorkChain(
      meetingTitle: '${json['meetingTitle'] ?? ''}',
      brokenAt: '${json['brokenAt'] ?? ''}',
      taskCount: (json['taskCount'] as num?)?.toInt() ?? 0,
      hasMinutes: json['hasMinutes'] == true,
    );
  }

  String get brokenLabel {
    switch (brokenAt) {
      case 'minutes':
        return '断在纪要';
      case 'kb':
        return '断在知识入库';
      case 'task':
        return '断在任务落地';
      case 'ok':
        return '已闭环';
      default:
        return brokenAt;
    }
  }
}

class EfficiencyTimelineItem {
  const EfficiencyTimelineItem({
    required this.at,
    required this.title,
    required this.kind,
    required this.event,
    this.evidenceRef = '',
  });

  final DateTime? at;
  final String title;
  final String kind;
  final String event;
  final String evidenceRef;

  factory EfficiencyTimelineItem.fromJson(Map<String, dynamic> json) {
    return EfficiencyTimelineItem(
      at: DateTime.tryParse('${json['at'] ?? ''}'),
      title: '${json['title'] ?? ''}',
      kind: '${json['kind'] ?? ''}',
      event: '${json['event'] ?? ''}',
      evidenceRef: '${json['evidenceRef'] ?? ''}',
    );
  }
}

class EfficiencyScheduleInfo {
  const EfficiencyScheduleInfo({
    required this.enabled,
    required this.hour,
    required this.minute,
    required this.timezone,
    this.lastScheduledAt,
  });

  final bool enabled;
  final int hour;
  final int minute;
  final String timezone;
  final DateTime? lastScheduledAt;

  factory EfficiencyScheduleInfo.fromJson(Map<String, dynamic> json) {
    return EfficiencyScheduleInfo(
      enabled: json['enabled'] == true,
      hour: (json['hour'] as num?)?.toInt() ?? 2,
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      timezone: '${json['timezone'] ?? 'Asia/Shanghai'}',
      lastScheduledAt: DateTime.tryParse('${json['lastScheduledAt'] ?? ''}'),
    );
  }
}

class EfficiencyAiAction {
  const EfficiencyAiAction({
    required this.title,
    required this.ownerRole,
    required this.expectedImpact,
  });

  final String title;
  final String ownerRole;
  final String expectedImpact;

  factory EfficiencyAiAction.fromJson(Map<String, dynamic> json) {
    return EfficiencyAiAction(
      title: '${json['title'] ?? ''}',
      ownerRole: '${json['ownerRole'] ?? ''}',
      expectedImpact: '${json['expectedImpact'] ?? ''}',
    );
  }
}

class EfficiencyAiResult {
  const EfficiencyAiResult({
    required this.summary,
    required this.wins,
    required this.risks,
    required this.actions,
    required this.confidence,
  });

  final String summary;
  final List<String> wins;
  final List<String> risks;
  final List<EfficiencyAiAction> actions;
  final double confidence;

  factory EfficiencyAiResult.fromJson(Map<String, dynamic> json) {
    return EfficiencyAiResult(
      summary: '${json['summary'] ?? ''}',
      wins: (json['wins'] as List? ?? const [])
          .map((value) => '$value')
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false),
      risks: (json['risks'] as List? ?? const [])
          .map((value) => '$value')
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false),
      actions: (json['actions'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) =>
                EfficiencyAiAction.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }
}

class EfficiencyAnalysis {
  const EfficiencyAnalysis({
    required this.id,
    required this.status,
    required this.scope,
    required this.month,
    this.result,
    this.errorMessage = '',
    this.triggerKind = '',
  });

  final int id;
  final String status;
  final String scope;
  final String month;
  final EfficiencyAiResult? result;
  final String errorMessage;
  final String triggerKind;

  bool get isScheduled => triggerKind == 'scheduled';

  factory EfficiencyAnalysis.fromJson(Map<String, dynamic> json) {
    final rawResult = json['result'];
    return EfficiencyAnalysis(
      id: (json['id'] as num?)?.toInt() ?? 0,
      status: '${json['status'] ?? ''}',
      scope: '${json['scope'] ?? ''}',
      month: '${json['month'] ?? ''}',
      result: rawResult is Map
          ? EfficiencyAiResult.fromJson(Map<String, dynamic>.from(rawResult))
          : null,
      errorMessage: '${json['errorMessage'] ?? ''}',
      triggerKind: '${json['triggerKind'] ?? ''}',
    );
  }
}

class WorkSituationItem {
  const WorkSituationItem({
    required this.kind,
    required this.title,
    this.hint = '',
    this.taskId = 0,
    this.isSubtask = false,
  });

  final String kind;
  final String title;
  final String hint;
  final int taskId;
  final bool isSubtask;

  factory WorkSituationItem.fromJson(Map<String, dynamic> json) {
    return WorkSituationItem(
      kind: '${json['kind'] ?? ''}',
      title: '${json['title'] ?? ''}',
      hint: '${json['hint'] ?? ''}',
      taskId: (json['taskId'] as num?)?.toInt() ?? 0,
      isSubtask: json['isSubtask'] == true,
    );
  }
}

class WorkSituationDept {
  const WorkSituationDept({required this.id, required this.name});

  final int id;
  final String name;

  factory WorkSituationDept.fromJson(Map<String, dynamic> json) {
    return WorkSituationDept(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: '${json['name'] ?? ''}'.trim(),
    );
  }
}

class WorkSituationPerson {
  const WorkSituationPerson({
    required this.userId,
    required this.name,
    this.title = '',
    this.departmentId = 0,
    this.departmentName = '',
    this.note = '',
    this.taskTotal = 0,
    this.taskCompleted = 0,
    this.taskOverdue = 0,
    this.taskDoing = 0,
    this.taskOnTime = 0,
    this.taskPending = 0,
    this.taskRejected = 0,
    this.proposalRejected = 0,
    this.approvalPending = 0,
    this.meetings = 0,
    this.minutesGenerated = 0,
    this.meetingsLinkedTask = 0,
    this.noActionMeetings = 0,
    this.thinMinutes = 0,
    this.kbDocuments = 0,
    this.kbUnused = 0,
    this.kbReferences = 0,
    this.imSessions = 0,
    this.imCards = 0,
    this.imUniqueObjects = 0,
    this.imUrges = 0,
    this.imDuplicates = 0,
    this.imTalkLevel = '',
    this.imTalkWhy = '',
    this.taskSubtotal = 0,
    this.taskSubCompleted = 0,
    this.taskSubOverdue = 0,
    this.taskProgressLogs = 0,
    this.taskNoAcceptance = 0,
    this.taskWithoutDue = 0,
    this.taskWaitingOnOthers = 0,
    this.taskStaleOpen = 0,
    this.taskOverdueHighWeight = 0,
    this.taskReviewLevel = '',
    this.taskReviewWhy = '',
    this.items = const [],
  });

  final int userId;
  final String name;
  final String title;
  final int departmentId;
  final String departmentName;
  final String note;
  final int taskTotal;
  final int taskCompleted;
  final int taskOverdue;
  final int taskDoing;
  final int taskOnTime;
  final int taskPending;
  final int taskRejected;
  final int proposalRejected;
  final int approvalPending;
  final int meetings;
  final int minutesGenerated;
  final int meetingsLinkedTask;
  final int noActionMeetings;
  final int thinMinutes;
  final int kbDocuments;
  final int kbUnused;
  final int kbReferences;
  final int imSessions;
  final int imCards;
  final int imUniqueObjects;
  final int imUrges;
  final int imDuplicates;
  final String imTalkLevel;
  final String imTalkWhy;
  final int taskSubtotal;
  final int taskSubCompleted;
  final int taskSubOverdue;
  final int taskProgressLogs;
  final int taskNoAcceptance;
  final int taskWithoutDue;
  final int taskWaitingOnOthers;
  final int taskStaleOpen;
  final int taskOverdueHighWeight;
  final String taskReviewLevel;
  final String taskReviewWhy;
  final List<WorkSituationItem> items;

  factory WorkSituationPerson.fromJson(Map<String, dynamic> json) {
    return WorkSituationPerson(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      name: '${json['name'] ?? json['displayName'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      departmentId: (json['departmentId'] as num?)?.toInt() ?? 0,
      departmentName: '${json['departmentName'] ?? ''}'.trim(),
      note: '${json['note'] ?? ''}'.trim(),
      taskTotal: (json['taskTotal'] as num?)?.toInt() ?? 0,
      taskCompleted: (json['taskCompleted'] as num?)?.toInt() ?? 0,
      taskOverdue: (json['taskOverdue'] as num?)?.toInt() ?? 0,
      taskDoing: (json['taskDoing'] as num?)?.toInt() ?? 0,
      taskOnTime: (json['taskOnTime'] as num?)?.toInt() ?? 0,
      taskPending: (json['taskPending'] as num?)?.toInt() ?? 0,
      taskRejected: (json['taskRejected'] as num?)?.toInt() ?? 0,
      proposalRejected: (json['proposalRejected'] as num?)?.toInt() ?? 0,
      approvalPending: (json['approvalPending'] as num?)?.toInt() ?? 0,
      meetings: (json['meetings'] as num?)?.toInt() ?? 0,
      minutesGenerated: (json['minutesGenerated'] as num?)?.toInt() ?? 0,
      meetingsLinkedTask: (json['meetingsLinkedTask'] as num?)?.toInt() ?? 0,
      noActionMeetings: (json['noActionMeetings'] as num?)?.toInt() ?? 0,
      thinMinutes: (json['thinMinutes'] as num?)?.toInt() ?? 0,
      kbDocuments: (json['kbDocuments'] as num?)?.toInt() ?? 0,
      kbUnused: (json['kbUnused'] as num?)?.toInt() ?? 0,
      kbReferences: (json['kbReferences'] as num?)?.toInt() ?? 0,
      imSessions: (json['imSessions'] as num?)?.toInt() ?? 0,
      imCards: (json['imCards'] as num?)?.toInt() ?? 0,
      imUniqueObjects: (json['imUniqueObjects'] as num?)?.toInt() ?? 0,
      imUrges: (json['imUrges'] as num?)?.toInt() ?? 0,
      imDuplicates: (json['imDuplicates'] as num?)?.toInt() ?? 0,
      imTalkLevel: '${json['imTalkLevel'] ?? ''}'.trim(),
      imTalkWhy: '${json['imTalkWhy'] ?? ''}'.trim(),
      taskSubtotal: (json['taskSubtotal'] as num?)?.toInt() ?? 0,
      taskSubCompleted: (json['taskSubCompleted'] as num?)?.toInt() ?? 0,
      taskSubOverdue: (json['taskSubOverdue'] as num?)?.toInt() ?? 0,
      taskProgressLogs: (json['taskProgressLogs'] as num?)?.toInt() ?? 0,
      taskNoAcceptance: (json['taskNoAcceptance'] as num?)?.toInt() ?? 0,
      taskWithoutDue: (json['taskWithoutDue'] as num?)?.toInt() ?? 0,
      taskWaitingOnOthers: (json['taskWaitingOnOthers'] as num?)?.toInt() ?? 0,
      taskStaleOpen: (json['taskStaleOpen'] as num?)?.toInt() ?? 0,
      taskOverdueHighWeight: (json['taskOverdueHighWeight'] as num?)?.toInt() ?? 0,
      taskReviewLevel: '${json['taskReviewLevel'] ?? ''}'.trim(),
      taskReviewWhy: '${json['taskReviewWhy'] ?? ''}'.trim(),
      items: (json['items'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => WorkSituationItem.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false),
    );
  }

  WorkSituationPerson copyWith({List<WorkSituationItem>? items, String? note}) {
    return WorkSituationPerson(
      userId: userId,
      name: name,
      title: title,
      departmentId: departmentId,
      departmentName: departmentName,
      note: note ?? this.note,
      taskTotal: taskTotal,
      taskCompleted: taskCompleted,
      taskOverdue: taskOverdue,
      taskDoing: taskDoing,
      taskOnTime: taskOnTime,
      taskPending: taskPending,
      taskRejected: taskRejected,
      proposalRejected: proposalRejected,
      approvalPending: approvalPending,
      meetings: meetings,
      minutesGenerated: minutesGenerated,
      meetingsLinkedTask: meetingsLinkedTask,
      noActionMeetings: noActionMeetings,
      thinMinutes: thinMinutes,
      kbDocuments: kbDocuments,
      kbUnused: kbUnused,
      kbReferences: kbReferences,
      imSessions: imSessions,
      imCards: imCards,
      imUniqueObjects: imUniqueObjects,
      imUrges: imUrges,
      imDuplicates: imDuplicates,
      imTalkLevel: imTalkLevel,
      imTalkWhy: imTalkWhy,
      taskSubtotal: taskSubtotal,
      taskSubCompleted: taskSubCompleted,
      taskSubOverdue: taskSubOverdue,
      taskProgressLogs: taskProgressLogs,
      taskNoAcceptance: taskNoAcceptance,
      taskWithoutDue: taskWithoutDue,
      taskWaitingOnOthers: taskWaitingOnOthers,
      taskStaleOpen: taskStaleOpen,
      taskOverdueHighWeight: taskOverdueHighWeight,
      taskReviewLevel: taskReviewLevel,
      taskReviewWhy: taskReviewWhy,
      items: items ?? this.items,
    );
  }
}

class WorkSituationBoard {
  const WorkSituationBoard({
    required this.month,
    required this.viewAll,
    this.scopeLabel = '',
    this.departments = const [],
    this.people = const [],
  });

  final String month;
  final bool viewAll;
  final String scopeLabel;
  final List<WorkSituationDept> departments;
  final List<WorkSituationPerson> people;

  factory WorkSituationBoard.fromJson(Map<String, dynamic> json) {
    return WorkSituationBoard(
      month: '${json['month'] ?? ''}',
      viewAll: json['viewAll'] == true,
      scopeLabel: '${json['scopeLabel'] ?? ''}',
      departments: (json['departments'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => WorkSituationDept.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false),
      people: (json['people'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => WorkSituationPerson.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false),
    );
  }
}
