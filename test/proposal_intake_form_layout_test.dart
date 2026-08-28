import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/proposal_intake/native_proposal_intake_page.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_select.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_service.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProposalIntakeOptions _options() => ProposalIntakeOptions.fromJson({
  'market': {
    'sectors': ['数字营销事业部', '供应链科技事业部'],
    'proposalTypes': ['新增业务提案', '存量业务续签提案'],
    'products': [
      {
        'value': '智能投放平台',
        'projects': ['华东区域智能投放项目', '华南区域智能投放项目'],
      },
    ],
    'supplies': ['头部媒体供给', '中长尾流量供给', '自有媒体供给'],
    'channels': ['直客渠道', '代理商渠道', '生态合作渠道'],
    'profitModes': ['返点差价', '服务费', '技术服务分成'],
  },
  'technology': {
    'platforms': [
      {
        'value': '数据智能平台',
        'capabilities': ['人群圈选能力', '归因分析能力'],
      },
    ],
    'outputForms': ['API 接口', '私有化部署', 'SaaS 订阅'],
    'developmentTypes': ['全新开发', '复用现有能力'],
    'financeInterfaces': [
      {'key': 'invoice', 'label': '开票接口', 'required': true},
      {'key': 'settle', 'label': '结算对账接口', 'required': false},
    ],
  },
  'finance': {
    'costItems': ['服务器成本', '人力成本', '第三方采购成本'],
    'businessCostItems': ['员工提成'],
    'businessCostRules': '员工提成按已定规则累计，提案不填发生额。',
    'operatingCostRules': '差旅、小额营销按项目收入的 2% 为阈值。',
    'rollbackOptions': ['不回滚', '按季度回滚', '按年度回滚'],
  },
  'rules': {'minimumScale': 500, 'minimumMargin': 4.5},
});

ProposalIntakeRow _row() => ProposalIntakeRow.fromJson({
  'id': 1,
  'code': 'TA-2026-0001',
  'title': '',
  'status': 'filling',
  'version': 3,
  'createdBy': 11,
  'form': <String, dynamic>{},
  'review': <String, dynamic>{},
});

List<ProposalPerson> _people() => [
  ProposalPerson.fromJson({
    'userId': 11,
    'displayName': '王奕凡',
    'positionName': '市场部负责人二（华东大区）',
  }),
  ProposalPerson.fromJson({
    'userId': 12,
    'displayName': '李思',
    'positionName': '科技部负责人',
  }),
  ProposalPerson.fromJson({
    'userId': 4,
    'displayName': '市场一',
    'positionName': '市场部负责人一',
  }),
];

/// 合同下拉曾因选项过长导致横向溢出，这里刻意使用超长文案。
List<ProposalContractChoice> _contracts() => [
  ProposalContractChoice.fromJson({
    'id': 91,
    'contractNo': 'CG-2026-000001',
    'contractName': '上海某某数字科技有限公司智能投放平台年度框架采购合同（含补充协议）',
    'partyA': '沙丘科技',
    'partyB': '上海某某数字科技有限公司',
  }),
];

Widget _harness(
  double width, {
  AuthSession? session,
  ProposalIntakeRow? row,
  ProposalIntakeOptions? options,
  VoidCallback? onNext,
  int nextCount = 0,
}) {
  final auth =
      session ??
      AuthSession.fromJson(const {'userId': 11, 'displayName': '王奕凡'});
  final service = ProposalIntakeService(session: auth);
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: ProposalIntakeForm(
          row: row ?? _row(),
          session: auth,
          options: options ?? _options(),
          people: _people(),
          contracts: _contracts(),
          saving: false,
          service: service,
          enableComments: false,
          onChanged: (_) {},
          onSaved: (_) {},
          onSubmit: (_) {},
          onError: (_) {},
          onNext: onNext,
          nextCount: nextCount,
        ),
      ),
    ),
  );
}

Future<void> _scrollUntil(WidgetTester tester, String label) async {
  for (var i = 0; i < 20; i++) {
    if (find.text(label).evaluate().isNotEmpty) return;
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -420),
    );
    await tester.pump();
  }
}

Finder _fieldOf(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(ProposalField));

T _childInField<T extends Widget>(WidgetTester tester, String label) {
  return tester.widget<T>(
    find
        .descendant(
          of: _fieldOf(label).first,
          matching: find.byWidgetPredicate((widget) => widget is T),
        )
        .first,
  );
}

