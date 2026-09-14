import 'package:dunes_app/features/qianji/supervise_sort_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('superviseSortLabel maps known keys and falls back', () {
    expect(
      superviseSortLabel(kSessionSuperviseSortOptions, 'turns_asc'),
      '消息少→多',
    );
    expect(
      superviseSortLabel(kSessionSuperviseSortOptions, 'sessions_desc'),
      '会话多→少',
    );
    expect(
      superviseSortLabel(kKbSuperviseSortOptions, 'uploaded_desc'),
      '上传多→少',
    );
    expect(superviseSortLabel(kKbSuperviseSortOptions, 'unknown'), '文档多→少');
  });

  testWidgets('SuperviseSortMenu shows current label and options', (
    tester,
  ) async {
    var selected = 'docs_desc';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SuperviseSortMenu(
            selectedId: selected,
            options: kKbSuperviseSortOptions,
            onSelected: (id) => selected = id,
          ),
        ),
      ),
    );
    expect(find.text('文档多→少'), findsOneWidget);
    await tester.tap(find.text('文档多→少'));
    await tester.pumpAndSettle();
    expect(find.text('文档少→多'), findsOneWidget);
    expect(find.text('按姓名'), findsOneWidget);
    await tester.tap(find.text('按姓名'));
    await tester.pumpAndSettle();
    expect(selected, 'name_asc');
  });
}
