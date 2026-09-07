import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/conversation/conversation_models.dart';
import 'package:dunes_app/features/profile/native_work_profile_collaboration_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const session = AuthSession(
    phone: '13800000000',
    userId: 1,
    token: '',
    apiBase: '',
    roles: <String>[],
    displayName: '陈沙',
  );

  final conversations = <NativeConversation>[
    NativeConversation(
      id: 11,
      kind: 'PRIVATE',
      title: '私聊',
      peerDisplayName: '李明',
      peerDepartment: '运营部',
      unreadCount: 2,
      preview: '项目材料已更新',
      updatedAt: DateTime(2026, 9, 7),
    ),
    NativeConversation(
      id: 12,
      kind: 'WORKGROUP',
      title: '能源项目组',
      memberCount: 8,
      unreadCount: 1,
      preview: '请确认排期',
      updatedAt: DateTime(2026, 9, 6),
    ),
    NativeConversation(
      id: 13,
      kind: 'WORKGROUP_APPROVAL',
      title: '销售提案审批群',
      memberCount: 5,
      unreadCount: 0,
      preview: '审批已通过',
      updatedAt: DateTime(2026, 9, 5),
    ),
  ];

  testWidgets('shows current collaboration snapshot and opens conversation', (
    tester,
  ) async {
    NativeConversation? opened;
    var favoritesOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: NativeWorkProfileCollaborationPage(
          session: session,
          month: DateTime(2026, 9),
          onBack: () {},
          onOpenConversation: (conversation) => opened = conversation,
          onOpenFavorites: () => favoritesOpened = true,
          loadConversations: () async => conversations,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('协作沉淀'), findsOneWidget);
    expect(find.textContaining('按会话最近活跃时间统计当月协作'), findsOneWidget);
    expect(find.text('协作联系人'), findsOneWidget);
    expect(find.text('群聊'), findsWidgets);
    expect(find.text('审批工作群'), findsNothing);
    expect(find.text('审批群'), findsNothing);
    expect(find.text('李明'), findsOneWidget);
    expect(find.text('能源项目组'), findsOneWidget);
    expect(find.text('销售提案审批群'), findsNothing);

    await tester.tap(find.byKey(const Key('work-profile-filter-group')));
    await tester.pump();
    expect(find.text('能源项目组'), findsOneWidget);
    expect(find.text('李明'), findsNothing);

    await tester.tap(find.text('收藏消息'));
    expect(favoritesOpened, isTrue);

    await tester.tap(find.byKey(const Key('work-profile-filter-all')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('work-profile-collaboration-11')));
    await tester.pump();
    expect(opened?.id, 11);
  });

  testWidgets('filters conversations to the selected month', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeWorkProfileCollaborationPage(
          session: session,
          month: DateTime(2026, 7),
          onBack: () {},
          onOpenConversation: (_) {},
          loadConversations: () async => conversations,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('李明'), findsNothing);
    expect(find.text('能源项目组'), findsNothing);
    expect(find.textContaining('2026年7月'), findsOneWidget);
  });
}
