import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/conversation/conversation_realtime_hub.dart';
import 'package:dunes_app/features/shell/dunes_main_tab_bar.dart';
import 'package:dunes_app/features/shell/dunes_shell.dart';
import 'package:dunes_app/features/xflow/native_xflow_proposal_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('desktop main navigation preserves the open approval page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const session = AuthSession(phone: '13800138000', userId: 7,
      token: 'test-token', apiBase: 'http://localhost:8080', roles: []);
    await tester.pumpWidget(const MaterialApp(home: DunesShell(session: session, initialScreen: 'XFP')));
    await tester.pump();
    final approval = find.byType(NativeXflowProposalPage, skipOffstage: false);
    expect(approval, findsOneWidget);
    final original = tester.state(approval);

    final bar = tester.widget<DunesMainTabBar>(find.byType(DunesMainTabBar).first);
    bar.onSwitchMainTab!('C1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(bar.navigation.currentScreen, 'C1');
    expect(approval, findsOneWidget);
    expect(tester.state(approval), same(original));

    final returnBar = tester.widget<DunesMainTabBar>(find.byType(DunesMainTabBar).first);
    returnBar.onSwitchMainTab!('B2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(bar.navigation.currentScreen, 'XFP');
    expect(approval, findsOneWidget);
    expect(tester.state(approval), same(original));
    await tester.pumpWidget(const SizedBox());
    await ConversationRealtimeHub.instance.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
