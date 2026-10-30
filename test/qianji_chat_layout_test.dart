import 'package:dunes_app/features/qianji/native_qianji_hub_page.dart';
import 'package:dunes_app/features/qianji/qianji_chat_service.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'new layout switches scopes and retains old page',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeQianjiHubPage(
              onOpenCursorAccount: () {},
              onOpenCashFlow: () {},
              onOpenMonthlyOpinion: () {},
              onOpenProposalReview: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('范围 · 智能识别'), findsOneWidget);
      await tester.tap(find.byTooltip('展开板块'));
      await tester.pumpAndSettle();
      expect(find.text('数字员工'), findsNothing);
      expect(find.text('数字人'), findsNothing);
      await tester.tap(find.text('业务查阅'));
      await tester.pumpAndSettle();
      expect(find.text('月度舆情'), findsNothing);
      expect(find.text('提案审核'), findsNothing);
      await tester.tap(find.text('业务看板'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('资金流向'));
      await tester.pumpAndSettle();
      expect(find.text('范围 · 资金流向'), findsOneWidget);
      expect(find.text('资金流向概览'), findsOneWidget);
      await tester.tap(find.text('模块入口'));
      await tester.pumpAndSettle();
      expect(find.text('切换新版'), findsOneWidget);
      await tester.tap(find.text('切换新版'));
      await tester.pumpAndSettle();
      expect(find.text('范围 · 资金流向'), findsOneWidget);
    },
    skip: !qianjiHubNewLayoutEnabled,
  );
  testWidgets(
    'wide layout keeps the sidebar visible after selecting a scope',
    (tester) async {
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
      expect(find.text('业务查询'), findsOneWidget);
      // 宽屏也不再默认展开侧栏，先手动打开再选板块。
      await tester.tap(find.byTooltip('展开板块'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('业务看板'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('资金流向'));
      await tester.pumpAndSettle();
      expect(find.text('范围 · 资金流向'), findsOneWidget);
      expect(find.text('业务查询'), findsOneWidget);
      await tester.tap(find.byTooltip('收起板块').first);
      await tester.pumpAndSettle();
      expect(find.text('业务查询'), findsNothing);
    },
    skip: !qianjiHubNewLayoutEnabled,
  );
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
  testWidgets(
    'failed send keeps the question and can be retried',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = _FakeQianjiChatService()..failNextSend = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeQianjiHubPage(
              onOpenCursorAccount: () {},
              chatService: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '张三的知识库有多少文档');
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(find.text('张三的知识库有多少文档'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('重试'), findsNothing);
      expect(find.text('原业务结果'), findsOneWidget);
      expect(service.lastQuestion, '张三的知识库有多少文档');
    },
    skip: !qianjiHubNewLayoutEnabled,
  );
  testWidgets(
    'deleting the open conversation removes it and resets the chat',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = _FakeQianjiChatService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeQianjiHubPage(
              onOpenCursorAccount: () {},
              chatService: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '我的问题');
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('展开板块'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('历史对话'));
      await tester.pumpAndSettle();
      expect(find.text('对话 17'), findsOneWidget);
      await tester.tap(find.byTooltip('删除对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(service.deletedIds, isEmpty);
      await tester.tap(find.byTooltip('删除对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(service.deletedIds, [17]);
      expect(find.text('对话 17'), findsNothing);
      expect(find.text('原业务结果'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    },
    skip: !qianjiHubNewLayoutEnabled,
  );
  testWidgets(
    'person example fills the composer and selects the name',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = _FakeQianjiChatService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeQianjiHubPage(
              onOpenCursorAccount: () {},
              chatService: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('按人查询'));
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '张三的知识库有多少文档');
      expect(
        field.controller!.selection.textInside(field.controller!.text),
        '张三',
      );
      expect(service.lastQuestion, isNull);
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
  bool failNextSend = false;
  String? lastScope;
  String? lastQuestion;
  final deletedIds = <int>[];
  @override
  Future<void> delete(int id) async => deletedIds.add(id);
  @override
  Future<List<dynamic>> conversations({int offset = 0}) async =>
      created && !deletedIds.contains(17)
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
    lastQuestion = question;
    if (failNextSend) {
      failNextSend = false;
      throw Exception('network');
    }
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
