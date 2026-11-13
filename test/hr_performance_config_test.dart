import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_library_page.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final session = AuthSession(
  phone: '1',
  userId: 1,
  token: 'test',
  apiBase: 'https://example.com/api/v1',
  roles: [],
);

class LibraryService extends HrPerformanceService {
  LibraryService({this.initial = const []}) : super(session);
  final List<Map<String, dynamic>> initial;
  List<String>? savedDimensions;
  List<Map<String, dynamic>>? saved;
  @override
  Future<Map<String, dynamic>> library() async => {
    'version': 1,
    'indicators': initial,
  };
  @override
  Future<Map<String, dynamic>> saveLibrary(
    int version,
    List<Map<String, dynamic>> indicators, {
    List<String>? dimensions,
  }) async {
    saved = indicators;
    savedDimensions = dimensions;
    return {'version': 2, 'indicators': indicators, 'dimensions': dimensions};
  }
}

void main() {
  for (final width in [360.0, 1100.0]) {
    testWidgets('工作台逐项配置评分分档 $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = LibraryService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HrPerformanceLibraryPage(session: session, service: service),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('添加维度'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '维度名称'),
        '核心达成',
      );
      await tester.tap(find.byTooltip('确认维度'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('添加指标到核心达成'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('hr-field-考核维度')),
        '核心达成',
      );
      await tester.enterText(
        find.byKey(const ValueKey('hr-field-考核指标 / 具体任务')),
        '付款准确率',
      );
      await tester.tap(find.byTooltip('添加分档'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('hr-field-最低分')), '8');
      await tester.enterText(find.byKey(const ValueKey('hr-field-最高分')), '10');
      await tester.enterText(
        find.byKey(const ValueKey('hr-field-评分标准')),
        '付款准确',
      );
      await tester.ensureVisible(find.byTooltip('完成编辑'));
      await tester.tap(find.byTooltip('完成编辑'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('保存指标库'));
      await tester.tap(find.byTooltip('保存指标库'));
      await tester.pumpAndSettle();
      expect(service.saved, isNotNull);
      expect(service.saved!.single['bands'], [
        {'min': 8.0, 'max': 10.0, 'description': '付款准确'},
      ]);
      expect(find.text('从 Excel 导入'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });
  }
  testWidgets('无评分标准时不能完成，取消不添加指标', (tester) async {
    final service = LibraryService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HrPerformanceLibraryPage(session: session, service: service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加维度'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '维度名称'), '核心达成');
    await tester.tap(find.byTooltip('确认维度'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加指标到核心达成'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('hr-field-考核维度')), '核心达成');
    await tester.enterText(
      find.byKey(const ValueKey('hr-field-考核指标 / 具体任务')),
      '准确率',
    );
    await tester.tap(find.byTooltip('完成编辑'));
    await tester.pump();
    expect(find.text('新建指标'), findsOneWidget);
    await tester.tap(find.byTooltip('取消编辑'));
    await tester.pumpAndSettle();
    expect(find.text('准确率'), findsNothing);
    expect(service.saved, isNull);
    await tester.pump(const Duration(seconds: 3));
  });
  testWidgets('旧指标按维度归组并可整体改名，空维度可保存', (tester) async {
    final service = LibraryService(
      initial: [
        {
          'id': 'a',
          'project': '核心达成',
          'name': '任务甲',
          'weight': 50,
          'instructions': '标准',
          'enabled': true,
        },
        {
          'id': 'b',
          'project': '核心达成',
          'name': '任务乙',
          'weight': 50,
          'instructions': '标准',
          'enabled': true,
        },
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HrPerformanceLibraryPage(session: session, service: service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dimension-核心达成')), findsOneWidget);
    expect(find.text('任务甲'), findsOneWidget);
    expect(find.text('任务乙'), findsOneWidget);
    await tester.tap(find.byTooltip('编辑维度核心达成'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '维度名称'), '业务成果');
    await tester.tap(find.byTooltip('确认维度'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加维度'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '维度名称'), '团队协作');
    await tester.tap(find.byTooltip('确认维度'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('保存指标库'));
    await tester.tap(find.byTooltip('保存指标库'));
    await tester.pumpAndSettle();
    expect(service.savedDimensions, ['业务成果', '团队协作']);
    expect(service.saved!.map((item) => item['project']), everyElement('业务成果'));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
