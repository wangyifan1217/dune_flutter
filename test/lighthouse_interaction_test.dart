import 'dart:convert';
import 'dart:typed_data';

import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/chat/chat_lighthouse_card.dart';
import 'package:dunes_app/features/conversation/comm_unread_notifier.dart';
import 'package:dunes_app/features/conversation/conversation_service.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_card_share.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_feedback.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_hero_metric.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_period_bar.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_product_rules.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_shared_card_data.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_service.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_scroll_text.dart';
import 'package:dunes_app/features/lighthouse/native_lighthouse_page.dart';
import 'package:dunes_app/features/workbench/workbench_badge_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const session = AuthSession(
  phone: 'test',
  userId: 1,
  token: 'test',
  apiBase: 'http://127.0.0.1/api/v1',
  roles: [],
  lighthouseAccess: true,
);

Map<String, dynamic> row(String name, {bool child = false}) => {
  'name': name,
  'group': '能源',
  'sales': 9000000,
  'verifiedSales': 5000000,
  'gmv': 10000000,
  'profit': 200000,
  'netProfit': 160000,
  'revenue': 300000,
  'totalCost': 320000,
  'projectCost': 300000,
  'cost': 20000,
  'prepaid': -50000,
  'trend': {
    'labels': ['09.26', '09.27', '09.28'],
    'profit': [100000, 150000, 200000],
    'sales': [6000000, 7000000, 9000000],
    'verifiedSales': [3000000, 4000000, 5000000],
    'gmv': [6000000, 8000000, 10000000],
    'revenue': [200000, 250000, 300000],
    'totalCost': [200000, 250000, 320000],
    'prepaid': [-30000, -40000, -50000],
  },
  if (!child) 'children': [row('湖北细分', child: true)],
};

