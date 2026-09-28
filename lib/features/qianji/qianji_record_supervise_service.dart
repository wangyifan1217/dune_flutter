import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';

enum QianjiRecordSuperviseKind { task, dailyReport, groupReply }

class QianjiRecordSuperviseHit {
  const QianjiRecordSuperviseHit({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.time,
    this.userId = 0,
    this.personName = '',
    this.avatarPreset = '',
    this.avatarObjectKey = '',
    this.avatarUrl = '',
  });

  final String id;
  final String title;
  final String subtitle;
  final String status;
  final String time;
  final int userId;
  final String personName;
  final String avatarPreset;
  final String avatarObjectKey;
  final String avatarUrl;

  QianjiRecordSuperviseHit copyWithAvatar({
    int? userId,
    String? personName,
    String? avatarPreset,
    String? avatarObjectKey,
    String? avatarUrl,
  }) {
    return QianjiRecordSuperviseHit(
      id: id,
      title: title,
      subtitle: subtitle,
      status: status,
      time: time,
      userId: userId ?? this.userId,
      personName: personName ?? this.personName,
      avatarPreset: avatarPreset ?? this.avatarPreset,
      avatarObjectKey: avatarObjectKey ?? this.avatarObjectKey,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  factory QianjiRecordSuperviseHit.fromJson(Map<String, dynamic> json) {
    String text(List<String> keys) {
      for (final key in keys) {
        final value = '${json[key] ?? ''}'.trim();
        if (value.isNotEmpty && value != 'null') return value;
      }
      return '';
    }

    final id = text(['id', 'taskId', 'reportId', 'messageId', 'conversationId']);
    final userId =
        (json['userId'] as num?)?.toInt() ??
        (json['ownerUserId'] as num?)?.toInt() ??
        (json['senderUserId'] as num?)?.toInt() ??
        (json['personId'] as num?)?.toInt() ??
        0;
    return QianjiRecordSuperviseHit(
      id: id.isEmpty ? text(['title', 'name']) : id,
      title: text(['title', 'name', 'subject', 'taskTitle', 'bodyText']),
      subtitle: text([
        'subtitle',
        'summary',
        'departmentName',
      ]),
      status: text(['statusLabel', 'statusText', 'status']),
      time: text(['displayTime', 'time', 'reportDate', 'dueDate', 'createdAt']),
      userId: userId,
      personName: text([
        'personName',
        'ownerName',
        'displayName',
        'senderName',
        'userName',
      ]),
      avatarPreset: text(['avatarPreset', 'ownerAvatarPreset', 'peerAvatarPreset']),
      avatarObjectKey: text([
        'avatarObjectKey',
        'ownerAvatarObjectKey',
        'peerAvatarObjectKey',
      ]),
      avatarUrl: text(['avatarUrl', 'ownerAvatarUrl', 'peerAvatarUrl']),
    );
  }
}

class QianjiRecordSupervisePageResult {
  const QianjiRecordSupervisePageResult({
    required this.items,
    required this.totalCount,
  });

  final List<QianjiRecordSuperviseHit> items;
  final int totalCount;
}

class QianjiRecordDeptStat {
  const QianjiRecordDeptStat({
    required this.departmentId,
    required this.departmentName,
    required this.count,
  });

  final int? departmentId;
  final String departmentName;
  final int count;

  factory QianjiRecordDeptStat.fromJson(Map<String, dynamic> json) {
    final count =
        (json['count'] as num?)?.toInt() ??
        (json['meetingCount'] as num?)?.toInt() ??
        (json['accountCount'] as num?)?.toInt() ??
        (json['total'] as num?)?.toInt() ??
        0;
    return QianjiRecordDeptStat(
      departmentId: (json['departmentId'] as num?)?.toInt(),
      departmentName: '${json['departmentName'] ?? '未分配部门'}',
      count: count,
    );
  }
}

class QianjiRecordDeptStatsResult {
  const QianjiRecordDeptStatsResult({
    required this.departments,
    required this.total,
    required this.superviseAll,
  });

  final List<QianjiRecordDeptStat> departments;
  final int total;
  final bool superviseAll;

  factory QianjiRecordDeptStatsResult.fromJson(Map<String, dynamic> json) {
    final content =
        (json['content'] as List?) ??
        (json['items'] as List?) ??
        (json['departments'] as List?) ??
        const [];
    return QianjiRecordDeptStatsResult(
      departments: content
          .whereType<Map>()
          .map(
            (e) => QianjiRecordDeptStat.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
      total:
          (json['total'] as num?)?.toInt() ??
          (json['totalMeetings'] as num?)?.toInt() ??
          (json['totalCount'] as num?)?.toInt() ??
          0,
      superviseAll: json['superviseAll'] == true,
    );
  }
}

class QianjiRecordSuperviseService {
  QianjiRecordSuperviseService({
    required this.session,
    required this.kind,
  });

  final AuthSession session;
  final QianjiRecordSuperviseKind kind;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
  };

  String get _path => switch (kind) {
    QianjiRecordSuperviseKind.task => 'tasks/supervise',
    QianjiRecordSuperviseKind.dailyReport => 'task-daily-reports/supervise',
    QianjiRecordSuperviseKind.groupReply => 'reply-sla/supervise',
  };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/qianji/$path').replace(queryParameters: query);
  }

  Future<QianjiRecordSupervisePageResult> fetchListPage({
    int page = 0,
    int size = 20,
    String keyword = '',
    int? departmentId,
  }) async {
    final q = <String, String>{
      'page': '$page',
      'size': '$size',
      'scope': 'supervise',
    };
    final k = keyword.trim();
    if (k.isNotEmpty) q['q'] = k;
    if (departmentId != null) q['departmentId'] = '$departmentId';
    final data = _asMap(_unwrap(await http.get(_uri(_path, q), headers: _headers)));
    final content =
        (data['content'] as List?) ?? (data['items'] as List?) ?? const [];
    final items = content
        .whereType<Map>()
        .map(
          (e) => QianjiRecordSuperviseHit.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList(growable: false);
    final total =
        (data['total'] as num?)?.toInt() ??
        (data['totalCount'] as num?)?.toInt() ??
        (data['totalElements'] as num?)?.toInt() ??
        items.length;
    return QianjiRecordSupervisePageResult(items: items, totalCount: total);
  }

  Future<QianjiRecordDeptStatsResult> fetchDeptStats() async {
    final data = _asMap(
      _unwrap(await http.get(_uri('$_path/dept-stats'), headers: _headers)),
    );
    return QianjiRecordDeptStatsResult.fromJson(data);
  }

  dynamic _unwrap(http.Response resp) {
    final raw = utf8.decode(resp.bodyBytes);
    final body = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
    if (body is! Map) throw Exception('invalid response');
    if (resp.statusCode >= 400 || body['success'] == false) {
      throw Exception('${body['message'] ?? '请求失败'}');
    }
    return body['data'] ?? body;
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }
}
