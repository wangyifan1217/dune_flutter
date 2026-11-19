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
