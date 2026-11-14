import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/contacts/contact_models.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_service.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_templates_page.dart';
import 'package:flutter/gestures.dart';
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
    await tester.enterText(
      find.byKey(const ValueKey('hr-template-name')),
      '财务模板',
    );
    await tester.tap(find.text('添加指标'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hr-option-a')));
    await tester.tap(find.text('确认选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑模板指标'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('hr-band-max-0')), '90');
    await tester.enterText(
      find.byKey(const ValueKey('hr-band-description-0')),
      '本模板专属标准',
    );
    await tester.tap(find.byTooltip('完成模板指标编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('考核表预览'));
    await tester.pumpAndSettle();
    expect(find.text('本模板专属标准'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭考核表预览'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hr-template-departments')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('财务部'));
    await tester.tap(find.text('确认选择'));
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
    expect(find.byKey(const ValueKey('hr-template-name')), findsOneWidget);
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

  testWidgets('同一维度下多项指标可排序并预览考核表', (tester) async {
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = GroupedTemplateService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HrPerformanceTemplatesPage(
            session: session,
            service: service,
            onBack: () {},
            loadContacts: () async => const ContactOrgData(
              total: 0,
              departments: [],
              searchItems: [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('运营主管'));
    await tester.pumpAndSettle();
    expect(find.text('核心达成'), findsOneWidget);
    expect(find.text('协同能力'), findsOneWidget);
    expect(find.text('2 个指标'), findsOneWidget);
    expect(find.text('1 个指标'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('制券保供')).dy <
          tester.getTopLeft(find.text('日清月结')).dy,
      isTrue,
    );
    expect(
      tester.getTopLeft(find.text('核心达成')).dy <
          tester.getTopLeft(find.text('协同能力')).dy,
      isTrue,
    );

    final indicatorFrom = tester.getCenter(
      find.byKey(const ValueKey('hr-template-item-drag-coupon')),
    );
    final indicatorTo = tester.getCenter(
      find.byKey(const ValueKey('hr-template-item-drag-settle')),
    );
    final indicatorDrag = await tester.startGesture(indicatorFrom);
    await tester.pump(kPressTimeout);
    await indicatorDrag.moveBy(const Offset(0, 20));
    await tester.pump();
    await indicatorDrag.moveBy(
      Offset(0, indicatorTo.dy - indicatorFrom.dy + 24),
    );
    await tester.pump();
    await indicatorDrag.up();
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('日清月结')).dy <
          tester.getTopLeft(find.text('制券保供')).dy,
      isTrue,
    );

    final dimensionFrom = tester.getCenter(
      find.byKey(const ValueKey('hr-template-dimension-drag-核心达成')),
    );
    final dimensionTo = tester.getCenter(
      find.byKey(const ValueKey('hr-template-dimension-drag-协同能力')),
    );
    final dimensionDrag = await tester.startGesture(dimensionFrom);
    await tester.pump(kPressTimeout);
    await dimensionDrag.moveBy(const Offset(0, 20));
    await tester.pump();
    await dimensionDrag.moveBy(Offset(0, dimensionTo.dy - dimensionFrom.dy + 36));
    await tester.pump();
    await dimensionDrag.up();
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('协同能力')).dy <
          tester.getTopLeft(find.text('核心达成')).dy,
      isTrue,
    );

    await tester.tap(find.byTooltip('预览最终考核表'));
    await tester.pumpAndSettle();
    expect(find.text('考核维度'), findsOneWidget);
    expect(find.text('维度权重'), findsWidgets);
    expect(find.text('考核指标'), findsOneWidget);
    expect(find.text('指标权重'), findsOneWidget);
    expect(find.text('评分标准'), findsOneWidget);
    expect(find.text('沟通及时，信息透明'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭考核表预览'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('保存模板'));
    await tester.tap(find.text('保存模板'));
    await tester.pumpAndSettle();
    final saved = (service.saved!.single['items'] as List)
        .map((item) => (item as Map)['indicatorId'])
        .toList();
    expect(saved, ['talk', 'settle', 'coupon']);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}

class GroupedTemplateService extends HrPerformanceService {
  GroupedTemplateService() : super(session);
  List<Map<String, dynamic>>? saved;
  final indicators = <Map<String, dynamic>>[
    {
      'id': 'coupon',
      'name': '制券保供',
      'project': '核心达成',
      'weight': 50,
      'enabled': true,
      'bands': [
        {'min': 40, 'max': 50, 'description': '全月无主观断券'},
      ],
    },
    {
      'id': 'settle',
      'name': '日清月结',
      'project': '核心达成',
      'weight': 20,
      'enabled': true,
      'bands': [
        {'min': 15, 'max': 20, 'description': '月结按期闭环'},
      ],
    },
    {
      'id': 'talk',
      'name': '沟通合作',
      'project': '协同能力',
      'weight': 30,
      'enabled': true,
      'bands': [
        {'min': 24, 'max': 30, 'description': '沟通及时，信息透明'},
      ],
    },
  ];

  @override
  Future<Map<String, dynamic>> templates() async => {
    'version': 1,
    'indicators': indicators,
    'templates': [
      {
        'id': 'ops',
        'name': '运营主管',
        'enabled': false,
        'scoreMode': 'direct',
        'priority': 10,
        'keywords': <String>[],
        'departmentIds': <int>[],
        'userIds': <int>[],
        'items': [
          for (final indicator in indicators)
            {'indicatorId': indicator['id'], 'weight': indicator['weight']},
        ],
      },
    ],
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
