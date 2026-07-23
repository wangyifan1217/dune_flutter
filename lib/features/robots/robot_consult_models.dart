import 'robot_models.dart';

enum RobotConsultStatus { queued, running, success, failed }

extension RobotConsultStatusX on RobotConsultStatus {
  String get label => switch (this) {
        RobotConsultStatus.queued => '排队中',
        RobotConsultStatus.running => '处理中',
        RobotConsultStatus.success => '已完成',
        RobotConsultStatus.failed => '失败',
      };
}

RobotNodeStatus parseRobotNodeStatus(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'running':
      return RobotNodeStatus.running;
    case 'success':
      return RobotNodeStatus.success;
    case 'failed':
      return RobotNodeStatus.failed;
    case 'skipped':
      return RobotNodeStatus.skipped;
    default:
      return RobotNodeStatus.pending;
  }
}

RobotConsultStatus parseRobotConsultStatus(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'running':
      return RobotConsultStatus.running;
    case 'success':
      return RobotConsultStatus.success;
    case 'failed':
      return RobotConsultStatus.failed;
    default:
      return RobotConsultStatus.queued;
  }
}

class RobotConsultRecord {
  RobotConsultRecord({
    required this.id,
    required this.question,
    required this.status,
    required this.createdAt,
    required this.nodes,
    this.resultSummary = '',
    this.robotKey = 'r_lighthouse',
    this.unread = true,
    this.updatedAt,
  });

  final String id;
  final String question;
  final RobotConsultStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<RobotFlowNode> nodes;
  final String resultSummary;
  final String robotKey;
  final bool unread;

  RobotConsultRecord copyWith({
    RobotConsultStatus? status,
    List<RobotFlowNode>? nodes,
    String? resultSummary,
    bool? unread,
    DateTime? updatedAt,
  }) {
    return RobotConsultRecord(
      id: id,
      question: question,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      nodes: nodes ?? this.nodes,
      resultSummary: resultSummary ?? this.resultSummary,
      robotKey: robotKey,
      unread: unread ?? this.unread,
    );
  }

  bool get isTerminal =>
      status == RobotConsultStatus.success || status == RobotConsultStatus.failed;

  factory RobotConsultRecord.fromApi(Map<String, dynamic> json) {
    final nodesRaw = json['nodes'];
    final nodes = <RobotFlowNode>[];
    if (nodesRaw is List) {
      for (final e in nodesRaw) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final durationMs = m['durationMs'];
        var durationLabel = '';
        if (durationMs is num && durationMs > 0) {
          durationLabel = '${(durationMs / 1000).toStringAsFixed(
            durationMs >= 1000 ? 1 : 2,
          )}s';
        }
        nodes.add(
          RobotFlowNode(
            id: '${m['id'] ?? ''}',
            name: '${m['name'] ?? ''}',
            typeLabel: '${m['type'] ?? ''}',
            status: parseRobotNodeStatus('${m['status'] ?? ''}'),
            reply: '${m['reply'] ?? m['error'] ?? ''}',
            durationLabel: durationLabel,
          ),
        );
      }
    }

    final created = DateTime.tryParse('${json['createdAt'] ?? ''}') ??
        DateTime.now();
    final updated = DateTime.tryParse('${json['updatedAt'] ?? ''}');
    final readAt = '${json['readAt'] ?? ''}'.trim();
    final unreadFlag = json['unread'];
    final unread = unreadFlag is bool ? unreadFlag : readAt.isEmpty;

    return RobotConsultRecord(
      id: '${json['jobId'] ?? json['id'] ?? ''}',
      question: '${json['question'] ?? ''}',
      status: parseRobotConsultStatus('${json['status'] ?? ''}'),
      createdAt: created.toLocal(),
      updatedAt: updated?.toLocal(),
      nodes: nodes,
      resultSummary: '${json['resultSummary'] ?? ''}',
      robotKey: '${json['robotKey'] ?? 'r_lighthouse'}',
      unread: unread,
    );
  }
}

class RobotConsultListResult {
  const RobotConsultListResult({
    required this.items,
    required this.total,
    required this.unreadCount,
  });

  final List<RobotConsultRecord> items;
  final int total;
  final int unreadCount;
}
