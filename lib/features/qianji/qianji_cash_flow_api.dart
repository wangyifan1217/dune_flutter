import 'dart:convert';

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';

class QianjiCashFlowBoard {
  const QianjiCashFlowBoard({
    required this.from,
    required this.to,
    required this.kpi,
    required this.trend,
    required this.entities,
    required this.inflows,
    required this.outflows,
    required this.counterparties,
    required this.txns,
    required this.txnTotal,
    required this.txnPage,
    required this.txnPageSize,
  });

  final String from;
  final String to;
  final QianjiCashFlowKpi kpi;
  final List<QianjiCashFlowTrend> trend;
  final List<QianjiCashFlowEntity> entities;
  final List<QianjiCashFlowSlice> inflows;
  final List<QianjiCashFlowSlice> outflows;
  final List<QianjiCashFlowCounterparty> counterparties;
  final List<QianjiCashFlowTxn> txns;
  final int txnTotal;
  final int txnPage;
  final int txnPageSize;

  factory QianjiCashFlowBoard.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) map) {
      final raw = json[key];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => map(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    }

    return QianjiCashFlowBoard(
      from: '${json['from'] ?? ''}',
      to: '${json['to'] ?? ''}',
      kpi: QianjiCashFlowKpi.fromJson(
        json['kpi'] is Map
            ? Map<String, dynamic>.from(json['kpi'] as Map)
            : const {},
      ),
      trend: list('trend', QianjiCashFlowTrend.fromJson),
      entities: list('entities', QianjiCashFlowEntity.fromJson),
      inflows: list('inflows', QianjiCashFlowSlice.fromJson),
      outflows: list('outflows', QianjiCashFlowSlice.fromJson),
      counterparties: list('counterparties', QianjiCashFlowCounterparty.fromJson),
      txns: list('txns', QianjiCashFlowTxn.fromJson),
      txnTotal: (_num(json['txnTotal'])).round(),
      txnPage: (_num(json['txnPage'])).round(),
      txnPageSize: (_num(json['txnPageSize'])).round(),
    );
  }
}

class QianjiCashFlowTxnPage {
  const QianjiCashFlowTxnPage({
    required this.total,
    required this.page,
    required this.pageSize,
    required this.items,
  });

  final int total;
  final int page;
  final int pageSize;
  final List<QianjiCashFlowTxn> items;

  factory QianjiCashFlowTxnPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => QianjiCashFlowTxn.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false)
        : const <QianjiCashFlowTxn>[];
    return QianjiCashFlowTxnPage(
      total: (_num(json['total'])).round(),
      page: (_num(json['page'])).round(),
      pageSize: (_num(json['pageSize'])).round(),
      items: items,
    );
  }
}

class QianjiCashFlowKpi {
  const QianjiCashFlowKpi({
    required this.cashYuan,
    required this.netYuan,
    required this.operatingYuan,
    required this.alertCount,
    required this.alertHint,
    this.alerts = const [],
    this.health = const QianjiCashFlowHealth(
      total: 0,
      healthy: 0,
      low: 0,
      reserve: 0,
    ),
  });

  final double cashYuan;
  final double netYuan;
  final double operatingYuan;
  final int alertCount;
  final String alertHint;
  final List<QianjiCashFlowAlertAccount> alerts;
  final QianjiCashFlowHealth health;

  factory QianjiCashFlowKpi.fromJson(Map<String, dynamic> json) {
    final raw = json['alerts'];
    final alerts = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => QianjiCashFlowAlertAccount.fromJson(
                  Map<String, dynamic>.from(e),
                ))
            .toList(growable: false)
        : const <QianjiCashFlowAlertAccount>[];
    return QianjiCashFlowKpi(
      cashYuan: _num(json['cashYuan']),
      netYuan: _num(json['netYuan']),
      operatingYuan: _num(json['operatingYuan']),
      alertCount: (_num(json['alertCount'])).round(),
      alertHint: '${json['alertHint'] ?? ''}',
      alerts: alerts,
      health: QianjiCashFlowHealth.fromJson(
        json['health'] is Map
            ? Map<String, dynamic>.from(json['health'] as Map)
            : const {},
      ),
    );
  }
}

class QianjiCashFlowHealth {
  const QianjiCashFlowHealth({
    required this.total,
    required this.healthy,
    required this.low,
    required this.reserve,
  });

  final int total;
  final int healthy;
  final int low;
  final int reserve;

  factory QianjiCashFlowHealth.fromJson(Map<String, dynamic> json) {
    return QianjiCashFlowHealth(
      total: (_num(json['total'])).round(),
      healthy: (_num(json['healthy'])).round(),
      low: (_num(json['low'])).round(),
      reserve: (_num(json['reserve'])).round(),
    );
  }
}

