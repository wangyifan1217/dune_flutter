import 'package:dunes_app/features/hr_performance/hr_performance_service.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final cap in [5, 20]) {
    testWidgets('加减分表按所选模板显示单次上限 $cap', (tester) async {
      final record = HrPerformanceRecord.fromJson({
        'id': 1,
        'userId': 4,
        'month': '2026-10',
        'stage': 'indicators',
        'snapshot': {
          if (cap == 20) 'singleDeductionCap': 20,
          if (cap == 20) 'deductionInstructions': '严重违纪扣20分',
        },
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHrBonusSheet(context, {
                  'rules': {'singleDeductionCap': 5, 'monthlyDeductionCap': 20},
                  'adjustmentItems': [
                    {
                      'id': 'discipline',
                      'name': '规章制度遵守情况',
                      'direction': 'deduct',
                      'points': 5,
                      'enabled': true,
                      'requireSource': true,
                    },
                  ],
                }, record: record),
                child: const Text('录入扣分'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('录入扣分'));
      await tester.pumpAndSettle();
      expect(find.textContaining('扣分单次最多 $cap 分，每月累计最多 20 分'), findsOneWidget);
      if (cap == 20) expect(find.textContaining('严重违纪扣20分'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
