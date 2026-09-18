import 'dart:convert';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/contacts/contact_models.dart';
import 'package:dunes_app/features/contacts/contact_service.dart';
import 'package:dunes_app/features/contacts/contacts_widgets.dart';
import 'package:dunes_app/features/conversation/im_user_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  AuthSession session() => const AuthSession(
    phone: '13800000000',
    userId: 1,
    token: 'test',
    apiBase: 'http://127.0.0.1/api/v1',
    roles: <String>[],
  );

  test('通讯录解析预设与自定义 IM 状态', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{
            'total': 2,
            'departments': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 1,
                'name': '总裁办',
                'users': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'userId': 2,
                    'displayName': '许正阳',
                    'imStatus': 'busy',
                  },
                  <String, dynamic>{
                    'userId': 3,
                    'displayName': '李博睿',
                    'imStatus': 'custom',
                    'imStatusText': '过程舒适结果正确',
                    'imStatusIcon': 'star',
                    'imStatusColor': '#7B5CD8',
                  },
                ],
              },
            ],
          },
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    final data = await ContactService(
      session: session(),
      client: client,
    ).fetchOrgContacts();
    final users = data.departments.single.users;
    expect(users[0].statusValue.key, ImUserStatusCatalog.busy);
    expect(users[0].statusValue.showsBadge, isTrue);

    final custom = users[1].statusValue;
    expect(custom.key, ImUserStatusCatalog.custom);
    expect(custom.text, '过程舒适结果正确');
    expect(custom.icon, 'star');
    expect(custom.color, '#7b5cd8');
    expect(custom.showsBadge, isTrue);
  });

  testWidgets('通讯录行在姓名旁展示状态徽章', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContactRowTile(
            contact: const NativeContact(
              userId: 8,
              displayName: '王一凡',
              title: '数字化解决方案架构师',
              imStatus: 'meeting',
            ),
            currentUserId: 1,
            onOpenProfile: () {},
            onMessage: () {},
          ),
        ),
      ),
    );

    expect(find.text('王一凡'), findsOneWidget);
    expect(find.text('会议中'), findsOneWidget);
  });
}
