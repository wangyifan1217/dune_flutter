import 'package:dunes_app/features/xrxs/xrxs_opening_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows opening progress and a clear message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: XrxsOpeningIndicator())),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('正在打开薪人薪事…'), findsOneWidget);
  });
}
