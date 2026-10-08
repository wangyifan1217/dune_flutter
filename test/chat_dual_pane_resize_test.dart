import 'package:dunes_app/features/conversation/chat_dual_pane_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const listKey = Key('list');
const chatKey = Key('chat');
const dividerKey = ValueKey('desktop-conversation-divider');
const prefKey = 'dunes_desktop_conversation_width_v1';

Future<void> pumpShell(
  WidgetTester tester, {
  double width = 1024,
  TargetPlatform platform = TargetPlatform.windows,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  await tester.binding.setSurfaceSize(Size(width, 680));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatDualPaneShell(
          sideRail: const SizedBox(width: 64),
          listPane: const SizedBox(key: listKey),
          chatPane: const _DraftPane(key: chatKey),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _DraftPane extends StatefulWidget {
  const _DraftPane({super.key});
  @override
  State<_DraftPane> createState() => _DraftPaneState();
}

class _DraftPaneState extends State<_DraftPane> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: TextField(controller: controller),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('drag preserves draft, input focus, pane state and saves width', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpShell(tester);
    expect(tester.getSize(find.byKey(listKey)).width, 320);
    await tester.enterText(find.byType(TextField), '未发送草稿');
    final state = tester.state(find.byKey(chatKey));
    final focus = FocusManager.instance.primaryFocus;
    await tester.drag(find.byKey(dividerKey), const Offset(70, 0));
    await tester.pumpAndSettle();
    final width = tester.getSize(find.byKey(listKey)).width;
    expect(width, greaterThan(320));
    expect(tester.state(find.byKey(chatKey)), same(state));
    expect(find.text('未发送草稿'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(focus));
    expect((await SharedPreferences.getInstance()).getDouble(prefKey), width);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'saved width restores; drag limits and smaller window protect chat',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({prefKey: 410.0});
      await pumpShell(tester);
      expect(tester.getSize(find.byKey(listKey)).width, 410);
      await tester.drag(find.byKey(dividerKey), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(listKey)).width, 440);
      await tester.binding.setSurfaceSize(const Size(800, 680));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(chatKey)).width,
        greaterThanOrEqualTo(400),
      );
      await tester.binding.setSurfaceSize(const Size(1024, 680));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(listKey)).width, 440);
      await tester.drag(find.byKey(dividerKey), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(listKey)).width, 260);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('keyboard resizing and double tap reset preserve default width', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpShell(tester);
    final dividerFocus = tester
        .widget<Focus>(
          find
              .ancestor(
                of: find.byKey(dividerKey),
                matching: find.byType(Focus),
              )
              .first,
        )
        .focusNode!;
    dividerFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(listKey)).width, 336);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(listKey)).width, 320);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(dividerKey));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(dividerKey));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(listKey)).width, 320);
    expect((await SharedPreferences.getInstance()).getDouble(prefKey), 320);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'mobile keeps fixed layout and ignores saved desktop preference',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({prefKey: 440.0});
      await pumpShell(tester, platform: TargetPlatform.iOS);
      expect(find.byKey(dividerKey), findsNothing);
      expect(tester.getSize(find.byKey(listKey)).width, 320);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
