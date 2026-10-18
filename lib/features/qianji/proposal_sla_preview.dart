import '../auth/auth_session.dart';
import 'proposal_sla_lookup_service.dart';

/// 静态样例已停用。入口和页内数据都走组织用户的「提案时效查阅」权限与正式接口。
const kProposalSlaStaticPreview = false;

class ProposalSlaPreviewApi extends ProposalSlaLookupApi {
  ProposalSlaPreviewApi({required super.session});

  ProposalSlaConfig _config = const ProposalSlaConfig(
    enabled: true,
    totalHours: 72,
    nodeHours: 12,
    workStartMinute: 540,
    workEndMinute: 1260,
    warnHours: 2,
    remindIntervalHours: 12,
    appealWorkdays: 2,
    updatedAt: '2026-10-16 09:00',
  );

  final List<ProposalSlaInstance> _instances = [
    const ProposalSlaInstance(
      id: 260,
      code: 'TA-20261013-000260',
      title: '会员套餐订购-湖北电信',
      sector: '运营商',
      status: 'normal',
      round: 1,
      exempt: false,
      elapsedHours: 1.3,
      totalHours: 72,
      current: '按驳回意见重新提交·黄永刚',
      overdueNodes: 0,
      startedAt: '2026-10-16T08:47:00',
    ),
    const ProposalSlaInstance(
      id: 188,
      code: 'TA-20261012-000188',
      title: '渠道年框续签-华东',
      sector: '渠道',
      status: 'warning',
      round: 2,
      exempt: false,
      elapsedHours: 46.5,
      totalHours: 72,
      current: '财务整板块复核·陈丽',
      overdueNodes: 0,
      startedAt: '2026-10-14T11:20:00',
    ),
    const ProposalSlaInstance(
      id: 248,
      code: 'TA-20261008-000248',
      title: '渠道结算规则调整',
      sector: '销售',
      status: 'overdue',
      round: 2,
      exempt: false,
      elapsedHours: 86,
      totalHours: 72,
      current: '部门负责人审核·李娜',
      overdueNodes: 1,
      startedAt: '2026-10-12T10:20:00',
    ),
    const ProposalSlaInstance(
      id: 231,
      code: 'TA-20260928-000231',
      title: '套餐资费公示修订',
      sector: '产品',
      status: 'finished',
      round: 1,
      exempt: false,
      elapsedHours: 40,
      totalHours: 72,
      current: '—',
      overdueNodes: 0,
      startedAt: '2026-09-28T09:10:00',
    ),
    const ProposalSlaInstance(
      id: 77,
      code: 'TA-20260928-000077',
      title: '系统停机窗口申请',
      sector: '科技',
      status: 'exempt',
      round: 1,
      exempt: true,
      elapsedHours: 20,
      totalHours: 72,
      current: '—',
      overdueNodes: 1,
      startedAt: '2026-09-28T10:00:00',
    ),
  ];

  final Map<int, List<ProposalSlaNode>> _nodes = {
    260: const [
      ProposalSlaNode(
        id: 1,
        round: 1,
        label: '按驳回意见重新提交',
        assigneeName: '黄永刚',
        endedAt: '',
        state: 'running',
        exempt: false,
      ),
      ProposalSlaNode(
        id: 2,
        round: 1,
        label: '初审',
        assigneeName: '王敏',
        endedAt: '2026-10-16T08:40:00',
        state: 'done',
        exempt: false,
      ),
    ],
    188: const [
      ProposalSlaNode(
        id: 4,
        round: 2,
        label: '财务整板块复核',
        assigneeName: '陈丽',
        endedAt: '',
        state: 'warning',
        exempt: false,
      ),
    ],
    248: const [
      ProposalSlaNode(
        id: 3,
        round: 2,
        label: '部门负责人审核',
        assigneeName: '李娜',
        endedAt: '',
        state: 'overdue',
        exempt: false,
      ),
    ],
  };

