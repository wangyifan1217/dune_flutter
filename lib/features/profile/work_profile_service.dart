import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';

Map<String, dynamic> _workProfileMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

String _workProfileDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

dynamic _workProfileUnwrap(http.Response response) {
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('工作画像请求失败：HTTP ${response.statusCode}');
  }
  final decoded = jsonDecode(response.body);
  if (decoded is Map && decoded['success'] == false) {
    throw Exception('${decoded['message'] ?? '工作画像请求失败'}');
  }
  return decoded is Map && decoded.containsKey('data')
      ? decoded['data']
      : decoded;
}

class WorkProfileTrendPoint {
  const WorkProfileTrendPoint({
    required this.month,
    this.taskCompleted = 0,
    this.meetings = 0,
    this.minutesGenerated = 0,
    this.knowledgeDocuments = 0,
  });

  final String month;
  final int taskCompleted;
  final int meetings;
  final int minutesGenerated;
  final int knowledgeDocuments;

  factory WorkProfileTrendPoint.fromJson(Map<String, dynamic> json) =>
      WorkProfileTrendPoint(
        month: '${json['month'] ?? ''}',
        taskCompleted: (json['taskCompleted'] as num?)?.toInt() ?? 0,
        meetings: (json['meetings'] as num?)?.toInt() ?? 0,
        minutesGenerated: (json['minutesGenerated'] as num?)?.toInt() ?? 0,
        knowledgeDocuments: (json['knowledgeDocuments'] as num?)?.toInt() ?? 0,
      );
}

class WorkProfileSafePerson {
  const WorkProfileSafePerson({
    required this.userId,
    required this.name,
    this.username = '',
    this.title = '',
    this.departmentId = 0,
    this.departmentName = '',
    this.taskTotal = 0,
    this.taskCompleted = 0,
    this.taskOverdue = 0,
    this.taskDoing = 0,
    this.approvalTotal = 0,
    this.approvalPending = 0,
    this.proposalTotal = 0,
    this.proposalRejected = 0,
    this.meetings = 0,
    this.minutesGenerated = 0,
    this.meetingsLinkedTask = 0,
    this.knowledgeDocuments = 0,
    this.knowledgeReferences = 0,
    this.performanceMonth = '',
    this.performanceScore,
    this.performanceGrade = '',
    this.updatedAt = '',
    this.trend = const [],
  });

  final int userId;
  final String name;
  final String username;
  final String title;
  final int departmentId;
  final String departmentName;
  final int taskTotal;
  final int taskCompleted;
  final int taskOverdue;
  final int taskDoing;
  final int approvalTotal;
  final int approvalPending;
  final int proposalTotal;
  final int proposalRejected;
  final int meetings;
  final int minutesGenerated;
  final int meetingsLinkedTask;
  final int knowledgeDocuments;
  final int knowledgeReferences;
  final String performanceMonth;
  final double? performanceScore;
  final String performanceGrade;
  final String updatedAt;
  final List<WorkProfileTrendPoint> trend;

  factory WorkProfileSafePerson.fromJson(
    Map<String, dynamic> json,
  ) => WorkProfileSafePerson(
    userId: (json['userId'] as num?)?.toInt() ?? 0,
    name: '${json['name'] ?? ''}',
    username: '${json['username'] ?? ''}',
    title: '${json['title'] ?? ''}',
    departmentId: (json['departmentId'] as num?)?.toInt() ?? 0,
    departmentName: '${json['departmentName'] ?? ''}',
    taskTotal: (json['taskTotal'] as num?)?.toInt() ?? 0,
    taskCompleted: (json['taskCompleted'] as num?)?.toInt() ?? 0,
    taskOverdue: (json['taskOverdue'] as num?)?.toInt() ?? 0,
    taskDoing: (json['taskDoing'] as num?)?.toInt() ?? 0,
    approvalTotal: (json['approvalTotal'] as num?)?.toInt() ?? 0,
    approvalPending: (json['approvalPending'] as num?)?.toInt() ?? 0,
    proposalTotal: (json['proposalTotal'] as num?)?.toInt() ?? 0,
    proposalRejected: (json['proposalRejected'] as num?)?.toInt() ?? 0,
    meetings: (json['meetings'] as num?)?.toInt() ?? 0,
    minutesGenerated: (json['minutesGenerated'] as num?)?.toInt() ?? 0,
    meetingsLinkedTask: (json['meetingsLinkedTask'] as num?)?.toInt() ?? 0,
    knowledgeDocuments: (json['knowledgeDocuments'] as num?)?.toInt() ?? 0,
    knowledgeReferences: (json['knowledgeReferences'] as num?)?.toInt() ?? 0,
    performanceMonth: '${json['performanceMonth'] ?? ''}',
    performanceScore: (json['performanceScore'] as num?)?.toDouble(),
    performanceGrade: '${json['performanceGrade'] ?? ''}',
    updatedAt: '${json['updatedAt'] ?? ''}',
    trend: (json['trend'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (row) =>
              WorkProfileTrendPoint.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false),
  );
}

class WorkProfileTeamSnapshot {
  const WorkProfileTeamSnapshot({
    required this.month,
    required this.memberCount,
    required this.allowPersonDrilldown,
    this.scopeLabel = '',
    this.taskTotal = 0,
    this.taskCompleted = 0,
    this.approvalTotal = 0,
    this.approvalPending = 0,
    this.proposalTotal = 0,
    this.proposalRejected = 0,
    this.meetings = 0,
    this.minutesGenerated = 0,
    this.knowledgeDocuments = 0,
    this.people = const [],
    this.updatedAt = '',
    this.trend = const [],
  });

