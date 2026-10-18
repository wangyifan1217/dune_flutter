import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';

class ProposalSlaConfig {
  const ProposalSlaConfig({
    required this.enabled,
    required this.totalHours,
    required this.nodeHours,
    required this.workStartMinute,
    required this.workEndMinute,
    required this.warnHours,
    required this.remindIntervalHours,
    required this.appealWorkdays,
    this.kinds = const ['sales'],
    this.updatedAt = '',
  });

  final bool enabled;
  final int totalHours;
  final int nodeHours;
  final int workStartMinute;
  final int workEndMinute;
  final int warnHours;
  final int remindIntervalHours;
  final int appealWorkdays;
  final List<String> kinds;
  final String updatedAt;

  factory ProposalSlaConfig.fromJson(Map<String, dynamic> json) {
    return ProposalSlaConfig(
      enabled: json['enabled'] == true,
      totalHours: _int(json['totalHours'], 72),
      nodeHours: _int(json['nodeHours'], 12),
      workStartMinute: _int(json['workStartMinute'], 540),
      workEndMinute: _int(json['workEndMinute'], 1260),
      warnHours: _int(json['warnHours'], 2),
      remindIntervalHours: _int(json['remindIntervalHours'], 12),
      appealWorkdays: _int(json['appealWorkdays'], 2),
      kinds: (json['kinds'] as List?)?.map((e) => '$e').toList() ?? const ['sales'],
      updatedAt: '${json['updatedAt'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'totalHours': totalHours,
    'nodeHours': nodeHours,
    'workStartMinute': workStartMinute,
    'workEndMinute': workEndMinute,
    'warnHours': warnHours,
    'remindIntervalHours': remindIntervalHours,
    'appealWorkdays': appealWorkdays,
    'kinds': kinds,
  };

  ProposalSlaConfig copyWith({
    bool? enabled,
    int? totalHours,
    int? nodeHours,
    int? workStartMinute,
    int? workEndMinute,
    int? warnHours,
    int? remindIntervalHours,
    int? appealWorkdays,
  }) {
    return ProposalSlaConfig(
      enabled: enabled ?? this.enabled,
      totalHours: totalHours ?? this.totalHours,
      nodeHours: nodeHours ?? this.nodeHours,
      workStartMinute: workStartMinute ?? this.workStartMinute,
      workEndMinute: workEndMinute ?? this.workEndMinute,
      warnHours: warnHours ?? this.warnHours,
      remindIntervalHours: remindIntervalHours ?? this.remindIntervalHours,
      appealWorkdays: appealWorkdays ?? this.appealWorkdays,
      kinds: kinds,
      updatedAt: updatedAt,
    );
  }
}

class ProposalSlaInstance {
  const ProposalSlaInstance({
    required this.id,
    required this.code,
    required this.title,
    required this.sector,
    required this.status,
    required this.round,
    required this.exempt,
    required this.elapsedHours,
    required this.totalHours,
    required this.current,
    required this.overdueNodes,
    required this.startedAt,
  });

  final int id;
  final String code;
  final String title;
  final String sector;
  final String status;
  final int round;
  final bool exempt;
  final double elapsedHours;
  final int totalHours;
  final String current;
  final int overdueNodes;
  final String startedAt;

  factory ProposalSlaInstance.fromJson(Map<String, dynamic> json) {
    return ProposalSlaInstance(
      id: _int(json['id']),
      code: '${json['code'] ?? ''}',
      title: '${json['title'] ?? ''}',
      sector: '${json['sector'] ?? ''}',
      status: '${json['status'] ?? ''}',
      round: _int(json['round']),
      exempt: json['exempt'] == true,
      elapsedHours: _double(json['elapsedHours']),
      totalHours: _int(json['totalHours']),
      current: '${json['current'] ?? ''}',
      overdueNodes: _int(json['overdueNodes']),
      startedAt: '${json['startedAt'] ?? ''}',
    );
  }
}

class ProposalSlaNode {
  const ProposalSlaNode({
    required this.id,
    required this.round,
    required this.label,
    required this.assigneeName,
    required this.endedAt,
    required this.state,
    required this.exempt,
  });

  final int id;
  final int round;
  final String label;
  final String assigneeName;
  final String endedAt;
  final String state;
  final bool exempt;

  factory ProposalSlaNode.fromJson(Map<String, dynamic> json) {
    return ProposalSlaNode(
      id: _int(json['id']),
      round: _int(json['round']),
      label: '${json['label'] ?? ''}',
      assigneeName: '${json['assigneeName'] ?? ''}',
      endedAt: '${json['endedAt'] ?? ''}',
      state: '${json['state'] ?? ''}',
      exempt: json['exempt'] == true,
    );
  }
}

class ProposalSlaScore {
  const ProposalSlaScore({
    required this.id,
    required this.code,
    required this.title,
    required this.kind,
    required this.nodeLabel,
    required this.userName,
    required this.sourceUserName,
    required this.suggestedPoints,
    required this.finalPoints,
    required this.overdueMinutes,
    required this.status,
    required this.appealStatus,
    required this.appealReason,
    required this.reviewerName,
    required this.reviewComment,
  });

