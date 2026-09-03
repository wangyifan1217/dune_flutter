import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dunes_app/core/widgets/spotlight_tour.dart';
import 'package:dunes_app/features/profile/native_profile_tour.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('首次进入未看过，markSeen 后记住，且按用户隔离', () async {
    const a = ProfileTourPrefs(1);
    const b = ProfileTourPrefs(2);
    expect(await a.hasSeen(), isFalse);
    expect(await b.hasSeen(), isFalse);
    await a.markSeen();
    expect(await a.hasSeen(), isTrue);
    expect(await b.hasSeen(), isFalse);
  });

  testWidgets('单步指引指向目标后点完成会关闭', (tester) async {
    final target = GlobalKey();
    var closed = 0;
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Container(
                  key: target,
                  width: 42,
                  height: 42,
                  color: Colors.purple,
                ),
              ),
              SpotlightTourOverlay(
                steps: [
                  SpotlightTourStep(
                    targetKey: target,
                    title: '个人工作画像',
                    body: '点这里查看画像',
                    holeRadius: 99,
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

    expect(find.text('个人工作画像'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('上一步'), findsNothing);

    await tester.tap(find.text('完成'));
    await tester.pump();
    expect(closed, 1);
  });
}
