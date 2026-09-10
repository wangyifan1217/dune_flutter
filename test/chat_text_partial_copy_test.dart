import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/chat/chat_widgets.dart';

void main() {
  testWidgets('APP 长按文字气泡先出复制/全选/更多，不立刻打开宫格', (tester) async {
    var menuOpened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTextBubble(
            text: '你好世界可以截取一段',
            mine: false,
            selectAllOnLongPress: true,
            preferPartialTextCopy: true,
            onActionsMenu: (_, _) {
              menuOpened += 1;
            },
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(SelectableText));
    await tester.pumpAndSettle();

    expect(find.text('复制'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
    expect(menuOpened, 0);
  });

  testWidgets('更多不把长按选区带进宫格，按整条消息处理', (tester) async {
    String? passed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTextBubble(
            text: '你好世界可以截取一段',
            mine: false,
            selectAllOnLongPress: true,
            preferPartialTextCopy: true,
            onActionsMenu: (_, selected) {
              passed = selected;
            },
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(SelectableText));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();

    expect(passed, '');
  });

  testWidgets('长按文字默认全选整段', (tester) async {
    const text = '你好世界可以截取一段';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTextBubble(
            text: text,
            mine: false,
            selectAllOnLongPress: true,
            preferPartialTextCopy: true,
            onActionsMenu: (_, _) {},
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(SelectableText));
    await tester.pumpAndSettle();

    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.textEditingValue.selection.baseOffset, 0);
    expect(editable.textEditingValue.selection.extentOffset, text.length);
  });

  testWidgets('拖动选区后保持截取范围，复制当前选区', (tester) async {
    const text = '你好世界可以截取一段';
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTextBubble(
            text: text,
            mine: false,
            selectAllOnLongPress: true,
            preferPartialTextCopy: true,
            onActionsMenu: (_, _) {},
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(SelectableText));
    await tester.pumpAndSettle();

    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.userUpdateTextEditingValue(
      editable.textEditingValue.copyWith(
        selection: const TextSelection(baseOffset: 2, extentOffset: 5),
      ),
      SelectionChangedCause.drag,
    );
    await tester.pumpAndSettle();

    expect(editable.textEditingValue.selection.baseOffset, 2);
    expect(editable.textEditingValue.selection.extentOffset, 5);

    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(copied, '世界可');
  });
}
