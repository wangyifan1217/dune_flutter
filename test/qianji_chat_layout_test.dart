import 'package:dunes_app/features/qianji/native_qianji_hub_page.dart';
import 'package:dunes_app/features/qianji/qianji_chat_service.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('new layout switches scopes and retains old page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeQianjiHubPage(
            onOpenCursorAccount: () {},
            onOpenCashFlow: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('查询范围：全部板块'), findsOneWidget);
    await tester.tap(find.byTooltip('展开板块'));
    await tester.pumpAndSettle();
    expect(find.text('数字员工'), findsNothing);
    expect(find.text('数字人'), findsNothing);
    await tester.tap(find.text('资金流向'));
    await tester.pumpAndSettle();
    expect(find.text('查询范围：资金流向'), findsOneWidget);
    expect(find.text('资金流向概览'), findsOneWidget);
    await tester.tap(find.text('切换旧版'));
    await tester.pumpAndSettle();
    expect(find.text('切换新版'), findsOneWidget);
    await tester.tap(find.text('切换新版'));
    await tester.pumpAndSettle();
    expect(find.text('查询范围：资金流向'), findsOneWidget);
  }, skip: !qianjiHubNewLayoutEnabled);
  testWidgets('wide layout keeps the sidebar visible after selecting a scope', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeQianjiHubPage(
            onOpenCursorAccount: () {},
            onOpenCashFlow: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('饕 · 业务查询'), findsOneWidget);
    await tester.tap(find.text('资金流向'));
    await tester.pumpAndSettle();
    expect(find.text('查询范围：资金流向'), findsOneWidget);
    expect(find.text('饕 · 业务查询'), findsOneWidget);
    await tester.tap(find.byTooltip('收起板块').first);
    await tester.pumpAndSettle();
    expect(find.text('饕 · 业务查询'), findsNothing);
  }, skip: !qianjiHubNewLayoutEnabled);
  testWidgets(
    'independent history reloads and hides revoked results after returning',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = _FakeQianjiChatService();
      var session = const AuthSession(
        phone: '',
        userId: 7,
        token: 'test',
        apiBase: '',
        roles: [],
        qianjiAccess: true,
        cashFlowAccess: true,
        digitalEmployeeAccessKnown: true,
      );
      var visible = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Offstage(
                  offstage: !visible,
                  child: TickerMode(
                    enabled: visible,
                    child: NativeQianjiHubPage(
                      onOpenCursorAccount: () {},
                      chatService: service,
                      session: session,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '我的问题');
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(find.text('我的问题'), findsOneWidget);
      expect(find.text('原业务结果'), findsOneWidget);
      expect(service.lastScope, '全部板块');
      await tester.tap(find.byTooltip('展开板块'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建对话'));
      await tester.pumpAndSettle();
      expect(find.text('原业务结果'), findsNothing);
      await tester.tap(find.byTooltip('展开板块'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('历史对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('对话 17'));
      await tester.pumpAndSettle();
      expect(find.text('原业务结果'), findsOneWidget);
      service.revoked = true;
      update(() => session = session.copyWith(cashFlowAccess: false));
      await tester.pumpAndSettle();
      expect(find.text('原业务结果'), findsNothing);
      expect(find.text('当前无权查看该板块。'), findsOneWidget);
      update(() => visible = false);
      await tester.pump();
      service.revoked = true;
      update(() => visible = true);
      await tester.pumpAndSettle();
      expect(find.text('原业务结果'), findsNothing);
      expect(find.text('当前无权查看该板块。'), findsOneWidget);
    },
    skip: !qianjiHubNewLayoutEnabled,
  );
}

class _FakeQianjiChatService extends QianjiChatService {
  _FakeQianjiChatService()
    : super(
        const AuthSession(
          phone: '',
          userId: 7,
          token: '',
          apiBase: '',
          roles: [],
        ),
      );
  bool revoked = false;
  bool created = false;
  String? lastScope;
  @override
  Future<List<dynamic>> conversations({int offset = 0}) async => created
      ? [
          {'id': 17, 'updatedAt': '2026-10-29T00:00:00Z'},
        ]
      : [];
  @override
  Future<int> create() async {
    created = true;
    return 17;
  }

  @override
  Future<Map<String, dynamic>> send(
    int id,
    String scope,
    String question,
  ) async {
    lastScope = scope;
    return {'id': 1, 'scope': scope, 'question': question, 'reply': '原业务结果'};
  }

  @override
  Future<List<dynamic>> turns(int id, {int? before}) async => [
    revoked
        ? {
            'id': 1,
            'scope': '全部板块',
            'question': '该条历史内容因权限无法确认而隐藏。',
            'reply': '当前无权查看该板块。',
          }
        : {'id': 1, 'scope': '全部板块', 'question': '我的问题', 'reply': '原业务结果'},
  ];
}
