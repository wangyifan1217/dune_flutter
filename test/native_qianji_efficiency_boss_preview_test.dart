import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/qianji/efficiency/efficiency_models.dart';
import 'package:dunes_app/features/qianji/efficiency/efficiency_service.dart';
import 'package:dunes_app/features/qianji/efficiency/native_qianji_efficiency_boss_preview.dart';
import 'package:dunes_app/features/qianji/efficiency/work_situation_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _session = AuthSession(
  phone: '13800000000',
  userId: 1,
  token: 'test',
  apiBase: 'http://localhost/api/v1',
  roles: <String>[],
  displayName: '林舟',
  departmentName: '产品部',
  jobTitle: '产品经理',
);

WorkSituationPerson _person({
  required int userId,
  required String name,
  required String title,
  required int departmentId,
  required String departmentName,
  int taskOverdue = 0,
  int taskCompleted = 0,
  int taskDoing = 0,
  int proposalRejected = 0,
  int meetings = 0,
  int minutesGenerated = 0,
  int meetingsLinkedTask = 0,
  int noActionMeetings = 0,
  int kbUnused = 0,
  int kbUsed = 0,
  int kbFailed = 0,
  int kbUsable = 0,
  int kbSelfViewOnly = 0,
  int kbUnusedMeetingDocs = 0,
  int kbUncitedConversations = 0,
  int kbReferences = 0,
  int imSessions = 0,
  int imCards = 0,
  int imUrges = 0,
  String note = '',
  List<WorkSituationItem> items = const [],
}) {
  return WorkSituationPerson(
    userId: userId,
    name: name,
    title: title,
    departmentId: departmentId,
    departmentName: departmentName,
    note: note,
    taskOverdue: taskOverdue,
    taskCompleted: taskCompleted,
    taskDoing: taskDoing,
    proposalRejected: proposalRejected,
    meetings: meetings,
    minutesGenerated: minutesGenerated,
    meetingsLinkedTask: meetingsLinkedTask,
    noActionMeetings: noActionMeetings,
    kbUnused: kbUnused,
    kbUsed: kbUsed,
    kbFailed: kbFailed,
    kbUsable: kbUsable,
    kbSelfViewOnly: kbSelfViewOnly,
    kbUnusedMeetingDocs: kbUnusedMeetingDocs,
    kbUncitedConversations: kbUncitedConversations,
    kbReferences: kbReferences,
    imSessions: imSessions,
    imCards: imCards,
    imUrges: imUrges,
    items: items,
  );
}

class _FakeEfficiencyService extends EfficiencyService {
  _FakeEfficiencyService({this.viewAll = true}) : super(session: _session);

  final bool viewAll;

