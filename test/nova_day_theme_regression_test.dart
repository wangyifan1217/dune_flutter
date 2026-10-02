import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/nova/nova_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/pre_easter_eggs_day_theme.dart';

void main() {
  test('all Material day styles match the theme before the egg adaptation', () {
    // The palette extension only supplies semantic tokens; it does not style
    // Material widgets. Every other ThemeData property must equal the original.
    expect(
      DunesTheme.light().copyWith(extensions: const []),
      PreEggsDayTheme.light(),
    );
  });

  testWidgets('Nova pill stays unfilled and borderless across day/night', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    var sends = 0;
    Widget page(ThemeData theme, {bool voice = false}) => MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: NovaC4InputBar(
            controller: controller,
            focusNode: focus,
            voiceMode: voice,
            sending: false,
            enabled: true,
            hintText: kNovaInputPlaceholder,
            modelLabel: 'GPT',
            quickActionsOpen: false,
            onToggleVoice: () {},
            onSend: () => sends++,
            onPickModel: () {},
            onInputFocused: () {},
            onToggleQuickActions: () {},
            onOpenKb: () {},
            onOpenMeeting: () {},
            onVoiceCall: () {},
          ),
        ),
      ),
    );

    void checkEditor({required bool day}) {
      final editor = tester.widget<TextField>(find.byType(TextField));
      final decoration = tester
          .widget<InputDecorator>(find.byType(InputDecorator))
          .decoration;
      expect(decoration.filled, isFalse);
      expect(decoration.border, InputBorder.none);
      expect(decoration.enabledBorder, InputBorder.none);
      expect(decoration.focusedBorder, InputBorder.none);
      expect(decoration.disabledBorder, InputBorder.none);
      expect(
        decoration.contentPadding,
        const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      );
      expect(editor.style!.fontSize, 14.5);
      expect(editor.minLines, 1);
      expect(editor.maxLines, 4);
      final pill = tester
          .widgetList<Container>(
            find.ancestor(
              of: find.byType(TextField),
              matching: find.byType(Container),
            ),
          )
          .map((widget) => widget.decoration)
          .whereType<BoxDecoration>()
          .first;
      expect(pill.borderRadius, BorderRadius.circular(30));
      if (day) {
        expect(editor.style!.color, const Color(0xFF1D2129));
        expect(decoration.hintStyle!.color, const Color(0xFF86909C));
        expect(pill.color, Colors.white);
        expect((pill.border! as Border).top.color, const Color(0xFFEDEFF5));
      } else {
        expect(pill.color, DunesPalette.night.surface);
        expect(editor.style!.color!.computeLuminance(), greaterThan(.5));
      }
    }

    await tester.pumpWidget(page(PreEggsDayTheme.light()));
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byType(TextField));
    checkEditor(day: true);
    await tester.pumpWidget(page(DunesTheme.light()));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(TextField)), before);
    checkEditor(day: true);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    checkEditor(day: true);
    await tester.enterText(find.byType(TextField), '测试小饕');
    await tester.pumpAndSettle();
    checkEditor(day: true);
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    expect(sends, 1);

    await tester.pumpWidget(page(DunesTheme.dark()));
    await tester.pumpAndSettle();
    checkEditor(day: false);
    expect(controller.text, '测试小饕');
    await tester.pumpWidget(page(DunesTheme.light()));
    await tester.pumpAndSettle();
    checkEditor(day: true);
    expect(controller.text, '测试小饕');

    await tester.pumpWidget(page(DunesTheme.light(), voice: true));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('按住说话'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('按住说话')).style!.color,
      const Color(0xFF2E75FF),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
