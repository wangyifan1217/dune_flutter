import 'package:dunes_app/features/reconciliation/tag3_daily_table.dart';
import 'package:dunes_app/features/reconciliation/tag2_entity_table.dart';
import 'package:dunes_app/features/reconciliation/tag2_entity_models.dart';
import 'package:dunes_app/features/reconciliation/recon_pinned_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'recon_mobile_report_test.dart' as fixtures;

String? count(WidgetTester tester, String label) =>
    tester.widget<Text>(find.byKey(ValueKey('recon-summary-$label'))).data;
void main() {
  testWidgets(
    'desktop filters table and summary together and opens centered records',
    (tester) async {
      final first = fixtures.row('已核对项目');
      await fixtures.phone(
        tester,
        Tag3DailyTable(
          rows: [
            first,
            fixtures.row('待核对项目'),
            fixtures.row('累计项目', period: 'MONTH'),
          ],
          comments: [fixtures.confirmation(first)],
          myUserId: 99,
        ),
        width: 1280,
        height: 850,
      );
      expect(find.byType(ReconPinnedTable), findsOneWidget);
      expect(
        find.byKey(const ValueKey('recon-desktop-summary')),
        findsOneWidget,
      );
      expect(count(tester, '业务已确认'), '1');
      expect(
        tester
            .getSize(find.byKey(const ValueKey('recon-desktop-summary')))
            .height,
        lessThan(80),
      );
      await tester.tap(find.text('全部').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('业务已确认').last);
      await tester.pumpAndSettle();
      expect(find.text('待核对项目'), findsNothing);
      expect(find.text('累计项目'), findsNothing);
      expect(find.text('已核对项目'), findsOneWidget);
      await tester.tap(find.text('查看审核记录'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.textContaining('本人'), findsWidgets);
      await tester.tap(find.byTooltip('关闭汇总记录'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '不存在');
      await tester.pumpAndSettle();
      expect(find.text('没有符合条件的记录'), findsOneWidget);
      expect(count(tester, '业务已确认'), '0');
      await tester.tap(find.text('重置筛选'));
      await tester.pumpAndSettle();
      expect(find.text('待核对项目'), findsOneWidget);
      expect(count(tester, '业务已确认'), '1');
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [600.0, 760.0]) {
    testWidgets(
      'desktop layout fits a $width panel in a larger window with enlarged text',
      (tester) async {
        await fixtures.phone(
          tester,
          SizedBox(
            width: width,
            child: Tag3DailyTable(rows: [fixtures.row('长项目名称用于检查窄桌面布局')]),
          ),
          width: 1440,
          height: 900,
          scale: 1.5,
        );
        expect(
          find.byKey(const ValueKey('recon-desktop-summary')),
          findsOneWidget,
        );
        expect(find.byType(ReconPinnedTable), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'entity desktop shares compact counts and search without changing confirmation actions',
    (tester) async {
      final entity = Tag2EntityRow.fromJson({
        'rowKey': '甲',
        'counterpartyName': '测试主体',
        'confirmationStatus': 'WAIT_OPERATION',
        'rowType': 'DETAIL',
        'amounts': [],
      });
      await fixtures.phone(
        tester,
        Tag2EntityTable(
          rows: [entity],
          comments: [],
          busyKeys: {},
          onDrill: (_, _) {},
          onConfirm: (_) {},
          onComment: (_) {},
        ),
        width: 1100,
        height: 800,
      );
      expect(count(tester, '业务已确认'), '1');
      expect(count(tester, '运营已确认'), '0');
      expect(find.byType(ReconPinnedTable), findsOneWidget);
      await tester.tap(find.text('查看审核记录'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('源系统已有确认状态，暂无本地操作记录。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
