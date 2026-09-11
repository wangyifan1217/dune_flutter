import 'package:dunes_app/features/task_assistant/recon_channel_confirm_card.dart';
import 'package:dunes_app/features/task_assistant/recon_channel_confirm_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview supports multiple channels on the same day', () {
    final channels = reconChannelPreviewPack(asOfDate: '2026-09-11');
    expect(channels, hasLength(3));
    expect(channels.map((e) => e.asOfDate).toSet(), {'2026-09-11'});
    expect(channels.where((e) => !e.isMonthly), hasLength(2));
    expect(channels.where((e) => e.isMonthly).single.settlementCycle, 'M+1');
    expect(
      channels.singleWhere((e) => e.settlementCycle == 'D+3').lines,
      hasLength(3),
    );
    expect(
      channels.singleWhere((e) => e.settlementCycle == 'D+2').lines,
      hasLength(2),
    );
    expect(formatReconChannelMoney(128400), '128,400.00');
  });

  testWidgets('monthly card only shows monthly totals', (tester) async {
    final channel = reconChannelPreviewPack(
      asOfDate: '2026-09-11',
    ).where((e) => e.isMonthly).single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReconChannelConfirmCard(channel: channel)),
      ),
    );

    expect(find.textContaining('2026年9月  M+1'), findsOneWidget);
    expect(find.text('9月应收'), findsOneWidget);
    expect(find.text('9月实收'), findsOneWidget);
    expect(find.text('差额'), findsOneWidget);
    expect(find.text('2026-09-10'), findsNothing);
  });

  testWidgets('reconciliation card can confirm or submit a comment', (
    tester,
  ) async {
    final channel = reconChannelPreviewPack(asOfDate: '2026-09-11').first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReconChannelConfirmCard(channel: channel),
          ),
        ),
      ),
    );

    expect(find.textContaining('杭州推客'), findsOneWidget);
    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('确认'), findsOneWidget);
    expect(find.text('提意见'), findsOneWidget);

    await tester.tap(find.text('提意见'));
    await tester.pumpAndSettle();
    expect(find.text('提交并确认'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '9日少到账 2,200 元');
    await tester.tap(find.text('提交并确认'));
    await tester.pumpAndSettle();

    expect(find.text('已确认'), findsOneWidget);
    expect(find.textContaining('9日少到账'), findsOneWidget);
    expect(find.text('确认'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('direct confirmation requires a second confirmation', (
    tester,
  ) async {
    final channel = reconChannelPreviewPack(asOfDate: '2026-09-11').first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReconChannelConfirmCard(channel: channel)),
      ),
    );

    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('确认对账'), findsOneWidget);
    expect(find.text('确认无误'), findsOneWidget);
    expect(find.text('已确认'), findsNothing);

    await tester.tap(find.text('确认无误'));
    await tester.pumpAndSettle();
    expect(find.text('已确认'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
