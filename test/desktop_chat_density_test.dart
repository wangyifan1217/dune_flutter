import 'dart:convert';

import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/chat/chat_widgets.dart';
import 'package:dunes_app/features/chat/native_chat_view.dart';
import 'package:dunes_app/features/conversation/chat_message_cache.dart';
import 'package:dunes_app/features/conversation/conversation_models.dart';
import 'package:dunes_app/features/conversation/conversation_realtime_hub.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('consecutive messages keep individual metadata on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(
        Size(platform == TargetPlatform.windows ? 1120 : 420, 800),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const conversation = NativeConversation(
        id: 8675,
        kind: 'PRIVATE',
        title: '同事',
        unreadCount: 0,
        preview: '',
        updatedAt: null,
        peerUserId: 2,
      );
      NativeChatMessage message(
        int id,
        int sender,
        int minute, {
        bool read = false,
        Map<String, dynamic>? payload,
      }) => NativeChatMessage(
        id: id,
        senderUserId: sender,
        senderName: sender == 1 ? '我' : '同事',
        kind: 'TEXT',
        bodyText: '消息 $id',
        createdAt: DateTime(2026, 11, 19, 9, minute, id),
        payload: payload,
        peerRead: read,
      );
      final messages = [
        message(1, 2, 18),
        message(2, 2, 18),
        message(
          3,
          2,
          19,
          payload: {
            'mentionUserIds': [1],
          },
        ),
        message(4, 2, 19),
        message(5, 1, 19, read: true),
        message(6, 1, 19, read: true),
        message(7, 1, 19),
      ];
      addTearDown(() => ChatMessageCache.instance.remove(conversation.id));
      final openedUsers = <int>[];
      final desktop = platform == TargetPlatform.windows;

      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: desktop ? DunesTheme.desktop() : DunesTheme.light(),
              home: TickerMode(
                enabled: false,
                child: NativeChatView(
                  session: const AuthSession(
                    phone: '',
                    userId: 1,
                    token: 'test',
                    apiBase: 'http://local.test',
                    roles: [],
                  ),
                  kind: NativeChatKind.private,
                  conversationHint: conversation,
                  onBack: () {},
                  onOpenUser: (id, _) => openedUsers.add(id),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final rows = {
            for (final row in tester.widgetList<ChatMessageRow>(
              find.byType(ChatMessageRow),
            ))
              row.message.id: row,
          };
          expect(rows.keys, unorderedEquals([1, 2, 3, 4, 5, 6, 7]));
          for (final id in [1, 2, 5, 6, 7]) {
            final row = rows[id]!;
            expect(row.compactDesktop, desktop);
            expect(row.mine ? row.trailingAvatar : row.avatar, isNotNull);
            expect(
              find.descendant(
                of: find.byWidget(row),
                matching: find.text(row.timeLabel!),
              ),
              findsOneWidget,
            );
          }
          expect(rows[5]!.readLabel, '已读');
          expect(rows[6]!.readLabel, '已读');
          expect(rows[7]!.readLabel, '未读');
          if (desktop) {
            final avatar = rows[2]!.avatar!;
            await tester.tap(find.byWidget(avatar));
            expect(openedUsers, [2]);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await ConversationRealtimeHub.instance.dispose();
          await tester.pump(const Duration(milliseconds: 400));
        },
        () => MockClient((request) async {
          if (request.url.path !=
              '/conversations/${conversation.id}/messages') {
            return http.Response('{}', 404);
          }
          return http.Response(
            jsonEncode({
              'data': [
                for (final message in messages)
                  {
                    'id': message.id,
                    'senderUserId': message.senderUserId,
                    'senderName': message.senderName,
                    'kind': message.kind,
                    'bodyText': message.bodyText,
                    'createdAt': message.createdAt!.toIso8601String(),
                    'payload': message.payload,
                    'peerRead': message.peerRead,
                  },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=UTF-8'},
          );
        }),
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
