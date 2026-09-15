import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:dunes_app/features/kpi_assistant/kpi_chat_card.dart';

void main() {
  Map<String, dynamic> payload() => <String, dynamic>{
    'type': 'kpiResult',
    'month': '2026-08',
    'monthLabel': '2026年8月',
    'userId': 12,
    'userName': '王奕凡',
    'departmentName': '出行',
    'position': '产品经理',
    'templateLabel': '专业岗量表',
    'mainScore': 95,
    'grade': '优',
    'gradeLabel': '优（优秀）',
    'coefficient': 1.1,
    'scoredByName': '朱子姝',
    'status': 'pending_ack',
    'ackHint': '请确认已知悉本月绩效结果。',
    'items': <Map<String, dynamic>>[
      <String, dynamic>{'label': '目标完成', 'points': 28, 'maxPoints': 30},
    ],
    'team': <String, dynamic>{
      'departmentName': '出行',
      'projectScore': 8.95,
      'coefficient': 1,
    },
  };

  test('绩效助手卡片解析部门、分数、考核人和待确认', () {
    final data = KpiAssistantCardData.fromPayload(payload());
    expect(data.canConfirm, isTrue);
    expect(data.statusLabel, '待确认');
    expect(data.userName, '王奕凡');
    expect(data.identityLine, '出行 · 产品经理');
    expect(data.scoreText, '95');
    expect(data.gradeText, '优');
    expect(data.scoredByName, '朱子姝');
    expect(data.items.single.label, '目标完成');
    expect(data.teamProjectScore, 8.95);
    expect(data.ackHint, contains('请确认'));
  });

  test('结果已更新需要再确认；已确认不再出按钮', () {
    final updated = KpiAssistantCardData.fromPayload({
      ...payload(),
      'type': 'kpiResultUpdated',
      'status': 'updated',
    });
    expect(updated.canConfirm, isTrue);
    expect(updated.statusLabel, '结果已更新');
    final acked = KpiAssistantCardData.fromPayload({
      ...payload(),
      'type': 'kpiAcked',
      'status': 'acked',
      'ackedAt': '2026-09-15T02:00:00Z',
    });
    expect(acked.canConfirm, isFalse);
    expect(acked.statusLabel, '已确认');
  });

  testWidgets('卡片展示确认按钮，分项收进详情', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatKpiAssistantCard(
            data: KpiAssistantCardData.fromPayload(payload()),
            onConfirm: () => confirmed = true,
            onOpenDetail: () {},
          ),
        ),
      ),
    );
    expect(find.text('8月绩效已发布'), findsOneWidget);
    expect(find.textContaining('王奕凡'), findsOneWidget);
    expect(find.text('考核人 朱子姝'), findsOneWidget);
    expect(find.text('确认本月绩效'), findsOneWidget);
    expect(find.text('查看详情'), findsOneWidget);
    expect(find.text('目标完成'), findsNothing);
    await tester.tap(find.text('确认本月绩效'));
    expect(confirmed, isTrue);
  });
}
