import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/kpi/kpi_scope_dialog.dart';
import 'package:dunes_app/features/kpi/workbench_kpi_service.dart';

class FakeScopeService implements WorkbenchKpiService {
  @override
  Future<List<Map<String, dynamic>>> listScopeRules() async => [
    {
      'id': 1,
      'userId': 53,
      'userName': '石淼',
      'productName': '会员套餐订阅',
      'productL3': '出行会员',
      'province': '全国',
      'validFrom': '2026-01-01',
      'validTo': '2026-12-31',
      'enabled': true,
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> listLighthouseScopeOptions() async => [
    {'productGroup': '运营商', 'productName': '会员套餐订阅', 'productL3': '加油会员'},
    {'productGroup': '运营商', 'productName': '会员套餐订阅', 'productL3': '出行会员'},
    {'province': '湖北'},
    {'channelGroup': '平安', 'channelName': '平安渠道'},
  ];
  @override
  Future<List<Map<String, dynamic>>> listScopeCatalog() async => [
    {'lighthouseL2': '会员套餐订阅', 'lighthouseL3': '加油会员'},
    {'lighthouseL2': '会员套餐订阅', 'lighthouseL3': '出行会员'},
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('管理员可查看人员及绩效任务', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: KpiScopeDialog(service: FakeScopeService())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('绩效任务设置'), findsOneWidget);
    expect(find.text('会员套餐订阅 / 出行会员'), findsOneWidget);
    expect(find.text('灯塔看数权限单独管理'), findsOneWidget);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑绩效任务'), findsOneWidget);
    expect(find.text('保存修改'), findsOneWidget);
    expect(find.text('具体业务'), findsOneWidget);
    final business = find.byType(DropdownButtonFormField<String>).at(1);
    await tester.tap(business);
    await tester.pumpAndSettle();
    expect(find.text('加油会员'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('手机可查看和编辑绩效任务', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: KpiScopeDialog(service: FakeScopeService())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('会员套餐订阅 / 出行会员'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.text('编辑绩效任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
