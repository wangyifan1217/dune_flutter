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

  /// 是否存在总时长逾期或节点逾期（已免责除外）。
  bool get isOverdue =>
      !exempt &&
      (status == 'overdue' ||
          status == 'finished_overdue' ||
          overdueNodes > 0 ||
          (totalHours > 0 && elapsedHours > totalHours));

  /// 用于展示与筛选的统一有效状态（区分「已逾期」与「逾期完成」）。
  String get effectiveStatus {
    if (exempt || status == 'exempt') return 'exempt';
    if (status == 'finished_overdue') return 'finished_overdue';
    if (status == 'finished') {
      return isOverdue ? 'finished_overdue' : 'finished';
    }
    if (isOverdue) return 'overdue';
    return status;
  }

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
    this.effectiveMinutes = 0,
    this.limitMinutes = 0,
  });

  final int id;
  final int round;
  final String label;
  final String assigneeName;
  final String endedAt;
  final String state;
  final bool exempt;
  final int effectiveMinutes;
  final int limitMinutes;

  factory ProposalSlaNode.fromJson(Map<String, dynamic> json) {
    return ProposalSlaNode(
      id: _int(json['id']),
      round: _int(json['round']),
      label: '${json['label'] ?? ''}',
      assigneeName: '${json['assigneeName'] ?? ''}',
      endedAt: '${json['endedAt'] ?? ''}',
      state: '${json['state'] ?? ''}',
      exempt: json['exempt'] == true,
      effectiveMinutes: _int(json['effectiveMinutes']),
      limitMinutes: _int(json['limitMinutes']),
    );
  }
}

class ProposalSlaScore {
  const ProposalSlaScore({
    required this.id,
    this.proposalId = 0,
    this.round = 0,
    this.sector = '',
    this.overdueAt = '',
    this.createdAt = '',
    this.reviewedAt = '',
    this.appealDeadline = '',
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
  final int proposalId;
  final int round;
  final String sector;
  final String overdueAt;
  final String createdAt;
  final String reviewedAt;
  final String appealDeadline;
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

  ProposalSlaScore withReviewResult({
    required String status,
    required int points,
    required String comment,
  }) => ProposalSlaScore(
    id: id,
    proposalId: proposalId,
    round: round,
    sector: sector,
    overdueAt: overdueAt,
    createdAt: createdAt,
    appealDeadline: appealDeadline,
    code: code,
    title: title,
    kind: kind,
    nodeLabel: nodeLabel,
    userName: userName,
    sourceUserName: sourceUserName,
    suggestedPoints: suggestedPoints,
    finalPoints: points,
    overdueMinutes: overdueMinutes,
    status: status,
    appealStatus: appealStatus == 'pending'
        ? (status == 'exempt' || status == 'rejected' ? 'approved' : 'rejected')
        : appealStatus,
    appealReason: appealReason,
    reviewerName: '',
    reviewComment: comment,
  );

  factory ProposalSlaScore.fromJson(Map<String, dynamic> json) {
    return ProposalSlaScore(
      id: _int(json['id']),
      proposalId: _int(json['proposalId']),
      round: _int(json['round']),
      sector: '${json['sector'] ?? ''}',
      overdueAt: '${json['overdueAt'] ?? ''}',
      createdAt: '${json['createdAt'] ?? ''}',
      reviewedAt: '${json['reviewedAt'] ?? ''}',
      appealDeadline: '${json['appealDeadline'] ?? ''}',
      code: '${json['code'] ?? ''}',
      title: '${json['title'] ?? ''}',
      kind: '${json['kind'] ?? ''}',
      nodeLabel: '${json['nodeLabel'] ?? ''}',
      userName: '${json['userName'] ?? ''}',
      sourceUserName: '${json['sourceUserName'] ?? ''}',
      suggestedPoints: _int(json['suggestedPoints']),
      finalPoints: json['finalPoints'] == null
          ? null
          : _int(json['finalPoints']),
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
    this.warningRate = 0,
    this.exemptRate = 0,
    this.overdueCount = 0,
  });

  final String key;
  final String name;
  final int nodes;
  final double avgMinutes;
  final double overdueRate;
  final double warningRate;
  final double exemptRate;
  final int overdueCount;
  final int proposalCount;
  final int rejectRounds;

  factory ProposalSlaStat.fromJson(Map<String, dynamic> json) {
    return ProposalSlaStat(
      key: '${json['key'] ?? ''}',
      name: '${json['name'] ?? ''}',
      nodes: _int(json['nodes']),
      avgMinutes: _double(json['avgMinutes']),
      overdueRate: _double(json['overdueRate']),
      warningRate: _double(json['warningRate']),
      exemptRate: _double(json['exemptRate']),
      overdueCount: _int(json['overdueCount']),
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
    this.bySector = const [],
    this.sectorOptions = const [],
    this.items = const [],
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
  final List<ProposalSlaStat> bySector;
  final List<String> sectorOptions;
  final List<ProposalSlaInstance> overdueOpen;
  final List<ProposalSlaInstance> items;

  factory ProposalSlaDashboard.fromJson(Map<String, dynamic> json) {
    List<T> listOf<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
      final rows = raw is List ? raw : const [];
      return rows.whereType<Map>().map((e) => parse(Map<String, dynamic>.from(e))).toList();
    }

    final rawSectors = json['sectorOptions'] is List ? json['sectorOptions'] as List : const [];
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
      bySector: listOf(json['bySector'], ProposalSlaStat.fromJson),
      sectorOptions: rawSectors
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      overdueOpen: listOf(json['overdueOpen'], ProposalSlaInstance.fromJson),
      items: listOf(json['items'], ProposalSlaInstance.fromJson),
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

  Future<ProposalSlaDashboard> fetchDashboard({
    String? from,
    String? to,
    String? sector,
    String? stage,
    String? status,
  }) async {
    final data = await _data(
      'GET',
      '/xflow/proposal-sla/dashboard${_query({
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        if (sector != null && sector.isNotEmpty) 'sector': sector,
        if (stage != null && stage.isNotEmpty) 'stage': stage,
        if (status != null && status.isNotEmpty) 'status': status,
      })}',
    );
    return ProposalSlaDashboard.fromJson(_map(data));
  }

  Future<List<ProposalSlaScore>> fetchScores({
    required String status,
    String q = '',
    String? from,
    String? to,
    String? sector,
    String? kind,
  }) async {
    final data = await _data(
      'GET',
      '/xflow/proposal-sla/scores${_query({
        'status': status,
        'q': q.trim(),
        'grouped': '1',
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        if (sector != null && sector.isNotEmpty) 'sector': sector,
        if (kind != null && kind.isNotEmpty) 'kind': kind,
      })}',
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

