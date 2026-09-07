import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/kb/native_kb_models.dart';
import 'package:dunes_app/features/meeting/native_meeting_models.dart';
import 'package:dunes_app/features/profile/native_work_profile_detail_pages.dart';
import 'package:dunes_app/features/profile/work_profile_kpi.dart';
import 'package:dunes_app/features/tasks/task_models.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const session = AuthSession(
    phone: '13800000000',
    userId: 1,
    token: '',
    apiBase: '',
    roles: <String>[],
  );

  testWidgets('rhythm page filters and opens task', (tester) async {
    int? openedTask;
    final tasks = [
      const TaskItem(
        id: 1,
        title: '整理项目材料',
        ownerUserId: 1,
        creatorUserId: 1,
        progressPct: 40,
      ),
      const TaskItem(
        id: 2,
        title: '完成复盘',
        ownerUserId: 1,
        creatorUserId: 1,
        status: 'completed',
        progressPct: 100,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: NativeWorkProfileRhythmPage(
          session: session,
          month: DateTime(2026, 9),
          onBack: () {},
          onOpenTask: (id) => openedTask = id,
          loadTasks: () async => tasks,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('整理项目材料'), findsOneWidget);
    await tester.tap(find.byKey(const Key('work-profile-task-1')));
    expect(openedTask, 1);

    await tester.tap(find.byKey(const Key('work-profile-filter-completed')));
    await tester.pump();
    expect(find.text('整理项目材料'), findsNothing);
    expect(find.text('完成复盘'), findsOneWidget);
  });

  testWidgets('knowledge page opens documents and meetings', (tester) async {
    NativeKbDocument? openedDocument;
    int? openedMeeting;
    const document = NativeKbDocument(
      id: '8',
      title: '产品知识手册',
      fileName: '产品知识手册.pdf',
      fileExtension: 'pdf',
      ingestionStatus: 'INDEXED',
      indexed: true,
    );
    const summary = NativeKbSummary(
      documentCount: 1,
      categoryCount: 1,
      unreadCount: 0,
      ready: true,
      documents: [document],
      folderId: 'mine',
    );
    const meeting = NativeMeetingSummary(
      meetingId: 9,
      title: '项目周会',
      meetingDate: '2026-09-07',
      createdAt: '2026-09-07T09:00:00',
      updatedAt: '2026-09-07T10:00:00',
      status: 'DONE',
      asrProgress: 100,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NativeWorkProfileKnowledgePage(
          session: session,
          month: DateTime(2026, 9),
          onBack: () {},
          onOpenDocument: (doc) => openedDocument = doc,
          onOpenMeeting: (id) => openedMeeting = id,
          loadSummary: () async => summary,
          loadMeetings: () async => [meeting],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('work-profile-document-8')));
    expect(openedDocument?.id, '8');
    await tester.tap(find.byKey(const Key('work-profile-meeting-9')));
    expect(openedMeeting, 9);
  });

  testWidgets('knowledge page keeps documents and filters meetings by month', (
    tester,
  ) async {
    const document = NativeKbDocument(
      id: '8',
      title: '产品知识手册',
      fileName: '产品知识手册.pdf',
      fileExtension: 'pdf',
      ingestionStatus: 'INDEXED',
      indexed: true,
    );
    const summary = NativeKbSummary(
      documentCount: 1,
      categoryCount: 1,
      unreadCount: 0,
      ready: true,
      documents: [document],
      folderId: 'mine',
    );
    const meeting = NativeMeetingSummary(
      meetingId: 9,
      title: '项目周会',
      meetingDate: '2026-09-07',
      createdAt: '2026-09-07T09:00:00',
      updatedAt: '2026-09-07T10:00:00',
      status: 'DONE',
      asrProgress: 100,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NativeWorkProfileKnowledgePage(
          session: session,
          month: DateTime(2026, 7),
          onBack: () {},
          onOpenDocument: (_) {},
          onOpenMeeting: (_) {},
          loadSummary: () async => summary,
          loadMeetings: () async => [meeting],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('产品知识手册'), findsOneWidget);
    expect(find.text('项目周会'), findsNothing);
    expect(find.textContaining('文档与分类为当前累计'), findsOneWidget);
  });

  testWidgets('business page shows monthly proposal and KPI task', (
    tester,
  ) async {
    int? openedProposal;
    final proposal = XflowProposalItem(
      id: 3,
      businessType: 'PROPOSAL',
      code: 'P-003',
      title: '能源业务提案',
      status: 'APPROVED',
      createdByName: '陈沙',
      createdAt: DateTime(2026, 9, 3),
    );
    final score = WorkProfileKpiScore.fromJson({
      'month': '2026-09',
      'people': [
        {
          'userId': 1,
          'userName': '陈沙',
          'mainScore': 88,
          'categories': [
            {
              'category': 'energy',
              'categoryLabel': '能源',
              'categoryWeight': 100,
              'score': 88,
              'tasks': [
                {
                  'taskId': 6,
                  'taskName': '华东能源项目',
                  'province': '上海',
                  'bucketLabel': '能源',
                  'weightPct': 100,
                  'taskTotal': 88,
                },
              ],
            },
          ],
        },
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: NativeWorkProfileBusinessPage(
          session: session,
          month: DateTime(2026, 9),
          onBack: () {},
          onOpenProposal: (item) => openedProposal = item.id,
          loadProposals: () async => [proposal],
          loadScore: () async => score,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('能源业务提案'), findsOneWidget);
    expect(find.text('华东能源项目'), findsOneWidget);
    await tester.tap(find.byKey(const Key('work-profile-proposal-3')));
    expect(openedProposal, 3);
  });
}