  WorkSituationBoard _boardFor(String month) {
    if (!viewAll) {
      return WorkSituationBoard(
        month: month,
        viewAll: false,
        scopeLabel: '本人及下级',
        departments: const [WorkSituationDept(id: 1, name: '产品部')],
        people: [
          _person(
            userId: 2,
            name: '林舟',
            title: '产品经理',
            departmentId: 1,
            departmentName: '产品部',
            taskCompleted: 1,
            taskDoing: 1,
            items: const [
              WorkSituationItem(kind: 'doing', title: '权限模型说明稿', hint: '进行中'),
            ],
          ),
        ],
      );
    }
    final closed = month != '2026-09';
    return WorkSituationBoard(
      month: month,
      viewAll: true,
      scopeLabel: '全部部门',
      departments: const [
        WorkSituationDept(id: 1, name: '产品部'),
        WorkSituationDept(id: 2, name: '交付部'),
        WorkSituationDept(id: 3, name: '运营部'),
      ],
      people: [
        _person(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          taskOverdue: closed ? 0 : 2,
          taskCompleted: closed ? 2 : 1,
          meetings: 1,
          minutesGenerated: closed ? 1 : 1,
          meetingsLinkedTask: closed ? 1 : 0,
          noActionMeetings: closed ? 0 : 1,
          kbUnused: closed ? 0 : 1,
          kbUsed: closed ? 1 : 0,
          kbReferences: closed ? 1 : 0,
          imSessions: 8,
          imCards: closed ? 2 : 1,
          note: closed ? '本月事项按期推进。' : '有过原定日期还没办完的事',
          items: closed
              ? const [
                  WorkSituationItem(kind: 'done', title: '8月版本评审', hint: '已完成'),
                ]
              : const [
                  WorkSituationItem(
                    kind: 'overdue',
                    title: '需求评审纪要落地',
                    hint: '已超期',
                  ),
                  WorkSituationItem(
                    kind: 'meeting',
                    title: '8/29 产品周会',
                    hint: '纪要还没变成可跟进的事',
                  ),
                ],
        ),
        _person(
          userId: 3,
          name: '周衡',
          title: '交付经理',
          departmentId: 2,
          departmentName: '交付部',
          taskOverdue: closed ? 0 : 3,
          taskCompleted: closed ? 2 : 0,
          meetings: 1,
          meetingsLinkedTask: closed ? 1 : 0,
          minutesGenerated: 1,
          imSessions: 12,
          imCards: 2,
          imUrges: 2,
          items: const [
            WorkSituationItem(kind: 'overdue', title: '华东客户上线清单', hint: '已超期'),
          ],
        ),
        _person(
          userId: 4,
          name: '王敏',
          title: '运营专员',
          departmentId: 3,
          departmentName: '运营部',
          taskCompleted: 1,
          kbUsed: 1,
          kbReferences: 1,
        ),
      ],
    );
  }

  @override
  Future<WorkSituationBoard> fetchWorkSituation({required String month}) async {
    return _boardFor(month);
  }

  @override
  Future<WorkSituationPerson> fetchWorkSituationPerson({
    required String month,
    required int userId,
  }) async {
    return _boardFor(month).people.firstWhere((p) => p.userId == userId);
  }
}

