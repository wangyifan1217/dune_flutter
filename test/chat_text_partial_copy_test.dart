import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/chat/chat_widgets.dart';

void main() {
  testWidgets('APP 长按文字一次列出全部功能，不出更多', (tester) async {
    var menuOpened = 0;
    final actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTextBubble(
            text: '你好世界可以截取一段',
            mine: false,
            selectAllOnLongPress: true,
            preferPartialTextCopy: true,
            showFavorite: true,
            showPin: true,
            showMulti: true,
            onActionsMenu: (_, _) {
              menuOpened += 1;
            },
            onTextMenuAction: actions.add,
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(SelectableText));
    await tester.pumpAndSettle();

    expect(find.text('复制'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('引用'), findsOneWidget);
    expect(find.text('转发'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('多选'), findsOneWidget);
    expect(find.text('更多'), findsNothing);
    expect(menuOpened, 0);

    await tester.tap(find.text('引用'));
    await tester.pumpAndSettle();
    expect(actions, ['quote']);
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
