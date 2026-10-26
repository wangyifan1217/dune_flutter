import 'package:dunes_app/features/nova/nova_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'interrupted reply preserves text and exposes retry at width $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var retried = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: NovaC4MessageRow(
                  mine: false,
                  text: '已经生成的部分内容',
                  thinkStatus: '回复已中断',
                  streaming: false,
                  onRetryReply: () => retried = true,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('回复已中断'), findsOneWidget);
        expect(find.text('重新生成'), findsOneWidget);
        expect(find.byType(NovaC4ThinkingDots), findsNothing);
        await tester.tap(find.text('重新生成'));
        expect(retried, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
