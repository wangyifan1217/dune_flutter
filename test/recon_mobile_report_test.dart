import 'package:dunes_app/features/reconciliation/recon_mobile_report.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/reconciliation/recon_pinned_table.dart';
import 'package:dunes_app/features/reconciliation/tag2_entity_models.dart';
import 'package:dunes_app/features/reconciliation/tag2_entity_table.dart';
import 'package:dunes_app/features/reconciliation/tag3_daily_models.dart';
import 'package:dunes_app/features/reconciliation/tag3_daily_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Tag3DailyRow row(
  String name, {
  String period = 'DAY',
  String paymentTerm = 'D+1',
  String statDate = '2026-10-09',
  String channel = '渠道甲',
  double salesScale = 0,
  bool confirm = true,
  bool comment = true,
}) => Tag3DailyRow(
  rowKey: name,
  channelCategoryL1Name: channel,
  projectName: name,
  period: period,
  periodLabel: period == 'DAY' ? statDate : '2026-10',
  statDate: statDate,
  paymentTerm: paymentTerm,
  salesAmount: 15000,
  salesScale: salesScale,
  writeOffAmount: 13000,
  profitAmount: 2000,
  cashFlowAmount: 3000,
  cashReceivableAmount: 12000,
  cashPaidAmount: 11800,
  cashReceivableDiff: 200,
  subsidyReceivableAmount: 500,
  confirmationStatus: 'WAIT_BUSINESS',
  confirmationStatusLabel: '待业务确认',
  canConfirm: confirm,
  canComment: comment,
  canConfirmStage: 'BUSINESS',
);

Tag3DailyComment confirmation(Tag3DailyRow r) => Tag3DailyComment(
  id: 1,
  rowKey: r.rowKey,
  period: r.period,
  statDate: r.statDate,
  periodLabel: r.periodLabel,
  projectName: r.projectName,
  userId: 7,
  userName: '本人',
  kind: 'CONFIRM',
  stage: 'BUSINESS',
  body: '',
  createdAt: '2026-10-10T10:00:00',
);

