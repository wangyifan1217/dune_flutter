/// 销售提案时限管理（提案管理办法）。计时都在服务端，这里只解析并展示。
library;

int _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}'.trim()) ?? 0;
}

String _str(Object? v) => '${v ?? ''}'.trim();

Map<String, dynamic> _mapOf(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _listOf(Object? v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

DateTime? proposalSlaParseTime(String raw) {
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

/// 「3 小时 20 分」这种写法；不足 1 分钟按 0 分。
String proposalSlaDuration(int minutes) {
  final m = minutes.abs();
  final h = m ~/ 60;
  final r = m % 60;
  if (h > 0 && r > 0) return '$h 小时 $r 分';
  if (h > 0) return '$h 小时';
  return '$r 分钟';
}

String proposalSlaClock(DateTime? t) {
  if (t == null) return '—';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

class ProposalSlaNode {
  const ProposalSlaNode({
    required this.id,
    required this.round,
    required this.stageKey,
    required this.stageLabel,
    required this.nodeKey,
    required this.label,
    required this.role,
    required this.assigneeId,
    required this.assigneeName,
    required this.startedAt,
    required this.endedAt,
    required this.effectiveMinutes,
    required this.limitMinutes,
    required this.remainingMinutes,
    required this.overdueMinutes,
    required this.state,
    required this.stateLabel,
    required this.remindCount,
    required this.exempt,
  });

  final int id;
  final int round;
  final String stageKey;
  final String stageLabel;
  final String nodeKey;
  final String label;
  final String role;
  final int assigneeId;
  final String assigneeName;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int effectiveMinutes;
  final int limitMinutes;
  final int remainingMinutes;
  final int overdueMinutes;
  final String state;
  final String stateLabel;
  final int remindCount;
  final bool exempt;

  bool get open => endedAt == null;

  factory ProposalSlaNode.fromJson(Map<String, dynamic> json) => ProposalSlaNode(
    id: _int(json['id']),
    round: _int(json['round']),
    stageKey: _str(json['stageKey']),
    stageLabel: _str(json['stageLabel']),
    nodeKey: _str(json['nodeKey']),
    label: _str(json['label']),
    role: _str(json['role']),
    assigneeId: _int(json['assigneeId']),
    assigneeName: _str(json['assigneeName']),
    startedAt: proposalSlaParseTime(_str(json['startedAt'])),
    endedAt: proposalSlaParseTime(_str(json['endedAt'])),
    effectiveMinutes: _int(json['effectiveMinutes']),
    limitMinutes: _int(json['limitMinutes']),
    remainingMinutes: _int(json['remainingMinutes']),
    overdueMinutes: _int(json['overdueMinutes']),
    state: _str(json['state']),
    stateLabel: _str(json['stateLabel']),
    remindCount: _int(json['remindCount']),
    exempt: json['exempt'] == true,
  );

  /// 节点时钟一行：剩余 / 已超时 / 用时。
  String get clockText {
    if (state == 'exempt') return '已免责';
    if (!open) {
      final used = '用时 ${proposalSlaDuration(effectiveMinutes)}';
      return overdueMinutes > 0
          ? '$used · 超时 ${proposalSlaDuration(overdueMinutes)}'
          : used;
    }
    if (state == 'overdue') return '已超时 ${proposalSlaDuration(overdueMinutes)}';
    return '剩余 ${proposalSlaDuration(remainingMinutes)}';
  }
}

class ProposalSlaSummary {
  const ProposalSlaSummary({
    required this.instanceId,
    required this.status,
    required this.statusLabel,
    required this.startedAt,
    required this.finishedAt,
    required this.round,
    required this.totalLimitMinutes,
    required this.totalElapsedMinutes,
    required this.totalRemainingMinutes,
    required this.totalOverdue,
    required this.nodeLimitMinutes,
    required this.remindCount,
    required this.overdueCount,
    required this.exempt,
    required this.paused,
    this.suspended = false,
    required this.currentStageLabel,
    required this.current,
  });

  final int instanceId;
  final String status;
  final String statusLabel;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int round;
  final int totalLimitMinutes;
  final int totalElapsedMinutes;
  final int totalRemainingMinutes;
  final bool totalOverdue;
  final int nodeLimitMinutes;
  final int remindCount;
  final int overdueCount;
  final bool exempt;
  final bool paused;

  /// 退回填写、等待重新提交复核时没有开着的节点，总时钟暂停。
  final bool suspended;
  final String currentStageLabel;
  final List<ProposalSlaNode> current;

  bool get finished => finishedAt != null;
  bool get isWarning => status == 'warning';
  bool get isOverdue => status == 'overdue';

  /// 最紧的那个开着的节点（超时最久，或剩余最少）。
  ProposalSlaNode? get tightest {
    if (current.isEmpty) return null;
    final list = [...current]
      ..sort((a, b) {
        final byOver = b.overdueMinutes.compareTo(a.overdueMinutes);
        if (byOver != 0) return byOver;
        return a.remainingMinutes.compareTo(b.remainingMinutes);
      });
    return list.first;
  }

  double get totalProgress {
    if (totalLimitMinutes <= 0) return 0;
    return (totalElapsedMinutes / totalLimitMinutes).clamp(0.0, 1.0);
  }

  String get totalText {
    if (finished) return '总用时 ${proposalSlaDuration(totalElapsedMinutes)}';
    if (totalOverdue) {
      return '总时长已超 ${proposalSlaDuration(totalElapsedMinutes - totalLimitMinutes)}';
    }
    if (suspended) {
      return '填写中暂停计时 · 总时钟剩余 ${proposalSlaDuration(totalRemainingMinutes)}';
    }
    return '总时钟剩余 ${proposalSlaDuration(totalRemainingMinutes)}';
  }

  static ProposalSlaSummary? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    if (_int(json['instanceId']) <= 0) return null;
    return ProposalSlaSummary(
      instanceId: _int(json['instanceId']),
      status: _str(json['status']),
      statusLabel: _str(json['statusLabel']),
      startedAt: proposalSlaParseTime(_str(json['startedAt'])),
      finishedAt: proposalSlaParseTime(_str(json['finishedAt'])),
      round: _int(json['round']),
      totalLimitMinutes: _int(json['totalLimitMinutes']),
      totalElapsedMinutes: _int(json['totalElapsedMinutes']),
      totalRemainingMinutes: _int(json['totalRemainingMinutes']),
      totalOverdue: json['totalOverdue'] == true,
      nodeLimitMinutes: _int(json['nodeLimitMinutes']),
      remindCount: _int(json['remindCount']),
      overdueCount: _int(json['overdueCount']),
      exempt: json['exempt'] == true,
      paused: json['paused'] == true,
      suspended: json['suspended'] == true,
      currentStageLabel: _str(json['currentStageLabel']),
      current: _listOf(json['current']).map(ProposalSlaNode.fromJson).toList(),
    );
  }
}

class ProposalSlaEvent {
  const ProposalSlaEvent({
    required this.id,
    required this.round,
    required this.type,
    required this.nodeId,
    required this.actorName,
    required this.detail,
    required this.createdAt,
  });

  final int id;
  final int round;
  final String type;
  final int nodeId;
  final String actorName;
  final Map<String, dynamic> detail;
  final DateTime? createdAt;

  factory ProposalSlaEvent.fromJson(Map<String, dynamic> json) => ProposalSlaEvent(
    id: _int(json['id']),
    round: _int(json['round']),
    type: _str(json['type']),
    nodeId: _int(json['nodeId']),
    actorName: _str(json['actorName']),
    detail: _mapOf(json['detail']),
    createdAt: proposalSlaParseTime(_str(json['createdAt'])),
  );
}

class ProposalSlaExemption {
  const ProposalSlaExemption({
    required this.id,
    required this.type,
    required this.reasonType,
    required this.reason,
    required this.status,
    required this.applicantName,
    required this.reviewerName,
    required this.reviewComment,
    required this.createdAt,
  });

  final int id;
  final String type;
  final String reasonType;
  final String reason;
  final String status;
  final String applicantName;
  final String reviewerName;
  final String reviewComment;
  final DateTime? createdAt;

  factory ProposalSlaExemption.fromJson(Map<String, dynamic> json) =>
      ProposalSlaExemption(
        id: _int(json['id']),
        type: _str(json['type']),
        reasonType: _str(json['reasonType']),
        reason: _str(json['reason']),
        status: _str(json['status']),
        applicantName: _str(json['applicantName']),
        reviewerName: _str(json['reviewerName']),
        reviewComment: _str(json['reviewComment']),
        createdAt: proposalSlaParseTime(_str(json['createdAt'])),
      );
}

class ProposalSlaScore {
  const ProposalSlaScore({
    required this.id,
    required this.nodeLabel,
    required this.round,
    required this.kind,
    required this.suggestedPoints,
    required this.finalPoints,
    required this.overdueMinutes,
    required this.status,
    required this.appealDeadline,
    required this.appealOpen,
    required this.appealStatus,
    required this.reviewComment,
  });

  final int id;
  final String nodeLabel;
  final int round;
  final String kind;
  final int suggestedPoints;
  final int? finalPoints;
  final int overdueMinutes;
  final String status;
  final DateTime? appealDeadline;
  final bool appealOpen;
  final String appealStatus;
  final String reviewComment;

  factory ProposalSlaScore.fromJson(Map<String, dynamic> json) => ProposalSlaScore(
    id: _int(json['id']),
    nodeLabel: _str(json['nodeLabel']),
    round: _int(json['round']),
    kind: _str(json['kind']),
    suggestedPoints: _int(json['suggestedPoints']),
    finalPoints: json['finalPoints'] == null ? null : _int(json['finalPoints']),
    overdueMinutes: _int(json['overdueMinutes']),
    status: _str(json['status']),
    appealDeadline: proposalSlaParseTime(_str(json['appealDeadline'])),
    appealOpen: json['appealOpen'] == true,
    appealStatus: _str(json['appealStatus']),
    reviewComment: _str(json['reviewComment']),
  );

  String get kindLabel => switch (kind) {
    'leader' => '部门负责人连带',
    'total' => '总时长超 72 小时',
    _ => '节点超时',
  };

  String get statusLabel {
    if (appealStatus == 'pending') return '申诉中';
    return switch (status) {
      'confirmed' => '已确认',
      'rejected' => '已撤销',
      'adjusted' => '已调整',
      'exempt' => '已免责',
      _ => '待行政人事复核',
    };
  }

  String get pointsText {
    if (finalPoints != null && status != 'pending') return '$finalPoints 分';
    return '建议 $suggestedPoints 分';
  }
}

class ProposalSlaDetail {
  const ProposalSlaDetail({
    required this.summary,
    required this.nodes,
    required this.events,
    required this.exemptions,
    required this.myScores,
  });

  final ProposalSlaSummary? summary;
  final List<ProposalSlaNode> nodes;
  final List<ProposalSlaEvent> events;
  final List<ProposalSlaExemption> exemptions;
  final List<ProposalSlaScore> myScores;

  /// 服务端返回 `{enabled, detail}`；功能关闭或该提案未纳入时为 null。
  static ProposalSlaDetail? tryParse(Object? raw) {
    if (raw is! Map || raw['enabled'] != true) return null;
    final json = _mapOf(raw['detail']);
    final summary = ProposalSlaSummary.tryParse(json['summary']);
    if (summary == null) return null;
    return ProposalSlaDetail(
      summary: summary,
      nodes: _listOf(json['nodes']).map(ProposalSlaNode.fromJson).toList(),
      events: _listOf(json['events']).map(ProposalSlaEvent.fromJson).toList(),
      exemptions:
          _listOf(json['exemptions']).map(ProposalSlaExemption.fromJson).toList(),
      myScores: _listOf(json['myScores']).map(ProposalSlaScore.fromJson).toList(),
    );
  }

  /// 节点的开始 / 结束、催办、超时、免责、申诉、复核、轮回合并成一条时间线。
  List<({DateTime? at, String title, String body, String type})> get timeline {
    final out = <({DateTime? at, String title, String body, String type})>[];
    String nodeLabel(int id) =>
        nodes.where((n) => n.id == id).map((n) => n.label).firstOrNull ?? '';
    for (final e in events) {
      final label = _str(e.detail['label']).isNotEmpty
          ? _str(e.detail['label'])
          : nodeLabel(e.nodeId);
      final who = e.actorName.isEmpty ? '系统' : e.actorName;
      final item = switch (e.type) {
        'start' => ('进入时效管理', '开始复核，72 小时总时钟开始计时'),
        'round' => (
          '第 ${e.round - 1} 次轮回',
          _str(e.detail['comment']).isEmpty
              ? '最终人驳回，重新填写'
              : '最终人驳回：${_str(e.detail['comment'])}',
        ),
        'warning' => ('卡点', '「$label」剩余不足 ${proposalSlaDuration(_int(e.detail['remainingMinutes']))}'),
        'overdue' => ('超时', '「$label」已超时'),
        'total_overdue' => ('总时长超时', '提案总时长超过 72 小时'),
        'remind' => (
          _str(e.detail['kind']) == 'manual' ? '催办' : '系统催办',
          _str(e.detail['kind']) == 'manual' ? '$who 发起提醒' : '已提醒相关负责人',
        ),
        'exempt' => (
          '免责',
          '${_str(e.detail['reasonLabel'])}：${_str(e.detail['reason'])}',
        ),
        'appeal' => ('申诉', '$who：${_str(e.detail['reason'])}'),
        'score_review' => ('行政人事复核', '$who：${_str(e.detail['comment']).isEmpty ? '已处理' : _str(e.detail['comment'])}'),
        'finish' => ('最终确认通过', '时效管理结束'),
        _ => ('', ''),
      };
      if (item.$1.isEmpty) continue;
      out.add((at: e.createdAt, title: item.$1, body: item.$2, type: e.type));
    }
    return out;
  }
}
