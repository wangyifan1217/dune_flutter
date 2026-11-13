import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';

/// 用户看到的名称。已发布得分仍叫「绩效」，灯塔导入发布仍叫「月度绩效考评」。
const hrPerformanceTitle = '绩效考核';

const hrPerformanceStageLabels = <String, String>{
  'opening': '开启考核 / 待补配',
  'indicators': '指标确认',
  'review': '主管初评',
  'calibration': '绩效校准',
  'hr': 'HR 审核',
  'final': '总裁办终审',
  'result': '结果确认',
  'interview': '面谈',
  'archived': '已归档',
  'exempt': '免考核',
};

class HrPerformanceAccess {
  const HrPerformanceAccess({
    this.allowed = false,
    this.team = false,
    this.all = false,
    this.pendingCount = 0,
    this.hr = false,
    this.finalAccess = false,
    this.followup = false,
  });
  final bool allowed;
  final bool team;
  final bool all;
  final int pendingCount;
  final bool hr, finalAccess, followup;
  factory HrPerformanceAccess.fromJson(Map<String, dynamic> json) =>
      HrPerformanceAccess(
        allowed: json['allowed'] == true,
        hr: json['hr'] == true,
        finalAccess: json['final'] == true,
        followup: json['followup'] == true,
        team: json['team'] == true,
        all: json['all'] == true,
        pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
      );
}

class HrPerformanceRecord {
  HrPerformanceRecord.fromJson(Map<String, dynamic> json)
    : id = (json['id'] as num).toInt(),
      userId = (json['userId'] as num).toInt(),
      month = '${json['month'] ?? ''}',
      stage = '${json['stage'] ?? 'opening'}',
      adjustmentDueAt = DateTime.tryParse('${json['adjustmentDueAt'] ?? ''}'),
      snapshot = Map<String, dynamic>.from(json['snapshot'] as Map),
      version = (json['version'] as num?)?.toInt() ?? 1,
      draftVisible = json['draftVisible'] == true,
      actions = (json['actions'] as List? ?? const [])
          .map((x) => '$x')
          .toList(),
      todoGroups = (json['todoGroups'] as List? ?? const [])
          .map((x) => '$x')
          .toList(),
      warnings = (json['warnings'] as List? ?? const [])
          .map((x) => '$x')
          .toList();

  final int version;
  final bool draftVisible;
  final List<String> actions, todoGroups, warnings;
  final int id;
  final int userId;
  final String month;
  final String stage;
  final DateTime? adjustmentDueAt;
  final Map<String, dynamic> snapshot;
  Map<String, dynamic> get workflow => snapshot['workflow'] is Map
      ? Map<String, dynamic>.from(snapshot['workflow'])
      : {};
  List<Map<String, dynamic>> get requests => _maps(workflow['requests']);
  List<Map<String, dynamic>> get bonuses => _maps(workflow['bonuses']);
  bool get scoresVisible => released || draftVisible;
  String get name => '${snapshot['name'] ?? ''}';
  String get department => '${snapshot['departmentName'] ?? ''}';
  String get position => '${snapshot['positionName'] ?? ''}';
  String get stageLabel => hrPerformanceStageLabels[stage] ?? stage;
  bool get released =>
      const ['result', 'interview', 'archived'].contains(stage) &&
      workflow['archiveReason'] != '离职未确认';
  bool get probation => snapshot['probation'] == true;
  bool get exemptionEligible => snapshot['exemptionEligible'] == true;
  List<String> get blockers =>
      (snapshot['blockers'] as List? ?? const []).map((v) => '$v').toList();
  List<Map<String, dynamic>> get evidence => _maps(snapshot['evidence']);
  List<Map<String, dynamic>> get lines => _maps(snapshot['lines']);
  static List<Map<String, dynamic>> _maps(dynamic raw) =>
      (raw as List? ?? const [])
          .whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
}

class HrPerformanceService {
  HrPerformanceService(this.session);
  final AuthSession session;

  dynamic _unwrap(http.Response response) {
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map) throw Exception('服务返回格式无效');
    if (response.statusCode >= 400 || body['success'] == false) {
      throw Exception('${body['message'] ?? '请求失败'}');
    }
    return body['data'];
  }

  Future<HrPerformanceAccess> access() async {
    final data = _unwrap(await dunesHttpGet(session, '/hr-performance/access'));
    return HrPerformanceAccess.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<HrPerformanceRecord>> records(String month, String scope) async {
    final query = Uri(queryParameters: {'month': month, 'scope': scope}).query;
    final data = _unwrap(
      await dunesHttpGet(session, '/hr-performance/records?$query'),
    );
    return (data as List)
        .map((v) => HrPerformanceRecord.fromJson(Map<String, dynamic>.from(v)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> logs(int id) async {
    final data = _unwrap(
      await dunesHttpGet(session, '/hr-performance/records/$id/logs'),
    );
    return HrPerformanceRecord._maps(data);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async => Map<String, dynamic>.from(
    _unwrap(await dunesHttpPost(session, path, body: jsonEncode(body))) as Map,
  );
  Future<HrPerformanceRecord> detail(int id) async =>
      HrPerformanceRecord.fromJson(
        Map<String, dynamic>.from(
          _unwrap(await dunesHttpGet(session, '/hr-performance/records/$id'))
              as Map,
        ),
      );
  Future<Map<String, dynamic>> options(
    int id,
  ) async => Map<String, dynamic>.from(
    _unwrap(await dunesHttpGet(session, '/hr-performance/records/$id/options'))
        as Map,
  );
  Future<HrPerformanceRecord> action(
    HrPerformanceRecord record,
    Map<String, dynamic> command,
  ) async => HrPerformanceRecord.fromJson(
    await _post('/hr-performance/records/${record.id}/actions', {
      'version': record.version,
      ...command,
    }),
  );
  Future<HrPerformanceRecord> assign(
    HrPerformanceRecord record,
    Map<String, dynamic> values,
  ) async => HrPerformanceRecord.fromJson(
    Map<String, dynamic>.from(
      _unwrap(
            await dunesHttpPatch(
              session,
              '/hr-performance/records/${record.id}/assignment',
              body: jsonEncode({'version': record.version, ...values}),
            ),
          )
          as Map,
    ),
  );
  Future<List<Map<String,dynamic>>> batch(List<HrPerformanceRecord> records,String action,String reason)async{
    final results=<Map<String,dynamic>>[];
    for(var offset=0;offset<records.length;offset+=200){final batch=records.skip(offset).take(200);final data=_unwrap(await dunesHttpPost(session,'/hr-performance/batch',body:jsonEncode({'items':[for(final r in batch){'id':r.id,'version':r.version}],'action':action,'reason':reason})));results.addAll(HrPerformanceRecord._maps(data));}
    return results;
  }

  Future<Map<String, dynamic>> summary(
    String month,
    List<int> ids, {
    bool confirmScores = false,
  }) => _post('/hr-performance/summary', {
    'month': month,
    'ids': ids,
    'confirmScores': confirmScores,
  });
  Future<Map<String, dynamic>> export(String month, List<int> ids) =>
      _post('/hr-performance/export', {'month': month, 'ids': ids});
  Future<List<Map<String, dynamic>>> alerts() async =>
      HrPerformanceRecord._maps(
        _unwrap(await dunesHttpGet(session, '/hr-performance/alerts')),
      );
  Future<void> closeAlert(int id, String resolution) async {
    await _post('/hr-performance/alerts', {'id': id, 'resolution': resolution});
  }
}
