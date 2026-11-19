import 'dart:async';
import 'dart:convert';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/proposal_intake/native_proposal_intake_page.dart';
import 'package:dunes_app/features/proposal_intake/proposal_list_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('list searches initiator by name, alongside code and title', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1050, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var listRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/proposal-intakes') listRequests++;
      final data = switch (request.url.path) {
        '/proposal-intakes/options' => <String, dynamic>{},
        '/org/users' => [
          {'id': 27, 'displayName': '李凡伊'},
        ],
        '/proposal-intakes' => {
          'total': 2,
          'items': [
            {
              'id': 1,
              'code': 'TA-202611-01',
              'title': '第一份提案',
              'createdBy': 27,
              'form': {'product': '产品甲'},
            },
            {
              'id': 2,
              'code': 'TA-202611-02',
              'title': '第二份提案',
              'createdBy': 28,
              'form': {'createdByName': '王一凡', 'product': '产品乙'},
            },
          ],
        },
        _ => throw StateError('Unexpected request: ${request.url}'),
      };
      return http.Response.bytes(
        utf8.encode(jsonEncode({'success': true, 'data': data})),
        200,
      );
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NativeProposalIntakePage(
              session: AuthSession(
                token: 'test',
                userId: 1,
                phone: '',
                apiBase: 'http://local.test',
                roles: [],
              ),
              kind: 'sales',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.widgetWithText(TextField, '搜索编号、名称或发起人');
      final first = find.byKey(
        const ValueKey('proposal-tag-group-collapse-产品甲'),
      );
      final second = find.byKey(
        const ValueKey('proposal-tag-group-collapse-产品乙'),
      );

      Future<void> searchFor(String input) async {
        await tester.enterText(search, input);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
      }

      await searchFor('凡伊');
      expect(first, findsOneWidget);
      expect(second, findsNothing);
      await searchFor('王一');
      expect(first, findsNothing);
      expect(second, findsOneWidget);
      await searchFor('ta-202611-01');
      expect(first, findsOneWidget);
      expect(second, findsNothing);
      await searchFor('第二份');
      expect(first, findsNothing);
      expect(second, findsOneWidget);
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      expect(listRequests, 1);
    }, () => client);
  });

  testWidgets('hidden proposal list detaches and pauses prefetch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(540, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final pages = <int>[];
    final pendingPage = Completer<void>();
    final client = MockClient((request) async {
      Object data;
      switch (request.url.path) {
        case '/proposal-intakes/options':
          data = <String, dynamic>{};
        case '/org/users':
          data = [];
        case '/proposal-intakes':
          final page = int.parse(request.url.queryParameters['page']!);
          pages.add(page);
          if (page == 1) await pendingPage.future;
          data = {
            'items': [
              for (var id = page * 10; id < (page + 1) * 10; id++)
                {
                  'id': id + 1,
                  'title': '提案 $id',
                  'form': {'product': '产品 $id'},
                },
            ],
            'total': 30,
          };
        default:
          throw StateError('Unexpected request: ${request.url}');
      }
      return http.Response.bytes(
        utf8.encode(jsonEncode({'success': true, 'data': data})),
        200,
      );
    });

    Widget page({required bool visible}) => MaterialApp(
      home: Scaffold(
        body: TickerMode(
          enabled: visible,
          child: const NativeProposalIntakePage(
            session: AuthSession(
              token: 'test',
              userId: 1,
              phone: '',
              apiBase: 'http://local.test',
              roles: [],
            ),
            kind: 'sales',
          ),
        ),
      ),
    );

    await http.runWithClient(() async {
      await tester.pumpWidget(page(visible: true));
      await tester.pumpAndSettle();
      expect(pages, [0, 1]);
      final toggle = find.byKey(
        const ValueKey('proposal-tag-group-collapse-产品 0'),
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('提案 0'), findsOneWidget);
      final list = find.byKey(const PageStorageKey('proposal-intake-list'));
      final scroll = tester.widget<ListView>(list).controller!;
      scroll.jumpTo(300);
      await tester.pumpAndSettle();

      await tester.pumpWidget(page(visible: false));
      expect(
        find.byType(ProposalTagGroupCard, skipOffstage: false),
        findsNothing,
      );
      pendingPage.complete();
      await tester.pumpAndSettle();
      expect(pages, [0, 1]);

      await tester.pumpWidget(page(visible: true));
      await tester.pumpAndSettle();
      expect(pages, [0, 1, 2]);
      expect(scroll.offset, 300);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('提案 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => client);
  });
}
