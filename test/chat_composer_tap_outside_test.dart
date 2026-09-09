import 'package:dunes_app/features/chat/chat_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping blank area outside IM composer unfocuses the field', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var outsideTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Scaffold(
            body: Column(
              children: [
                const Expanded(child: ColoredBox(color: Colors.white)),
                ChatInputBar(
                  controller: controller,
                  focusNode: focus,
                  voiceMode: false,
                  voiceEnabled: false,
                  sending: false,
                  onToggleVoice: () {},
                  onSend: () {},
                  onPlus: null,
                  showMobilePlusButton: false,
                  onTapOutside: () => outsideTaps++,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.tapAt(const Offset(40, 80));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    expect(outsideTaps, 1);
  });

  testWidgets(
    'IME send restore is skipped when shouldKeepFocusAfterSend is false',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final controller = TextEditingController(text: 'hello');
      addTearDown(controller.dispose);
      var sent = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(
              body: ChatInputBar(
                controller: controller,
                focusNode: focus,
                voiceMode: false,
                voiceEnabled: false,
                sending: false,
                onToggleVoice: () {},
                onSend: () => sent = true,
                onPlus: null,
                showMobilePlusButton: false,
                shouldKeepFocusAfterSend: () => false,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(focus.hasFocus, isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(sent, isTrue);
      expect(focus.hasFocus, isFalse);
    },
  );
}
