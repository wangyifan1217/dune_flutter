import 'dart:ui' show Tristate;

import 'package:dunes_app/features/xflow/proposal_launch_config.dart';
import 'package:dunes_app/features/xflow/xflow_approval_catalog.dart';
import 'package:dunes_app/features/xflow/xflow_category_switcher.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('38 张审批模板全部进入唯一二级目录，未知模板进入其他', () {
    expect(xflowApprovalCatalogKeys, hasLength(38));
    expect(
      xflowApprovalCatalogKeys.toSet(),
      hasLength(xflowApprovalCatalogKeys.length),
    );
    expect(xflowApprovalGroupsForCategory('biz'), hasLength(5));
    expect(xflowApprovalGroupsForCategory('adm'), hasLength(5));

    expect(
      xflowApprovalGroupForTemplate('finance-invoice-request').title,
      '客户与回款',
    );
    expect(
      xflowApprovalGroupForTemplate('electronic-reimbursement').title,
      '内部费用与报销',
    );
    expect(xflowApprovalGroupForTemplate('unknown-template').title, '其他');
  });

  test('二级目录按接口实际模板计算数量并过滤空组', () {
    XflowTemplateCard template(String key, String category) =>
        XflowTemplateCard(
          templateKey: key,
          title: key,
          subtitle: '',
          endpoint: '',
          tagLabel: '',
          category: category,
        );

    final groups = xflowPopulatedApprovalGroups([
      template('sales-proposal', 'biz'),
      template('finance-invoice-request', 'biz'),
      template('new-biz-template', 'biz'),
    ], category: 'biz');

    expect(groups.map((group) => group.group.title), ['客户与回款', '其他']);
    expect(groups.map((group) => group.templates.length), [1, 1]);
    expect(
      groups.expand((group) => group.templates).map((item) => item.templateKey),
      isNot(contains('sales-proposal')),
    );
  });

  test('搜索可按二级目录名称命中模板', () {
    final templates = [
      XflowTemplateCard(
        templateKey: 'finance-invoice-request',
        title: '发票申请',
        subtitle: '增值税发票',
        endpoint: '',
        tagLabel: '',
        category: 'biz',
      ),
      XflowTemplateCard(
        templateKey: 'finance-contract-payment',
        title: '合同付款申请单',
        subtitle: '合同项下付款',
        endpoint: '',
        tagLabel: '',
        category: 'biz',
      ),
    ];

    expect(
      xflowSearchApprovalTemplates(templates, '客户与回款').single.templateKey,
      'finance-invoice-request',
    );
  });

  testWidgets('审批入口清楚区分业务与非业务并切换 category', (tester) async {
    var selected = 'biz';

    Widget app() => MaterialApp(
      home: Material(
        child: SizedBox(
          width: 390,
          height: 48,
          child: XflowApprovalCategorySwitcher(
            selectedCategory: selected,
            businessCount: 18,
            administrationCount: 20,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.pumpWidget(app());
    expect(find.text('业务审批'), findsOneWidget);
    expect(find.text('非业务审批'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('xflow-category-adm')));
    expect(selected, 'adm');
    await tester.pumpWidget(app());

    final admSemantics = tester.getSemantics(
      find.byKey(const ValueKey('xflow-category-adm')),
    );
    expect(admSemantics.flagsCollection.isSelected, Tristate.isTrue);
  });

  testWidgets('二级目录显示数量、选中状态并可切换', (tester) async {
    var selected = 'biz-initiative';
    const groups = [
      XflowPopulatedApprovalGroup.preview(
        groupId: 'biz-initiative',
        title: '业务立项',
        count: 1,
      ),
      XflowPopulatedApprovalGroup.preview(
        groupId: 'biz-payment',
        title: '经营付款',
        count: 5,
      ),
    ];

    Widget app() => MaterialApp(
      home: Material(
        child: SizedBox(
          width: 390,
          child: XflowApprovalGroupRail(
            groups: groups,
            selectedGroupId: selected,
            isAdm: false,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.pumpWidget(app());
    expect(find.text('业务立项'), findsOneWidget);
    expect(find.text('经营付款'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('xflow-group-biz-payment')));
    expect(selected, 'biz-payment');
    await tester.pumpWidget(app());
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('xflow-group-biz-payment')))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
  });

  testWidgets('390px 手机宽度下目录与模板面板无溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final templates = [
      const XflowTemplateCard(
        templateKey: 'finance-invoice-request',
        title: '发票申请',
        subtitle: '增值税专票、普票、电子发票',
        endpoint: '',
        tagLabel: '回款审批',
        category: 'biz',
      ),
      const XflowTemplateCard(
        templateKey: 'finance-receipt-request',
        title: '收据申请',
        subtitle: '非发票凭证收据开具',
        endpoint: '',
        tagLabel: '回款审批',
        category: 'biz',
      ),
    ];
    final groups = xflowPopulatedApprovalGroups(templates, category: 'biz');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const XflowApprovalCategorySwitcher(
                selectedCategory: 'biz',
                businessCount: 18,
                administrationCount: 20,
                onChanged: _ignoreCategory,
              ),
              const SizedBox(height: 12),
              XflowApprovalGroupRail(
                groups: groups,
                selectedGroupId: groups.single.id,
                isAdm: false,
                onChanged: _ignoreCategory,
              ),
              const SizedBox(height: 12),
              ProposalTemplateGroupPanel(
                title: '业务审批 / 客户与回款',
                description: '客户服务、开票与回款',
                templates: templates,
                isAdm: false,
                onOpen: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('业务审批 / 客户与回款'), findsOneWidget);
  });

  test('模板图标随后台 icon 与单据语义变化', () {
    XflowTemplateCard template({
      required String key,
      required String category,
      String icon = '',
    }) => XflowTemplateCard(
      templateKey: key,
      title: key,
      subtitle: '',
      endpoint: '',
      tagLabel: '',
      category: category,
      icon: icon,
    );

    expect(
      xflowTemplateIcon(
        template(key: 'ctrip-travel-approval', category: 'adm', icon: 'plane'),
      ),
      Icons.flight_takeoff_rounded,
    );
    expect(
      xflowTemplateIcon(
        template(key: 'finance-invoice-request', category: 'biz'),
      ),
      Icons.receipt_long_outlined,
    );
    expect(
      XflowTemplateCard.fromJson({
        'templateKey': 'admin-account-opening',
        'category': 'adm',
        'icon': 'bank',
      }).icon,
      'bank',
    );
  });
}

void _ignoreCategory(String _) {}
