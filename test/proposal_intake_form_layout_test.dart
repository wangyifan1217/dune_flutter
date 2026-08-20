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
          options: _options(),
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
    expect(find.text('保存'), findsNothing);
    expect(find.text('转发'), findsNothing);
    expect(find.text('通知科技'), findsNothing);
    expect(find.text('删除'), findsNothing);
    expect(find.text('D'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('market filler is locked to the current user', (tester) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(1440));
    await tester.pump();

    expect(find.text('市场部负责人二（填写人）'), findsOneWidget);
    expect(find.text('当前用户'), findsOneWidget);
    expect(
      tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .any((field) => field.initialValue == '王奕凡'),
      isTrue,
    );
  });

  testWidgets('empty proposal form has no mock values, 万元, or draft wording', (
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
    expect(find.text('保存'), findsNothing);
    expect(find.textContaining('万元'), findsNothing);
    expect(find.text('选择合同'), findsNothing);
    expect(find.text('行政复核'), findsWidgets);

    Future<void> scrollUntil(String label) async {
      await _scrollUntil(tester, label);
    }

    await scrollUntil('市场部负责人二复核');
    expect(find.text('市场部负责人二复核'), findsWidgets);
    await scrollUntil('销售规模目标（元）');
    expect(find.text('销售规模目标（元）'), findsOneWidget);
    expect(find.text('收入（元）'), findsOneWidget);
    expect(find.text('发票（元）'), findsOneWidget);
    expect(find.text('财务部负责人二复核'), findsWidgets);
    await scrollUntil('补贴出资方');
    expect(find.text('补贴出资方'), findsWidgets);
    expect(find.text('清算 / 支付机构'), findsWidgets);
    expect(find.text('我方开票主体'), findsWidgets);
    expect(find.text('服务 / 承接机构'), findsWidgets);
    expect(find.textContaining('万元'), findsNothing);
    expect(find.textContaining('万里通'), findsNothing);
    expect(find.textContaining('平安（清算'), findsNothing);
    expect(find.textContaining('13% 油专'), findsNothing);
    expect(find.textContaining('6% 增专'), findsNothing);
    expect(find.text('终端用户'), findsNothing);
    expect(find.textContaining('保费'), findsNothing);
    expect(find.textContaining('用户领取'), findsNothing);
  });

  testWidgets('four-flow entity fields do not overflow in a two-column grid', (
    tester,
  ) async {
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
    await _scrollUntil(tester, '清算 / 支付机构');

    expect(tester.takeException(), isNull);
    expect(find.text('测试'), findsWidgets);
    expect(find.textContaining('由市场部负责人二（填写人）填写'), findsOneWidget);
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

    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '开票接口 *'),
    );
    expect(chip.selected, isFalse);
    expect(
      find.ancestor(
        of: find.widgetWithText(ChoiceChip, '开票接口 *'),
        matching: find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '结算对账接口'))
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
    expect(find.text('请指定科技部负责人。技术字段由对方填写，你只做逐条复核。'), findsOneWidget);
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
    expect(find.text('由市场部负责人二填写。当前账号不可编辑本板块。'), findsOneWidget);

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
        'contractAdmin': '王奕凡',
        'contractAdminUserId': 11,
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
    expect(find.text('指定审核人 · 无需复核'), findsWidgets);
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(
              of: _fieldOf('合同编号').first,
              matching: find.widgetWithText(OutlinedButton, '行政复核'),
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
    expect(find.text('未签合同 · 可查看'), findsOneWidget);
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
    expect(find.text('下一个(2)'), findsOneWidget);
    await tester.tap(find.text('下一个(2)'));
    expect(tapped, isTrue);
  });
}
