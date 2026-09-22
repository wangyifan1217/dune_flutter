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

  test('routes that do not add up to remaining are not netted', () {
    final summary = FundSecondmentSummary(
      remainingTotalWan: 239,
      routes: const [
        FundSecondmentRouteBucket(
          borrowSubject: '积分',
          paySubject: '中石油',
          remainingWan: 35,
        ),
      ],
    );
    expect(fundSecondmentNetting(summary), isNull);
  });

  test('bridge subjects net down to who is still advancing money', () {
    final netting = fundSecondmentNetting(_bridgeBoard());
    expect(netting, isNotNull);
    expect(netting!.grossWan, 1205);
    expect(netting.netWan, 708);
    expect(netting.bridgeWan, 497);
    expect(
      netting.netLenders.map((item) => (item.subject, item.netWan)).toList(),
      [
        ('其他（厦油借款）', 300),
        ('中石化', 150),
        ('运营商和出行', 144),
        ('积分', 114),
      ],
    );
    expect(netting.netLenders.map((item) => item.subject), isNot(contains('中石油')));
    expect(netting.bridgeSubjects.map((item) => item.subject).toList(), [
      '中石油',
      '中石化',
    ]);
    final sinopec = netting.netLenders.firstWhere((item) => item.subject == '中石化');
    expect(sinopec.isBridge, isTrue);
    expect(sinopec.owedWan, 350);
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
    expect(find.text('谁还在垫钱'), findsOneWidget);
    expect(find.text('积分  欠  中石油'), findsOneWidget);
    expect(find.text('中石油'), findsOneWidget);
    expect(find.text('120万'), findsOneWidget);
    expect(find.text('借款主体还欠付款主体'), findsOneWidget);
    expect(find.textContaining('→'), findsNothing);
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

  testWidgets('phone APP still shows who is advancing money', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FundSecondmentKanban(
            summary: FundSecondmentSummary(
              count: 9,
              unsettledCount: 6,
              remainingTotalWan: 239,
              borrowTotalWan: 773,
              repaidTotalWan: 534,
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

    expect(find.text('谁欠谁'), findsOneWidget);
    expect(find.text('谁还在垫钱'), findsOneWidget);
    expect(find.text('付款主体未收回余额'), findsOneWidget);
    expect(find.text('中石油'), findsOneWidget);
    expect(find.text('120万'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bridge board keeps document total and nets the pad column', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FundSecondmentKanban(summary: _bridgeBoard()),
        ),
      ),
    );

    expect(find.text('待收回'), findsOneWidget);
    expect(find.text('1205万'), findsOneWidget);
    expect(find.textContaining('还要归还 708万'), findsOneWidget);
    expect(find.textContaining('497万'), findsOneWidget);
    expect(find.text('去掉过桥后还垫在外面'), findsOneWidget);
    expect(find.text('150万'), findsOneWidget);
    expect(find.text('过桥'), findsOneWidget);
    expect(find.text('297万'), findsNothing);
    expect(find.textContaining('中石油、中石化两边都有账'), findsOneWidget);
    expect(find.text('其他（兴业贷款）  欠  中石化'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

FundSecondmentSummary _bridgeBoard() {
  FundSecondmentRouteBucket route(String from, String to, double wan) {
    return FundSecondmentRouteBucket(
      borrowSubject: from,
      paySubject: to,
      remainingWan: wan,
    );
  }

  return FundSecondmentSummary(
    count: 27,
    settledCount: 19,
    unsettledCount: 8,
    borrowTotalWan: 2306,
    repaidTotalWan: 1106,
    remainingTotalWan: 1205,
    routes: [
      route('其他（兴业贷款）', '中石化', 350),
      route('中石油', '其他（厦油借款）', 300),
      route('其他（兴业贷款）', '中石油', 197),
      route('中石化', '中石油', 100),
      route('中石化', '运营商和出行', 100),
      route('中石油', '积分', 100),
      route('中石油', '运营商和出行', 44),
      route('其他（退股东款）', '积分', 14),
    ],
    lenders: const [
      FundSecondmentSubjectBucket(subject: '中石化', remainingWan: 350),
      FundSecondmentSubjectBucket(subject: '其他（厦油借款）', remainingWan: 300),
      FundSecondmentSubjectBucket(subject: '中石油', remainingWan: 297),
      FundSecondmentSubjectBucket(subject: '运营商和出行', remainingWan: 144),
      FundSecondmentSubjectBucket(subject: '积分', remainingWan: 114),
    ],
  );
}