Future<void> phone(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double scale = 1,
  double height = 780,
}) async {
  tester.view.reset();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: DunesTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: Column(
            children: [
              const SizedBox(height: 140),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> chooseFilter(WidgetTester tester, String label) async {
  await reveal(tester, find.byKey(const ValueKey('recon-filter-open')));
  await tester.tap(find.byKey(const ValueKey('recon-filter-open')));
  await tester.pumpAndSettle();
  final chip = find.widgetWithText(ChoiceChip, label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.tap(find.byKey(const ValueKey('recon-filter-apply')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sales scale appears on the card and in business details', (
    tester,
  ) async {
    await phone(
      tester,
      Tag3DailyTable(rows: [row('销售规模项目', salesScale: 24680.5)]),
    );
    expect(find.text('销售规模'), findsOneWidget);
    expect(find.text('24680.50'), findsOneWidget);
    await reveal(tester, find.text('查看明细'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看明细'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('销售规模')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('24680.50')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('15000.00')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'project groups keep dates and actions separate and do not merge channels',
    (tester) async {
      final older = row('同一项目', statDate: '2026-10-07');
      final newer = row('同一项目', statDate: '2026-10-08', paymentTerm: 'D+2');
      final monthly = row('同一项目', period: 'MONTH');
      final otherChannel = row('同一项目', channel: '渠道乙');
      final confirmed = <String>[];
      await phone(
        tester,
        Tag3DailyTable(
          rows: [newer, monthly, older, otherChannel],
          onConfirm: (r) => confirmed.add(r.actionId),
          onComment: (_) {},
        ),
        width: 320,
        scale: 1.3,
        height: 3200,
      );
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.text('同一项目'), findsNWidgets(2));
      final oldEntry = find.byKey(ValueKey('recon-entry-${older.actionId}'));
      final newEntry = find.byKey(ValueKey('recon-entry-${newer.actionId}'));
      final monthEntry = find.byKey(
        ValueKey('recon-entry-${monthly.actionId}'),
      );
      expect(
        find.descendant(of: oldEntry, matching: find.text('2026-10-07')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: newEntry, matching: find.text('2026-10-08')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(oldEntry).dy,
        lessThan(tester.getTopLeft(newEntry).dy),
      );
      expect(
        find.descendant(of: monthEntry, matching: find.text('本月累计')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: monthEntry, matching: find.byType(FilledButton)),
        findsNothing,
      );
      await tester.tap(
        find.descendant(
          of: newEntry,
          matching: find.widgetWithText(FilledButton, '业务确认'),
        ),
      );
      await tester.pumpAndSettle();
      expect(confirmed, [newer.actionId]);
      await tester.tap(
        find.descendant(of: oldEntry, matching: find.text('查看明细')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.textContaining('2026-10-07'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.textContaining('2026-10-08'),
        ),
        findsNothing,
      );
      await tester.tap(find.byTooltip('关闭明细'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 3200));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'D+2');
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('2026-10-08'), findsOneWidget);
      expect(find.text('2026-10-07'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all periods and payment terms are visible in the main list by default',
    (tester) async {
      await phone(
        tester,
        Tag3DailyTable(
          rows: [
            row('次日回款项目'),
            row('隔日回款项目', paymentTerm: 'D+2'),
            row('上月项目', period: 'PREV_MONTH'),
            row('累计项目', period: 'MONTH'),
          ],
          onConfirm: (_) {},
          onComment: (_) {},
        ),
        height: 2400,
      );
      expect(find.byKey(const ValueKey('recon-filter-open')), findsOneWidget);
      expect(find.text('次日回款项目'), findsOneWidget);
      expect(find.text('隔日回款项目'), findsOneWidget);
      expect(find.text('上月项目'), findsOneWidget);
      expect(find.text('累计项目'), findsOneWidget);
      expect(find.text('回款周期 D+2'), findsOneWidget);
      final cumulative = find.ancestor(
        of: find.text('累计项目'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(of: cumulative, matching: find.text('本月累计')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: cumulative, matching: find.byType(FilledButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: cumulative, matching: find.text('提意见')),
        findsNothing,
      );
      await tester.enterText(find.byType(TextField), 'D+2');
      await tester.pumpAndSettle();
      expect(find.text('隔日回款项目'), findsOneWidget);
      expect(find.text('次日回款项目'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await chooseFilter(tester, '日清');
      await tester.pumpAndSettle();
      expect(find.text('隔日回款项目'), findsOneWidget);
      expect(find.text('累计项目'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'outer record links open separate confirmation and opinion sheets',
    (tester) async {
      final target = row('记录核对项目');
      Tag3DailyComment comment(int id, String kind, String body) =>
          Tag3DailyComment(
            id: id,
            rowKey: target.rowKey,
            period: target.period,
            statDate: target.statDate,
            periodLabel: target.periodLabel,
            projectName: target.projectName,
            userId: 7,
            userName: '测试人员',
            kind: kind,
            stage: 'BUSINESS',
            body: body,
            createdAt: '2026-10-10T10:00:00',
          );
      await phone(
        tester,
        Tag3DailyTable(
          rows: [target],
          comments: [
            comment(1, 'CONFIRM', '确认备注内容'),
            comment(2, 'COMMENT', '意见备注内容'),
            comment(3, 'REJECT', '驳回备注内容'),
          ],
        ),
        width: 320,
        scale: 1.3,
      );
      Future<void> open(String label) async {
        await reveal(tester, find.text(label).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).first);
        await tester.pumpAndSettle();
      }

      await open('确认记录');
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.textContaining('确认备注内容')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.textContaining('意见备注内容')),
        findsNothing,
      );
      await tester.tap(find.byTooltip('关闭记录'));
      await tester.pumpAndSettle();
      await open('意见记录');
      expect(
        find.descendant(of: sheet, matching: find.textContaining('意见备注内容')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.textContaining('驳回备注内容')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.textContaining('确认备注内容')),
        findsNothing,
      );
      await tester.tap(find.byTooltip('关闭记录'));
      await tester.pumpAndSettle();
      await open('查看明细');
      expect(
        find.descendant(of: sheet, matching: find.text('确认记录')),
        findsNothing,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('意见记录')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'card actions retain confirmation dialog and busy state blocks all mutations',
    (tester) async {
      final target = row('需要核对的项目');
      var confirms = 0;
      var opinions = 0;
      var busy = false;
      late StateSetter update;
      await phone(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Tag3DailyTable(
              rows: [target],
              busyKeys: busy ? {target.actionId} : {},
              onConfirm: (r) async {
                final result = await showTag3DailyActionDialog(
                  context: context,
                  row: r,
                  confirm: true,
                );
                if (result != null) confirms++;
              },
              onComment: (_) => opinions++,
            );
          },
        ),
      );
      await reveal(tester, find.text('业务确认'));
      await tester.tap(find.text('业务确认'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('确定以业务身份确认'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(confirms, 0);
      await tester.tap(find.text('提意见'));
      expect(opinions, 1);
      update(() => busy = true);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '提交中…'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '提意见'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'detail sheet preserves the list search, filter and scroll position',
    (tester) async {
      await phone(
        tester,
        Tag3DailyTable(
          rows: [row('项目甲'), row('项目乙')],
          onConfirm: (_) {},
          onComment: (_) {},
        ),
      );
      await tester.enterText(find.byType(TextField), '项目');
      await chooseFilter(tester, '待我确认');
      await tester.pumpAndSettle();
      await reveal(tester, find.text('查看明细').first);
      final scrollable = find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      final offset = tester.state<ScrollableState>(scrollable).position.pixels;
      await tester.tap(find.text('查看明细').first);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );
      await tester.tap(find.byTooltip('关闭明细'));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        closeTo(offset, 0.01),
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '项目',
      );
      expect(find.text('全部周期 · 待我确认'), findsOneWidget);
    },
  );

  testWidgets('search remains usable in the space left by the phone keyboard', (
    tester,
  ) async {
    await phone(
      tester,
      Tag3DailyTable(
        rows: [row('键盘测试项目')],
        onConfirm: (_) {},
        onComment: (_) {},
      ),
      width: 320,
      height: 360,
    );
    await tester.enterText(find.byType(TextField), '键盘');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('业务确认'),
      120,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('业务确认'), findsOneWidget);
    expect(tester.getRect(find.text('业务确认')).center.dy, lessThan(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone uses cards, searches, filters by permission and keeps period-specific actions',
    (tester) async {
      final day = row('可确认项目');
      final other = row('只读项目', confirm: false, comment: false);
      await phone(
        tester,
        Tag3DailyTable(
          rows: [
            day,
            other,
            row('月累计项目', period: 'MONTH'),
          ],
          onConfirm: (_) {},
          onComment: (_) {},
        ),
      );
      expect(find.byType(ReconPinnedTable), findsNothing);
      expect(find.byType(ReconMobileReport), findsOneWidget);
      await chooseFilter(tester, '待我确认');
      await tester.pumpAndSettle();
      expect(find.text('可确认项目'), findsOneWidget);
      expect(find.text('只读项目'), findsNothing);
      await tester.enterText(find.byType(TextField), '不存在');
      await tester.pumpAndSettle();
      expect(find.text('没有符合条件的记录'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await chooseFilter(tester, '本月累计');
      await tester.pumpAndSettle();
      expect(find.text('月累计项目'), findsOneWidget);
      await reveal(tester, find.text('查看明细'));
      await tester.tap(find.text('查看明细'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('仅供查看，不参与确认'),
        ),
        findsOneWidget,
      );
      expect(find.text('提意见'), findsNothing);
      expect(find.text('以业务身份确认'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirms directly from cards and updates the pending and confirmed filters',
    (tester) async {
      final first = row('第一个项目');
      final second = row('第二个项目');
      late StateSetter update;
      final comments = <Tag3DailyComment>[];
      await phone(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Tag3DailyTable(
              rows: [first, second],
              comments: comments,
              myUserId: 7,
              onConfirm: (r) => update(() => comments.add(confirmation(r))),
              onComment: (_) {},
            );
          },
        ),
      );
      await reveal(tester, find.text('业务确认').first);
      expect(
        tester.getSize(find.widgetWithText(FilledButton, '业务确认').first).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.text('业务确认').first);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(Card), matching: find.text('我已确认')),
        findsOneWidget,
      );
      expect(find.byType(BottomSheet), findsNothing);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      await chooseFilter(tester, '待我确认');
      await tester.pumpAndSettle();
      expect(find.text('第一个项目'), findsNothing);
      expect(find.text('第二个项目'), findsOneWidget);
      await chooseFilter(tester, '我已确认');
      await tester.pumpAndSettle();
      expect(find.text('第一个项目'), findsOneWidget);
      expect(find.text('第二个项目'), findsNothing);
    },
  );

  testWidgets('320px screen supports enlarged text and metric drilldown', (
    tester,
  ) async {
    var drills = 0;
    await phone(
      tester,
      Tag3DailyTable(
        rows: [row('长项目名称用于检验手机排版')],
        onConfirm: (_) {},
        onComment: (_) {},
        onReceivableTap: (_) => drills++,
      ),
      width: 320,
      scale: 1.3,
    );
    await reveal(tester, find.text('12000.00'));
    await tester.tap(find.text('12000.00'));
    await tester.pumpAndSettle();
    expect(drills, 1);
    await reveal(tester, find.text('查看明细'));
    await tester.tap(find.text('查看明细'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(FilledButton),
      ),
      findsNothing,
    );
    await tester.tap(find.byTooltip('关闭明细'));
    await tester.pumpAndSettle();
    expect(find.text('业务确认'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'entity cards preserve reject permission and full names while hiding totals',
    (tester) async {
      final snap = Tag2EntitySnapshot.fromJson({
        'rows': [
          {
            'rowKey': 'entity',
            'rowType': 'DETAIL',
            'provinceName': '广东',
            'counterpartyName': '对方主体名称',
            'ourEntityName': '我方主体完整名称',
            'supplierName': '供应商',
            'confirmationStatus': 'WAIT_OPERATION',
            'canConfirmStage': 'OPERATION',
            'currentHandlers': '运营人员',
            'amounts': [
              {
                'key': 'transit',
                'label': '在途资金',
                'display': '100.00',
                'drill': true,
              },
            ],
          },
          {'rowKey': 'total', 'rowType': 'TOTAL', 'amounts': []},
        ],
      });
      var rejected = 0;
      await phone(
        tester,
        Tag2EntityTable(
          rows: snap.rows,
          comments: [],
          busyKeys: {},
          onDrill: (_, _) {},
          onConfirm: (_) {},
          onComment: (_) {},
          onReject: (_) => rejected++,
        ),
      );
      await reveal(tester, find.text('驳回到业务'));
      expect(find.text('运营确认'), findsOneWidget);
      await tester.tap(find.text('驳回到业务'));
      expect(rejected, 1);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.text('查看明细').first);
      await tester.pumpAndSettle();
      expect(find.text('我方主体完整名称'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭明细'));
      await tester.pumpAndSettle();
      expect(find.text('合计'), findsNothing);
      expect(find.text('查看明细'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('business and operation lanes show assignee names', (
    tester,
  ) async {
    final item = row(
      '平安项目',
      channel: '平安',
      period: 'PREV_MONTH',
      confirm: false,
    );
    await phone(
      tester,
      Tag3DailyTable(
        rows: [item],
        assignees: const [
          Tag3DailyAssignee(
            rowKey: '平安项目',
            businessUsers: [
              Tag3DailyPerson(userId: '1', name: '王奕凡', phone: ''),
            ],
            operationUsers: [
              Tag3DailyPerson(userId: '2', name: '李同池', phone: ''),
            ],
          ),
        ],
        onConfirm: (_) {},
        onComment: (_) {},
      ),
      height: 1400,
    );
    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('待业务确认'), findsNothing);
    expect(find.text('业务：王奕凡'), findsOneWidget);
    expect(find.text('运营：李同池'), findsOneWidget);
    expect(find.text('业务：王奕凡 未确认'), findsNothing);
    expect(find.byIcon(Icons.schedule), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
