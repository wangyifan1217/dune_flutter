import 'package:dunes_app/features/qianji/fund_secondment_kanban.dart';
import 'package:dunes_app/features/qianji/fund_secondment_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('summary parses overdue routes and lenders for the boss board', () {
    final summary = FundSecondmentSummary.fromJson({
      'count': 9,
      'settledCount': 3,
      'unsettledCount': 6,
      'borrowTotalWan': 773,
      'repaidTotalWan': 534,
      'remainingTotalWan': 239,
      'overdueCount': 1,
      'overdueRemainingWan': 12,
      'dueSoonCount': 2,
      'dueSoonRemainingWan': 40,
      'borrowers': [
        {'subject': '积分', 'count': 2, 'remainingWan': 35},
      ],
      'lenders': [
        {'subject': '中石油', 'count': 2, 'remainingWan': 120},
      ],
      'routes': [
        {
          'borrowSubject': '积分',
          'paySubject': '中石油',
          'count': 2,
          'remainingWan': 35,
        },
      ],
    });
    expect(summary.remainingTotalWan, 239);
    expect(summary.overdueCount, 1);
    expect(summary.lenders.single.subject, '中石油');
    expect(summary.routes.single.borrowSubject, '积分');
    expect((summary.repaidRatio * 100).round(), 69);
    expect(formatFundSecondmentWan(239), '239万');
  });

  test('missing board fields stay empty so old APIs still parse', () {
    final summary = FundSecondmentSummary.fromJson({
      'count': 2,
      'settledCount': 1,
      'borrowTotalWan': 10,
      'repaidTotalWan': 4,
      'remainingTotalWan': 6,
    });
    expect(summary.unsettledCount, 1);
    expect(summary.overdueCount, 0);
    expect(summary.routes, isEmpty);
    expect(summary.lenders, isEmpty);
  });

  testWidgets('kanban shows remaining money, who-owes-whom, and overdue', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FundSecondmentKanban(
            summary: FundSecondmentSummary(
              count: 9,
              settledCount: 3,
              unsettledCount: 6,
              borrowTotalWan: 773,
              repaidTotalWan: 534,
              remainingTotalWan: 239,
              overdueCount: 1,
              overdueRemainingWan: 12,
              routes: const [
                FundSecondmentRouteBucket(
                  borrowSubject: '积分',
                  paySubject: '中石油',
                  count: 2,
                  remainingWan: 35,
                ),
              ],
              lenders: const [
                FundSecondmentSubjectBucket(
                  subject: '中石油',
                  count: 2,
                  remainingWan: 120,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('待收回'), findsOneWidget);
    expect(find.text('239万'), findsOneWidget);
    expect(find.textContaining('已收回 534万'), findsOneWidget);
    expect(find.text('未还清 6 笔'), findsOneWidget);
    expect(find.text('谁欠谁'), findsOneWidget);
    expect(find.text('积分  →  中石油'), findsOneWidget);
    expect(find.textContaining('已过预计还款日'), findsOneWidget);
  });

  testWidgets('cleared board tells the boss there is nothing left outside', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FundSecondmentKanban(
            summary: FundSecondmentSummary(
              count: 3,
              settledCount: 3,
              borrowTotalWan: 100,
              repaidTotalWan: 100,
              remainingTotalWan: 0,
            ),
          ),
        ),
      ),
    );

    expect(find.text('目前没有未收回的钱'), findsOneWidget);
    expect(find.text('0万'), findsOneWidget);
    expect(find.text('谁欠谁'), findsNothing);
  });
}
