import 'package:dunes_app/features/hr_performance/hr_performance_category.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('部门按上级分层，上级本身保留为节点', () {
    final nodes = hrDepartmentNodes([
      {'id': 3, 'name': '能源组', 'parentId': 2},
      {'id': 1, 'name': '科技研发中心'},
      {'id': 2, 'name': '产业研发', 'parentId': 1},
      {'id': 4, 'name': '总裁办'},
    ]);
    expect(nodes.map((node) => node.name), ['科技研发中心', '总裁办']);
    expect(nodes.first.children.single.name, '产业研发');
    expect(nodes.first.children.single.children.single.name, '能源组');
  });
  testWidgets('选择部门时上级可单独勾选，不再拼成路径', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = HrCatalog({
      'departments': [
        {'id': 1, 'name': '科技研发中心'},
        {'id': 2, 'name': '产业研发', 'parentId': 1},
        {'id': 3, 'name': '能源组', 'parentId': 2},
      ],
      'positions': <Map<String, dynamic>>[],
    });
    Set<int>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showHrDepartmentPicker(
                  context,
                  catalog: catalog,
                  selected: {},
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('科技研发中心 / 产业研发'), findsNothing);
    expect(find.text('科技研发中心'), findsOneWidget);
    expect(find.text('产业研发'), findsOneWidget);
    expect(find.text('能源组'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hr-option-1')));
    await tester.pumpAndSettle();
    for (final id in [1, 2, 3]) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('hr-option-$id')),
          matching: find.byIcon(Icons.check_box_rounded),
        ),
        findsOneWidget,
      );
    }
    await tester.tap(find.text('确认选择'));
    await tester.pumpAndSettle();
    expect(result, {1});
    expect(tester.takeException(), isNull);
  });
  test('部门筛选匹配上下级但不匹配其他部门', () {
    final catalog = HrCatalog({
      'departments': [
        {'id': 1, 'name': '总部'},
        {'id': 2, 'name': '财务部', 'parentId': 1},
        {'id': 3, 'name': '运营部', 'parentId': 1},
      ],
      'positions': [],
    });
    final category = hrCategory({
      'mode': 'scoped',
      'departmentIds': [2],
    });
    expect(
      hrCategoryMatches(category, department: 1, catalog: catalog),
      isTrue,
    );
    expect(
      hrCategoryMatches(category, department: 3, catalog: catalog),
      isFalse,
    );
  });
  for (final width in [360.0, 1100.0]) {
    testWidgets('筛选部门岗位时保留勾选和未分类指标 $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog = HrCatalog({
        'departments': [
          {'id': 7, 'name': '财务部'},
          {'id': 8, 'name': '运营中心'},
        ],
        'positions': [
          {'id': 11, 'name': '出纳'},
          {'id': 12, 'name': '运营专员'},
        ],
        'assessmentCategories': ['出纳序列', '运营序列（制券）'],
      });
      final indicators = <Map<String, dynamic>>[
        {
          'id': 'a',
          'name': '付款核对',
          'project': '成果',
          'weight': 50,
          'enabled': true,
          'instructions': '检查付款准确性',
          'category': {
            'mode': 'scoped',
            'departmentIds': [7],
            'categoryNames': ['出纳序列'],
          },
        },
        {
          'id': 'b',
          'name': '运营汇总',
          'project': '成果',
          'weight': 50,
          'enabled': true,
          'category': {
            'mode': 'scoped',
            'departmentIds': [8],
            'categoryNames': ['运营序列（制券）'],
          },
        },
        {
          'id': 'c',
          'name': '共同协作',
          'project': '协作',
          'weight': 10,
          'enabled': true,
          'category': {'mode': 'common'},
        },
        {
          'id': 'd',
          'name': '历史指标',
          'project': '成果',
          'weight': 10,
          'enabled': true,
        },
      ];
      Set<String>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showHrIndicatorPicker(
                    context,
                    catalog: catalog,
                    indicators: indicators,
                    selected: {},
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hr-option-b')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部部门'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('财务部'));
      await tester.pumpAndSettle();
      expect(find.text('付款核对'), findsOneWidget);
      expect(find.text('运营汇总'), findsNothing);
      expect(find.text('共同协作'), findsOneWidget);
      expect(find.text('历史指标'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hr-option-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部考核分类'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('出纳序列'));
      await tester.pumpAndSettle();
      expect(find.text('付款核对'), findsOneWidget);
      expect(find.text('已选 2 项'), findsOneWidget);
      await tester.tap(find.text('确认选择'));
      await tester.pumpAndSettle();
      expect(result, {'a', 'b'});
      expect(tester.takeException(), isNull);
    });
  }
}
