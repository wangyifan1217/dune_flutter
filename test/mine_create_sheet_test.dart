import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/profile/mine_home.dart';

void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    required Size surface,
    VoidCallback? onWorkbench,
    bool showProposals = true,
  }) async {
    await tester.binding.setSurfaceSize(surface);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    showMineCreateSheet(
                      context,
                      showProposals: showProposals,
                      onSales: () {},
                      onPurchase: () {},
                      onApproval: () {},
                      onMeeting: () {},
                      onKnowledge: () {},
                      onWorkbench: onWorkbench == null
                          ? null
                          : () {
                              opened = true;
                              onWorkbench();
                            },
                    );
                  },
                  child: const Text('打开新建'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('打开新建'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(opened, isFalse);
  }

  testWidgets('短屏展开新建面板不溢出，工作台在最上面且图标可见', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openSheet(
      tester,
      surface: const Size(390, 640),
      onWorkbench: () {},
    );

    expect(find.text('更多'), findsOneWidget);
    expect(find.text('新建'), findsNothing);
    expect(find.text('工作台'), findsOneWidget);
    expect(find.text('打开任务与协作工作台'), findsOneWidget);
    expect(find.byIcon(Icons.apps_rounded), findsOneWidget);
    expect(find.byIcon(Icons.request_quote_outlined), findsOneWidget);
    expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
    expect(find.byIcon(Icons.add_task_rounded), findsOneWidget);
    expect(find.byIcon(Icons.article_rounded), findsOneWidget);
    expect(find.text('销'), findsNothing);
    expect(find.text('采'), findsNothing);
    expect(find.text('审'), findsNothing);

    final workbenchY = tester.getTopLeft(find.text('工作台')).dy;
    final salesY = tester.getTopLeft(find.text('销售提案')).dy;
    expect(workbenchY, lessThan(salesY));

    await tester.scrollUntilVisible(
      find.text('企业知识库'),
      80,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('企业知识库'), findsOneWidget);
    expect(find.byIcon(Icons.auto_stories_rounded), findsOneWidget);
  });

  testWidgets('不传工作台回调时面板不出现工作台', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openSheet(tester, surface: const Size(390, 800));

    expect(find.text('更多'), findsOneWidget);
    expect(find.text('工作台'), findsNothing);
    expect(find.text('销售提案'), findsOneWidget);
  });

  testWidgets('大字号下会议纪要仍完整落在面板内', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(() {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    showMineCreateSheet(
                      context,
                      onSales: () {},
                      onPurchase: () {},
                      onApproval: () {},
                      onMeeting: () {},
                      onKnowledge: () {},
                      onWorkbench: () {},
                    );
                  },
                  child: const Text('打开新建'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('打开新建'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('会议纪要'),
      120,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final sheet = tester.getRect(find.byType(Material).last);
    final meeting = tester.getRect(find.text('会议纪要'));
    expect(meeting.bottom, lessThanOrEqualTo(sheet.bottom + 1));
  });
}
