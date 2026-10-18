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
}

class _FakeProposalSlaApi extends ProposalSlaLookupApi {
  _FakeProposalSlaApi()
    : super(
        session: const AuthSession(
          phone: '13812345678',
          userId: 1001,
          token: 'test-token',
          apiBase: 'https://test.api',
          roles: ['ADMIN'],
        ),
      );

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

  @override
  Future<List<ProposalSlaNode>> fetchNodes(int instanceId) async => const [];
}
