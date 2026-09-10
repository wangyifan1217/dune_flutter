import 'package:dunes_app/core/platform/desktop_features.dart';
import 'package:dunes_app/features/qianji/efficiency/efficiency_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses efficiency snapshot contract', () {
    final snapshot = EfficiencySnapshot.fromJson({
      'scope': 'department',
      'month': '2026-09',
      'title': '部门效能分析',
      'peopleCount': 8,
      'hasDepartmentView': true,
      'privacyProtected': false,
      'metricVersion': 'v1',
      'generatedAt': '2026-09-08T01:00:00Z',
      'metrics': [
        {
          'key': 'taskCompletionRate',
          'label': '任务完成率',
          'value': 82.5,
          'unit': '%',
          'deltaPct': 5.2,
        },
      ],
      'stages': [
        {
          'key': 'task',
          'label': '任务',
          'total': 20,
          'completed': 16,
          'rate': 80,
        },
      ],
      'bottlenecks': [
        {
          'kind': 'approval',
          'label': '审批中事项',
          'count': 3,
          'severity': 'medium',
          'ref': 'approvals:pending',
        },
      ],
      'sources': [
        {'key': 'task', 'label': '任务', 'available': true},
      ],
    });

    expect(snapshot.scope, 'department');
    expect(snapshot.peopleCount, 8);
    expect(snapshot.metrics.single.value, 82.5);
    expect(snapshot.stages.single.completed, 16);
    expect(snapshot.bottlenecks.single.ref, 'approvals:pending');
    expect(snapshot.quality, isEmpty);
    expect(snapshot.funnel, isEmpty);
    expect(snapshot.latestAnalysis, isNull);
  });

  test('parses scheduled analysis and trends', () {
    final snapshot = EfficiencySnapshot.fromJson({
      'scope': 'department',
      'month': '2026-09',
      'title': '部门效能分析',
      'peopleCount': 8,
      'hasDepartmentView': true,
      'privacyProtected': false,
      'metricVersion': 'v2',
      'generatedAt': '2026-09-08T02:00:00Z',
      'metrics': [],
      'stages': [],
      'funnel': [
        {'key': 'task', 'label': '任务', 'total': 10, 'completed': 8, 'rate': 80},
      ],
      'trends': [
        {
          'month': '2026-09',
          'taskCompletionRate': 80,
          'onTimeRate': 70,
          'proposalDoneRate': 60,
          'approvalCycleHours': 12,
        },
      ],
      'latestAnalysis': {
        'id': 9,
        'status': 'done',
        'scope': 'department',
        'month': '2026-09',
        'triggerKind': 'scheduled',
        'result': {'summary': '昨夜已生成', 'wins': [], 'risks': [], 'actions': []},
      },
      'schedule': {
        'enabled': true,
        'hour': 2,
        'minute': 0,
        'timezone': 'Asia/Shanghai',
      },
      'chains': [
        {
          'meetingTitle': '周会',
          'brokenAt': 'task',
          'taskCount': 0,
          'hasMinutes': true,
        },
      ],
      'quality': [
        {
          'kind': 'kb',
          'label': '上传后从未被打开或引用',
          'count': 2,
          'severity': 'high',
          'ref': 'kb:unused',
        },
      ],
      'bottlenecks': [],
      'sources': [],
    });
    expect(snapshot.funnel.single.key, 'task');
    expect(snapshot.quality.single.ref, 'kb:unused');
    expect(snapshot.chains.single.brokenLabel, '断在任务落地');
    expect(snapshot.trends.single.taskCompletionRate, 80);
    expect(snapshot.latestAnalysis?.isScheduled, isTrue);
    expect(snapshot.latestAnalysis?.result?.summary, '昨夜已生成');
    expect(snapshot.schedule?.hour, 2);
  });

  test('parses work situation task review fields', () {
    final person = WorkSituationPerson.fromJson({
      'userId': 8,
      'name': '陈可',
      'taskOverdue': 1,
      'taskSubOverdue': 1,
      'taskWaitingOnOthers': 2,
      'taskStaleOpen': 1,
      'taskOverdueHighWeight': 1,
      'taskReviewLevel': 'stalled',
      'taskReviewWhy': '重点单两周没进度',
      'items': [
        {
          'kind': 'overdue',
          'title': '渠道方案 / 拆报价',
          'hint': '子任务 · 已过期',
          'taskId': 91,
          'isSubtask': true,
        },
      ],
    });
    expect(person.taskSubOverdue, 1);
    expect(person.taskWaitingOnOthers, 2);
    expect(person.taskStaleOpen, 1);
    expect(person.taskOverdueHighWeight, 1);
    expect(person.taskReviewLevel, 'stalled');
    expect(person.items.single.taskId, 91);
    expect(person.items.single.isSubtask, isTrue);
  });

  test('parses work situation board', () {
    final board = WorkSituationBoard.fromJson({
      'month': '2026-09',
      'viewAll': true,
      'scopeLabel': '全部部门',
      'departments': [
        {'id': 1, 'name': '产品部'},
      ],
      'people': [
        {
          'userId': 8,
          'name': '陈可',
          'title': '产品经理',
          'departmentId': 1,
          'departmentName': '产品部',
          'taskOverdue': 2,
          'meetings': 1,
          'imSessions': 6,
          'items': [
            {'kind': 'overdue', 'title': '需求评审纪要落地', 'hint': '已超期'},
          ],
        },
      ],
    });
    expect(board.viewAll, isTrue);
    expect(board.people.single.taskOverdue, 2);
    expect(board.people.single.items.single.title, '需求评审纪要落地');
  });

  test('QJEA is allowed on desktop', () {
    expect(isDesktopAllowedCommScreen('QJEA'), isTrue);
  });
}
