import 'dart:io';
import 'dart:ui' as ui;

import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/meeting/meeting_live_controller.dart';
import 'package:dunes_app/features/nova/presence/nova_presence_host.dart';
import 'package:dunes_app/features/nova/presence/nova_presence_model.dart';
import 'package:dunes_app/features/nova/presence/nova_presence_panel.dart';
import 'package:dunes_app/features/tasks/task_models.dart';
import 'package:dunes_app/features/shell/dunes_main_tab_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const session = AuthSession(
  phone: '',
  userId: 42,
  token: 'test',
  apiBase: 'https://example.invalid',
  roles: [],
  taskPermissions: {'pending': false},
);

TaskItem task(
  int id, {
  int owner = 42,
  String status = 'active',
  int day = 16,
}) => TaskItem(
  id: id,
  title: '完成客户方案与交付材料',
  description: '整理方案，核对交付清单。',
  ownerUserId: owner,
  creatorUserId: 42,
  status: status,
  progressPct: 65,
  dueAt: DateTime(2026, 10, day, 18),
);

Future<void> pumpPresence(
  WidgetTester tester,
  DunesNavigationController navigation, {
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  double keyboard = 0,
  double scale = 1,
  NovaPresenceHandle? handle,
  bool mainNavigation = false,
  bool composer = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        fontFamily: 'PresenceQA',
        colorSchemeSeed: novaPresenceAccent,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: NovaPresenceHost(
          session: session,
          handle: handle,
          navigation: navigation,
          floatEnabled: true,
          child: Builder(
            builder: (context) => Stack(
              children: [
                if (composer)
                  const Positioned(
                    left: 120,
                    right: 20,
                    bottom: 20,
                    child: TextField(key: ValueKey('background-composer')),
                  ),
                Center(
                  child: TextButton(
                    onPressed: () => NovaPresenceScope.maybeOf(context)!.open(),
                    child: const Text('打开小饕'),
                  ),
                ),
                if (mainNavigation)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: DunesMainTabBar(
                      navigation: navigation,
                      activeScreen: navigation.currentScreen,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(
      'PresenceQA',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test('due suggestions exclude other users, completed and non-near tasks', () {
    final now = DateTime(2026, 10, 16, 10);
    expect(
      novaDueTaskMessage(
        [
          task(1, owner: 9),
          task(2, status: 'completed'),
          task(3, day: 19),
          task(4, day: 15),
        ],
        userId: 42,
        now: now,
      ),
      isNull,
    );
    final message = novaDueTaskMessage(
      [task(1, day: 17), task(2, status: 'in_progress')],
      userId: 42,
      now: now,
    )!;
    expect(message.task!.id, 2);
    expect(message.text, contains('今天到期'));
    expect(message.prompt, contains('65%'));
  });

  testWidgets(
    'page tip is delayed, dismissible and not repeated after navigation',
    (tester) async {
      final navigation = DunesNavigationController(initialScreen: 'K1');
      addTearDown(navigation.dispose);
      await pumpPresence(tester, navigation);
      expect(find.text('想快速抓住重点？我可以陪你一起整理。'), findsNothing);
      await tester.pump(const Duration(seconds: 7));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('想快速抓住重点？我可以陪你一起整理。'), findsOneWidget);
      await tester.tap(find.text('想快速抓住重点？我可以陪你一起整理。'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('忽略这条提示'));
      await tester.pump();
      navigation.go('C1');
      navigation.go('K1');
      await tester.pump(const Duration(seconds: 20));
      expect(find.text('想快速抓住重点？我可以陪你一起整理。'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('keyboard and active recording suppress proactive speech', (
    tester,
  ) async {
    final navigation = DunesNavigationController(initialScreen: 'K1');
    addTearDown(navigation.dispose);
    await pumpPresence(tester, navigation, keyboard: 300);
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('想快速抓住重点？我可以陪你一起整理。'), findsNothing);
    tester.view.viewInsets = FakeViewPadding.zero;
    MeetingLiveController.instance.active.value = true;
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('一起看看'), findsNothing);
    expect(find.byType(NovaPresenceAvatar), findsNothing);
    MeetingLiveController.instance.active.value = false;
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('panel stays on page and closes without navigating', (
    tester,
  ) async {
    final navigation = DunesNavigationController(initialScreen: 'K1');
    addTearDown(navigation.dispose);
    await pumpPresence(tester, navigation);
    await tester.tap(find.text('打开小饕'));
    await tester.pumpAndSettle();
    expect(find.byType(NovaPresencePanel), findsOneWidget);
    expect(navigation.currentScreen, 'K1');
    await tester.tap(find.byTooltip('收起小饕'));
    await tester.pumpAndSettle();
    expect(find.byType(NovaPresencePanel), findsNothing);
    expect(navigation.currentScreen, 'K1');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('back dismisses the panel before application navigation', (
    tester,
  ) async {
    final navigation = DunesNavigationController(initialScreen: 'K1');
    final handle = NovaPresenceHandle();
    addTearDown(navigation.dispose);
    await pumpPresence(tester, navigation, handle: handle);
    await tester.tap(find.text('打开小饕'));
    await tester.pumpAndSettle();
    expect(handle.closeIfOpen!(), isTrue);
    await tester.pumpAndSettle();
    expect(navigation.currentScreen, 'K1');
    expect(handle.closeIfOpen!(), isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(handle.closeIfOpen, isNull);
  });

  testWidgets('existing avatar opens presence without leaving main tab', (
    tester,
  ) async {
    final navigation = DunesNavigationController(initialScreen: 'C1');
    addTearDown(navigation.dispose);
    await pumpPresence(tester, navigation, mainNavigation: true);
    await tester.tap(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image is AssetImage &&
                (widget.image as AssetImage).assetName ==
                    'assets/images/ai_tab_avatar.png',
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(NovaPresencePanel), findsOneWidget);
    expect(navigation.currentScreen, 'C1');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('large text bubble fits and quiet preference survives remount', (
    tester,
  ) async {
    final navigation = DunesNavigationController(initialScreen: 'K1');
    addTearDown(navigation.dispose);
    await pumpPresence(
      tester,
      navigation,
      size: const Size(360, 740),
      scale: 1.6,
    );
    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('想快速抓住重点？我可以陪你一起整理。'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('提示设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24 小时内不主动提示'));
    await tester.pumpAndSettle();
    expect(find.text('一起看看'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    final preferences = await SharedPreferences.getInstance();
    final quietKey = preferences.getKeys().singleWhere(
      (key) => key.endsWith('.quiet'),
    );
    expect(
      DateTime.parse(preferences.getString(quietKey)!).isAfter(DateTime.now()),
      isTrue,
    );
    // A different page suggestion would otherwise be eligible after cooldown.
    final lastKey = preferences.getKeys().singleWhere(
      (key) => key.endsWith('.last'),
    );
    await preferences.remove(lastKey);
    navigation.go('MM-L');
    await pumpPresence(tester, navigation);
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('一起看看'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Windows conversation shows companion above composer and opens in place',
    (tester) async {
      final navigation = DunesNavigationController(initialScreen: 'C5');
      addTearDown(navigation.dispose);
      await pumpPresence(tester, navigation, size: const Size(1280, 900));
      await tester.pump(const Duration(seconds: 7));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text('要做点什么？我可以帮你整理思路，或一起看下一步。'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('要做点什么？我可以帮你整理思路，或一起看下一步。'));
      await tester.pumpAndSettle();
      expect(find.text('和我说一句'), findsOneWidget);
      final field = find.byType(TextField);
      expect(tester.getRect(field).bottom, lessThan(700));
      expect(find.byType(NovaPresencePanel), findsNothing);
      expect(navigation.currentScreen, 'C5');
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'Windows typing suppresses proactive bubble without an onscreen keyboard',
    (tester) async {
      final navigation = DunesNavigationController(initialScreen: 'C2');
      addTearDown(navigation.dispose);
      await pumpPresence(
        tester,
        navigation,
        size: const Size(1280, 900),
        composer: true,
      );
      await tester.tap(find.byKey(const ValueKey('background-composer')));
      await tester.enterText(
        find.byKey(const ValueKey('background-composer')),
        '正在编辑的消息',
      );
      await tester.pump(const Duration(seconds: 7));
      expect(
        find.text('要做点什么？我可以帮你整理思路，或一起看下一步。'),
        findsNothing,
      );
      expect(find.text('正在编辑的消息'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final spec in [
    (
      name: 'mobile',
      size: const Size(390, 844),
      brightness: Brightness.light,
      keyboard: 0.0,
      scale: 1.0,
    ),
    (
      name: 'mobile_keyboard',
      size: const Size(360, 740),
      brightness: Brightness.light,
      keyboard: 300.0,
      scale: 1.0,
    ),
    (
      name: 'desktop_dark',
      size: const Size(1200, 850),
      brightness: Brightness.dark,
      keyboard: 0.0,
      scale: 1.0,
    ),
    (
      name: 'accessible',
      size: const Size(360, 740),
      brightness: Brightness.light,
      keyboard: 0.0,
      scale: 1.6,
    ),
  ]) {
    testWidgets('panel layout ${spec.name}', (tester) async {
      final navigation = DunesNavigationController(initialScreen: 'K1');
      addTearDown(navigation.dispose);
      await pumpPresence(
        tester,
        navigation,
        size: spec.size,
        brightness: spec.brightness,
        scale: spec.scale,
      );
      await tester.tap(find.text('打开小饕'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(bottom: spec.keyboard);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final panelRect = tester.getRect(find.byType(NovaPresencePanel));
      expect(
        panelRect.bottom,
        lessThanOrEqualTo(spec.size.height - spec.keyboard),
      );
      expect(panelRect.top, greaterThanOrEqualTo(0));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('capture task panel for visual review', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: 'PresenceQA',
          colorSchemeSeed: novaPresenceAccent,
        ),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            backgroundColor: const Color(0xFFF1F0F5),
            body: Center(
              child: SizedBox(
                width: 392,
                height: 620,
                child: NovaPresencePanel(
                  session: session,
                  pageName: '工作台',
                  message: novaDueTaskMessage(
                    [task(1)],
                    userId: 42,
                    now: DateTime(2026, 10, 16),
                  ),
                  onClose: () {},
                  onExpand: (_) {},
                  onSend: (_) {},
                  onOpenTask: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (Platform.environment['NOVA_CAPTURE'] == '1') {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('test_reports/nova_presence/panel.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets('right click hides the desktop float and keeps it hidden', (
    tester,
  ) async {
    final navigation = DunesNavigationController(initialScreen: 'C1');
    addTearDown(navigation.dispose);
    await pumpPresence(tester, navigation, size: const Size(1200, 850));
    await tester.pump();
    expect(find.byType(NovaPresenceAvatar), findsOneWidget);
    await tester.tap(
      find.byType(NovaPresenceAvatar),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text('隐藏小饕浮框'), findsOneWidget);
    await tester.tap(find.text('隐藏小饕浮框'));
    await tester.pumpAndSettle();
    expect(find.byType(NovaPresenceAvatar), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await pumpPresence(tester, navigation, size: const Size(1200, 850));
    await tester.pumpAndSettle();
    expect(find.byType(NovaPresenceAvatar), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reopened chat keeps the conversation on screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovaPresencePanel(
            session: session,
            pageName: '消息',
            onClose: () {},
            onExpand: (_) {},
            onSend: (_) {},
            turns: const [
              NovaPresenceTurn(fromUser: true, text: '帮我看一下今天的安排'),
              NovaPresenceTurn(
                fromUser: false,
                text: '可以。先说你最想处理的一件事，我再帮你往下拆。',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('帮我看一下今天的安排'), findsOneWidget);
    expect(find.textContaining('先说你最想处理的一件事'), findsOneWidget);
    expect(find.text('我在。\n想一起处理点什么？'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop chat window can be dragged', (tester) async {
    final navigation = DunesNavigationController(initialScreen: 'C1');
    addTearDown(navigation.dispose);
    await pumpPresence(tester, navigation, size: const Size(1200, 850));
    await tester.tap(find.text('打开小饕'));
    await tester.pumpAndSettle();
    final panel = find.byType(NovaPresencePanel);
    final before = tester.getTopLeft(panel);
    await tester.drag(find.text('小饕'), const Offset(-160, -80));
    await tester.pump();
    final after = tester.getTopLeft(panel);
    expect(after.dx, lessThan(before.dx - 60));
    expect(after.dy, lessThan(before.dy - 40));
    expect(after.dx, greaterThanOrEqualTo(0));
    expect(after.dy, greaterThanOrEqualTo(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('wide desktop float can be dragged and stays inside', (
    tester,
  ) async {
    final navigation = DunesNavigationController(initialScreen: 'C1');
    addTearDown(navigation.dispose);
    await pumpPresence(tester, navigation, size: const Size(1200, 850));
    await tester.pump();
    final avatar = find.byType(NovaPresenceAvatar);
    expect(avatar, findsOneWidget);
    final before = tester.getTopLeft(avatar);
    await tester.drag(avatar, const Offset(-180, -120));
    await tester.pump();
    final after = tester.getTopLeft(avatar);
    expect(after.dx, lessThan(before.dx - 80));
    expect(after.dy, lessThan(before.dy - 60));
    expect(after.dx, greaterThanOrEqualTo(0));
    expect(after.dy, greaterThanOrEqualTo(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('float is hidden until the feature is turned back on', (
    tester,
  ) async {
    final navigation = DunesNavigationController(initialScreen: 'C1');
    addTearDown(navigation.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 850);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovaPresenceHost(
            session: session,
            navigation: navigation,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => NovaPresenceScope.maybeOf(context)!.open(),
                child: const Text('打开小饕'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 7));
    expect(find.byType(NovaPresenceAvatar), findsNothing);
    expect(find.byType(NovaPresencePanel), findsNothing);
    await tester.tap(find.text('打开小饕'));
    await tester.pump();
    expect(find.byType(NovaPresencePanel), findsNothing);
    expect(navigation.currentScreen, 'C4');
    await tester.pumpWidget(const SizedBox());
  });
}