  Future<List<ProposalSlaInstance>> fetchInstances({
    required String status,
    String q = '',
    String? from,
    String? to,
    String? sector,
  }) async {
    final data = await _data(
      'GET',
      '/xflow/proposal-sla/instances${_query({
        'status': status,
        'q': q.trim(),
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        if (sector != null && sector.isNotEmpty) 'sector': sector,
      })}',
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
  'normal' => '正常进行',
  'warning' => '即将逾期',
  'overdue' => '已逾期',
  'finished_overdue' => '逾期完成',
  'exempt' => '已免责',
  'finished' => '按时完成',
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

String _csvCell(Object? value) {
  final raw = '${value ?? ''}'.replaceAll('\r\n', ' ').replaceAll('\n', ' ');
  final needsQuote = raw.contains(',') || raw.contains('"');
  final escaped = raw.replaceAll('"', '""');
  return needsQuote ? '"$escaped"' : escaped;
}

String _csvRow(List<Object?> cells) => cells.map(_csvCell).join(',');

/// 构建「时效看板」按当前筛选条件导出的 UTF-8 BOM CSV（Excel / WPS 直接打开不乱码）。
String buildProposalSlaDashboardCsv({
  required ProposalSlaDashboard data,
  required List<ProposalSlaStat> stages,
  required List<ProposalSlaStat> sectors,
  required List<ProposalSlaStat> people,
  required List<ProposalSlaInstance> proposals,
  required String filterSummary,
}) {
  final buf = StringBuffer('\uFEFF');
  final now = proposalSlaTimeText(DateTime.now().toIso8601String());
  buf.writeln(_csvRow(['提案时效看板报表']));
  buf.writeln(_csvRow(['统计区间', '${data.from} 至 ${data.to}']));
  buf.writeln(_csvRow(['筛选条件', filterSummary]));
  buf.writeln(_csvRow(['导出时间', now]));
  buf.writeln();

  buf.writeln(_csvRow(['一、核心指标汇总']));
  buf.writeln(_csvRow(['纳入考核提案', '进行中', '已完成', '当前在途超时', '已办结平均总用时(h)', '驳回轮回次数', '待复核扣分', '申诉待处理']));
  buf.writeln(_csvRow([
    data.proposals,
    data.open,
    data.finished,
    data.openOverdue,
    data.avgTotalHours,
    data.rejectRounds,
    data.pendingScores,
    data.pendingAppeals,
  ]));
  buf.writeln();

  void writeStats(String sectionTitle, String dimLabel, List<ProposalSlaStat> rows) {
    buf.writeln(_csvRow([sectionTitle]));
    buf.writeln(_csvRow([dimLabel, '涉及提案数', '经办节点数', '平均用时', '超时节点数', '超时率(%)', '预警率(%)', '免责率(%)', '驳回轮回']));
    for (final r in rows) {
      buf.writeln(_csvRow([
        r.name.isEmpty ? '—' : r.name,
        r.proposalCount,
        r.nodes,
        proposalSlaMinutes(r.avgMinutes.round()),
        r.overdueCount,
        '${r.overdueRate}%',
        '${r.warningRate}%',
        '${r.exemptRate}%',
        r.rejectRounds,
      ]));
    }
    buf.writeln();
  }

  writeStats('二、按审核环节统计', '审核环节', stages);
  writeStats('三、按业务板块统计', '业务板块', sectors);
  writeStats('四、按责任人统计', '责任人', people);

  buf.writeln(_csvRow(['五、提案时效明细（共 ${proposals.length} 条）']));
  buf.writeln(_csvRow(['提案编号', '提案名称', '所属板块', '状态', '已耗时(h)', '总时限(h)', '当前节点/责任人', '超时节点数', '驳回轮回', '开始时间']));
  for (final p in proposals) {
    buf.writeln(_csvRow([
      p.code,
      p.title,
      p.sector.isEmpty ? '未填写' : p.sector,
      proposalSlaStatusLabel(p.effectiveStatus),
      p.elapsedHours,
      p.totalHours,
      p.current.isEmpty ? '—' : p.current,
      p.overdueNodes,
      p.round > 0 ? p.round - 1 : 0,
      proposalSlaTimeText(p.startedAt),
    ]));
  }
  return buf.toString();
}

