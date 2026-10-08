import 'dart:io';
import 'dart:ui' as ui;

import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/conversation/chat_dual_pane_shell.dart';
import 'package:dunes_app/features/conversation/inbox_widgets.dart';
import 'package:dunes_app/features/shell/dunes_main_tab_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment['DUNES_CAPTURE_PREVIEWS'] != '1') return;
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      final data = ByteData.sublistView(await font.readAsBytes());
      for (final family in ['Roboto', 'Microsoft YaHei']) {
        await (FontLoader(family)..addFont(Future.value(data))).load();
      }
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets('desktop colors are isolated on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final desktop =
          platform == TargetPlatform.windows ||
          platform == TargetPlatform.macOS;
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: desktop ? DunesTheme.desktop() : DunesTheme.light(),
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        DunesColors.resolve(
          context,
          DunesColors.bgApp,
          role: DunesColorRole.surface,
        ),
        desktop ? Colors.white : DunesColors.bgApp,
      );
      expect(
        DunesColors.resolve(context, DunesColors.coral),
        DunesColors.coral,
      );
      expect(
        DunesColors.resolve(context, DunesColors.brandPurple),
        DunesColors.brandPurple,
      );
      expect(
        DunesColors.resolve(
          context,
          DunesColors.bgSoft.withValues(alpha: .5),
          role: DunesColorRole.surface,
        ).a,
        closeTo(.5, .005),
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets(
    'desktop shell keeps navigation and search at minimum window size',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.binding.setSurfaceSize(const Size(1024, 680));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final navigation = DunesNavigationController();
      addTearDown(navigation.dispose);
      final search = TextEditingController();
      addTearDown(search.dispose);
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: DunesTheme.desktop(),
          home: RepaintBoundary(
            key: const Key('desktop-preview'),
            child: Scaffold(
              body: ChatDualPaneShell(
                sideRail: DunesMainTabBar(
                  navigation: navigation,
                  activeScreen: 'C1',
                  axis: Axis.vertical,
                  onSwitchMainTab: (value) => selected = value,
                  onDesktopSettingsTap: () => selected = 'settings',
                ),
                listPane: Column(
                  children: [
                    ChatInboxHeader(
                      onOpenContacts: () {},
                      showNovaLeading: false,
                    ),
                    ChatInboxSearchBar(controller: search),
                    ChatInboxRow(
                      kind: ChatInboxRowKind.private,
                      title: '设计讨论',
                      preview: '统一桌面端的视觉风格',
                      timeLabel: '10:24',
                      selected: true,
                      onTap: () => selected = 'chat',
                    ),
                  ],
                ),
                chatPane: const ChatDualPaneEmpty(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), '设计');
      expect(search.text, '设计');
      await tester.tap(find.text('设计讨论'));
      expect(selected, 'chat');
      await tester.tap(find.text('我的'));
      expect(selected, 'B2');
      await tester.tap(find.text('设置'));
      expect(selected, 'settings');
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      if (Platform.environment['DUNES_CAPTURE_PREVIEWS'] == '1') {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('desktop-preview')),
          );
          final image = await boundary.toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('.dart_tool/visual_checks')
            ..createSync(recursive: true);
          File(
            '${dir.path}/desktop_apple.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
