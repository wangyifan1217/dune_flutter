import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/contacts/contact_models.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_service.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_templates_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final session = AuthSession(
  phone: '1',
  userId: 1,
  token: 'test',
  apiBase: 'https://example.com/api/v1',
  roles: [],
);

class TemplateService extends HrPerformanceService {
  TemplateService() : super(session);
  List<Map<String, dynamic>>? saved;
  final indicators = <Map<String, dynamic>>[
    {
      'id': 'a',
      'name': '质量',
      'project': '核心达成',
      'weight': 100,
      'enabled': true,
      'bands': [
        {'min': 80, 'max': 100, 'description': '完成'},
      ],
    },
  ];
  @override
  Future<Map<String, dynamic>> templates() async => {
    'version': 1,
    'templates': <Map<String, dynamic>>[],
    'indicators': indicators,
  };
  @override
  Future<Map<String, dynamic>> saveTemplates(
    int version,
    List<Map<String, dynamic>> data,
  ) async {
    saved = data;
    return {'version': 2, 'templates': data, 'indicators': indicators};
  }
}

void main() {
  testWidgets('模板从指标库组装并分配部门', (tester) async {
    tester.view.physicalSize = const Size(1100, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = TemplateService();
    const org = ContactOrgData(
      total: 1,
      departments: [
        NativeDepartment(
          id: 7,
          name: '财务部',
          userCount: 1,
          users: [NativeContact(userId: 5, displayName: '员工甲')],
        ),
      ],
      searchItems: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HrPerformanceTemplatesPage(
            session: session,
            service: service,
            onBack: () {},
            loadContacts: () async => org,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建模板'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '模板名称'), '财务模板');
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('核心达成 · 质量'),
          matching: find.byType(Card),
        ),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('考核表预览'), findsOneWidget);
    await tester.tap(find.byTooltip('编辑模板指标'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '最高分'), '90');
    await tester.enterText(
      find.widgetWithText(TextFormField, '评分标准'),
      '本模板专属标准',
    );
    await tester.tap(find.byTooltip('完成模板指标编辑'));
    await tester.pumpAndSettle();
    expect(find.text('本模板专属标准'), findsOneWidget);
    await tester.ensureVisible(find.text('财务部'));
    await tester.tap(find.text('财务部'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存模板'));
    await tester.tap(find.text('保存模板'));
    await tester.pumpAndSettle();
    expect(service.saved, isNotNull);
    expect(service.saved!.single['departmentIds'], [7]);
    expect((service.saved!.single['items'] as List).single['indicatorId'], 'a');
    final item = (service.saved!.single['items'] as List).single as Map;
    expect(
      ((item['snapshot'] as Map)['bands'] as List).single['description'],
      '本模板专属标准',
    );
    expect(
      ((service.indicators.single['bands'] as List).single
          as Map)['description'],
      '完成',
    );
    await tester.tap(find.byTooltip('复制模板'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '模板名称'), findsOneWidget);
    await tester.ensureVisible(find.text('保存模板'));
    await tester.tap(find.text('保存模板'));
    await tester.pumpAndSettle();
    expect(service.saved!.length, 2);
    expect(service.saved!.last['enabled'], false);
    expect(service.saved!.last['departmentIds'], isEmpty);
    expect(
      (((service.saved!.last['items'] as List).single as Map)['snapshot']
          as Map)['bands'],
      (item['snapshot'] as Map)['bands'],
    );
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