class QianjiCashFlowAlertAccount {
  const QianjiCashFlowAlertAccount({
    required this.company,
    required this.accountNo,
    required this.balanceYuan,
    required this.reasons,
  });

  final String company;
  final String accountNo;
  final double balanceYuan;
  final List<String> reasons;

  factory QianjiCashFlowAlertAccount.fromJson(Map<String, dynamic> json) {
    final raw = json['reasons'];
    final reasons = raw is List
        ? raw.map((e) => '$e').where((e) => e.trim().isNotEmpty).toList()
        : const <String>[];
    return QianjiCashFlowAlertAccount(
      company: '${json['company'] ?? ''}',
      accountNo: '${json['accountNo'] ?? ''}',
      balanceYuan: _num(json['balanceYuan']),
      reasons: reasons,
    );
  }
}

class QianjiCashFlowTrend {
  const QianjiCashFlowTrend({
    required this.date,
    required this.cashYuan,
    required this.inflowYuan,
    required this.outflowYuan,
  });

  final DateTime date;
  final double cashYuan;
  final double inflowYuan;
  final double outflowYuan;

  factory QianjiCashFlowTrend.fromJson(Map<String, dynamic> json) {
    return QianjiCashFlowTrend(
      date: DateTime.tryParse('${json['date'] ?? ''}') ?? DateTime.now(),
      cashYuan: _num(json['cashYuan']),
      inflowYuan: _num(json['inflowYuan']),
      outflowYuan: _num(json['outflowYuan']),
    );
  }
}

class QianjiCashFlowEntity {
  const QianjiCashFlowEntity({
    required this.id,
    required this.name,
    required this.cashYuan,
    required this.netYuan,
  });

  final String id;
  final String name;
  final double cashYuan;
  final double netYuan;

  factory QianjiCashFlowEntity.fromJson(Map<String, dynamic> json) {
    return QianjiCashFlowEntity(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      cashYuan: _num(json['cashYuan']),
      netYuan: _num(json['netYuan']),
    );
  }
}

class QianjiCashFlowSlice {
  const QianjiCashFlowSlice({
    required this.id,
    required this.name,
    required this.entityId,
    required this.amountYuan,
  });

  final String id;
  final String name;
  final String entityId;
  final double amountYuan;

  factory QianjiCashFlowSlice.fromJson(Map<String, dynamic> json) {
    return QianjiCashFlowSlice(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      entityId: '${json['entityId'] ?? ''}',
      amountYuan: _num(json['amountYuan']),
    );
  }
}

class QianjiCashFlowCounterparty {
  const QianjiCashFlowCounterparty({
    required this.name,
    required this.amountYuan,
    required this.entityId,
    required this.flowId,
  });

  final String name;
  final double amountYuan;
  final String entityId;
  final String flowId;

  factory QianjiCashFlowCounterparty.fromJson(Map<String, dynamic> json) {
    return QianjiCashFlowCounterparty(
      name: '${json['name'] ?? ''}',
      amountYuan: _num(json['amountYuan']),
      entityId: '${json['entityId'] ?? ''}',
      flowId: '${json['flowId'] ?? ''}',
    );
  }
}

class QianjiCashFlowTxn {
  const QianjiCashFlowTxn({
    required this.date,
    required this.account,
    required this.counterparty,
    required this.memo,
    required this.amountYuan,
    required this.entityId,
    required this.flowId,
  });

  final String date;
  final String account;
  final String counterparty;
  final String memo;
  final double amountYuan;
  final String entityId;
  final String flowId;

  factory QianjiCashFlowTxn.fromJson(Map<String, dynamic> json) {
    return QianjiCashFlowTxn(
      date: '${json['date'] ?? ''}',
      account: '${json['account'] ?? ''}',
      counterparty: '${json['counterparty'] ?? ''}',
      memo: '${json['memo'] ?? ''}',
      amountYuan: _num(json['amountYuan']),
      entityId: '${json['entityId'] ?? ''}',
      flowId: '${json['flowId'] ?? ''}',
    );
  }
}

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

class QianjiCashFlowTrack {
  const QianjiCashFlowTrack({
    required this.company,
    required this.accountNo,
    required this.points,
  });

  final String company;
  final String accountNo;
  final List<QianjiCashFlowTrend> points;

  factory QianjiCashFlowTrack.fromJson(Map<String, dynamic> json) {
    final raw = json['points'];
    final points = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => QianjiCashFlowTrend.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false)
        : const <QianjiCashFlowTrend>[];
    return QianjiCashFlowTrack(
      company: '${json['company'] ?? ''}',
      accountNo: '${json['accountNo'] ?? ''}',
      points: points,
    );
  }
}

