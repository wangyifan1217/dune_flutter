import 'package:dunes_app/core/widgets/org_folder_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('folder display name falls back to uncategorized', () {
    const folders = [OrgFolderItem(id: 9, name: '产品资料')];
    expect(orgFolderDisplayName(null, folders), '未分类');
    expect(orgFolderDisplayName(0, folders), '未分类');
    expect(orgFolderDisplayName(9, folders), '产品资料');
    expect(orgFolderDisplayName(8, folders), '已分类');
  });

  test('folder filter query keeps all-list compatible', () {
    expect(const OrgFolderFilter.all().queryValue, isNull);
    expect(const OrgFolderFilter.uncategorized().queryValue, 'uncategorized');
    expect(const OrgFolderFilter.folder(12).queryValue, '12');
    expect(const OrgFolderFilter.all().uploadFolderId, isNull);
    expect(const OrgFolderFilter.folder(12).uploadFolderId, 12);
  });

  test('folder json reads kb and meeting counts', () {
    expect(
      OrgFolderItem.fromJson({
        'id': 3,
        'name': '合同',
        'documentCount': 4,
      }).itemCount,
      4,
    );
    expect(
      OrgFolderItem.fromJson({
        'id': 5,
        'name': '周会',
        'meetingCount': 2,
      }).itemCount,
      2,
    );
  });

  testWidgets('folder bar shows all uncategorized and create chips', (
    tester,
  ) async {
    var created = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrgFolderBar(
            folders: const [OrgFolderItem(id: 9, name: '产品资料')],
            selected: const OrgFolderFilter.all(),
            onSelected: (_) {},
            onCreate: () => created = true,
          ),
        ),
      ),
    );
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('未分类'), findsOneWidget);
    expect(find.text('产品资料'), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
    final createChip = find.widgetWithText(FilterChip, '新建');
    await tester.ensureVisible(createChip);
    await tester.tap(createChip);
    await tester.pump();
    expect(created, isTrue);
  });

  testWidgets('folder more button opens delete action', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrgFolderBar(
            folders: const [OrgFolderItem(id: 9, name: '产品资料')],
            selected: const OrgFolderFilter.all(),
            onSelected: (_) {},
            onCreate: () {},
            onDelete: (_) => deleted = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('folder-more-9')));
    await tester.pumpAndSettle();
    expect(find.textContaining('删除文件夹'), findsOneWidget);
    await tester.tap(find.textContaining('删除文件夹'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets('select bar can toggle select all', (tester) async {
    var selectAll = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: OrgFolderSelectBar(
            count: 1,
            total: 5,
            onCancel: () {},
            onMove: () {},
            onToggleSelectAll: () => selectAll = true,
          ),
        ),
      ),
    );
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(selectAll, isTrue);
  });

  testWidgets('create folder dialog can submit without disposing the field', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showOrgFolderNameDialog(context, title: '新建文件夹'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('新建文件夹'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '周会');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('新建文件夹'), findsNothing);
  });
}
