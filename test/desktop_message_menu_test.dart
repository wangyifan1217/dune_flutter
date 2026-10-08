import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/chat/desktop_message_menu.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

void main() {
  testWidgets('desktop menu returns original action and keeps all options', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: DunesTheme.desktop(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDesktopMessageMenu(context, const [
                  DesktopMessageMenuItem(
                    id: 'copy',
                    label: '复制',
                    icon: Icons.copy,
                  ),
                  DesktopMessageMenuItem(
                    id: 'reveal_file',
                    label: '打开文件夹',
                    icon: Icons.folder_open,
                  ),
                  DesktopMessageMenuItem(
                    id: 'recall',
                    label: '撤回',
                    icon: Icons.undo,
                  ),
                ], anchor: const Offset(780, 580));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('撤回'), findsOneWidget);
    expect(find.byType(PopupMenuDivider), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('打开文件夹'));
    await tester.pumpAndSettle();
    expect(result, 'reveal_file');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('撤回'), findsNothing);
  });
}