class QianjiCashFlowChatMessage {
  const QianjiCashFlowChatMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class QianjiCashFlowAnalyzeJob {
  const QianjiCashFlowAnalyzeJob({
    required this.id,
    required this.status,
    this.answer = '',
    this.error = '',
    this.model = '',
  });

  final String id;
  final String status;
  final String answer;
  final String error;
  final String model;

  bool get isRunning => status == 'running';
  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';

  factory QianjiCashFlowAnalyzeJob.fromJson(Map<String, dynamic> json) {
    return QianjiCashFlowAnalyzeJob(
      id: '${json['id'] ?? ''}',
      status: '${json['status'] ?? ''}',
      answer: '${json['answer'] ?? ''}'.trim(),
      error: '${json['error'] ?? ''}'.trim(),
      model: '${json['model'] ?? ''}'.trim(),
    );
  }
}

class QianjiCashFlowApi {
  QianjiCashFlowApi(this.session);

  final AuthSession session;

  Future<QianjiCashFlowBoard> board({
    required DateTime from,
    required DateTime to,
    String? company,
    String? flow,
    String? q,
    String? sort,
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _get(
      '/qianji/cash-flow/board',
      from: from,
      to: to,
      company: company,
      flow: flow,
      q: q,
      sort: sort,
      page: page,
      pageSize: pageSize,
    );
    return QianjiCashFlowBoard.fromJson(data);
  }

  Future<QianjiCashFlowTxnPage> txns({
    required DateTime from,
    required DateTime to,
    String? company,
    String? flow,
    String? q,
    String? sort,
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _get(
      '/qianji/cash-flow/txns',
      from: from,
      to: to,
      company: company,
      flow: flow,
      q: q,
      sort: sort,
      page: page,
      pageSize: pageSize,
    );
    return QianjiCashFlowTxnPage.fromJson(data);
  }

  Future<QianjiCashFlowAnalyzeJob> startAnalyze({
    required DateTime from,
    required DateTime to,
    String? company,
    required List<QianjiCashFlowChatMessage> messages,
  }) async {
    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final payload = <String, dynamic>{
      'from': ymd(from),
      'to': ymd(to),
      'messages': messages.map((m) => m.toJson()).toList(),
    };
    if (company != null && company.trim().isNotEmpty) {
      payload['company'] = company.trim();
    }
    final resp = await dunesHttpPost(
      session,
      '/qianji/cash-flow/analyze',
      body: jsonEncode(payload),
    );
    return QianjiCashFlowAnalyzeJob.fromJson(_unwrap(resp));
  }

  Future<QianjiCashFlowAnalyzeJob> getAnalyze(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      throw Exception('analysis not found');
    }
    final resp = await dunesHttpGet(session, '/qianji/cash-flow/analyze/$trimmed');
    return QianjiCashFlowAnalyzeJob.fromJson(_unwrap(resp));
  }

  Map<String, dynamic> _unwrap(dynamic resp) {
    final body = resp.body.isEmpty ? <String, dynamic>{} : jsonDecode(resp.body);
    if (resp.statusCode >= 400) {
      final msg = body is Map
          ? (body['message'] ?? body['error'] ?? resp.body)
          : resp.body;
      throw Exception('$msg');
    }
    final data = body is Map && body.containsKey('data') ? body['data'] : body;
    return Map<String, dynamic>.from(data as Map);
  }

  Future<QianjiCashFlowTrack> track({
    required DateTime from,
    required DateTime to,
    required String account,
    String? company,
  }) async {
    final data = await _get(
      '/qianji/cash-flow/track',
      from: from,
      to: to,
      company: company,
      account: account,
      page: 1,
      pageSize: 1,
    );
    return QianjiCashFlowTrack.fromJson(data);
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    required DateTime from,
    required DateTime to,
    String? company,
    String? flow,
    String? q,
    String? sort,
    String? account,
    required int page,
    required int pageSize,
  }) async {
    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final query = <String, String>{
      'from': ymd(from),
      'to': ymd(to),
      'page': '$page',
      'pageSize': '$pageSize',
    };
    if (company != null && company.trim().isNotEmpty) {
      query['company'] = company.trim();
    }
    if (flow != null && flow.trim().isNotEmpty) {
      query['flow'] = flow.trim();
    }
    if (q != null && q.trim().isNotEmpty) {
      query['q'] = q.trim();
    }
    if (sort != null && sort.trim().isNotEmpty) {
      query['sort'] = sort.trim();
    }
    if (account != null && account.trim().isNotEmpty) {
      query['account'] = account.trim();
    }
    final qs = query.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final resp = await dunesHttpGet(session, '$path?$qs');
    final body = resp.body.isEmpty ? <String, dynamic>{} : jsonDecode(resp.body);
    if (resp.statusCode >= 400) {
      final msg = body is Map ? (body['message'] ?? body['error'] ?? resp.body) : resp.body;
      throw Exception('$msg');
    }
    final data = body is Map && body.containsKey('data') ? body['data'] : body;
    return Map<String, dynamic>.from(data as Map);
  }
}
