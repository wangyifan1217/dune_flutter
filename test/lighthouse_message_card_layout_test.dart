import 'package:dunes_app/features/lighthouse/lighthouse_message_card_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('IM 灯塔卡按设备屏宽定目标、按消息行限宽，不会二次缩水', () {
    expect(lighthouseMessageCardWidth(320), 260);
    expect(lighthouseMessageCardWidth(390), closeTo(296.4, 0.01));
    expect(lighthouseMessageCardWidth(940), 360);
    expect(lighthouseMessageCardWidth(390, maxAvailable: 280), 280);
    expect(lighthouseMessageCardWidth(double.infinity), 260);
  });

  testWidgets('内部始终按 480 画布排版，再整体等比缩放', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(390, 844)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: LighthouseMessageCardFrame(
                child: SizedBox(
                  width: lighthouseMessageCardDesignWidth,
                  height: 240,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(lighthouseMessageCardDesignWidth, 480);
    final rendered = tester.getSize(find.byType(FittedBox));
    expect(rendered.width, closeTo(296.4, 0.01));
    expect(rendered.height, closeTo(148.2, 0.01));
  });
}