void main() {
  for (final width in <double>[1440, 1180, 1024, 760, 420, 390]) {
    testWidgets('proposal form lays out without overflow at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(width));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact top bar shows all action buttons without clipping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        390,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'status': 'filling',
          'createdBy': 11,
          'form': {'marketOwner2UserId': 11, 'marketOwner2': '王奕凡'},
          'review': <String, dynamic>{},
        }),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('保存'), findsOneWidget);
    expect(find.byTooltip('转发'), findsOneWidget);
    expect(find.byTooltip('通知科技负责人'), findsOneWidget);
    expect(find.byTooltip('删除'), findsOneWidget);
    expect(find.byTooltip('协作提案流程'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('转发'), findsOneWidget);
    expect(tester.getSize(find.widgetWithText(OutlinedButton, '保存')).height,
        greaterThanOrEqualTo(44));
    expect(tester.getSize(find.widgetWithText(OutlinedButton, '转发')).height,
        greaterThanOrEqualTo(44));
    expect(find.text('通知科技'), findsNothing);
    expect(find.text('删除'), findsNothing);
    expect(find.text('D'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('proposal form help icon shows the collaboration process', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(1440));
    await tester.pump();

    expect(find.byTooltip('协作提案流程'), findsOneWidget);
    await tester.tap(find.byTooltip('协作提案流程'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('协作提案流程'), findsWidgets);
    expect(find.textContaining('通知科技部负责人填写科技内容'), findsOneWidget);
    expect(find.text('知道了'), findsOneWidget);
  });

  testWidgets(
    'unsaved new proposal hides server actions until content is saved',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _harness(
          1440,
          row: ProposalIntakeRow.fromJson({
            'id': 0,
            'code': '',
            'status': 'draft',
            'createdBy': 11,
            'form': {'marketOwner2UserId': 11, 'marketOwner2': '王奕凡'},
          }),
        ),
      );
      await tester.pump();

      expect(find.text('未保存'), findsOneWidget);
      expect(find.byTooltip('保存'), findsOneWidget);
      expect(find.byTooltip('转发'), findsOneWidget);
      expect(find.byTooltip('通知科技负责人'), findsNothing);
      expect(find.byTooltip('删除'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pc top bar shows proposal name and keeps locator aligned', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-20260820-000012',
          'title': 'Fintech保险分发试点',
          'status': 'pending_president',
        }),
      ),
    );
    await tester.pump();

    expect(find.text('Fintech保险分发试点'), findsWidgets);
    expect(find.text('销售业务提案'), findsNothing);
    expect(find.text('定位'), findsOneWidget);
    expect(find.text('市场部'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locked proposal shows selected options as text not all chips', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'status': 'pending_president',
          'form': {
            'supplies': ['头部媒体供给'],
            'channels': ['直客渠道'],
            'proposalName': 'Fintech保险分发试点',
          },
        }),
      ),
    );
    await tester.pump();
    await _scrollUntil(tester, '供给（标签二）');

    expect(find.text('头部媒体供给'), findsWidgets);
    expect(find.text('直客渠道'), findsWidgets);
    expect(find.text('中长尾流量供给'), findsNothing);
    expect(find.text('自有媒体供给'), findsNothing);
    expect(find.text('代理商渠道'), findsNothing);
    expect(find.byType(ProposalPills), findsNothing);
    // 最终审核 / 完成态明细需可长按选中复制。
    expect(find.byType(SelectableText), findsWidgets);
    expect(
      find.ancestor(
        of: find.text('头部媒体供给'),
        matching: find.byType(SelectableText),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed proposal detail text is selectable', (tester) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'status': 'done',
          'form': {
            'proposalName': '已完成提案名称',
            'supplies': ['头部媒体供给'],
          },
        }),
      ),
    );
    await tester.pump();
    await _scrollUntil(tester, '供给（标签二）');

    expect(
      find.ancestor(
        of: find.text('已完成提案名称'),
        matching: find.byType(SelectableText),
      ),
      findsWidgets,
    );
    expect(
      find.ancestor(
        of: find.text('头部媒体供给'),
        matching: find.byType(SelectableText),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('proposal form drops the dark chapter navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(1440));
    await tester.pump();

    expect(find.text('章节'), findsNothing);
    expect(find.text('财务复核'), findsNothing);
    expect(find.text('定位'), findsOneWidget);
  });

  testWidgets('section locator jumps to the technology block', (tester) async {
    tester.view.physicalSize = const Size(1440, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(1440));
    await tester.pump();

    final techTitle = find.text('二、科技部内容', skipOffstage: false);
    expect(techTitle, findsOneWidget);
    final before = tester.getTopLeft(techTitle).dy;
    expect(before, greaterThan(800));

    await tester.tap(find.widgetWithText(OutlinedButton, '科技部'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final after = tester.getTopLeft(techTitle).dy;
    expect(after, lessThan(before));
    expect(after, lessThan(260));
  });

  testWidgets('market owner2 is a person picker, not locked to current user', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(1440));
    await tester.pump();

    expect(find.text('市场部负责人二（科技审核）'), findsOneWidget);
    expect(find.text('市场部负责人二（填写人）'), findsNothing);
    expect(
      _childInField<ProposalSelectField<int>>(
        tester,
        '市场部负责人二（科技审核）',
      ).onSelected,
      isNotNull,
    );
  });

  testWidgets('empty proposal form has no mock values or draft wording', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(390));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('章节'), findsNothing);
    expect(find.text('保存草稿'), findsNothing);
    expect(find.byTooltip('保存'), findsWidgets);
    expect(find.text('保存'), findsWidgets);
    expect(find.text('选择合同'), findsNothing);
    expect(find.text('行政复核'), findsNothing);
    expect(find.text('财务部负责人二复核'), findsWidgets);

    Future<void> scrollUntil(String label) async {
      await _scrollUntil(tester, label);
    }

    await scrollUntil('市场部负责人二复核');
    expect(find.text('市场部负责人二复核'), findsWidgets);
    await scrollUntil('销售规模目标（万元）');
    expect(find.text('销售规模目标（万元）'), findsOneWidget);
    expect(find.text('收入（万元）'), findsOneWidget);
    expect(find.text('发票（万元）'), findsOneWidget);
    expect(find.text('财务部负责人二复核'), findsWidgets);
    await scrollUntil('提案全链路');
    expect(find.text('提案全链路'), findsWidgets);
    expect(find.text('补贴出资方'), findsNothing);
    expect(find.text('清算 / 支付机构'), findsNothing);
    expect(find.text('我方开票主体'), findsNothing);
    expect(find.text('服务 / 承接机构'), findsNothing);
    expect(find.textContaining('万里通'), findsNothing);
    expect(find.textContaining('平安（清算'), findsNothing);
    expect(find.textContaining('13% 油专'), findsNothing);
    expect(find.textContaining('6% 增专'), findsNothing);
    expect(find.text('终端用户'), findsNothing);
    expect(find.textContaining('保费'), findsNothing);
    expect(find.textContaining('用户领取'), findsNothing);
  });

  testWidgets('four-flow entity fields are hidden', (tester) async {
    tester.view.physicalSize = const Size(760, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        760,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'title': '',
          'status': 'filling',
          'version': 3,
          'createdBy': 11,
          'form': {
            'subsidyName': '是',
            'clearingName': '测试',
            'billingName': '收到',
            'serviceOrgName': '收到',
          },
          'review': <String, dynamic>{},
        }),
      ),
    );
    await tester.pump();
    await _scrollUntil(tester, '提案全链路');

    expect(tester.takeException(), isNull);
    expect(find.text('补贴出资方'), findsNothing);
    expect(find.text('清算 / 支付机构'), findsNothing);
    expect(find.text('我方开票主体'), findsNothing);
    expect(find.text('服务 / 承接机构'), findsNothing);
    expect(find.textContaining('由提交人填写；也可直接点图中节点改名'), findsNothing);
  });

  testWidgets('configured dropdown lists all options when opened', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: ProposalSelectField<String>(
              value: '能源',
              hint: '请选择或输入搜索',
              searchable: true,
              options: const [
                ProposalSelectOption(value: '能源', label: '能源'),
                ProposalSelectOption(value: '运营商', label: '运营商'),
                ProposalSelectOption(value: '公共出行', label: '公共出行'),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text('运营商'), findsOneWidget);
    expect(find.text('公共出行'), findsOneWidget);
  });

  testWidgets('people dropdown stays empty until a keyword is typed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: ProposalSelectField<int>(
              value: null,
              hint: '输入姓名或岗位搜索',
              searchable: true,
              requireKeyword: true,
              options: const [
                ProposalSelectOption(value: 11, label: '王奕凡', meta: '市场部负责人二'),
                ProposalSelectOption(value: 12, label: '李思', meta: '科技部负责人'),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: ProposalSelectField<int>(
              value: selected,
              hint: '输入姓名或岗位搜索',
              searchable: true,
              requireKeyword: true,
              options: const [
                ProposalSelectOption(value: 11, label: '王奕凡', meta: '市场部负责人二'),
                ProposalSelectOption(value: 12, label: '李思', meta: '科技部负责人'),
              ],
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text('王奕凡'), findsNothing);
    expect(find.text('李思'), findsNothing);
    final field = tester.getRect(find.byType(TextField));
    final menu = tester.getRect(
      find.byKey(const ValueKey('proposal-select-menu')),
    );
    expect(menu.top, greaterThanOrEqualTo(field.bottom));
    expect(menu.width, closeTo(field.width, 1));

    await tester.enterText(find.byType(TextField), '王');
    await tester.pumpAndSettle();

    expect(find.text('王奕凡'), findsOneWidget);
    expect(find.text('李思'), findsNothing);

    await tester.tap(find.text('王奕凡'));
    await tester.pumpAndSettle();
    expect(selected, 11);
  });

  testWidgets('remote contract options skip local keyword filtering', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: ProposalSelectField<int>(
              value: null,
              hint: '输入合同编号、名称或对方主体搜索',
              searchable: true,
              requireKeyword: true,
              remoteOptions: true,
              options: const [ProposalSelectOption(value: 91, label: '年度框架协议')],
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'CG-2020');
    await tester.pumpAndSettle();

    expect(find.text('年度框架协议'), findsOneWidget);
  });

  testWidgets('remote contract overlay survives parent option updates', (
    tester,
  ) async {
    var options = const <ProposalSelectOption<int>>[];
    late StateSetter setOuter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: StatefulBuilder(
              builder: (context, setState) {
                setOuter = setState;
                return ProposalSelectField<int>(
                  value: null,
                  hint: '输入合同编号、名称或对方主体搜索',
                  searchable: true,
                  requireKeyword: true,
                  remoteOptions: true,
                  options: options,
                  onQueryChanged: (_) {},
                  onSelected: (_) {},
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'CG');
    await tester.pumpAndSettle();

    setOuter(() {
      options = const [ProposalSelectOption(value: 91, label: '年度框架协议')];
    });
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('年度框架协议'), findsOneWidget);
  });

  testWidgets('finance interface chips start unselected on an empty form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(1440));
    await tester.pump();

    for (var i = 0; i < 20; i++) {
      if (find.text('开票接口 *').evaluate().isNotEmpty) break;
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -420),
      );
      await tester.pump();
    }

    final chip = tester.widget<ProposalChoiceChip>(
      find.widgetWithText(ProposalChoiceChip, '开票接口 *'),
    );
    expect(chip.selected, isFalse);
    expect(
      find.ancestor(
        of: find.widgetWithText(ProposalChoiceChip, '开票接口 *'),
        matching: find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ProposalChoiceChip>(
            find.widgetWithText(ProposalChoiceChip, '结算对账接口'),
          )
          .selected,
      isFalse,
    );
  });

  testWidgets('market filler can edit market fields but not tech fill fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(1440));
    await tester.pump();

    expect(
      _childInField<ProposalSelectField<String>>(tester, '业务板块').onSelected,
      isNotNull,
    );

    await _scrollUntil(tester, '科技部负责人（填写人）');
    expect(find.text('请指定科技部负责人。技术字段由对方填写，市场部负责人二做逐条复核。'), findsOneWidget);
    expect(
      _childInField<ProposalSelectField<int>>(tester, '科技部负责人（填写人）').onSelected,
      isNotNull,
    );

    await _scrollUntil(tester, '交付时间');
    expect(
      tester
          .widget<InkWell>(find.byKey(const ValueKey('date-deliveryDate')))
          .onTap,
      isNull,
    );
    expect(
      _childInField<ProposalSelectField<String>>(tester, 'τ-标签一').onSelected,
      isNull,
    );
  });

  testWidgets('tech filler can edit tech fields but not market fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final session = AuthSession.fromJson(const {
      'userId': 12,
      'displayName': '李思',
    });
    final row = ProposalIntakeRow.fromJson({
      'id': 1,
      'code': 'TA-2026-0001',
      'title': '',
      'status': 'filling',
      'version': 3,
      'createdBy': 11,
      'form': {
        'marketOwner2': '王奕凡',
        'marketOwner2UserId': 11,
        'technologyOwner': '李思',
        'technologyOwnerUserId': 12,
      },
      'review': <String, dynamic>{},
    });

    await tester.pumpWidget(_harness(1440, session: session, row: row));
    await tester.pump();

    expect(
      _childInField<ProposalSelectField<String>>(tester, '业务板块').onSelected,
      isNull,
    );
    expect(find.text('由提交人填写。当前账号不可编辑本板块。'), findsOneWidget);

    await _scrollUntil(tester, '交付时间');
    expect(
      tester
          .widget<InkWell>(find.byKey(const ValueKey('date-deliveryDate')))
          .onTap,
      isNotNull,
    );
    expect(
      _childInField<ProposalSelectField<String>>(tester, 'τ-标签一').onSelected,
      isNotNull,
    );
    expect(
      _childInField<ProposalSelectField<int>>(tester, '科技部负责人（填写人）').onSelected,
      isNull,
    );
  });

  testWidgets('market owner2 cannot edit submitter-owned market fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final session = AuthSession.fromJson(const {
      'userId': 12,
      'displayName': '李思',
    });
    final row = ProposalIntakeRow.fromJson({
      'id': 1,
      'code': 'TA-2026-0001',
      'title': '',
      'status': 'filling',
      'version': 3,
      'createdBy': 11,
      'form': {
        'marketOwner2': '李思',
        'marketOwner2UserId': 12,
        'proposalName': '智能投放试点',
      },
      'review': <String, dynamic>{},
    });

    await tester.pumpWidget(_harness(1440, session: session, row: row));
    await tester.pump();

    expect(
      _childInField<ProposalSelectField<String>>(tester, '业务板块').onSelected,
      isNull,
    );
    expect(find.text('由提交人填写。当前账号不可编辑本板块。'), findsOneWidget);
    expect(find.byTooltip('通知科技负责人'), findsNothing);
  });

  testWidgets(
    'unsigned contract shows a file picker and purchase products add',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final row = ProposalIntakeRow.fromJson({
        'id': 1,
        'code': 'TA-2026-0001',
        'title': '',
        'status': 'filling',
        'version': 3,
        'createdBy': 11,
        'form': {'purchaseMode': '未签署合同'},
        'review': <String, dynamic>{},
      });

      await tester.pumpWidget(_harness(1440, row: row));
      await tester.pump();

      await _scrollUntil(tester, '上传合同文件');
      expect(find.text('点击选择未签合同 PDF / Word'), findsOneWidget);
      expect(find.text('PDF / Word（保存至合同归集后自动解析）'), findsNothing);

      await _scrollUntil(tester, '采购产品');
      expect(find.text('采购产品'), findsOneWidget);
      expect(find.text('+ 新增'), findsWidgets);
    },
  );

  testWidgets('sales contract number stays reviewable when mode is empty', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const reviewed = {
      'sales.Mode': true,
      'sales.Name': true,
      'sales.SignDate': true,
      'sales.OurParty': true,
      'sales.Counterparty': true,
      'sales.ValidPeriod': true,
      'sales.CoreTerms': true,
    };
    final row = ProposalIntakeRow.fromJson({
      'id': 1,
      'code': 'TA-2026-0001',
      'title': '测试提案',
      'status': 'reviewing',
      'version': 3,
      'createdBy': 11,
      'form': {
        'marketOwner2': '王奕凡',
        'marketOwner2UserId': 11,
        'financeOwner2': '王奕凡',
        'financeOwner2UserId': 11,
        'salesName': '测试',
      },
      'review': {'stage': 'reviewing', 'contractItems': reviewed},
    });

    await tester.pumpWidget(_harness(1440, row: row));
    await tester.pump();
    await _scrollUntil(tester, '合同编号');

    expect(find.text('选择合同'), findsNothing);
    expect(find.text('合同编号'), findsWidgets);
    expect(find.textContaining('还差：合同编号'), findsWidgets);
    expect(find.text('行政负责人（合同审核）'), findsNothing);
    expect(find.text('指定审核人 · 无需复核'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(
              of: _fieldOf('合同编号').first,
              matching: find.widgetWithText(OutlinedButton, '财务部负责人二复核'),
            ),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('uploaded contract stays openable during review', (tester) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final row = ProposalIntakeRow.fromJson({
      'id': 1,
      'code': 'TA-2026-0001',
      'title': '测试提案',
      'status': 'reviewing',
      'version': 3,
      'createdBy': 11,
      'form': {
        'marketOwner2': '王奕凡',
        'marketOwner2UserId': 11,
        'contractAdmin': '王奕凡',
        'contractAdminUserId': 11,
        'salesMode': '未签署合同',
        'salesFileName': '销售合同.pdf',
        'salesObjectKey': 'proposals/sales-contract.pdf',
      },
      'review': {'stage': 'reviewing'},
    });

    await tester.pumpWidget(_harness(1440, row: row));
    await tester.pump();
    await _scrollUntil(tester, '上传合同文件');

    expect(find.text('销售合同.pdf'), findsOneWidget);
    expect(find.text('查看合同'), findsOneWidget);
    expect(find.text('下载合同'), findsOneWidget);
    expect(find.text('未签合同 · 可查看下载'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find
                .descendant(
                  of: _fieldOf('上传合同文件').first,
                  matching: find.byType(TextButton),
                )
                .first,
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<InkWell>(
            find
                .ancestor(
                  of: find.text('销售合同.pdf'),
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .onTap,
      isNotNull,
    );
  });

  testWidgets('new proposal shows launch files without product templates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(1440));
    await tester.pump();
    await _scrollUntil(tester, '上线产品文件');
    expect(find.text('产品模板与上线文件'), findsNothing);
    expect(find.text('产品模板'), findsNothing);
    expect(find.text('上线产品文件'), findsWidgets);
    expect(find.text('点击选择上线产品文件'), findsOneWidget);
    expect(find.text('点击上传图片 / PDF，最多 5 个'), findsNothing);
    expect(
      find.text('支持 PDF / Word / Excel / PPT，单个不超过 20MB。'),
      findsOneWidget,
    );
  });

  testWidgets('policy section hosts launch rows without channel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'title': '测试提案',
          'status': 'filling',
          'version': 3,
          'createdBy': 11,
          'form': {
            'launchRows': [
              {
                'id': 'lr-1',
                'province': '河南',
                'faceValue': '100',
                'needFinanceModule': true,
              },
            ],
          },
        }),
      ),
    );
    await tester.pump();
    await _scrollUntil(tester, '产品上线');
    expect(find.text('产品上线'), findsOneWidget);
    expect(find.text('新增上线'), findsOneWidget);
    expect(find.textContaining('不带渠道'), findsOneWidget);
    expect(find.text('产品上线表'), findsNothing);
    expect(find.text('需要财务模块'), findsOneWidget);
    expect(find.text('面值'), findsOneWidget);
    expect(find.text('待财务新增或关联模块'), findsOneWidget);
  });

  testWidgets('finance owner 2 can add modules during review', (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        session: AuthSession.fromJson(const {
          'userId': 12,
          'displayName': '李思',
        }),
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'title': '测试提案',
          'status': 'reviewing',
          'createdBy': 11,
          'form': {
            'financeOwner2': '李思',
            'financeOwner2UserId': 12,
            'launchRows': [
              {
                'id': 'lr-1',
                'province': '河南',
                'faceValue': '100',
                'needFinanceModule': true,
              },
            ],
          },
          'review': {'stage': 'reviewing'},
        }),
      ),
    );
    await tester.pump();
    await _scrollUntil(tester, '新增财务模块');
    expect(find.text('新增财务模块'), findsOneWidget);
    expect(find.text('新增上线'), findsNothing);
    expect(find.textContaining('由财务在对应行点新增或关联'), findsOneWidget);
  });

  testWidgets('uploaded product file can be viewed and downloaded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'title': '测试提案',
          'status': 'filling',
          'version': 3,
          'createdBy': 11,
          'form': {
            'marketOwner2': '王奕凡',
            'marketOwner2UserId': 11,
            'onlineProductFiles': [
              {
                'fileName': '产品说明书.pdf',
                'objectKey': 'proposals/product.pdf',
                'url': 'https://example.com/product.pdf',
              },
            ],
          },
        }),
      ),
    );
    await tester.pump();
    await _scrollUntil(tester, '上线产品文件');
    expect(find.text('产品说明书.pdf'), findsOneWidget);
    expect(find.byTooltip('查看'), findsOneWidget);
    expect(find.byTooltip('下载'), findsOneWidget);
  });

  testWidgets('submitter can delete before final review', (tester) async {
    tester.view.physicalSize = const Size(1440, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'title': '测试1',
          'status': 'reviewing',
          'createdBy': 11,
          'version': 3,
          'form': {'marketOwner2': '王奕凡', 'marketOwner2UserId': 11},
          'review': {'stage': 'reviewing'},
        }),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('删除'), findsOneWidget);
    expect(find.text('删除提案'), findsNothing);
  });

  testWidgets('submitter cannot delete after final review starts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        row: ProposalIntakeRow.fromJson({
          'id': 2,
          'code': 'TA-2026-0002',
          'title': '测试1',
          'status': 'pending_president',
          'createdBy': 11,
          'version': 3,
          'form': {'marketOwner2': '王奕凡', 'marketOwner2UserId': 11},
        }),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('删除'), findsNothing);
    expect(find.text('删除提案'), findsNothing);
  });

  testWidgets('assistant detail shows next pending footer', (tester) async {
    tester.view.physicalSize = const Size(1440, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var tapped = false;
    await tester.pumpWidget(
      _harness(
        1440,
        nextCount: 2,
        onNext: () => tapped = true,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'title': '测试1',
          'status': 'pending_president',
          'createdBy': 11,
          'version': 3,
          'form': {
            'marketOwner2': '王奕凡',
            'marketOwner2UserId': 11,
            'presidentUserId': 11,
          },
        }),
      ),
    );
    await tester.pump();
    expect(find.text('下一个'), findsOneWidget);
    await tester.tap(find.text('下一个'));
    expect(tapped, isTrue);
  });

  testWidgets('mobile president sees large labeled confirm and reject', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        390,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'title': 'Fintech保险分发试点',
          'status': 'pending_president',
          'createdBy': 11,
          'form': {'presidentUserId': 11, 'president': '王奕凡'},
        }),
      ),
    );
    await tester.pump();

    final approve = find.byKey(const ValueKey('proposal-president-approve'));
    final reject = find.byKey(const ValueKey('proposal-president-reject'));
    expect(approve, findsOneWidget);
    expect(reject, findsOneWidget);
    expect(find.text('确认通过'), findsWidgets);
    expect(find.text('驳回'), findsWidgets);
    expect(tester.getSize(approve).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(reject).height, greaterThanOrEqualTo(48));
    expect(find.byTooltip('确认通过'), findsNothing);
  });

  testWidgets('mobile non-president does not see decision bar', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        390,
        session: AuthSession.fromJson(const {
          'userId': 12,
          'displayName': '李思',
        }),
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'status': 'pending_president',
          'createdBy': 11,
          'form': {'presidentUserId': 11, 'president': '王奕凡'},
        }),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('proposal-president-approve')), findsNothing);
    expect(find.byKey(const ValueKey('proposal-president-reject')), findsNothing);
  });

  testWidgets('long core terms expand to show full content', (tester) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final longTerms = List.generate(
      24,
      (i) => '${i + 1}. 您自愿就生活服务业务与甲方开展合作并遵守本条款。',
    ).join('\n');
    await tester.pumpWidget(
      _harness(
        1440,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'title': '',
          'status': 'filling',
          'version': 3,
          'createdBy': 11,
          'form': {'purchaseMode': '未签署合同', 'purchaseCoreTerms': longTerms},
          'review': <String, dynamic>{},
        }),
      ),
    );
    await tester.pump();
    await _scrollUntil(tester, '核心条款');

    final box = tester.getSize(
      find
          .descendant(
            of: _fieldOf('核心条款'),
            matching: find.byType(TextFormField),
          )
          .first,
    );
    expect(box.height, greaterThan(200));
  });

  testWidgets('selected product pill uses green fill', (tester) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'title': '',
          'status': 'filling',
          'version': 3,
          'createdBy': 11,
          'form': {
            'purchaseMode': '未签署合同',
            'purchaseProducts': ['智能投放平台'],
          },
          'review': <String, dynamic>{},
        }),
      ),
    );
    await tester.pump();
    await _scrollUntil(tester, '采购产品');

    final chip = tester.widget<ProposalChoiceChip>(
      find.widgetWithText(ProposalChoiceChip, '智能投放平台'),
    );
    expect(chip.selected, isTrue);
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.widgetWithText(ProposalChoiceChip, '智能投放平台'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, ProposalChoiceChip.selectedFill);
  });

  testWidgets('module reject is available before item-by-item reviews', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'title': '测试提案',
          'status': 'reviewing',
          'version': 3,
          'createdBy': 11,
          'form': {
            'financeOwner2': '王奕凡',
            'financeOwner2UserId': 11,
            'salesMode': '未签署合同',
            'salesName': '测试销售合同',
          },
          'review': {'stage': 'reviewing'},
        }),
      ),
    );
    await tester.pump();
    await _scrollUntil(tester, '销售合同复核');

    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(
              const ValueKey('proposal-module-approve-salesContractCompleted'),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(
              const ValueKey('proposal-module-reject-salesContractCompleted'),
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.textContaining('发现问题可直接点「驳回」'), findsWidgets);
  });

  testWidgets('rejected module banner tells submitter to notify reviewer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'title': '测试提案',
          'status': 'filling',
          'version': 4,
          'createdBy': 11,
          'form': {'financeOwner2': '王奕凡', 'financeOwner2UserId': 11},
          'review': {
            'stage': 'awaiting_start_review',
            'reviewRejected': true,
            'reviewRejectSection': 'salesContract',
            'reviewRejectComment': '合同主体不对',
            'reviewRejectUserId': 11,
          },
        }),
      ),
    );
    await tester.pump();

    expect(find.textContaining('重新提交并通知审核人'), findsWidgets);
    expect(find.textContaining('财务部负责人二'), findsWidgets);
    expect(find.byTooltip('重新提交并通知审核人'), findsOneWidget);
  });

  testWidgets('filled proposal form adapts on a phone-width layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        390,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'title': '华东区域智能投放年度框架合作提案（含补充说明）',
          'status': 'reviewing',
          'version': 3,
          'createdBy': 11,
          'form': {
            'sector': '数字营销事业部',
            'proposalName': '华东区域智能投放年度框架合作提案（含补充说明）',
            'financeOwner2': '王奕凡',
            'financeOwner2UserId': 11,
            'salesMode': '未签署合同',
            'salesName': '上海某某数字科技有限公司智能投放平台年度框架采购合同（含补充协议）',
            'salesCoreTerms': List.generate(
              8,
              (i) => '${i + 1}. 双方就合作范围、结算周期与开票主体达成一致。',
            ).join('\n'),
            'purchaseProducts': ['智能投放平台'],
            'channels': ['直客渠道', '代理商渠道', '生态合作渠道'],
          },
          'review': {'stage': 'reviewing'},
        }),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    await _scrollUntil(tester, '销售合同复核');
    expect(find.textContaining('发现问题可直接点「驳回」'), findsWidgets);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(
              const ValueKey('proposal-module-reject-salesContractCompleted'),
            ),
          )
          .onPressed,
      isNotNull,
    );
    await _scrollUntil(tester, '提案全链路');
    expect(find.text('提案全链路'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone-width proposal fields share a full-width column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        390,
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'title': '测试提案',
          'status': 'filling',
          'version': 3,
          'createdBy': 11,
          'form': {
            'product': '中石油—现金券',
            'projectName': '抖音渠道中石油产品上线提案',
            'supplies': ['江苏'],
            'channels': ['抖音'],
            'marketOwner1': '王奕凡',
            'marketOwner1UserId': 11,
          },
        }),
      ),
    );
    await tester.pump();
    await _scrollUntil(tester, '产品（标签一）');

    final product = tester.getSize(_fieldOf('产品（标签一）').first);
    final project = tester.getSize(_fieldOf('项目名称（标签一二级）').first);
    final supply = tester.getSize(_fieldOf('供给（标签二）').first);
    expect(product.width, closeTo(project.width, 1));
    expect(product.width, closeTo(supply.width, 1));
    expect(product.width, greaterThan(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'finance cost buckets ask for expected amounts without rule copy',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _harness(
          1440,
          row: _row().copyWith(
            form: {
              'costItems': ['服务器成本'],
            },
          ),
        ),
      );
      await tester.pump();
      await _scrollUntil(tester, '经营成本（万元）');

      expect(find.text('项目成本标准（万元）'), findsNothing);
      expect(find.text('税务成本标准（万元）'), findsNothing);
      expect(find.text('税务成本（万元）'), findsOneWidget);
      expect(find.text('项目成本'), findsOneWidget);
      expect(find.text('业务成本'), findsOneWidget);
      expect(find.text('经营成本（万元）'), findsOneWidget);
      expect(find.text('由市场部负责人一在财务复核时填写'), findsOneWidget);
      expect(find.textContaining('已加密上锁'), findsNothing);
      expect(
        tester.getTopLeft(find.text('税务成本（万元）')).dy,
        greaterThan(tester.getTopLeft(find.text('经营成本（万元）')).dy),
      );
      expect(find.text('规则已定，整块默认可藏。提案只挂表头，不填提成等发生额。'), findsNothing);
      expect(find.text('经营成本（提案留空）'), findsNothing);
      expect(find.textContaining('差旅、小额营销按项目收入的 2%'), findsNothing);
      expect(find.text('预计/标准，非发生额'), findsNothing);
      expect(find.text('合计 0 万元'), findsNothing);
      expect(find.text('结算单价/比例'), findsOneWidget);
      expect(find.text('结算规则'), findsOneWidget);
      expect(find.text('对方主体'), findsWidgets);
      expect(find.text('我方主体'), findsWidgets);
      expect(find.text('税率'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('结算单价/比例')).dy,
        closeTo(tester.getTopLeft(find.text('结算规则')).dy, 2),
      );
      expect(
        tester.getTopLeft(find.text('结算规则')).dy,
        closeTo(tester.getTopLeft(find.text('税率')).dy, 2),
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == '预计（万元）',
        ),
        findsNothing,
      );
    },
  );

  testWidgets('finance cost items show asset bill-type headers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        options: ProposalIntakeOptions.fromJson({
          'finance': {
            'costItems': ['机构返佣', '平台服务费'],
            'businessCostItems': ['供给侧H'],
            'costItemSource': 'asset',
            'costItemOptions': [
              {'code': 'ap_YFFY_JGFY', 'name': '机构返佣'},
              {'code': 'ap_FW_PTF', 'name': '平台服务费'},
            ],
            'businessCostItemOptions': [
              {'code': 'ap_YWCB_GJCH', 'name': '供给侧H'},
            ],
          },
        }),
      ),
    );
    await tester.pump();
    await _scrollUntil(tester, '项目成本');

    expect(find.text('资管账单三级 · 勾选适用表头'), findsNothing);
    expect(find.text('机构返佣'), findsOneWidget);
    expect(find.text('平台服务费'), findsOneWidget);
    expect(find.text('新增成本项'), findsNothing);
  });

  testWidgets('business cost stays locked for every owner 2', (tester) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        session: AuthSession.fromJson(const {
          'userId': 12,
          'displayName': '李思',
        }),
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'status': 'reviewing',
          'createdBy': 11,
          'form': {
            'financeOwner2UserId': 12,
            'businessCostItems': ['供给侧H'],
            'businessCostItemAmounts': {'ap_YWCB_GJCH': 8},
            'businessCost': 8,
          },
          'review': {'stage': 'reviewing'},
        }),
      ),
    );
    await tester.pump();
    await _scrollUntil(tester, '业务成本');

    expect(find.textContaining('已加密上锁'), findsOneWidget);
    expect(find.text('供给侧H'), findsNothing);
    expect(find.text('合计 8 万元'), findsNothing);
  });

  testWidgets('market owner 1 fills business cost during finance review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        session: AuthSession.fromJson(const {
          'userId': 4,
          'displayName': '市场一',
        }),
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'status': 'reviewing',
          'createdBy': 11,
          'form': {'marketOwner1UserId': 4},
          'review': {'stage': 'reviewing'},
        }),
      ),
    );
    await tester.pump();
    await _scrollUntil(tester, '业务成本');

    expect(find.text('员工提成'), findsOneWidget);
    expect(find.text('由市场部负责人一在财务复核时填写'), findsNothing);
    expect(find.textContaining('已加密上锁'), findsNothing);
    expect(
      tester
          .widget<ProposalPills>(
            find.descendant(
              of: _fieldOf('业务成本'),
              matching: find.byType(ProposalPills),
            ),
          )
          .enabled,
      isTrue,
    );
  });

  testWidgets('selected business cost items show five settlement columns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        session: AuthSession.fromJson(const {
          'userId': 4,
          'displayName': '市场一',
        }),
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'status': 'reviewing',
          'createdBy': 11,
          'form': {
            'marketOwner1UserId': 4,
            'businessCostItems': ['员工提成'],
          },
          'review': {'stage': 'reviewing'},
        }),
      ),
    );
    await tester.pump();
    await _scrollUntil(tester, '业务成本');

    expect(find.text('员工提成'), findsWidgets);
    expect(find.text('结算单价/比例'), findsOneWidget);
    expect(find.text('结算规则'), findsOneWidget);
    expect(find.text('税率'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('结算单价/比例')).dy,
      closeTo(tester.getTopLeft(find.text('结算规则')).dy, 2),
    );
    expect(
      tester.getTopLeft(find.text('结算规则')).dy,
      closeTo(tester.getTopLeft(find.text('税率')).dy, 2),
    );
    expect(find.text('合计 0 万元'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == '预计（万元）',
      ),
      findsNothing,
    );
  });

  testWidgets('done proposal shows start tech revision for tech owner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        session: AuthSession.fromJson(const {
          'userId': 12,
          'displayName': '李思',
        }),
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'status': 'done',
          'createdBy': 11,
          'form': {'technologyOwnerUserId': 12, 'technologyOwner': '李思'},
          'review': {'stage': 'done'},
        }),
      ),
    );
    await tester.pump();

    expect(find.text('发起科技变更'), findsWidgets);
    expect(find.byTooltip('发起科技变更'), findsOneWidget);
    expect(find.text('科技变更中'), findsNothing);
  });

  testWidgets('tech revising shows add-record and confirm actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        session: AuthSession.fromJson(const {
          'userId': 12,
          'displayName': '李思',
        }),
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'status': 'done',
          'createdBy': 11,
          'form': {
            'technologyOwnerUserId': 12,
            'technologyOwner': '李思',
            'technologyPlatform': '数据智能平台',
          },
          'review': {'stage': 'tech_revising', 'techRevisionRound': 2},
        }),
      ),
    );
    await tester.pump();

    expect(find.text('科技变更中'), findsOneWidget);
    expect(find.text('确认本轮科技变更'), findsWidgets);
    expect(find.byTooltip('确认本轮科技变更'), findsOneWidget);
    await _scrollUntil(tester, '新增对接记录');
    expect(find.text('新增对接记录'), findsOneWidget);
  });

  testWidgets('tech reviewing locks market until technology is done', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        session: AuthSession.fromJson(const {
          'userId': 4,
          'displayName': '市场一',
        }),
        row: ProposalIntakeRow.fromJson({
          'id': 1,
          'code': 'TA-2026-0001',
          'status': 'done',
          'createdBy': 11,
          'form': {'marketOwner1UserId': 4, 'technologyOwnerUserId': 12},
          'review': {
            'stage': 'tech_reviewing',
            'technologyCompleted': false,
            'marketCompleted': false,
          },
        }),
      ),
    );
    await tester.pump();
    await _scrollUntil(tester, '整个板块复核通过');

    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('proposal-module-approve-marketCompleted')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('purchase intake uses template title and hides sales contract', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        1440,
        row: ProposalIntakeRow.fromJson({
          'id': 2,
          'code': 'CG-2026-0001',
          'kind': 'purchase',
          'title': '',
          'status': 'filling',
          'createdBy': 11,
          'form': <String, dynamic>{},
          'review': <String, dynamic>{},
        }),
      ),
    );
    await tester.pump();

    expect(find.text('采购业务提案 · 新增'), findsOneWidget);
    expect(find.text('未命名采购业务提案'), findsWidgets);
    expect(find.text('销售合同'), findsNothing);
    expect(find.text('采购合同'), findsWidgets);
    expect(find.text('HUN 联系方式'), findsWidgets);
  });
}
