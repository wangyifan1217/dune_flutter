import 'dart:io';
import 'dart:ui' as ui;

import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/chat/user_avatar_widget.dart';
import 'package:dunes_app/features/contacts/contact_models.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_library_page.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_service.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_templates_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _session = AuthSession(
  phone: '1',
  userId: 1,
  token: 'test',
  apiBase: 'https://example.com/api/v1',
  roles: [],
  hrPerformanceHrAccess: true,
);
const _captureKey = Key('hr-config-preview');
const _org = ContactOrgData(
  total: 2,
  searchItems: [],
  departments: [
    NativeDepartment(
      id: 7,
      name: '财务部',
      userCount: 1,
      users: [
        NativeContact(
          userId: 5,
          displayName: '示例财务人员',
          department: '财务部',
          avatarPreset: 'cartoon-01',
        ),
      ],
    ),
    NativeDepartment(
      id: 8,
      name: '运营中心',
      userCount: 1,
      users: [
        NativeContact(userId: 6, displayName: '示例运营人员', department: '运营中心'),
      ],
    ),
  ],
);

class _Service extends HrPerformanceService {
  _Service() : super(_session);
  List<Map<String, dynamic>>? savedIndicators, savedTemplates;
  final indicators = <Map<String, dynamic>>[
    {
      'id': 'target',
      'name': '目标完成度',
      'project': '工作业绩',
      'weight': 60,
      'instructions': '参考本人负责主任务的按期完成率；主管结合证据评分',
      'taskSuggestion': true,
      'enabled': true,
    },
    {
      'id': 'quality',
      'name': '工作质量',
      'project': '工作业绩',
      'weight': 20,
      'instructions': '核对网银付款与交付质量，差错记录留痕',
      'enabled': true,
      'bands': [
        {'min': 15, 'max': 20, 'description': '到账及时，付款信息准确，复核记录完整'},
      ],
    },
    {
      'id': 'collaboration',
      'name': '协作与责任',
      'project': '工作表现',
      'weight': 20,
      'instructions': '根据协作、责任及反馈记录评分',
      'enabled': true,
    },
  ];
  List<Map<String, dynamic>> get initialTemplates => [
    {
      'id': 'finance',
      'name': '财务管理',
      'enabled': true,
      'scoreMode': '',
      'priority': 100,
      'keywords': ['会计', '出纳'],
      'departmentIds': [7],
      'userIds': [],
      'items': [
        for (final i in indicators)
          {'indicatorId': i['id'], 'weight': i['weight']},
      ],
    },
    {
      'id': 'operations',
      'name': '运营管理',
      'enabled': true,
      'priority': 100,
      'keywords': ['运营经理'],
      'departmentIds': [8],
      'userIds': [],
      'items': [
        {'indicatorId': 'target', 'weight': 100},
      ],
    },
  ];
  @override
  Future<Map<String, dynamic>> library() async => {
    'version': 1,
    'indicators': indicators,
  };
  @override
  Future<Map<String, dynamic>> saveLibrary(
    int version,
    List<Map<String, dynamic>> data, {
    List<String>? dimensions,
  }) async {
    savedIndicators = data;
    return {'version': 2, 'indicators': data, 'dimensions': dimensions};
  }

  @override
  Future<Map<String, dynamic>> templates() async => {
    'version': 1,
    'templates': initialTemplates,
    'indicators': indicators,
  };
  @override
  Future<Map<String, dynamic>> saveTemplates(
    int version,
    List<Map<String, dynamic>> data,
  ) async {
    savedTemplates = data;
    return {'version': 2, 'templates': data, 'indicators': indicators};
  }
}

