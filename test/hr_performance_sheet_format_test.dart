import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_sheet.dart';

void main() {
  testWidgets('fixed columns and direct scores match assessment format', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HrAssessmentSheet(
            scoresVisible: true,
            lines: [
              {
                'project': '核心达成',
                'name': '任务一',
                'weight': 20,
                'score': 15,
                'directScore': true,
                'bands': [
                  {'description': '达到目标', 'min': 15, 'max': 20},
                ],
              },
              {
                'project': '核心达成',
                'name': '任务二',
                'weight': 80,
                'score': 70,
                'directScore': true,
              },
            ],
          ),
        ),
      ),
    );
    expect(find.text('分值'), findsOneWidget);
    expect(find.text('自评分'), findsNothing);
    expect(find.text('加权得分'), findsNothing);
    expect(find.text('达到目标'), findsOneWidget);
    expect(find.text('15–20'), findsOneWidget);
    expect(find.text('最终得分 85'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'compact assessment keeps criteria readable and hides unreleased scores',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HrAssessmentSheet(
                lines: [
                  {
                    'project': '工作成果',
                    'name': '任务完成',
                    'weight': 100,
                    'score': 88,
                    'bands': [
                      {'description': '按时完成目标', 'min': 80, 'max': 100},
                    ],
                  },
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('工作成果 · 维度权重 100%'), findsOneWidget);
      expect(find.text('按时完成目标'), findsOneWidget);
      expect(find.textContaining('上级评分'), findsNothing);
      expect(find.textContaining('88'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