void main() {
  Future<void> pumpPreview(
    WidgetTester tester, {
    bool viewAll = true,
    bool tourSeen = true,
    String initialFilter = 'all',
    DateTime? initialMonth,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (tourSeen) workSituationTourSeenKey(1): true,
    });
    tester.view.physicalSize = const Size(400, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: NativeQianjiEfficiencyBossPreview(
          onBack: () {},
          session: _session,
          service: _FakeEfficiencyService(viewAll: viewAll),
          now: DateTime(2026, 9, 8),
          viewAll: viewAll,
          viewerName: '林舟',
          initialFilter: initialFilter,
          initialMonth: initialMonth,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders efficiency glance and people', (tester) async {
    await pumpPreview(tester);
    expect(find.text('工作情况'), findsWidgets);
    expect(find.text('每个人工作实不实'), findsOneWidget);
    expect(find.text('工作实不实'), findsOneWidget);
    expect(find.textContaining('任务 3人在推进'), findsOneWidget);
    expect(find.text('把事办掉'), findsNothing);

    await tester.tap(find.text('工作实不实'));
    await tester.pumpAndSettle();
    expect(find.text('把事办掉'), findsOneWidget);
    expect(find.text('好好开会'), findsOneWidget);
    expect(find.text('用好知识库'), findsOneWidget);
    expect(find.text('沟通跟得上事'), findsOneWidget);
    expect(find.text('3个部门'), findsNothing);
    expect(find.text('陈可'), findsOneWidget);
    expect(find.text('王敏'), findsOneWidget);
    expect(find.textContaining('开会有闭环'), findsWidgets);

    await tester.tap(find.text('9月'));
    await tester.pumpAndSettle();
    expect(find.textContaining('任务超期未结'), findsWidgets);

    await tester.tap(find.text('7月'));
    await tester.pumpAndSettle();
    expect(find.textContaining('知识用上了'), findsWidgets);
  });

  testWidgets('search person and open efficiency details', (tester) async {
    await pumpPreview(tester);
    await tester.enterText(find.byType(TextField), '陈可');
    await tester.pumpAndSettle();
    expect(find.text('周衡'), findsNothing);
    await tester.ensureVisible(find.text('产品经理').first);
    await tester.tap(find.text('产品经理').first);
    await tester.pumpAndSettle();
    expect(find.text('本月事项按期推进。'), findsWidgets);
    expect(find.text('8月版本评审'), findsWidgets);
  });

  testWidgets('select department then person', (tester) async {
    await pumpPreview(tester);
    await tester.tap(find.text('交付部 1'));
    await tester.pumpAndSettle();
    expect(find.text('周衡'), findsWidgets);
    expect(find.text('陈可'), findsNothing);
    await tester.tap(find.text('周衡').first);
    await tester.pumpAndSettle();
    expect(find.text('华东客户上线清单'), findsWidgets);
  });

  testWidgets('limited scope only shows self and reports', (tester) async {
    await pumpPreview(tester, viewAll: false);
    expect(find.textContaining('本人及下级'), findsWidgets);
    expect(find.text('林舟'), findsOneWidget);
    expect(find.text('陈可'), findsNothing);
    expect(find.text('周衡'), findsNothing);
  });

  testWidgets('help icon explains analysis sources', (tester) async {
    await pumpPreview(tester);
    await tester.tap(find.byIcon(Icons.help_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('这些内容根据什么分析'), findsOneWidget);
    expect(find.text('任务没办完'), findsWidgets);
    expect(find.textContaining('来自任务助手'), findsOneWidget);
    expect(find.textContaining('来自会议纪要'), findsOneWidget);
    expect(find.textContaining('来自知识库'), findsOneWidget);
    expect(find.textContaining('抽本月活跃会话给 AI'), findsOneWidget);
    expect(find.text('再看一遍指引'), findsOneWidget);
  });

  testWidgets('first visit shows spotlight tour', (tester) async {
    await pumpPreview(tester, tourSeen: false);
    expect(find.text('先选月份'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
    await tester.tap(find.text('跳过').first);
    await tester.pumpAndSettle();
    expect(find.text('先选月份'), findsNothing);
  });

  test('task judgment prefers overdue and rejected over AI', () {
    expect(
      workSituationTaskChipLabel(
        _person(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          taskOverdue: 1,
          taskCompleted: 4,
        ),
      ),
      '超期未结',
    );
    expect(
      workSituationTaskIsAdvancing(
        _person(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          taskOverdue: 1,
        ),
      ),
      isFalse,
    );
    expect(
      workSituationTaskChipLabel(
        WorkSituationPerson(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          proposalRejected: 1,
          taskReviewLevel: 'delivering',
        ),
      ),
      '被退回',
    );
    expect(
      workSituationTaskChipLabel(
        WorkSituationPerson(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          taskTotal: 3,
          taskDoing: 3,
          taskReviewLevel: 'stalled',
          taskReviewWhy: '抽看后多数空壳',
        ),
      ),
      '空转',
    );
    expect(
      workSituationTaskChipLabel(
        _person(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          taskCompleted: 2,
        ),
      ),
      '按期',
    );
    expect(
      workSituationTaskIsAdvancing(
        WorkSituationPerson(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          taskDoing: 2,
          taskWaitingOnOthers: 2,
        ),
      ),
      isTrue,
    );
    expect(
      workSituationTaskChipLabel(
        WorkSituationPerson(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          taskDoing: 2,
          taskWaitingOnOthers: 2,
        ),
      ),
      '待下级',
    );
    expect(
      workSituationTaskChipLabel(
        WorkSituationPerson(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          taskDoing: 1,
          taskWithoutDue: 1,
        ),
      ),
      '没约期',
    );
    expect(
      workSituationTaskChipLabel(
        WorkSituationPerson(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          taskDoing: 1,
        ),
      ),
      '在办',
    );
    expect(
      workSituationTaskChipLabel(
        WorkSituationPerson(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          imTalkLevel: 'substantial',
          taskReviewWhy: '这个月任务不多',
        ),
      ),
      '本月少事',
    );
    expect(
      workSituationTaskWhy(
        WorkSituationPerson(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          imTalkLevel: 'substantial',
          taskReviewWhy: '这个月任务不多',
        ),
      ),
      contains('会话在跟'),
    );
  });

  test('meeting judgment does not veto the month for one hollow meeting', () {
    expect(
      workSituationMeetChipLabel(
        WorkSituationPerson(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          meetings: 3,
          minutesGenerated: 3,
          meetingsLinkedTask: 2,
          noActionMeetings: 1,
        ),
      ),
      '部分没落',
    );
    expect(
      workSituationMeetChipLabel(
        WorkSituationPerson(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          meetings: 2,
          minutesGenerated: 2,
          meetingsLinkedTask: 0,
          noActionMeetings: 2,
        ),
      ),
      '没落地',
    );
    expect(
      workSituationMeetChipLabel(
        WorkSituationPerson(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          meetings: 1,
          minutesGenerated: 1,
          meetingsLinkedTask: 1,
          assignedOverdue: 2,
        ),
      ),
      '行动超期',
    );
    expect(
      workSituationMeetChipLabel(
        WorkSituationPerson(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          meetings: 1,
          minutesGenerated: 0,
          transcribeFailed: 1,
        ),
      ),
      '没纪要',
    );
    expect(
      workSituationMeetChipLabel(
        WorkSituationPerson(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          meetings: 1,
          minutesGenerated: 1,
          waitingOnOthersMeet: 1,
        ),
      ),
      '待下级',
    );
    expect(
      workSituationMeetChipLabel(
        WorkSituationPerson(
          userId: 1,
          name: '陈可',
          title: '产品经理',
          departmentId: 1,
          departmentName: '产品部',
          assignedOpen: 2,
          assignedWithoutDue: 2,
        ),
      ),
      '没约期',
    );
  });

  test(
    'knowledge judgment does not veto the month for one unused document',
    () {
      expect(
        workSituationKbChipLabel(
          WorkSituationPerson(
            userId: 1,
            name: '陈可',
            title: '产品经理',
            departmentId: 1,
            departmentName: '产品部',
            kbUsed: 2,
            kbUnused: 1,
          ),
        ),
        '部分没用',
      );
      expect(
        workSituationKbChipLabel(
          WorkSituationPerson(
            userId: 1,
            name: '陈可',
            title: '产品经理',
            departmentId: 1,
            departmentName: '产品部',
            kbUnused: 3,
            kbUsed: 0,
            kbUsable: 3,
          ),
        ),
        '没人用',
      );
      expect(
        workSituationKbChipLabel(
          WorkSituationPerson(
            userId: 1,
            name: '陈可',
            title: '产品经理',
            departmentId: 1,
            departmentName: '产品部',
            kbUsed: 2,
            kbUnused: 0,
          ),
        ),
        '用上了',
      );
      expect(
        workSituationKbChipLabel(
          WorkSituationPerson(
            userId: 1,
            name: '陈可',
            title: '产品经理',
            departmentId: 1,
            departmentName: '产品部',
            kbFailed: 2,
            kbUsable: 0,
            kbUsed: 0,
          ),
        ),
        '入库失败',
      );
      expect(
        workSituationKbChipLabel(
          WorkSituationPerson(
            userId: 1,
            name: '陈可',
            title: '产品经理',
            departmentId: 1,
            departmentName: '产品部',
            kbUncitedConversations: 2,
          ),
        ),
        '问了没引用',
      );
      expect(
        workSituationKbWhy(
          WorkSituationPerson(
            userId: 1,
            name: '陈可',
            title: '产品经理',
            departmentId: 1,
            departmentName: '产品部',
            kbUnused: 2,
            kbUsed: 0,
            taskDoing: 1,
            taskOnTime: 1,
          ),
        ),
        contains('事在办，知识没人用'),
      );
    },
  );

  test('tour seen flag is per user', () async {
    SharedPreferences.setMockInitialValues({});
    const a = WorkSituationTourPrefs(1);
    const b = WorkSituationTourPrefs(2);
    expect(await a.hasSeen(), isFalse);
    await a.markSeen();
    expect(await a.hasSeen(), isTrue);
    expect(await b.hasSeen(), isFalse);
  });
}