Future<void> _mount(
  WidgetTester tester,
  Widget page,
  double width, {
  double height = 1100,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? DunesTheme.light(),
        home: Scaffold(body: page),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (Platform.environment['DUNES_CAPTURE_PREVIEWS'] != '1') return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final raster = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('../tmp/hr-performance-previews')
      ..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    raster.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['DUNES_CAPTURE_PREVIEWS'] != '1') return;
    for (final (family, asset) in const [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ('Geist', 'assets/fonts/Geist-Regular.ttf'),
      ('Noto Sans SC', 'assets/fonts/NotoSansSC-Regular.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });
  for (final width in [360.0, 1100.0]) {
    testWidgets('指标搜索按维度、说明、分档匹配且保留全部草稿 $width', (tester) async {
      final service = _Service();
      await _mount(
        tester,
        HrPerformanceLibraryPage(session: _session, service: service),
        width,
      );
      final search = find.byKey(const ValueKey('hr-library-search'));
      await tester.enterText(search, '到账及时');
      await tester.pumpAndSettle();
      expect(find.text('工作质量'), findsOneWidget);
      expect(find.text('目标完成度'), findsNothing);
      expect(find.text('找到 1 / 3 个指标'), findsOneWidget);
      await tester.tap(find.byTooltip('编辑指标'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('hr-field-考核指标 / 具体任务')),
        '付款核对质量',
      );
      await tester.ensureVisible(find.byTooltip('完成编辑'));
      await tester.tap(find.byTooltip('完成编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(search, '网银 付款');
      await tester.pumpAndSettle();
      expect(find.text('付款核对质量'), findsOneWidget);
      await tester.enterText(search, '工作表现');
      await tester.pumpAndSettle();
      expect(find.text('协作与责任'), findsOneWidget);
      expect(find.text('付款核对质量'), findsNothing);
      await tester.enterText(search, '没有这个指标');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的指标或维度，试试其他关键词'), findsOneWidget);
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('付款核对质量'));
      expect(find.text('付款核对质量'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('保存指标库'));
      await tester.tap(find.byTooltip('保存指标库'));
      await tester.pumpAndSettle();
      expect(service.savedIndicators, hasLength(3));
      expect(
        service.savedIndicators!.any((i) => i['name'] == '付款核对质量'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
    });
    testWidgets('模板搜索和指标筛选保留完整模板 $width', (tester) async {
      final service = _Service();
      await _mount(
        tester,
        HrPerformanceTemplatesPage(
          session: _session,
          service: service,
          onBack: () {},
          loadContacts: () async => _org,
        ),
        width,
      );
      await tester.enterText(
        find.byKey(const ValueKey('hr-template-search')),
        '财务部',
      );
      await tester.pumpAndSettle();
      expect(find.text('财务管理'), findsOneWidget);
      expect(find.text('运营管理'), findsNothing);
      await tester.tap(find.text('财务管理'));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('hr-template-indicator-search'));
      await tester.enterText(search, '到账及时');
      await tester.pumpAndSettle();
      expect(find.text('工作质量'), findsOneWidget);
      expect(find.text('目标完成度'), findsNothing);
      expect(find.text('指标权重合计：100.0%'), findsOneWidget);
      await tester.tap(find.byTooltip('清空指标搜索'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('hr-template-item-collaboration')),
          matching: find.byTooltip('移出模板'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('协作与责任'), findsNothing);
      await tester.tap(find.text('添加指标'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('hr-config-picker-search')),
        '工作表现',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hr-option-collaboration')));
      await tester.tap(find.text('确认选择'));
      await tester.pumpAndSettle();
      await tester.enterText(search, '网银');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存模板'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存模板'));
      await tester.pumpAndSettle();
      expect(service.savedTemplates, hasLength(2));
      expect(service.savedTemplates!.first['items'], hasLength(3));
      expect(service.savedTemplates!.first['departmentIds'], [7]);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
    });
  }
  for (final dark in [false, true]) {
    testWidgets('模板弹层取消、计分下拉和保存交互 ${dark ? '深色桌面' : '手机'}', (tester) async {
      final service = _Service();
      await _mount(
        tester,
        HrPerformanceTemplatesPage(
          session: _session,
          service: service,
          onBack: () {},
          loadContacts: () async => _org,
        ),
        dark ? 1100 : 360,
        height: dark ? 900 : 844,
        theme: dark ? DunesTheme.dark() : DunesTheme.light(),
      );
      await tester.tap(find.text('财务管理'));
      await tester.pumpAndSettle();
      if (dark) {
        final pageMaterial = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(HrPerformanceTemplatesPage),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(pageMaterial.color!.computeLuminance(), lessThan(.2));
        final inputContext = tester.element(
          find.byKey(const ValueKey('hr-template-name')),
        );
        expect(
          Theme.of(
            inputContext,
          ).inputDecorationTheme.fillColor!.computeLuminance(),
          lessThan(.2),
        );
      }
      await _capture(
        tester,
        dark ? 'template-editor-dark' : 'template-editor-phone',
      );
      await tester.enterText(
        find.byKey(const ValueKey('hr-template-name')),
        '财务模板修改',
      );
      await tester.tap(find.byKey(const ValueKey('hr-template-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '按指标分值直接计分'));
      await tester.pumpAndSettle();
      expect(find.text('保存模板').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('返回模板列表'));
      await tester.pumpAndSettle();
      expect(find.text('放弃本次修改？'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(find.text('财务模板修改'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('hr-template-users')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hr-template-users')));
      await tester.pumpAndSettle();
      final avatar = tester.widget<ImUserAvatar>(
        find.byKey(const ValueKey('hr-picker-avatar-5')),
      );
      expect(avatar.avatarPreset, 'cartoon-01');
      expect(avatar.avatarService, isNotNull);
      expect(avatar.seed, 5);
      final fallback = tester.widget<ImUserAvatar>(
        find.byKey(const ValueKey('hr-picker-avatar-6')),
      );
      expect(fallback.initial, '示');
      expect(fallback.avatarObjectKey, isNull);
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const ValueKey('hr-option-5')))
            .controlAffinity,
        ListTileControlAffinity.trailing,
      );
      await _capture(
        tester,
        dark ? 'template-people-avatars-dark' : 'template-people-avatars-phone',
      );
      await tester.tap(find.byKey(const ValueKey('hr-option-5')));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hr-template-users')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const ValueKey('hr-option-5')))
            .value,
        isFalse,
      );
      await tester.enterText(
        find.byKey(const ValueKey('hr-config-picker-search')),
        '财务',
      );
      await tester.pumpAndSettle();
      if (!dark) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(find.text('确认选择').hitTestable(), findsOneWidget);
        await _capture(tester, 'template-picker-phone');
      }
      await tester.tap(find.byKey(const ValueKey('hr-option-5')));
      await tester.tap(find.text('确认选择'));
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存模板'));
      await tester.pumpAndSettle();
      expect(service.savedTemplates!.first['userIds'], [5]);
      expect(service.savedTemplates!.first['name'], '财务模板修改');
      expect(service.savedTemplates!.first['scoreMode'], 'direct');
      expect(service.savedTemplates!.first['items'], hasLength(3));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
    });
  }
  testWidgets('模板配置真实页面预览', (tester) async {
    final service = _Service();
    await _mount(
      tester,
      HrPerformanceLibraryPage(session: _session, service: service),
      1100,
      height: 1000,
    );
    expect(find.text('考核模板'), findsOneWidget);
    await _capture(tester, 'indicator-library-search');
    await _mount(
      tester,
      HrPerformanceTemplatesPage(
        session: _session,
        service: service,
        onBack: () {},
        loadContacts: () async => _org,
      ),
      1100,
      height: 900,
    );
    await _capture(tester, 'template-list');
    await tester.tap(find.text('财务管理'));
    await tester.pumpAndSettle();
    await _capture(tester, 'template-editor');
    await tester.tap(find.byKey(const ValueKey('hr-template-departments')));
    await tester.pumpAndSettle();
    await _capture(tester, 'template-department-picker');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑模板指标').first);
    await tester.pumpAndSettle();
    await _capture(tester, 'template-indicator-editor');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hr-template-mode')));
    await tester.pumpAndSettle();
    await _capture(tester, 'template-mode-menu');
    await tester.tap(find.widgetWithText(MenuItemButton, '百分制加权计分'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('考核表预览'));
    await tester.pumpAndSettle();
    await _capture(tester, 'template-sheet-preview');
    await tester.tap(find.byTooltip('关闭考核表预览'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
