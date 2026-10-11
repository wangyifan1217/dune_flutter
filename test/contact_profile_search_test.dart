import 'dart:async';

import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/contacts/contact_models.dart';
import 'package:dunes_app/features/contacts/native_contact_profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const session = AuthSession(
  token: 'test',
  userId: 1,
  phone: '',
  apiBase: 'http://local.test',
  roles: [],
);

Future<void> profile(
  WidgetTester tester, {
  int userId = 2,
  int? conversationId,
  Future<void> Function(NativeContact)? onContactSearch,
  ValueChanged<int>? onSearch,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: DunesTheme.light(),
      home: NativeContactProfilePage(
        session: session,
        contactHint: NativeContact(userId: userId, displayName: '搜索到的联系人'),
        onBack: () {},
        onOpenPrivateChat: (_) {},
        conversationId: conversationId,
        onOpenSearch: onSearch,
        onOpenContactSearch: onContactSearch,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'profile opened without a conversation shows search and targets its contact',
    (tester) async {
      await http.runWithClient(() async {
        final pending = Completer<void>();
        final peers = <int>[];
        var oldSearch = 0;
        await profile(
          tester,
          onContactSearch: (contact) {
            peers.add(contact.userId);
            return pending.future;
          },
          onSearch: (_) => oldSearch++,
        );
        expect(find.text('消息免打扰'), findsNothing);
        expect(find.text('查找聊天内容'), findsOneWidget);
        await tester.ensureVisible(find.text('查找聊天内容'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('查找聊天内容'));
        await tester.pump();
        await tester.tap(find.text('查找聊天内容'));
        await tester.pump();
        expect(peers, [2]);
        expect(oldSearch, 0);
        pending.complete();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }, () => MockClient((_) async => http.Response('{}', 404)));
    },
  );

  testWidgets(
    'existing conversation search remains available when settings fail',
    (tester) async {
      await http.runWithClient(() async {
        var searched = 0;
        await profile(
          tester,
          conversationId: 42,
          onSearch: (id) => searched = id,
        );
        await tester.ensureVisible(find.text('查找聊天内容'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('查找聊天内容'));
        expect(searched, 42);
        expect(tester.takeException(), isNull);
      }, () => MockClient((_) async => http.Response('{}', 500)));
    },
  );

  testWidgets('own contact profile does not offer private history search', (
    tester,
  ) async {
    await http.runWithClient(() async {
      await profile(tester, userId: 1, onContactSearch: (_) async {});
      expect(find.text('查找聊天内容'), findsNothing);
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });
}
