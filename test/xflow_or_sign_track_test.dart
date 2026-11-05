import 'package:dunes_app/features/xflow/xflow_detail_widgets.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

XflowApprovalStep _step({
  required int stepNo,
  required int assigneeId,
  required String name,
  required String mode,
  int requiredApprovals = 1,
  String stageName = '差旅管家',
}) {
  return XflowApprovalStep(
    stepNo: stepNo,
    stepName: '差旅管家',
    decision: 'APPROVED',
    assigneeId: assigneeId,
    assigneeName: name,
    comment: '同意',
    updatedAt: null,
    raw: {
      'parallelMode': mode,
      'requiredApprovals': requiredApprovals,
      'stageName': stageName,
      'stepType': 'ROLE',
      'decidedAt': '2026-11-05T10:00:00',
    },
  );
}

XflowDetailBundle _bundle(List<XflowApprovalStep> steps) {
  return XflowDetailBundle(
    detail: const XflowProposalDetail(
      id: 1094,
      code: '#1094',
      title: '差旅',
      status: 'approved',
      summary: '',
      beaconId: '',
      ownerName: '徐峥',
      amountText: '',
      formValues: {},
      products: [],
      slots: [],
      createdById: 1,
      raw: {},
    ),
    trail: XflowApprovalTrail(
      status: 'approved',
      initiatorId: 1,
      steps: steps,
      raw: const {},
    ),
    fields: const [],
    detailConfig: const {},
    stages: const [],
    myTodo: null,
  );
}

void main() {
  test('or-sign is one-of, n-of-m is not', () {
    expect(
      _step(stepNo: 4, assigneeId: 1, name: '叶睿', mode: 'PARALLEL_N_OF_M').isOrSign,
      isTrue,
    );
    expect(
      _step(
        stepNo: 4,
        assigneeId: 1,
        name: '叶睿',
        mode: 'PARALLEL_N_OF_M',
        requiredApprovals: 2,
      ).isOrSign,
      isFalse,
    );
    expect(
      _step(stepNo: 4, assigneeId: 1, name: '叶睿', mode: 'SEQUENTIAL_AND').isOrSign,
      isFalse,
    );
  });

  testWidgets('or-sign approvers share one step and sit side by side', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: XfDetTrackTimeline(
            bundle: _bundle([
              _step(stepNo: 4, assigneeId: 11, name: '叶睿', mode: 'PARALLEL_N_OF_M'),
              _step(stepNo: 4, assigneeId: 12, name: '朱虹旭', mode: 'PARALLEL_N_OF_M'),
              _step(
                stepNo: 5,
                assigneeId: 13,
                name: '许正阳',
                mode: 'SINGLE',
                stageName: '总裁审批',
              ),
            ]),
          ),
        ),
      ),
    );

    expect(find.text('或签'), findsOneWidget);
    expect(find.text('叶睿'), findsOneWidget);
    expect(find.text('朱虹旭'), findsOneWidget);
    expect(find.text('差旅管家'), findsOneWidget);
    final ye = tester.getTopLeft(find.text('叶睿'));
    final zhu = tester.getTopLeft(find.text('朱虹旭'));
    expect((ye.dy - zhu.dy).abs(), lessThan(8));
    expect(ye.dx, isNot(closeTo(zhu.dx, 8)));
  });
}
