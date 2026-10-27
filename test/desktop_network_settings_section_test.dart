import 'dart:async';

import 'package:dunes_app/core/network/desktop_network_settings.dart';
import 'package:dunes_app/core/network/network_diagnostics.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/desktop/desktop_network_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Diagnostics extends DesktopNetworkDiagnostics {
  final result = Completer<List<NetworkProbeResult>>();
  @override
  Future<List<NetworkProbeResult>> run(AuthSession? session) => result.future;
}

void main() {
  testWidgets(
    'network mode is saved and testing locks changes until results arrive',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = DesktopNetworkSettings();
      final diagnostics = _Diagnostics();
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DesktopNetworkSettingsSection(
                settings: settings,
                diagnostics: diagnostics,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('desktop-network-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('直连，不使用代理').last);
      await tester.pumpAndSettle();
      expect(settings.direct, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString(
          DesktopNetworkSettings.prefsKey,
        ),
        'direct',
      );
      expect(find.textContaining('VPN / TUN'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('desktop-network-test')));
      await tester.pump();
      expect(find.text('检测中…'), findsOneWidget);
      final dropdown = tester.widget<DropdownButton<DesktopNetworkMode>>(
        find.byKey(const ValueKey('desktop-network-mode')),
      );
      expect(dropdown.onChanged, isNull);
      diagnostics.result.complete(const [
        NetworkProbeResult('业务接口', '连接正常', success: true),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('业务接口：连接正常'), findsOneWidget);
      expect(find.text('测试连接'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