Future<void> mountPage(
  WidgetTester tester, {
  double width = 390,
  List<Map<String, dynamic>> notices = const [],
  List<Map<String, dynamic>> Function()? noticesProvider,
  Duration refreshDelay = Duration.zero,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = Size(width, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final rows = [row('满减券（交易）'), row('中石化普惠现金券（交易）'), row('中石油普惠现金券（交易）')];
  var summaryRequests = 0;
  final client = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/summary')) {
      summaryRequests++;
      if (summaryRequests > 1 && refreshDelay > Duration.zero) {
        await Future<void>.delayed(refreshDelay);
      }
    }
    final data = path.endsWith('/dimension')
        ? {'rows': rows}
        : path.endsWith('/summary')
        ? {
            'sales': 27000000,
            'verifiedSales': 15000000,
            'gmv': 30000000,
            'profit': 600000,
            'revenue': 900000,
            'totalCost': 960000,
            'netProfit': 480000,
            'heroSeriesLabels': ['07月', '08月', '09月'],
            'verifiedSalesSeries': [12000000, 14000000, 15000000],
            'salesSeries': [22000000, 25000000, 27000000],
            'revenueSeries': [700000, 800000, 900000],
            'totalCostSeries': [780000, 860000, 960000],
            'profitSeries': [420000, 510000, 600000],
          }
        : path.endsWith('/trend')
        ? {
            'trends': {for (final r in rows) '${r['name']}::能源': r['trend']},
          }
        : path.endsWith('/detail')
        ? {
            'detail': {
              ...rows.first,
              if ((request.url.queryParameters['key'] ?? '').startsWith(
                '湖北细分::',
              ))
                ...row('湖北细分', child: true),
              'productL3': (rows.first['children'] as List),
              'product_drill': {'fixture': rows.first},
            },
          }
        : path.endsWith('/delay-notice')
        ? {'notices': noticesProvider?.call() ?? notices}
        : <String, dynamic>{};
    return http.Response(
      jsonEncode({'success': true, 'data': data}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  addTearDown(client.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: NativeLighthousePage(
        session: session,
        navigation: DunesNavigationController(),
        commUnread: CommUnreadNotifier(),
        workbenchBadge: WorkbenchBadgeNotifier(),
        service: LighthouseService(session: session, client: client),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder card(String title) => find.byWidgetPredicate(
  (widget) => widget is LighthouseShareableCard && widget.title == title,
);

Finder label(String text) => find.byWidgetPredicate(
  (widget) =>
      (widget is Text && widget.data == text) ||
      (widget is LhScrollText && widget.data == text),
);

Finder labelContaining(String text) => find.byWidgetPredicate(
  (widget) =>
      (widget is Text && (widget.data?.contains(text) ?? false)) ||
      (widget is LhScrollText && widget.data.contains(text)),
);

LighthouseSharedCardData sharedData({String kind = 'entity', String? section}) {
  final entity = row('满减券（交易）');
  return LighthouseSharedCardData.create({
    'kind': kind,
    'section': section,
    'title': '满减券（交易）',
    'range': '09.01–09.28',
    'period': 'day',
    'tab': 'product',
    'row': entity,
    'index': 2,
    'capturedAt': '2026-09-28T04:00:00Z',
    'totals': {
      'grossMargin': 2,
      'rate': 62.5,
      for (final entry in entity.entries)
        if (entry.value is num) entry.key: entry.value,
    },
    'metrics': {
      'heroSeriesLabels': ['09.26', '09.27', '09.28'],
      for (final entry in (entity['trend'] as Map).entries)
        if (entry.value is List && entry.key != 'labels')
          '${entry.key}Series': entry.value,
    },
  });
}

Future<void> mountShared(
  WidgetTester tester,
  LighthouseSharedCardData data, {
  double width = 320,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: ChatLighthouseCard(session: session, data: data),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lighthouse.feedback.sound': false,
      'lighthouse.feedback.haptics': false,
    });
    await LighthouseFeedback.instance.load();
  });
  for (final name in ['满减券（交易）', '满减券(交易)', '中石化满减券（交易）', '中石化普惠现金券（交易）']) {
    test('$name uses GMV', () {
      expect(lighthouseProductUsesGmv(name), isTrue);
      expect(
        lighthouseGrossMarginDisplayPct(
          profit: 20,
          verifiedSales: 80,
          gmv: 200,
          product: name,
        ),
        10,
      );
    });
  }
  for (final name in ['中石油普惠现金券（交易）', '满减券（权益收入）', '中石化普惠现金券', '其他']) {
    test('$name keeps the existing denominator', () {
      expect(lighthouseProductUsesGmv(name), isFalse);
      expect(
        lighthouseGrossMarginDisplayPct(
          profit: 20,
          verifiedSales: 80,
          gmv: 200,
          product: name,
        ),
        25,
      );
    });
  }
  test('subdivision, trend and formula all use inherited GMV', () {
    expect(
      lighthouseGrossMarginDisplayPct(
        profit: 20,
        verifiedSales: 80,
        gmv: 200,
        basis: 'gmv',
      ),
      10,
    );
    expect(
      lighthouseGrossMarginSeries(
        profit: [20, 30],
        verifiedSales: [80, 100],
        gmv: [200, 300],
        basis: 'gmv',
      ),
      [10, 10],
    );
    expect(
      lighthouseHeroFormulaForKey('grossMargin', basis: 'gmv')!.expression,
      '利润 ÷ GMV',
    );
    expect(
      lighthouseHeroTraceRole('grossMargin', 'gmv', basis: 'gmv'),
      LighthouseHeroFormulaRole.denominator,
    );
    expect(
      lighthouseHeroTraceRole('grossMargin', 'verifiedSales', basis: 'gmv'),
      isNull,
    );
  });
  test('zero/missing GMV never falls back to verified sales', () {
    expect(
      lighthouseGrossMarginDisplayPct(
        profit: 20,
        verifiedSales: 80,
        product: '满减券（交易）',
      ),
      isNull,
    );
    expect(
      lighthouseGrossMarginSeries(
        profit: [20],
        verifiedSales: [80],
        product: '满减券（交易）',
      ),
      isEmpty,
    );
  });
  test('GMV taps use existing open/switch/close state', () {
    expect(lighthouseLedgerSoloTrendAfterTap(null, 'gmv'), 'gmv');
    expect(lighthouseLedgerSoloTrendAfterTap('profit', 'gmv'), 'gmv');
    expect(lighthouseLedgerSoloTrendAfterTap('gmv', 'gmv'), isNull);
  });
  test('GMV gross margin delta is a percentage-point difference', () {
    expect(
      lighthouseAggregateRowsDeltaPct(
        [
          {
            'profit': 20,
            'prevProfit': 10,
            'gmv': 200,
            'verifiedSales': 80,
            'deltas': {'gmv': 0},
          },
        ],
        key: 'grossMargin',
        usesGmvGrossMargin: true,
      ),
      5,
    );
  });
  test('each action has a distinct valid short PCM sound', () {
    final sounds = LighthouseFeedbackKind.values
        .map(lighthouseFeedbackWav)
        .toList();
    expect(
      sounds.map(base64Encode).toSet().length,
      LighthouseFeedbackKind.values.length,
    );
    for (final bytes in sounds) {
      expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');
      expect(bytes.length, lessThan(5000));
    }
  });
  testWidgets(
    'actual page: starts closed; GMV tap opens trend AND all numeric panels',
    (tester) async {
      await mountPage(tester);
      final target = card('满减券（交易）');
      expect(target, findsOneWidget);
      expect(
        find.descendant(
          of: target,
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_TrendChart',
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: target, matching: label('GMV')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: target, matching: label('成本合计')),
        findsOneWidget,
      );
      expect(find.descendant(of: target, matching: label('核销额')), findsNothing);
      expect(
        find.descendant(
          of: target,
          matching: label(lighthouseLedgerPinnedGrossMarginText(2)),
        ),
        findsOneWidget,
      );
      final gmv = find.descendant(of: target, matching: label('GMV'));
      await tester.ensureVisible(gmv);
      await tester.pump();
      await tester.tap(gmv);
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('单指标走势 · GMV'), findsOneWidget);
      expect(
        find.descendant(of: target, matching: label('核销额')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: target, matching: label('成本合计')),
        findsWidgets,
      );
      expect(
        find.descendant(of: target, matching: label('净利润')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: target, matching: label('项目成本')),
        findsOneWidget,
      );
      expect(find.text('全部指标 · 规模 / 成本 / 利润'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.runtimeType.toString() == '_TrendChart' &&
              ((w as dynamic).costAltLabel == 'GMV' &&
                      (w as dynamic).costAlt.isNotEmpty &&
                      (w as dynamic).costAlt.last == 10000000 ||
                  (w as dynamic).scaleLabel == 'GMV' &&
                      (w as dynamic).scale.last == 10000000),
        ),
        findsOneWidget,
      );
      final unchanged = card('中石油普惠现金券（交易）');
      expect(
        find.descendant(of: unchanged, matching: label('核销额')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: unchanged, matching: label('成本合计')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: unchanged, matching: label('GMV')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(gmv.first);
      await tester.pump();
      await tester.tap(gmv.first);
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.descendant(of: target, matching: label('净利润')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('pull refresh reuses the period-switch soft loading animation', (
    tester,
  ) async {
    await mountPage(tester, refreshDelay: const Duration(milliseconds: 800));
    final refresh = find.byKey(const ValueKey('lighthouse-pull-refresh'));
    expect(refresh, findsOneWidget);
    final indicator = tester.widget<RefreshIndicator>(refresh);
    final refreshDone = indicator.onRefresh();
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.byKey(const ValueKey('lighthouse-soft-reload-progress')),
      findsOneWidget,
    );
    expect(find.text('同步中'), findsWidgets);

    await tester.pump(const Duration(milliseconds: 900));
    await refreshDone;
    expect(
      find.byKey(const ValueKey('lighthouse-soft-reload-progress')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'current-month forecast report entry does not depend on history readiness',
    (tester) async {
      await mountPage(tester);
      final periodBar = find.byType(LhPeriodBar);
      await tester.tap(
        find.descendant(of: periodBar, matching: find.text('月')),
      );
      await tester.pump(const Duration(milliseconds: 900));

      expect(tester.widget<LhPeriodBar>(periodBar).selectedIndex, 2);
      expect(find.text('报告 ›'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'name and margin column toggle the full row trend; square arrow alone opens detail',
    (tester) async {
      await mountPage(tester);
      const trendKey = 'product::满减券（交易）::能源';
      final target = card('满减券（交易）');
      final rowToggle = find.descendant(
        of: target,
        matching: find.byKey(const ValueKey('ledger-row-toggle-$trendKey')),
      );
      expect(rowToggle, findsOneWidget);
      await tester.tap(rowToggle);
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('整行走势'), findsOneWidget);
      expect(find.text('名称列打开'), findsOneWidget);
      await tester.tap(rowToggle);
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('整行走势'), findsNothing);

      final detail = find.descendant(
        of: target,
        matching: find.byKey(const ValueKey('ledger-detail-$trendKey')),
      );
      await tester.ensureVisible(detail);
      await tester.pump();
      await tester.tap(detail);
      await tester.pump(const Duration(milliseconds: 700));
      expect(labelContaining('满减券（交易）详情'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('actual page: expanded subdivisions inherit parent GMV rule', (
    tester,
  ) async {
    await mountPage(tester, width: 940);
    final target = card('满减券（交易）');
    final expand = find.descendant(of: target, matching: find.text('展开'));
    await tester.ensureVisible(expand);
    await tester.pump();
    await tester.tap(expand);
    await tester.pump(const Duration(milliseconds: 450));
    final child = card('湖北细分');
    expect(child, findsOneWidget);
    expect(find.descendant(of: child, matching: label('GMV')), findsOneWidget);
    expect(
      find.descendant(
        of: child,
        matching: label(lighthouseLedgerPinnedGrossMarginText(2)),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'interactive card previews locally and cancel does not send to IM',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: LighthouseShareableCard(
                session: session,
                title: '满减券（交易）',
                rangeLabel: '09.01–09.28',
                data: sharedData,
                previewBuilder: (data) =>
                    LighthouseEmbeddedCard(session: session, data: data),
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: const Text('GMV 1000万 · 毛利率 2%'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('转发卡片'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      // The share button deliberately stays busy until the dialog is dismissed.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('转发灯塔卡片'), findsOneWidget);
      expect(find.byType(LighthouseEmbeddedCard), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.text('选择会话'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        await tester.tap(find.text('取消'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.text('转发灯塔卡片'), findsNothing);
      expect(find.byTooltip('转发卡片'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('three alerts share one compact panel on a narrow screen', (
    tester,
  ) async {
    await mountPage(
      tester,
      width: 360,
      notices: const [
        {'sourceCode': 'SINOPEC', 'message': '中石化存量数据同步延迟，当前展示截止 09-30 04:21。'},
        {
          'sourceCode': 'SERVER_PROBE',
          'bizDeptCode': 'CX',
          'bizDeptName': '出行',
          'message': '灯塔服务不可用',
        },
        {
          'sourceCode': 'SERVER_PROBE',
          'bizDeptCode': 'DIGITALG',
          'bizDeptName': '数商',
          'message': '数商测活联调，请忽略',
        },
      ],
    );

    expect(find.bySemanticsLabel('3 条运行提醒'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.campaign_rounded));
    // Hero 的同步绿点有常驻呼吸动画，不能使用 pumpAndSettle。
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('运行提醒'), findsOneWidget);
    expect(find.text('3 条待关注'), findsOneWidget);
    expect(find.text('数据同步'), findsOneWidget);
    expect(find.text('出行'), findsOneWidget);
    expect(find.text('数商'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('grey horn turns active when a new notice arrives', (
    tester,
  ) async {
    var liveNotices = <Map<String, dynamic>>[];
    await mountPage(tester, noticesProvider: () => liveNotices);

    expect(find.byIcon(Icons.campaign_rounded), findsOneWidget);
    liveNotices = [
      {
        'sourceCode': 'server_probe',
        'bizDeptCode': 'CX',
        'bizDeptName': '出行',
        'message': '灯塔服务不可用',
      },
    ];

    await tester.pump(const Duration(seconds: 31));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.bySemanticsLabel('1 条运行提醒'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.campaign_rounded));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('灯塔服务不可用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('IM snapshot header and image stay readable at narrow width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ChatLighthouseLegacyImageCard(
              metadata: const {'title': '中石化普惠现金券（交易）', 'range': '09.01–09.28'},
              child: const SizedBox(
                width: 280,
                height: 180,
                child: Text('卡片图像'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('灯塔 · 卡片快照'), findsOneWidget);
    expect(find.text('09.01–09.28'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'IM upload carries card metadata without replacing attachment security fields',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'success': true,
            'data': request.url.path.endsWith('/upload')
                ? {
                    'url': 'https://example.test/card.png',
                    'objectKey': 'im-attachments/card.png',
                  }
                : {},
          }),
          200,
        );
      });
      final service = ConversationService(session: session, client: client);
      await service.sendImage(
        conversationId: 7,
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'card.png',
        mimeType: 'image/png',
        sourceLabel: '灯塔',
        lighthouseCard: {'version': 1, 'title': '满减券（交易）', 'range': '09.28'},
      );
      expect(requests.length, 2);
      expect(requests.first.body, contains('name="conversationId"'));
      final body = jsonDecode(requests.last.body) as Map;
      expect(body['kind'], 'IMAGE');
      expect(body['payload']['objectKey'], 'im-attachments/card.png');
      expect(body['payload']['lighthouseCard']['title'], '满减券（交易）');
      service.close();
    },
  );
}
