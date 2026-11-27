import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/qianji/native_qianji_hub_page.dart';
import 'package:dunes_app/features/qianji/native_qianji_proposal_sla_page.dart';
import 'package:dunes_app/features/qianji/proposal_sla_lookup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('业务查阅在开通权限后显示提案时效入口', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeQianjiHubPage(
            session: const AuthSession(
              phone: '13812345678',
              userId: 1001,
              token: 'test-token',
              apiBase: 'https://test.api',
              roles: ['ADMIN'],
              qianjiAccess: true,
              proposalSlaLookupAccess: true,
            ),
            onOpenCursorAccount: () {},
            onOpenProposalSla: () => opened = true,
          ),
        ),
      ),
    );
    await tester.pump();
    if (qianjiHubNewLayoutEnabled) {
      await tester.tap(find.text('模块入口'));
      await tester.pump();
    }

    expect(find.text('提案时效'), findsOneWidget);
    expect(find.text('任务 · 日报 · 群响应 · 提案时效'), findsOneWidget);
    await tester.tap(find.text('提案时效'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('提案时效页展示进行中提案并可以打开免责登记', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: NativeQianjiProposalSlaPage(
          session: const AuthSession(
            phone: '13812345678',
            userId: 1001,
            token: 'test-token',
            apiBase: 'https://test.api',
            roles: ['ADMIN'],
            proposalSlaLookupAccess: true,
          ),
          onBack: () {},
          api: _FakeProposalSlaApi(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('会员套餐订购-湖北电信'), findsOneWidget);
    expect(find.text('登记免责'), findsOneWidget);

    await tester.tap(find.text('登记免责'));
    await tester.pumpAndSettle();
    expect(find.text('整张提案（全部节点）'), findsOneWidget);
    expect(find.text('系统故障'), findsOneWidget);
  });

  for (final width in [390.0, 1080.0]) {
    testWidgets('同一提案的两类超时分别展示并按单条复核 ($width)', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _FakeProposalSlaApi();
      await tester.pumpWidget(
        MaterialApp(
          home: NativeQianjiProposalSlaPage(
            session: _FakeProposalSlaApi.testSession,
            onBack: () {},
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('proposal-sla-tab-scores')));
      await tester.pumpAndSettle();

      final proposalTitle = find.text('季度渠道提案');
      expect(proposalTitle, findsOneWidget);
      expect(find.text('1 项提案 · 2 条记录'), findsOneWidget);
      expect(find.text('总时长超时'), findsOneWidget);
      expect(find.text('单环节超时'), findsOneWidget);
      expect(find.textContaining('销售复核：负责人甲'), findsOneWidget);
      expect(find.textContaining('财务复核：负责人乙'), findsOneWidget);
      await tester.tap(proposalTitle);
      await tester.pumpAndSettle();
      final dialog = find.byType(Dialog);
      expect(
        find.descendant(of: dialog, matching: find.text('总时长超时 · 1 条')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('单环节超时 · 1 条')),
        findsOneWidget,
      );
      expect(find.text('超时 2 小时'), findsOneWidget);
      final totalRow = find.byKey(const ValueKey('proposal-sla-score-row-11'));
      expect(
        tester.getSize(totalRow).height,
        lessThan(width >= 620 ? 74 : 130),
      );
      expect(
        find.descendant(of: totalRow, matching: find.textContaining('申诉截止')),
        findsOneWidget,
      );
      if (width >= 620) {
        final nodeRow = find.byKey(const ValueKey('proposal-sla-score-row-12'));
        final action = find.descendant(of: nodeRow, matching: find.text('复核'));
        expect(
          tester.getCenter(action).dy,
          closeTo(tester.getCenter(find.text('超时 2 小时')).dy, 1),
        );
      }
      expect(find.textContaining('申诉理由'), findsOneWidget);
      final row = find.byKey(const ValueKey('proposal-sla-score-row-12'));
      final scrollable = find
          .ancestor(of: row, matching: find.byType(Scrollable))
          .first;
      final scrollState = tester.state<ScrollableState>(scrollable);
      final review = find.descendant(of: row, matching: find.text('复核'));
      await tester.ensureVisible(review);
      final offset = scrollState.position.pixels;
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(find.text('复核 · 负责人乙'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(scrollable), same(scrollState));
      expect(scrollState.position.pixels, offset);
      expect(api.reviewedId, isNull);

      await tester.tap(review);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认扣分（3分）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(api.reviewedId, 12);
      expect(tester.state<ScrollableState>(scrollable), same(scrollState));
      expect(scrollState.position.pixels, offset);
      expect(
        find.descendant(of: row, matching: find.text('已确认')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('扣 3 分')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    '时效看板支持快捷时间与多维筛选、瓶颈切换与PC导出',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeProposalSlaApi();
    await tester.pumpWidget(
      MaterialApp(
        home: NativeQianjiProposalSlaPage(
          session: _FakeProposalSlaApi.testSession,
          onBack: () {},
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('proposal-sla-tab-dashboard')));
    await tester.pumpAndSettle();

    // 清晰白话 KPI 与 PC 导出按钮
    expect(find.text('纳入考核提案'), findsOneWidget);
    expect(find.text('当前在途超时'), findsOneWidget);
    expect(find.text('已办结平均用时'), findsOneWidget);
    expect(find.text('待复核绩效'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('proposal-sla-dashboard-export')),
      findsOneWidget,
    );

    // 快捷时间筛选：点击「近7天」触发带 from/to 的重新请求
    await tester.tap(find.byKey(const ValueKey('proposal-sla-preset-days7')));
    await tester.pumpAndSettle();
    expect(api.lastDashboardFrom, isNotNull);
    expect(api.lastDashboardTo, isNotNull);

    // 切换瓶颈分析维度：按业务板块
    await tester.tap(find.byKey(const ValueKey('proposal-sla-dim-sector')));
    await tester.pumpAndSettle();
    expect(find.text('运营商'), findsWidgets);

    // 验证 CSV 导出内容含 UTF-8 BOM、筛选条件与明细
    final dash = await api.fetchDashboard();
    final csv = buildProposalSlaDashboardCsv(
      data: dash,
      stages: dash.byStage,
      sectors: dash.bySector,
      people: dash.byPerson,
      proposals: dash.items,
      filterSummary: '区间：2026-11-01 至 2026-11-27 · 板块：运营商',
    );
    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(csv, contains('提案时效看板报表'));
    expect(csv, contains('运营商'));
    expect(csv, contains('会员套餐订购-湖北电信'));
  });
}

class _FakeProposalSlaApi extends ProposalSlaLookupApi {
  _FakeProposalSlaApi() : super(session: testSession);

  String? lastDashboardFrom;
  String? lastDashboardTo;
  String? lastDashboardSector;
  String? lastDashboardStage;
  String? lastDashboardStatus;

  static const testSession = AuthSession(
    phone: '13812345678',
    userId: 1001,
    token: 'test-token',
    apiBase: 'https://test.api',
    roles: ['ADMIN'],
    proposalSlaLookupAccess: true,
  );

  @override
  Future<ProposalSlaDashboard> fetchDashboard({
    String? from,
    String? to,
    String? sector,
    String? stage,
    String? status,
  }) async {
    lastDashboardFrom = from;
    lastDashboardTo = to;
    lastDashboardSector = sector;
    lastDashboardStage = stage;
    lastDashboardStatus = status;
    return ProposalSlaDashboard(
      from: from ?? '2026-11-01',
      to: to ?? '2026-11-27',
      proposals: 12,
      open: 4,
      finished: 8,
      openOverdue: 1,
      avgTotalHours: 18.5,
      rejectRounds: 3,
      pendingScores: 2,
      pendingAppeals: 1,
      sectorOptions: const ['运营商', '政企'],
      byStage: const [
        ProposalSlaStat(
          key: 'finance',
          name: '财务复核',
          nodes: 10,
          avgMinutes: 320,
          overdueRate: 20,
          overdueCount: 2,
          proposalCount: 8,
          rejectRounds: 1,
        ),
      ],
      bySector: const [
        ProposalSlaStat(
          key: '运营商',
          name: '运营商',
          nodes: 12,
          avgMinutes: 280,
          overdueRate: 16.7,
          overdueCount: 2,
          proposalCount: 9,
          rejectRounds: 2,
        ),
      ],
      byPerson: const [
        ProposalSlaStat(
          key: '101',
          name: '负责人乙',
          nodes: 5,
          avgMinutes: 400,
          overdueRate: 40,
          overdueCount: 2,
          proposalCount: 4,
          rejectRounds: 1,
        ),
      ],
      overdueOpen: const [
        ProposalSlaInstance(
          id: 7,
          code: 'TA-20261013-000260',
          title: '会员套餐订购-湖北电信',
          sector: '运营商',
          status: 'overdue',
          round: 2,
          exempt: false,
          elapsedHours: 80.5,
          totalHours: 72,
          current: '财务复核·负责人乙',
          overdueNodes: 1,
          startedAt: '2026-10-16T00:47:00Z',
        ),
      ],
      items: const [
        ProposalSlaInstance(
          id: 7,
          code: 'TA-20261013-000260',
          title: '会员套餐订购-湖北电信',
          sector: '运营商',
          status: 'overdue',
          round: 2,
          exempt: false,
          elapsedHours: 80.5,
          totalHours: 72,
          current: '财务复核·负责人乙',
          overdueNodes: 1,
          startedAt: '2026-10-16T00:47:00Z',
        ),
      ],
    );
  }

  @override
  Future<ProposalSlaConfig> fetchConfig() async {
    return const ProposalSlaConfig(
      enabled: true,
      totalHours: 72,
      nodeHours: 12,
      workStartMinute: 540,
      workEndMinute: 1260,
      warnHours: 2,
      remindIntervalHours: 12,
      appealWorkdays: 2,
    );
  }

  @override
  Future<List<ProposalSlaInstance>> fetchInstances({
    required String status,
    String q = '',
    String? from,
    String? to,
    String? sector,
  }) async {
    return const [
      ProposalSlaInstance(
        id: 7,
        code: 'TA-20261013-000260',
        title: '会员套餐订购-湖北电信',
        sector: '运营商',
        status: 'normal',
        round: 1,
        exempt: false,
        elapsedHours: 1.3,
        totalHours: 72,
        current: '按驳回意见重新提交·黄永刚',
        overdueNodes: 0,
        startedAt: '2026-10-16T00:47:00Z',
      ),
    ];
  }

  int? reviewedId;

  @override
  Future<void> reviewScore({
    required int id,
    required String action,
    int? points,
    required String comment,
  }) async {
    reviewedId = id;
  }

  @override
  Future<List<ProposalSlaScore>> fetchScores({
    required String status,
    String q = '',
    String? from,
    String? to,
    String? sector,
    String? kind,
  }) async => [
    ProposalSlaScore.fromJson({
      'id': 11,
      'proposalId': 101,
      'code': 'TA-101',
      'title': '季度渠道提案',
      'kind': 'total',
      'nodeLabel': '销售复核',
      'userName': '负责人甲',
      'round': 1,
      'suggestedPoints': 2,
      'finalPoints': 2,
      'overdueMinutes': 15,
      'createdAt': '2026-11-24T01:12:00Z',
      'appealDeadline': '2026-11-26T15:59:00Z',
      'status': 'pending',
    }),
    if (reviewedId == null)
      ProposalSlaScore.fromJson({
        'id': 12,
        'proposalId': 101,
        'code': 'TA-101',
        'title': '季度渠道提案',
        'kind': 'node',
        'nodeLabel': '财务复核',
        'userName': '负责人乙',
        'round': 1,
        'suggestedPoints': 3,
        'overdueMinutes': 120,
        'status': 'pending',
        'appealStatus': 'pending',
        'appealReason': '补充说明',
      }),
  ];

  @override
  Future<List<ProposalSlaNode>> fetchNodes(int instanceId) async => const [];
}
