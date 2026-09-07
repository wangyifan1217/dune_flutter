import 'package:flutter/material.dart';
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
}
