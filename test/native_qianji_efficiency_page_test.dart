import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/qianji/efficiency/efficiency_models.dart';
import 'package:dunes_app/features/qianji/efficiency/efficiency_service.dart';
import 'package:dunes_app/features/qianji/efficiency/native_qianji_efficiency_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = AuthSession(
  phone: '13800000000',
  userId: 1,
  token: 'test',
  apiBase: 'http://localhost/api/v1',
  roles: <String>[],
  displayName: '测试用户',
  departmentName: '产品部',
  jobTitle: '产品经理',
);

class _FakeEfficiencyService extends EfficiencyService {
  _FakeEfficiencyService() : super(session: _session);

  @override
  Future<EfficiencySnapshot> fetchOverview({
    required String scope,
    required String month,
  }) async {
    return EfficiencySnapshot(
      scope: scope,
      month: month,
      title: scope == 'personal' ? '我的效能分析' : '部门效能分析',
      peopleCount: scope == 'personal' ? 1 : 8,
      hasDepartmentView: true,
      privacyProtected: false,
      metricVersion: 'v1',
      generatedAt: DateTime(2026, 9, 8),
      metrics: const [
        EfficiencyMetric(
          key: 'taskCompletionRate',
          label: '任务完成率',
          value: 80,
          unit: '%',
        ),
      ],
      stages: const [
        EfficiencyStage(
          key: 'task',
          label: '任务',
          total: 10,
          completed: 8,
          rate: 80,
        ),
      ],
      bottlenecks: const [],
      quality: const [
        EfficiencyEvidence(
          kind: 'kb',
          label: '上传后从未被打开或引用',
          count: 2,
          severity: 'high',
          ref: 'kb:unused',
        ),
      ],
      insights: const ['[空洞纪要]《周会》：待补充'],
      sources: const [
        EfficiencySource(key: 'task', label: '任务', available: true),
      ],
    );
  }
}

void main() {
  testWidgets('renders personal and department efficiency tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeQianjiEfficiencyPage(
          session: _session,
          onBack: () {},
          service: _FakeEfficiencyService(),
          now: DateTime(2026, 9, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI效能分析'), findsOneWidget);
    expect(find.text('2026.8'), findsOneWidget);
    expect(find.text('个人分析'), findsOneWidget);
    expect(find.text('部门汇总'), findsOneWidget);
    expect(find.text('任务完成率'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('质量抽样'), findsNothing);

    await tester.tap(find.byKey(const Key('efficiency-help')));
    await tester.pumpAndSettle();
    expect(find.text('这些指标怎么算'), findsOneWidget);
    expect(find.textContaining('已完成任务'), findsOneWidget);
    Navigator.of(tester.element(find.text('这些指标怎么算'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('部门汇总'));
    await tester.pumpAndSettle();
    expect(find.text('部门效能分析'), findsOneWidget);
    expect(find.textContaining('看闭环和质量'), findsOneWidget);
  });

  test('metric grid fills width without wrapping early', () {
    expect(efficiencyMetricColumnCount(500), 2);
    expect(efficiencyMetricColumnCount(800), 3);
    expect(efficiencyMetricColumnCount(1200), 4);
    const width = 900.0;
    final tile = efficiencyMetricTileWidth(width);
    expect(3 * tile + 2 * 12, closeTo(width, 0.01));
  });
}
