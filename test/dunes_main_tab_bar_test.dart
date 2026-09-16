import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/conversation/comm_unread_notifier.dart';
import 'package:dunes_app/features/shell/dunes_main_tab_bar.dart';
import 'package:dunes_app/features/workbench/workbench_badge_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _mainTabs = {'通讯': 'C1', '饕': 'QJ', '灯塔': 'LH', '我的': 'B2'};

Future<void> _pumpBar(
  WidgetTester tester, {
  required DunesNavigationController navigation,
  VoidCallback? onOpenAi,
  ValueChanged<String>? onSwitchMainTab,
  CommUnreadNotifier? commUnread,
  WorkbenchBadgeNotifier? workbenchBadge,
  bool chatOnlyMode = false,
  Axis axis = Axis.horizontal,
  Size size = const Size(390, 844),
  double bottomInset = 0,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: EdgeInsets.only(bottom: bottomInset),
          viewPadding: EdgeInsets.only(bottom: bottomInset),
          textScaler: TextScaler.linear(textScale),
        ),
        child: ListenableBuilder(
          listenable: navigation,
          builder: (context, _) {
            final bar = DunesMainTabBar(
              navigation: navigation,
              activeScreen: navigation.currentScreen,
              onOpenAi: onOpenAi,
              onSwitchMainTab: onSwitchMainTab,
              commUnread: commUnread,
              workbenchBadge: workbenchBadge,
              chatOnlyMode: chatOnlyMode,
              axis: axis,
            );
            return Scaffold(
              body: axis == Axis.vertical
                  ? Row(children: [bar, const Expanded(child: SizedBox())])
                  : const SizedBox.expand(),
              bottomNavigationBar: axis == Axis.horizontal ? bar : null,
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _unreadDots() => find.descendant(
  of: find.byType(DunesMainTabBar),
  matching: find.byWidgetPredicate((widget) {
    if (widget is! Container) return false;
    final decoration = widget.decoration;
    return decoration is BoxDecoration &&
        decoration.shape == BoxShape.circle &&
        decoration.color == DunesColors.coral;
  }),
);

void main() {
  testWidgets('narrow mobile bar keeps AI and all tabs above the safe area', (
    tester,
  ) async {
    final navigation = DunesNavigationController();
    addTearDown(navigation.dispose);
    final selected = <String>[];
    var aiOpened = false;
    const size = Size(320, 720);
    const bottomInset = 34.0;

    await _pumpBar(
      tester,
      navigation: navigation,
      size: size,
      bottomInset: bottomInset,
      textScale: 1.5,
      onOpenAi: () => aiOpened = true,
      onSwitchMainTab: selected.add,
    );

    expect(tester.takeException(), isNull);
    final labels = ['AI', ..._mainTabs.keys];
    var previousRight = 0.0;
    for (final label in labels) {
      final entry = find.text(label);
      expect(entry, findsOneWidget);
      final rect = tester.getRect(entry);
      expect(rect.left, greaterThanOrEqualTo(previousRight));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(rect.bottom, lessThanOrEqualTo(size.height - bottomInset));
      previousRight = rect.right;
      await tester.tap(entry);
      await tester.pumpAndSettle();
    }
    expect(aiOpened, isTrue);
    expect(selected, _mainTabs.values.toList());
    expect(navigation.history, ['C1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI opens C4 and back restores the previous page', (tester) async {
    final navigation = DunesNavigationController(initialScreen: 'C4');
    addTearDown(navigation.dispose);
    navigation.go('B2');
    navigation.go('MM-L');
    await _pumpBar(tester, navigation: navigation);

    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(navigation.currentScreen, 'C4');
    expect(navigation.history, ['C4', 'B2', 'MM-L', 'C4']);

    expect(navigation.handleBack(), isTrue);
    await tester.pumpAndSettle();
    expect(navigation.currentScreen, 'MM-L');
    expect(navigation.history, ['C4', 'B2', 'MM-L']);
  });

  testWidgets('AI uses its host callback without switching the main tab', (
    tester,
  ) async {
    final navigation = DunesNavigationController(initialScreen: 'B2');
    addTearDown(navigation.dispose);
    var aiOpenCount = 0;
    final selected = <String>[];
    await _pumpBar(
      tester,
      navigation: navigation,
      onOpenAi: () => aiOpenCount++,
      onSwitchMainTab: selected.add,
    );

    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(aiOpenCount, 1);
    expect(selected, isEmpty);
    expect(navigation.history, ['B2']);
  });

  testWidgets('main tabs retain their routes and clear child pages on return', (
    tester,
  ) async {
    final navigation = DunesNavigationController();
    addTearDown(navigation.dispose);
    await _pumpBar(tester, navigation: navigation);

    for (final entry in _mainTabs.entries) {
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(navigation.currentScreen, entry.value);
    }

    navigation.go('MM-L');
    navigation.go('MM0');
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(navigation.currentScreen, 'B2');
    expect(navigation.history, isNot(contains('MM-L')));
    expect(navigation.history, isNot(contains('MM0')));
  });

  testWidgets('chat-only users see communication and profile only', (
    tester,
  ) async {
    final navigation = DunesNavigationController();
    final commUnread = CommUnreadNotifier()..update(2);
    final workbenchBadge = WorkbenchBadgeNotifier()..update(3);
    addTearDown(navigation.dispose);
    addTearDown(commUnread.dispose);
    addTearDown(workbenchBadge.dispose);
    await _pumpBar(
      tester,
      navigation: navigation,
      chatOnlyMode: true,
      commUnread: commUnread,
      workbenchBadge: workbenchBadge,
    );

    expect(find.text('AI'), findsNothing);
    expect(find.text('饕'), findsNothing);
    expect(find.text('灯塔'), findsNothing);
    expect(find.text('工作台'), findsNothing);
    expect(find.text('通讯'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(_unreadDots(), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(navigation.currentScreen, 'B2');
  });

  testWidgets('desktop rail keeps workbench and does not add mobile AI', (
    tester,
  ) async {
    final navigation = DunesNavigationController();
    addTearDown(navigation.dispose);
    await _pumpBar(
      tester,
      navigation: navigation,
      axis: Axis.vertical,
      size: const Size(1024, 768),
    );

    expect(find.text('AI'), findsNothing);
    expect(find.text('工作台'), findsOneWidget);
    for (final label in _mainTabs.keys) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('工作台'));
    await tester.pumpAndSettle();
    expect(navigation.currentScreen, 'QJA');
    expect(tester.takeException(), isNull);
  });

  testWidgets('communication and pending approval badges remain reactive', (
    tester,
  ) async {
    final navigation = DunesNavigationController();
    final commUnread = CommUnreadNotifier();
    final workbenchBadge = WorkbenchBadgeNotifier();
    addTearDown(navigation.dispose);
    addTearDown(commUnread.dispose);
    addTearDown(workbenchBadge.dispose);
    await _pumpBar(
      tester,
      navigation: navigation,
      commUnread: commUnread,
      workbenchBadge: workbenchBadge,
    );

    expect(_unreadDots(), findsNothing);
    commUnread.update(2);
    workbenchBadge.update(3);
    await tester.pump();
    expect(_unreadDots(), findsNWidgets(2));

    commUnread.update(0);
    await tester.pump();
    expect(_unreadDots(), findsOneWidget);
    expect(
      tester.getCenter(_unreadDots()).dx,
      greaterThan(tester.getCenter(find.text('灯塔')).dx),
    );

    workbenchBadge.update(0);
    await tester.pump();
    expect(_unreadDots(), findsNothing);
  });

  testWidgets('APP list bottom padding clears the floating nav overlay', (
    tester,
  ) async {
    const size = Size(390, 844);
    const bottomInset = 34.0;
    late double padding;
    late double overlay;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: size,
          padding: EdgeInsets.only(bottom: bottomInset),
          viewPadding: EdgeInsets.only(bottom: bottomInset),
        ),
        child: Builder(
          builder: (context) {
            overlay = dunesAppBottomNavOverlayExtent(
              context,
              appOverlay: true,
            );
            padding = dunesAppBottomNavContentPadding(
              context,
              fallback: 14,
              appOverlay: true,
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(overlay, kDunesAppBottomNavStackHeight + bottomInset);
    expect(
      padding,
      kDunesAppBottomNavStackHeight +
          bottomInset +
          kDunesAppBottomNavContentGap,
    );
    expect(padding, greaterThan(overlay));
    expect(
      dunesAppBottomNavContentPadding(
        tester.element(find.byType(SizedBox)),
        fallback: 14,
        appOverlay: false,
      ),
      14,
    );
  });
}
