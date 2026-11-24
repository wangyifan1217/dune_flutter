// 灯塔顶栏「灯塔  资管  业务  运营」：给了 onOps 才出现第四格，选中态跟着 opsSelected 走。
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_zg.dart';

Widget _host({required bool opsSelected, VoidCallback? onOps}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: LhBrandSwitch(
          assetSelected: false,
          onLighthouse: () {},
          onAsset: () {},
          onBiz: () {},
          opsSelected: opsSelected,
          onOps: onOps,
          selectedColor: Colors.black,
          idleColor: Colors.grey,
          trackColor: const Color(0x142B2147),
          thumbColor: Colors.white,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('不给 onOps 时只有三格', (tester) async {
    await tester.pumpWidget(_host(opsSelected: false));
    expect(find.text('业务'), findsOneWidget);
    expect(find.text('运营'), findsNothing);
  });

  testWidgets('给了 onOps 出现「运营」，点了回调', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_host(opsSelected: false, onOps: () => tapped++));
    expect(find.text('运营'), findsOneWidget);
    await tester.tap(find.text('运营'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tapped, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opsSelected 时「运营」是选中态', (tester) async {
    await tester.pumpWidget(_host(opsSelected: true, onOps: () {}));
    await tester.pump(const Duration(milliseconds: 300));
    final semantics = tester.getSemantics(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '运营',
      ),
    );
    expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
  });
}