  final int id;
  final String code;
  final String title;
  final String kind;
  final String nodeLabel;
  final String userName;
  final String sourceUserName;
  final int suggestedPoints;
  final int? finalPoints;
  final int overdueMinutes;
  final String status;
  final String appealStatus;
  final String appealReason;
  final String reviewerName;
  final String reviewComment;

  factory ProposalSlaScore.fromJson(Map<String, dynamic> json) {
    return ProposalSlaScore(
      id: _int(json['id']),
      code: '${json['code'] ?? ''}',
      title: '${json['title'] ?? ''}',
      kind: '${json['kind'] ?? ''}',
      nodeLabel: '${json['nodeLabel'] ?? ''}',
      userName: '${json['userName'] ?? ''}',
      sourceUserName: '${json['sourceUserName'] ?? ''}',
      suggestedPoints: _int(json['suggestedPoints']),
      finalPoints: json['finalPoints'] == null ? null : _int(json['finalPoints']),
      overdueMinutes: _int(json['overdueMinutes']),
      status: '${json['status'] ?? ''}',
      appealStatus: '${json['appealStatus'] ?? ''}',
      appealReason: '${json['appealReason'] ?? ''}',
      reviewerName: '${json['reviewerName'] ?? ''}',
      reviewComment: '${json['reviewComment'] ?? ''}',
    );
  }
}

class ProposalSlaStat {
  const ProposalSlaStat({
    required this.key,
    required this.name,
    required this.nodes,
    required this.avgMinutes,
    required this.overdueRate,
    required this.proposalCount,
    required this.rejectRounds,
  });

  final String key;
  final String name;
  final int nodes;
  final double avgMinutes;
  final double overdueRate;
  final int proposalCount;
  final int rejectRounds;

  factory ProposalSlaStat.fromJson(Map<String, dynamic> json) {
    return ProposalSlaStat(
      key: '${json['key'] ?? ''}',
      name: '${json['name'] ?? ''}',
      nodes: _int(json['nodes']),
      avgMinutes: _double(json['avgMinutes']),
      overdueRate: _double(json['overdueRate']),
      proposalCount: _int(json['proposalCount']),
      rejectRounds: _int(json['rejectRounds']),
    );
  }
}

class ProposalSlaDashboard {
  const ProposalSlaDashboard({
    required this.from,
    required this.to,
    required this.proposals,
    required this.open,
    required this.finished,
    required this.openOverdue,
    required this.avgTotalHours,
    required this.rejectRounds,
    required this.pendingScores,
    required this.pendingAppeals,
    required this.byStage,
    required this.byPerson,
    required this.overdueOpen,
  });

  final String from;
  final String to;
  final int proposals;
  final int open;
  final int finished;
  final int openOverdue;
  final double avgTotalHours;
  final int rejectRounds;
  final int pendingScores;
  final int pendingAppeals;
  final List<ProposalSlaStat> byStage;
  final List<ProposalSlaStat> byPerson;
  final List<ProposalSlaInstance> overdueOpen;

  factory ProposalSlaDashboard.fromJson(Map<String, dynamic> json) {
    List<T> listOf<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
      final rows = raw is List ? raw : const [];
      return rows.whereType<Map>().map((e) => parse(Map<String, dynamic>.from(e))).toList();
    }

    return ProposalSlaDashboard(
      from: '${json['from'] ?? ''}',
      to: '${json['to'] ?? ''}',
      proposals: _int(json['proposals']),
      open: _int(json['open']),
      finished: _int(json['finished']),
      openOverdue: _int(json['openOverdue']),
      avgTotalHours: _double(json['avgTotalHours']),
      rejectRounds: _int(json['rejectRounds']),
      pendingScores: _int(json['pendingScores']),
      pendingAppeals: _int(json['pendingAppeals']),
      byStage: listOf(json['byStage'], ProposalSlaStat.fromJson),
      byPerson: listOf(json['byPerson'], ProposalSlaStat.fromJson),
      overdueOpen: listOf(json['overdueOpen'], ProposalSlaInstance.fromJson),
    );
  }
}

class ProposalSlaLookupApi {
  ProposalSlaLookupApi({required this.session, http.Client? client}) : _client = client;

  final AuthSession session;
  final http.Client? _client;

  Future<ProposalSlaConfig> fetchConfig() async {
    final data = await _data('GET', '/xflow/proposal-sla/config');
    return ProposalSlaConfig.fromJson(_map(data));
  }

