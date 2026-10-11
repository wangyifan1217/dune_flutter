import 'dart:convert';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/reconciliation/native_daily_reconciliation_page.dart';
import 'package:dunes_app/features/reconciliation/recon_report_summary.dart';
import 'package:dunes_app/features/reconciliation/reconciliation_shucai_models.dart';
import 'package:dunes_app/features/reconciliation/tag2_entity_models.dart';
import 'package:dunes_app/features/reconciliation/tag2_entity_table.dart';
import 'package:dunes_app/features/reconciliation/tag3_daily_models.dart';
import 'package:dunes_app/features/reconciliation/tag3_daily_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'recon_mobile_report_test.dart' as fixtures;

void main() {
  testWidgets(
    'small viewport keeps filter actions accessible and compact counts match both review periods',
    (tester) async {
      final day = fixtures.row('甲');
      final previous = fixtures.row('乙', period: 'PREV_MONTH');
      final cumulative = fixtures.row('丙', period: 'MONTH');
      Tag3DailyComment opinion(Tag3DailyRow row) => Tag3DailyComment.fromJson({
        'id': 42,
        'rowKey': row.rowKey,
        'period': row.period,
        'statDate': row.statDate,
        'kind': 'COMMENT',
        'body': '待核对',
      });
      await fixtures.phone(
        tester,
        Tag3DailyTable(
          rows: [day, previous, cumulative],
          comments: [
            fixtures.confirmation(day),
            fixtures.confirmation(previous),
            fixtures.confirmation(cumulative),
            opinion(day),
            opinion(day),
          ],
          myUserId: 7,
        ),
        width: 320,
        height: 640,
        scale: 1.5,
      );
      expect(find.byType(ChoiceChip), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('recon-summary-业务已确认')))
            .data,
        '2',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('recon-summary-意见')))
            .data,
        '1',
      );
      final summary = find.byKey(const ValueKey('recon-mobile-summary'));
      expect(tester.getSize(summary).height, lessThan(200));
      await tester.tap(find.byKey(const ValueKey('recon-filter-open')));
      await tester.pumpAndSettle();
      final apply = find.byKey(const ValueKey('recon-filter-apply'));
      final rect = tester.getRect(apply);
      expect(rect.bottom, lessThanOrEqualTo(640));
      expect(rect.height, greaterThanOrEqualTo(44));
      final last = find.widgetWithText(ChoiceChip, '无本地记录');
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      await tester.tap(last);
      await tester.tap(find.byTooltip('关闭筛选'));
      await tester.pumpAndSettle();
      expect(find.text('全部周期 · 无本地记录'), findsNothing);
      await fixtures.chooseFilter(tester, '日清');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('recon-summary-业务已确认')))
            .data,
        '1',
      );
      await fixtures.chooseFilter(tester, '本月累计');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('recon-summary-业务已确认')))
            .data,
        '0',
      );
      await tester.tap(find.byKey(const ValueKey('recon-filter-open')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '重置'));
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('recon-summary-业务已确认')))
            .data,
        '2',
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'progress matches visible identities, ignores cumulative and empty opinions',
    () {
      final day = fixtures.row('项目');
      final cumulative = fixtures.row('项目', period: 'MONTH');
      final foreign = fixtures.row('其他项目');
      final snapshot = Tag3DailySnapshot(
        asOfDate: '2026-10-09',
        rows: [day, day, cumulative],
        assignees: [],
        comments: [
          fixtures.confirmation(day),
          fixtures.confirmation(cumulative),
          fixtures.confirmation(foreign),
          Tag3DailyComment.fromJson({
            'id': 2,
            'rowKey': day.rowKey,
            'period': day.period,
            'statDate': day.statDate,
            'kind': 'COMMENT',
            'body': '   ',
          }),
          Tag3DailyComment.fromJson({
            'id': 3,
            'rowKey': day.rowKey,
            'period': day.period,
            'statDate': day.statDate,
            'kind': 'COMMENT',
            'body': '需要核对',
          }),
        ],
      );
      final progress = tag3ReportProgress(snapshot, 7);
      expect(progress.total, 1);
      expect(progress.businessConfirmed, 1);
      expect(progress.operationConfirmed, 0);
      expect(progress.opinions, 1);
      expect(progress.completed, 0);
      expect(progress.mine, isTrue);
      expect(progress.line, '业务已确认 1/1 条 · 运营已确认 0/1 条 · 意见 1 条');
    },
  );

  test('explicit stage prevents same-name people confirming both roles', () {
    final person = Tag3DailyPerson.fromJson({'userId': '7', 'name': '本人'});
    final r = fixtures.row('项目');
    final lanes = tag3DailyAuditLanes(
      assignee: Tag3DailyAssignee(
        rowKey: r.rowKey,
        businessUsers: [person],
        operationUsers: [person],
      ),
      comments: [fixtures.confirmation(r)],
      row: r,
    );
    expect(lanes[0].done, isTrue);
    expect(lanes[1].done, isFalse);
  });

  test(
    'entity source state overrides historical confirms after return to business',
    () {
      final row = Tag2EntityRow.fromJson({
        'rowKey': '主体',
        'rowType': 'DETAIL',
        'confirmationStatus': 'WAIT_BUSINESS',
      });
      final snapshot = Tag2EntitySnapshot(
        asOfDate: '2026-10-09',
        rows: [
          row,
          Tag2EntityRow.fromJson({'rowKey': '合计', 'rowType': 'TOTAL'}),
        ],
        comments: [
          Tag3DailyComment.fromJson({
            'id': 1,
            'rowKey': '主体',
            'kind': 'CONFIRM',
            'stage': 'BUSINESS',
            'userId': 7,
          }),
        ],
      );
      final progress = tag2ReportProgress(snapshot, 7);
      expect(progress.total, 1);
      expect(progress.businessConfirmed, 0);
      expect(progress.operationConfirmed, 0);
      expect(reconSummaryAmount('1,234.50'), 1234.5);
      for (final value in ['', '-', '13%', 'NaN', 'Infinity']) {
        expect(reconSummaryAmount(value), isNull);
      }
    },
  );

  testWidgets(
    'viewer filters role status and can read audit without gaining confirm permission',
    (tester) async {
      final confirmed = fixtures.row('已核对项目', confirm: false, comment: false);
      final pending = fixtures.row('未核对项目', confirm: false, comment: false);
      await fixtures.phone(
        tester,
        Tag3DailyTable(
          rows: [confirmed, pending],
          comments: [fixtures.confirmation(confirmed)],
          myUserId: 99,
        ),
        width: 320,
        scale: 1.3,
      );
      await fixtures.chooseFilter(tester, '业务已确认');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('recon-summary-业务已确认')))
            .data,
        '1',
      );
      expect(find.text('未核对项目'), findsNothing);
      expect(find.text('业务确认'), findsNothing);
      await fixtures.reveal(tester, find.text('查看审核记录'));
      await tester.tap(find.text('查看审核记录'));
      await tester.pumpAndSettle();
      expect(find.text('审核记录 · 当前筛选'), findsOneWidget);
      expect(find.textContaining('本人'), findsWidgets);
      expect(find.byType(FilledButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact summary counts daily and previous month reviews and omits money and cumulative',
    (tester) async {
      await fixtures.phone(
        tester,
        Tag3DailyTable(
          rows: [
            fixtures.row('甲'),
            fixtures.row('乙'),
            fixtures.row('甲', period: 'MONTH'),
          ],
        ),
        width: 320,
        scale: 1.3,
        height: 1600,
      );
      final summary = find.byKey(const ValueKey('recon-mobile-summary'));
      expect(
        find.descendant(of: summary, matching: find.byType(ExpansionTile)),
        findsNothing,
      );
      expect(
        find.descendant(of: summary, matching: find.textContaining('合计')),
        findsNothing,
      );
      expect(
        find.descendant(of: summary, matching: find.textContaining('汇总')),
        findsNothing,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('recon-summary-业务已确认')))
            .data,
        '0',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('recon-summary-运营已确认')))
            .data,
        '0',
      );
      expect(find.text('查看审核记录'), findsOneWidget);
      expect(find.text('查看意见记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'entity compact summary excludes total and retains source audit history',
    (tester) async {
      Tag2EntityRow entity(String key, String value, {bool total = false}) =>
          Tag2EntityRow.fromJson({
            'rowKey': key,
            'counterpartyName': key,
            'rowType': total ? 'TOTAL' : 'DETAIL',
            'confirmationStatus': 'WAIT_OPERATION',
            'assigned': false,
            'amounts': [
              {'key': 'prepayment', 'label': '期末预付款余额', 'display': value},
              {'key': 'invoice_tax_rate', 'label': '发票税率', 'display': '13%'},
            ],
          });
      await fixtures.phone(
        tester,
        Tag2EntityTable(
          rows: [
            entity('甲', '1,200.50'),
            entity('乙', ''),
            entity('合计', '99999', total: true),
          ],
          comments: [],
          busyKeys: {},
          onDrill: (_, _) {},
          onConfirm: (_) {},
          onComment: (_) {},
        ),
        width: 320,
        scale: 1.3,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('recon-summary-业务已确认')))
            .data,
        '2',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('recon-summary-运营已确认')))
            .data,
        '0',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('recon-summary-意见')))
            .data,
        '0',
      );
      expect(find.textContaining('99999'), findsNothing);
      expect(find.textContaining('期末预付款余额合计'), findsNothing);
      await fixtures.reveal(tester, find.text('查看审核记录'));
      await tester.tap(find.text('查看审核记录'));
      await tester.pumpAndSettle();
      expect(find.text('源系统已有确认状态，暂无本地操作记录。'), findsWidgets);
      expect(find.text('业务确认'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date cards use detail scope instead of global historical counters and stay current after return',
    (tester) async {
      final date = tag3DailyYmd(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      var detailRequests = 0;
      var opinionCount = 1;
      VoidCallback? back;
      final client = MockClient((request) async {
        final path = request.url.path;
        final asOf = request.url.queryParameters['asOfDate'] ?? date;
        Map<String, dynamic> data;
        if (path.endsWith('/dates')) {
          data = {
            'items': [
              {
                'asOfDate': date,
                'tag3BusinessConfirmRows': 999,
                'tag3OperationConfirmRows': 999,
                'tag3CommentCount': 999,
              },
            ],
          };
        } else if (path.endsWith('/tag3-daily')) {
          detailRequests++;
          data = {
            'asOfDate': asOf,
            'rows': [
              {
                'rowKey': '项目',
                'projectName': '项目',
                'period': 'DAY',
                'statDate': date,
                'periodLabel': date,
                'confirmationStatus': 'WAIT_BUSINESS',
                'canConfirm': false,
                'canComment': false,
              },
            ],
            'comments': [
              {
                'id': 1,
                'rowKey': '项目',
                'period': 'DAY',
                'statDate': date,
                'kind': 'CONFIRM',
                'stage': 'BUSINESS',
              },
              for (var i = 0; i < opinionCount; i++)
                {
                  'id': i + 10,
                  'rowKey': '项目',
                  'period': 'DAY',
                  'statDate': date,
                  'kind': 'COMMENT',
                  'body': '意见$i',
                },
            ],
          };
        } else {
          data = {'asOfDate': asOf, 'rows': [], 'comments': []};
        }
        return http.Response(
          jsonEncode({'success': true, 'data': data}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await http.runWithClient(() async {
        await fixtures.phone(
          tester,
          NativeDailyReconciliationPage(
            session: const AuthSession(
              phone: '13800000000',
              userId: 99,
              token: 'test',
              apiBase: 'https://test.invalid',
              roles: [],
            ),
            onChromeChanged: (chrome) => back = chrome.onBack,
          ),
          height: 1100,
        );
        expect(find.textContaining('999'), findsNothing);
        expect(find.text('业务已确认 1/1 条 · 运营已确认 0/1 条 · 意见 1 条'), findsOneWidget);
        expect(detailRequests, 1);
        opinionCount = 2;
        await tester.tap(find.text('标签三 · 业财一体-日清月结'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('recon-summary-业务已确认')))
              .data,
          '1',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('recon-summary-意见')))
              .data,
          '2',
        );
        expect(back, isNotNull);
        back!();
        await tester.pumpAndSettle();
        expect(find.text('业务已确认 1/1 条 · 运营已确认 0/1 条 · 意见 2 条'), findsOneWidget);
        expect(detailRequests, 2);
        await tester.pumpWidget(const SizedBox());
      }, () => client);
    },
  );
}
