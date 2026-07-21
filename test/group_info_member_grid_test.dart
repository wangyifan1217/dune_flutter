import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/chat/group_info_widgets.dart';
import 'package:dunes_app/features/conversation/conversation_models.dart';
import 'package:dunes_app/features/conversation/conversation_service.dart';

void main() {
  AuthSession session() => const AuthSession(
        phone: '13800000000',
        userId: 1,
        token: 'test',
        apiBase: 'http://127.0.0.1',
        roles: <String>[],
      );

  List<NativeGroupMember> fourMembers() => const [
        NativeGroupMember(userId: 1, displayName: '王奕凡'),
        NativeGroupMember(userId: 2, displayName: '吴姝瑶'),
        NativeGroupMember(userId: 3, displayName: '朱子姝'),
        NativeGroupMember(userId: 4, displayName: '李凡伊'),
      ];

  Future<void> pumpGrid(
    WidgetTester tester, {
    required Size surface,
    required List<NativeGroupMember> members,
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = ConversationService(session: session());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: surface.width,
            child: GroupInfoMemberGrid(
              members: members,
              selfUserId: 1,
              avatarService: service,
              showAdd: true,
              showRemove: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('PC 宽屏：添加与移除同一行，网格高度紧凑', (tester) async {
    await pumpGrid(
      tester,
      surface: const Size(1200, 800),
      members: fourMembers(),
    );

    final addTop = tester.getTopLeft(find.text('添加')).dy;
    final removeTop = tester.getTopLeft(find.text('移除')).dy;
    expect(
      (removeTop - addTop).abs(),
      lessThan(8),
      reason: '宽屏下「移除」不应掉到下一行并拉开大空隙',
    );

    final wrapSize = tester.getSize(find.byType(Wrap));
    expect(
      wrapSize.height,
      lessThan(90),
      reason: '单元格不应随屏宽被比例拉高',
    );
  });

  testWidgets('窄屏：换行后行高仍紧凑', (tester) async {
    await pumpGrid(
      tester,
      surface: const Size(320, 640),
      members: fourMembers(),
    );

    final wrapSize = tester.getSize(find.byType(Wrap));
    // 两行左右：两行单元格（头像+字≈58）+ spacing
    expect(wrapSize.height, lessThan(150));
    expect(find.text('添加'), findsOneWidget);
    expect(find.text('移除'), findsOneWidget);
  });
}
