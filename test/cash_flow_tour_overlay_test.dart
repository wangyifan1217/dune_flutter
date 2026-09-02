import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dunes_app/features/qianji/native_qianji_cash_flow_tour.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('下一步推进步骤，右上角跳过关闭', (tester) async {
    final a = GlobalKey();
    final b = GlobalKey();
    var closed = 0;
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Column(
                children: [
                  Container(
                    key: a,
                    height: 80,
                    width: double.infinity,
                    color: Colors.red,
                    alignment: Alignment.center,
                    child: const Text('区间'),
                  ),
                  Container(
                    key: b,
                    height: 80,
                    width: double.infinity,
                    color: Colors.blue,
                    alignment: Alignment.center,
                    child: const Text('总览'),
                  ),
                ],
              ),
              CashFlowTourOverlay(
                steps: [
                  CashFlowTourStep(
                    targetKey: a,
                    title: '先选统计区间',
                    body: '说明一',
                  ),
                  CashFlowTourStep(
                    targetKey: b,
                    title: '看集团总览',
                    body: '说明二',
                  ),
                ],
                onClose: () => closed++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('先选统计区间'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('跳过'), findsWidgets);

    await tester.tap(find.text('下一步'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('看集团总览'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('上一步'), findsOneWidget);

    await tester.tap(find.text('上一步'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('先选统计区间'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);

    await tester.tap(find.text('跳过').first);
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('最后一步点完成会关闭', (tester) async {
    final a = GlobalKey();
    var closed = 0;
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Container(
                key: a,
                height: 80,
                width: double.infinity,
                color: Colors.red,
                alignment: Alignment.center,
                child: const Text('区间'),
              ),
              CashFlowTourOverlay(
                steps: [
                  CashFlowTourStep(
                    targetKey: a,
                    title: '先选统计区间',
                    body: '说明一',
                  ),
                ],
                onClose: () => closed++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('完成'), findsOneWidget);
    expect(find.text('上一步'), findsNothing);
    await tester.tap(find.text('完成'));
    await tester.pump();
    expect(closed, 1);
  });

  test('首次进入未看过，markSeen 后记住', () async {
    const prefs = CashFlowTourPrefs();
    expect(await prefs.hasSeen(), isFalse);
    await prefs.markSeen();
    expect(await prefs.hasSeen(), isTrue);
  });
}