/// 构建「绩效与申诉」按当前筛选条件导出的 UTF-8 BOM CSV。
String buildProposalSlaScoresCsv({
  required List<ProposalSlaScore> rows,
  required String filterSummary,
}) {
  final buf = StringBuffer('\uFEFF');
  final now = proposalSlaTimeText(DateTime.now().toIso8601String());
  buf.writeln(_csvRow(['提案时效绩效与申诉明细']));
  buf.writeln(_csvRow(['筛选条件', filterSummary]));
  buf.writeln(_csvRow(['导出时间', now]));
  buf.writeln();
  buf.writeln(_csvRow([
    '提案编号',
    '提案名称',
    '所属板块',
    '轮次',
    '超时类型',
    '卡点环节',
    '责任人',
    '源责任人',
    '超时时长',
    '建议扣分',
    '最终扣分',
    '复核状态',
    '申诉状态',
    '申诉理由',
    '复核人',
    '复核意见',
    '记录时间',
  ]));
  for (final r in rows) {
    buf.writeln(_csvRow([
      r.code,
      r.title,
      r.sector.isEmpty ? '未填写' : r.sector,
      r.round,
      proposalSlaKindLabel(r.kind),
      r.nodeLabel.isEmpty ? '—' : r.nodeLabel,
      r.userName,
      r.sourceUserName,
      proposalSlaMinutes(r.overdueMinutes),
      r.suggestedPoints,
      r.finalPoints ?? '',
      proposalSlaStatusLabel(r.status),
      r.appealStatus.isEmpty ? '无' : proposalSlaStatusLabel(r.appealStatus),
      r.appealReason,
      r.reviewerName,
      r.reviewComment,
      proposalSlaTimeText(r.createdAt),
    ]));
  }
  return buf.toString();
}

/// 构建「提案列表 / 免责登记」按当前筛选条件导出的 UTF-8 BOM CSV。
String buildProposalSlaInstancesCsv({
  required List<ProposalSlaInstance> rows,
  required String filterSummary,
}) {
  final buf = StringBuffer('\uFEFF');
  final now = proposalSlaTimeText(DateTime.now().toIso8601String());
  buf.writeln(_csvRow(['提案时效实例与免责明细']));
  buf.writeln(_csvRow(['筛选条件', filterSummary]));
  buf.writeln(_csvRow(['导出时间', now]));
  buf.writeln();
  buf.writeln(_csvRow(['提案编号', '提案名称', '所属板块', '状态', '是否免责', '已耗时(h)', '总时限(h)', '当前节点/责任人', '超时节点数', '驳回轮回', '开始时间']));
  for (final p in rows) {
    buf.writeln(_csvRow([
      p.code,
      p.title,
      p.sector.isEmpty ? '未填写' : p.sector,
      proposalSlaStatusLabel(p.effectiveStatus),
      p.exempt ? '是' : '否',
      p.elapsedHours,
      p.totalHours,
      p.current.isEmpty ? '—' : p.current,
      p.overdueNodes,
      p.round > 0 ? p.round - 1 : 0,
      proposalSlaTimeText(p.startedAt),
    ]));
  }
  return buf.toString();
}