  final List<ProposalSlaScore> _scores = [
    const ProposalSlaScore(
      id: 11,
      code: 'TA-20261008-000248',
      title: '渠道结算规则调整',
      kind: 'node',
      nodeLabel: '部门负责人审核',
      userName: '李娜',
      sourceUserName: '',
      suggestedPoints: 5,
      finalPoints: null,
      overdueMinutes: 840,
      status: 'pending',
      appealStatus: 'pending',
      appealReason: '上游材料晚到，节点无法按期完成',
      reviewerName: '',
      reviewComment: '',
    ),
    const ProposalSlaScore(
      id: 12,
      code: 'TA-20261008-000248',
      title: '渠道结算规则调整',
      kind: 'leader',
      nodeLabel: '部门负责人审核',
      userName: '林嘉宁',
      sourceUserName: '李娜',
      suggestedPoints: 3,
      finalPoints: null,
      overdueMinutes: 840,
      status: 'pending',
      appealStatus: '',
      appealReason: '',
      reviewerName: '',
      reviewComment: '',
    ),
    const ProposalSlaScore(
      id: 13,
      code: 'TA-20261012-000188',
      title: '渠道年框续签-华东',
      kind: 'total',
      nodeLabel: '',
      userName: '陈丽',
      sourceUserName: '',
      suggestedPoints: 2,
      finalPoints: 2,
      overdueMinutes: 0,
      status: 'confirmed',
      appealStatus: '',
      appealReason: '',
      reviewerName: '黄永刚',
      reviewComment: '确认计入',
    ),
  ];

  @override
  Future<ProposalSlaConfig> fetchConfig() async => _config;

  @override
  Future<ProposalSlaConfig> saveConfig(ProposalSlaConfig config) async {
    _config = ProposalSlaConfig(
      enabled: config.enabled,
      totalHours: config.totalHours,
      nodeHours: config.nodeHours,
      workStartMinute: config.workStartMinute,
      workEndMinute: config.workEndMinute,
      warnHours: config.warnHours,
      remindIntervalHours: config.remindIntervalHours,
      appealWorkdays: config.appealWorkdays,
      kinds: config.kinds,
      updatedAt: '2026-10-16 11:40',
    );
    return _config;
  }

  @override
  Future<ProposalSlaDashboard> fetchDashboard({String? from, String? to}) async {
    final open = _instances.where((e) => e.status != 'finished' && !e.exempt).toList();
    return ProposalSlaDashboard(
      from: from ?? '2026-10-01',
      to: to ?? '2026-10-16',
      proposals: _instances.length,
      open: open.length,
      finished: _instances.where((e) => e.status == 'finished').length,
      openOverdue: open.where((e) => e.status == 'overdue').length,
      avgTotalHours: 42.4,
      rejectRounds: 2,
      pendingScores: _scores.where((e) => e.status == 'pending').length,
      pendingAppeals: _scores.where((e) => e.appealStatus == 'pending').length,
      byStage: const [
        ProposalSlaStat(
          key: 'review',
          name: '部门负责人审核',
          nodes: 6,
          avgMinutes: 520,
          overdueRate: 16.7,
          proposalCount: 4,
          rejectRounds: 1,
        ),
        ProposalSlaStat(
          key: 'finance',
          name: '财务整板块复核',
          nodes: 5,
          avgMinutes: 340,
          overdueRate: 0,
          proposalCount: 4,
          rejectRounds: 1,
        ),
        ProposalSlaStat(
          key: 'final',
          name: '最终确认',
          nodes: 3,
          avgMinutes: 460,
          overdueRate: 33.3,
          proposalCount: 3,
          rejectRounds: 0,
        ),
      ],
      byPerson: const [
        ProposalSlaStat(
          key: 'lina',
          name: '李娜',
          nodes: 3,
          avgMinutes: 610,
          overdueRate: 33.3,
          proposalCount: 2,
          rejectRounds: 1,
        ),
        ProposalSlaStat(
          key: 'chenli',
          name: '陈丽',
          nodes: 4,
          avgMinutes: 310,
          overdueRate: 0,
          proposalCount: 3,
          rejectRounds: 1,
        ),
        ProposalSlaStat(
          key: 'huang',
          name: '黄永刚',
          nodes: 4,
          avgMinutes: 190,
          overdueRate: 0,
          proposalCount: 3,
          rejectRounds: 0,
        ),
      ],
      overdueOpen: open.where((e) => e.status == 'overdue').toList(),
    );
  }

