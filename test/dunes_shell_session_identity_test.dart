import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dunes_app/features/conversation/conversation_realtime_hub.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/shell/dunes_shell.dart';
import 'package:dunes_app/features/qianji_admin/native_qianji_admin_shell.dart';

void main() {
  testWidgets('token replacement preserves the mounted workbench', (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const session = AuthSession(phone: '13800138000', userId: 7,
      token: 'old', apiBase: 'http://localhost:8080', roles: []);
    Widget app(AuthSession value) => MaterialApp(home: DunesShell(
      session: value, initialScreen: 'QJA'));
    await tester.pumpWidget(app(session));
    await tester.pump();
    final finder = find.byType(NativeQianjiAdminShell);
    expect(finder, findsOneWidget);
    final before = tester.state(finder);
    await tester.pumpWidget(app(session.copyWith(token: 'new')));
    await tester.pump();
    expect(tester.state(finder), same(before));
    await tester.pumpWidget(const SizedBox());
    await ConversationRealtimeHub.instance.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
