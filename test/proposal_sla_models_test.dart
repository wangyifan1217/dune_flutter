import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> node({
    int id = 1,
    String state = 'normal',
    int remaining = 600,
    int overdue = 0,
    String? endedAt,
  }) => {
    'id': id,
    'round': 1,
    'stageKey': 'tech',
    'stageLabel': '研发审核',
    'nodeKey': 'tech_review',
    'label': '科技内容复核',
    'role': '科技负责人',
    'assigneeId': 7,
    'assigneeName': '张三',
    'startedAt': '2026-10-15T01:30:00Z',
    'endedAt': endedAt,
    'effectiveMinutes': 720 - remaining + overdue,
    'limitMinutes': 720,
    'remainingMinutes': remaining,
    'overdueMinutes': overdue,
    'state': state,
    'stateLabel': state,
    'remindCount': 0,
    'exempt': false,
  };

  test('row without sla parses to null and keeps old behavior', () {
    expect(ProposalSlaSummary.tryParse(null), isNull);
    expect(ProposalSlaSummary.tryParse({'instanceId': 0}), isNull);
    expect(ProposalSlaDetail.tryParse({'enabled': false}), isNull);
  });

  test('summary picks the tightest node and formats clocks', () {
    final sla = ProposalSlaSummary.tryParse({
      'instanceId': 3,
      'status': 'overdue',
      'statusLabel': '已超时',
      'startedAt': '2026-10-14T01:00:00Z',
      'round': 2,
      'totalLimitMinutes': 4320,
      'totalElapsedMinutes': 2160,
      'totalRemainingMinutes': 2160,
      'current': [
        node(id: 1, remaining: 100),
        node(id: 2, state: 'overdue', remaining: 0, overdue: 95),
      ],
    })!;
    expect(sla.tightest!.id, 2);
    expect(sla.tightest!.clockText, '已超时 1 小时 35 分');
    expect(sla.totalProgress, 0.5);
    expect(sla.totalText, '总时钟剩余 36 小时');
    expect(sla.current.first.clockText, '剩余 1 小时 40 分');
  });

  test('back to filling suspends the total clock', () {
    final sla = ProposalSlaSummary.tryParse({
      'instanceId': 3,
      'status': 'normal',
      'round': 1,
      'totalLimitMinutes': 4320,
      'totalElapsedMinutes': 240,
      'totalRemainingMinutes': 4080,
      'suspended': true,
      'current': [],
    })!;
    expect(sla.suspended, isTrue);
    expect(sla.tightest, isNull);
    expect(sla.totalText, '填写中暂停计时 · 总时钟剩余 68 小时');
  });

  test('closed node shows used time and overdue', () {
    final n = ProposalSlaNode.fromJson(
      node(state: 'overdue', remaining: 0, overdue: 30, endedAt: '2026-10-15T08:00:00Z'),
    );
    expect(n.open, isFalse);
    expect(n.clockText, '用时 12 小时 30 分 · 超时 30 分钟');
  });

  test('detail builds timeline and score labels', () {
    final detail = ProposalSlaDetail.tryParse({
      'enabled': true,
      'detail': {
        'summary': {'instanceId': 3, 'status': 'normal', 'round': 1},
        'nodes': [node()],
        'events': [
          {'id': 1, 'type': 'start', 'round': 1},
          {'id': 2, 'type': 'remind', 'actorName': '李四', 'detail': {'kind': 'manual'}},
          {'id': 3, 'type': 'unknown'},
        ],
        'myScores': [
          {'id': 9, 'kind': 'leader', 'suggestedPoints': 3, 'status': 'pending', 'appealOpen': true},
        ],
      },
    })!;
    expect(detail.timeline.map((e) => e.title), ['进入时效管理', '催办']);
    expect(detail.timeline[1].body, '李四 发起提醒');
    final score = detail.myScores.single;
    expect(score.kindLabel, '部门负责人连带');
    expect(score.pointsText, '建议 3 分');
    expect(score.statusLabel, '待行政人事复核');
  });
}