  final String month;
  final int memberCount;
  final bool allowPersonDrilldown;
  final String scopeLabel;
  final int taskTotal;
  final int taskCompleted;
  final int approvalTotal;
  final int approvalPending;
  final int proposalTotal;
  final int proposalRejected;
  final int meetings;
  final int minutesGenerated;
  final int knowledgeDocuments;
  final List<WorkProfileSafePerson> people;
  final String updatedAt;
  final List<WorkProfileTrendPoint> trend;

  factory WorkProfileTeamSnapshot.fromJson(Map<String, dynamic> json) {
    final summary = _workProfileMap(json['summary']);
    return WorkProfileTeamSnapshot(
      month: '${json['month'] ?? ''}',
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      allowPersonDrilldown: json['allowPersonDrilldown'] == true,
      scopeLabel: '${json['scopeLabel'] ?? ''}',
      taskTotal: (summary['taskTotal'] as num?)?.toInt() ?? 0,
      taskCompleted: (summary['taskCompleted'] as num?)?.toInt() ?? 0,
      approvalTotal: (summary['approvalTotal'] as num?)?.toInt() ?? 0,
      approvalPending: (summary['approvalPending'] as num?)?.toInt() ?? 0,
      proposalTotal: (summary['proposalTotal'] as num?)?.toInt() ?? 0,
      proposalRejected: (summary['proposalRejected'] as num?)?.toInt() ?? 0,
      meetings: (summary['meetings'] as num?)?.toInt() ?? 0,
      minutesGenerated: (summary['minutesGenerated'] as num?)?.toInt() ?? 0,
      knowledgeDocuments: (summary['knowledgeDocuments'] as num?)?.toInt() ?? 0,
      updatedAt: '${json['updatedAt'] ?? ''}',
      trend: (json['trend'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) =>
                WorkProfileTrendPoint.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false),
      people: (json['people'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) =>
                WorkProfileSafePerson.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false),
    );
  }
}

class WorkProfileService {
  WorkProfileService({required this.session, http.Client? client})
    : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;

  Future<Map<String, dynamic>> fetchMe({String month = ''}) async {
    final query = month.trim().isEmpty
        ? ''
        : '?month=${Uri.encodeQueryComponent(month.trim())}';
    final response = await dunesHttpGet(
      session,
      '/work-profile/me$query',
      client: _client,
    );
    return _workProfileMap(_workProfileUnwrap(response));
  }

  Future<WorkProfileTeamSnapshot> fetchTeam({
    DateTime? from,
    DateTime? to,
    String month = '',
  }) async {
    final params = <String, String>{};
    if (from != null && to != null) {
      params['from'] = _workProfileDay(from);
      params['to'] = _workProfileDay(to);
    } else if (month.trim().isNotEmpty) {
      params['month'] = month.trim();
    }
    final query = params.isEmpty
        ? ''
        : '?${Uri(queryParameters: params).query}';
    final response = await dunesHttpGet(
      session,
      '/work-profile/team$query',
      client: _client,
    );
    return WorkProfileTeamSnapshot.fromJson(
      _workProfileMap(_workProfileUnwrap(response)),
    );
  }

  Future<WorkProfileSafePerson> fetchPerson({
    required int userId,
    DateTime? from,
    DateTime? to,
    String month = '',
  }) async {
    final params = <String, String>{'userId': '$userId'};
    if (from != null && to != null) {
      params['from'] = _workProfileDay(from);
      params['to'] = _workProfileDay(to);
    } else if (month.trim().isNotEmpty) {
      params['month'] = month.trim();
    }
    final response = await dunesHttpGet(
      session,
      '/work-profile/person?${Uri(queryParameters: params).query}',
      client: _client,
    );
    final data = _workProfileMap(_workProfileUnwrap(response));
    final person = _workProfileMap(data['person'])
      ..['updatedAt'] = data['updatedAt']
      ..['trend'] = data['trend'];
    return WorkProfileSafePerson.fromJson(person);
  }
}
