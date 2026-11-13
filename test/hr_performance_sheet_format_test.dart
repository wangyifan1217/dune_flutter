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
}