  Future<ProposalSlaConfig> saveConfig(ProposalSlaConfig config) async {
    final data = await _data('PUT', '/xflow/proposal-sla/config', body: config.toJson());
    return ProposalSlaConfig.fromJson(_map(data));
  }

  Future<ProposalSlaDashboard> fetchDashboard({String? from, String? to}) async {
    final data = await _data(
      'GET',
      '/xflow/proposal-sla/dashboard${_query({
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      })}',
    );
    return ProposalSlaDashboard.fromJson(_map(data));
  }

  Future<List<ProposalSlaScore>> fetchScores({required String status, String q = ''}) async {
    final data = await _data(
      'GET',
      '/xflow/proposal-sla/scores${_query({'status': status, 'q': q.trim()})}',
    );
    return _list(data, ProposalSlaScore.fromJson);
  }

  Future<void> reviewScore({
    required int id,
    required String action,
    int? points,
    required String comment,
  }) async {
    await _data('POST', '/xflow/proposal-sla/scores/$id/review', body: {
      'action': action,
      if (points != null) 'points': points,
      'comment': comment,
    });
  }

  Future<List<ProposalSlaInstance>> fetchInstances({required String status, String q = ''}) async {
    final data = await _data(
      'GET',
      '/xflow/proposal-sla/instances${_query({'status': status, 'q': q.trim()})}',
    );
    return _list(data, ProposalSlaInstance.fromJson);
  }

  Future<List<ProposalSlaNode>> fetchNodes(int instanceId) async {
    final data = await _data('GET', '/xflow/proposal-sla/instances/$instanceId/nodes');
    return _list(data, ProposalSlaNode.fromJson);
  }

  Future<void> createExemption({
    required int instanceId,
    required int nodeId,
    required String reasonType,
    required String reason,
  }) async {
    await _data('POST', '/xflow/proposal-sla/exemptions', body: {
      'instanceId': instanceId,
      if (nodeId > 0) 'nodeId': nodeId,
      'reasonType': reasonType,
      'reason': reason,
    });
  }

  Future<dynamic> _data(String method, String path, {Map<String, dynamic>? body}) async {
    final encoded = body == null ? null : jsonEncode(body);
    final http.Response resp = switch (method) {
      'PUT' => await dunesHttpPut(session, path, body: encoded, client: _client),
      'POST' => await dunesHttpPost(session, path, body: encoded, client: _client),
      _ => await dunesHttpGet(session, path, client: _client),
    };
    return _unwrap(resp);
  }

  static dynamic _unwrap(http.Response resp) {
    Map<String, dynamic> map = const {};
    if (resp.body.isNotEmpty) {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) map = Map<String, dynamic>.from(decoded);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300 || map['success'] == false) {
      final message = '${map['message'] ?? ''}'.trim();
      throw Exception(message.isEmpty ? '请求失败' : message);
    }
    return map['data'];
  }

  static Map<String, dynamic> _map(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  static List<T> _list<T>(Object? data, T Function(Map<String, dynamic>) parse) {
    final rows = data is List ? data : const [];
    return rows.whereType<Map>().map((e) => parse(Map<String, dynamic>.from(e))).toList();
  }

  static String _query(Map<String, String> params) {
    final entries = params.entries.where((e) => e.value.isNotEmpty).toList();
    if (entries.isEmpty) return '';
    return '?${entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
  }
}

int _int(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

double _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

String proposalSlaClock(int minute) {
  final h = minute ~/ 60;
  final m = minute % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

int? proposalSlaClockToMinute(String raw) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
  if (match == null) return null;
  final h = int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  if (h > 24 || m > 59) return null;
  return h * 60 + m;
}

String proposalSlaStatusLabel(String status) => switch (status) {
  'normal' => '正常',
  'warning' => '卡点',
  'overdue' => '已超时',
  'exempt' => '已免责',
  'finished' => '已完成',
  'pending' => '待复核',
  'confirmed' => '已确认',
  'rejected' => '已撤销',
  'adjusted' => '已调整',
  _ => status.isEmpty ? '—' : status,
};

String proposalSlaKindLabel(String kind) => switch (kind) {
  'node' => '节点超时',
  'leader' => '部门负责人连带',
  'total' => '总时长超时',
  _ => kind,
};

String proposalSlaMinutes(int minutes) {
  final v = minutes < 0 ? 0 : minutes;
  final h = v ~/ 60;
  final r = v % 60;
  if (h > 0 && r > 0) return '$h 小时 $r 分';
  if (h > 0) return '$h 小时';
  return '$r 分钟';
}

String proposalSlaTimeText(String raw) {
  if (raw.isEmpty) return '—';
  final d = DateTime.tryParse(raw)?.toLocal();
  if (d == null) return raw;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