  @override
  Future<List<ProposalSlaScore>> fetchScores({required String status, String q = ''}) async {
    return _scores.where((row) {
      if (status == 'appeal') return row.appealStatus == 'pending';
      if (status.isNotEmpty && row.status != status) return false;
      return _hit(q, [row.code, row.title, row.userName]);
    }).toList();
  }

  @override
  Future<void> reviewScore({
    required int id,
    required String action,
    int? points,
    required String comment,
  }) async {
    final i = _scores.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final row = _scores[i];
    final appealApproved = row.appealStatus == 'pending' && (action == 'reject' || action == 'exempt');
    final next = switch (action) {
      'adjust' => 'adjusted',
      'reject' => 'rejected',
      'exempt' => 'exempt',
      _ => 'confirmed',
    };
    _scores[i] = ProposalSlaScore(
      id: row.id,
      code: row.code,
      title: row.title,
      kind: row.kind,
      nodeLabel: row.nodeLabel,
      userName: row.userName,
      sourceUserName: row.sourceUserName,
      suggestedPoints: row.suggestedPoints,
      finalPoints: action == 'adjust' ? points : row.suggestedPoints,
      overdueMinutes: row.overdueMinutes,
      status: next,
      appealStatus: row.appealStatus == 'pending' ? (appealApproved ? 'approved' : 'rejected') : row.appealStatus,
      appealReason: row.appealReason,
      reviewerName: '当前用户',
      reviewComment: comment,
    );
  }

  @override
  Future<List<ProposalSlaInstance>> fetchInstances({required String status, String q = ''}) async {
    return _instances.where((row) {
      final ok = switch (status) {
        'open' => row.status != 'finished' && !row.exempt,
        'overdue' => row.status == 'overdue' && !row.exempt,
        'warning' => row.status == 'warning',
        'finished' => row.status == 'finished',
        'exempt' => row.exempt || row.status == 'exempt',
        _ => true,
      };
      return ok && _hit(q, [row.code, row.title, row.sector, row.current]);
    }).toList();
  }

  @override
  Future<List<ProposalSlaNode>> fetchNodes(int instanceId) async {
    return List<ProposalSlaNode>.from(_nodes[instanceId] ?? const []);
  }

  @override
  Future<void> createExemption({
    required int instanceId,
    required int nodeId,
    required String reasonType,
    required String reason,
  }) async {
    final i = _instances.indexWhere((e) => e.id == instanceId);
    if (i < 0) return;
    final row = _instances[i];
    _instances[i] = ProposalSlaInstance(
      id: row.id,
      code: row.code,
      title: row.title,
      sector: row.sector,
      status: 'exempt',
      round: row.round,
      exempt: true,
      elapsedHours: row.elapsedHours,
      totalHours: row.totalHours,
      current: row.current,
      overdueNodes: row.overdueNodes,
      startedAt: row.startedAt,
    );
    if (nodeId > 0) {
      final nodes = _nodes[instanceId];
      if (nodes == null) return;
      final n = nodes.indexWhere((e) => e.id == nodeId);
      if (n < 0) return;
      final node = nodes[n];
      nodes[n] = ProposalSlaNode(
        id: node.id,
        round: node.round,
        label: node.label,
        assigneeName: node.assigneeName,
        endedAt: node.endedAt,
        state: 'exempt',
        exempt: true,
      );
    }
  }

  bool _hit(String q, List<String> fields) {
    final key = q.trim();
    if (key.isEmpty) return true;
    return fields.any((e) => e.contains(key));
  }
}
