import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/nova/native_nova_service.dart';
import 'package:dunes_app/features/nova/nova_chart_card.dart';
import 'package:dunes_app/features/nova/nova_personal_query.dart';

const _session = AuthSession(
  token: 't',
  userId: 7,
  phone: '13800000000',
  apiBase: 'https://test.dune.com',
  roles: ['USER'],
);

const _barChart = <String, dynamic>{
  'kind': 'bar',
  'title': '各供给利润变化',
  'labels': ['中石化销售', '中石油销售'],
  'series': [
    {
      'name': '各供给利润变化',
      'values': [-300000, 50000],
    },
  ],
};

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: SizedBox(width: 360, child: SingleChildScrollView(child: child)),
  ),
);

void main() {
  test('chart parsing keeps nulls and rejects broken shapes', () {
    final line = NovaChart.fromJson({
      'kind': 'line',
      'title': '每天的利润',
      'labels': ['10-01', '10-02', '10-03'],
      'series': [
        {
          'name': '中石油',
          'values': [5, null, 7.5],
        },
      ],
    });
    expect(line?.isLine, isTrue);
    expect(line?.series.single.values, [5.0, null, 7.5]);
    expect(
      NovaChart.fromJson({
        'kind': 'bar',
        'labels': ['a', 'b'],
        'series': [
          {
            'values': [1],
          },
        ],
      }),
      isNull,
    );
    expect(NovaChart.fromJson({'kind': 'pie'}), isNull);
    expect(NovaChart.fromJson(null), isNull);
  });

  test('personal reply carries a valid chart', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'data': {'text': '本月利润下降', 'chart': _barChart},
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final service = NativeNovaService(session: _session, client: client);
    final reply = await service.askPersonalCapability(
      capability: 'lighthouse',
      text: '本月利润为什么下降',
    );
    expect(NovaChart.fromJson(reply.chart)?.labels, ['中石化销售', '中石油销售']);
  });

  test('daily insight is fetched once per day when nothing is wrong', () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/ai/assistant/insight'));
      calls++;
      return http.Response(
        jsonEncode({
          'data': {'date': '2026-10-25'},
        }),
        200,
      );
    });
    final service = NativeNovaService(session: _session, client: client);
    expect(await service.dailyInsight(), isNull);
    expect(await service.dailyInsight(), isNull);
    expect(calls, 1);
  });

  test('daily insight with changes stays until marked seen', () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'data': {
              'date': '2026-10-25',
              'title': '昨天有 1 项利润明显下降',
              'lines': ['渠道「滴滴」利润 2.0万，比上月同日下降 2.5万'],
              'suggestions': ['昨天滴滴利润为什么下降'],
            },
          }),
        ),
        200,
      ),
    );
    final service = NativeNovaService(session: _session, client: client);
    final insight = await service.dailyInsight();
    expect(insight?.lines, hasLength(1));
    expect(await service.dailyInsight(), isNotNull);
    await service.markInsightSeen();
    expect(await service.dailyInsight(), isNull);
  });

  testWidgets('bar and line charts render without overflow', (tester) async {
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            NovaChartCard(chart: NovaChart.fromJson(_barChart)!),
            NovaChartCard(
              dark: true,
              chart: NovaChart.fromJson({
                'kind': 'line',
                'title': '本月利润走势对比',
                'labels': ['10.01', '10.02', '10.03', '10.04', '10.05'],
                'series': [
                  {
                    'name': '中石油',
                    'values': [10, 20, null, 15, -5],
                  },
                  {
                    'name': '中石化',
                    'values': [4, 5, 6, 7, 8],
                  },
                ],
              })!,
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('各供给利润变化'), findsOneWidget);
    expect(find.text('-30.0万'), findsOneWidget);
    expect(find.text('中石化'), findsOneWidget);
  });

  test('bar chart labels share a prefix only when it is safe', () {
    expect(
      novaChartCommonPrefix([
        '河南中石油200元加油券',
        '河南中石油300元加油券',
        '河南中石油满减券',
      ]),
      '河南中石油',
    );
    // 不把数字拆开。
    expect(
      novaChartCommonPrefix(['河南中石油200元', '河南中石油250元', '河南中石油210元']),
      '河南中石油',
    );
    expect(novaChartCommonPrefix(['中石化销售', '中石油销售']), '');
    expect(novaChartCommonPrefix(['平安', '滴滴', '高德']), '');
    expect(novaChartCommonPrefix(['河南中石油', '河南中石油A', '河南中石油B']), '');
  });

  testWidgets('bar chart shows long sku names in full width', (tester) async {
    await tester.pumpWidget(
      _host(
        NovaChartCard(
          chart: NovaChart.fromJson({
            'kind': 'bar',
            'title': 'SKU利润排名',
            'labels': [
              '河南中石油200元电子加油券（全省通用）',
              '河南中石油300元电子加油券',
              '河南中石油满200减10',
            ],
            'series': [
              {
                'name': '利润',
                'values': [4233, 1755, 20],
              },
            ],
          })!,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('以下均为「河南中石油」'), findsOneWidget);
    expect(find.text('200元电子加油券（全省通用）'), findsOneWidget);
    expect(find.text('满200减10'), findsOneWidget);
  });

  testWidgets('multi-metric bar chart shows every metric per row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        NovaChartCard(
          chart: NovaChart.fromJson({
            'kind': 'bar',
            'title': '本月渠道销售额、利润对比',
            'labels': ['产险', '(未分类)（平安）', '银行'],
            'series': [
              {
                'name': '销售额',
                'values': [1000000, 3000000, 5000000],
              },
              {
                'name': '利润',
                'values': [70000, 25000, -755],
              },
            ],
          })!,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('销售额'), findsOneWidget);
    expect(find.text('利润'), findsOneWidget);
    expect(find.text('(未分类)（平安）'), findsOneWidget);
  });

  testWidgets('insight card asks a suggestion and can be dismissed', (
    tester,
  ) async {
    final asked = <String>[];
    var dismissed = false;
    await tester.pumpWidget(
      _host(
        NovaInsightCard(
          insight: const NovaInsight(
            date: '2026-10-25',
            title: '昨天有 1 项利润明显下降',
            lines: ['渠道「滴滴」利润 2.0万，比上月同日下降 2.5万（-55.6%）'],
            suggestions: ['昨天滴滴利润为什么下降'],
          ),
          onAsk: asked.add,
          onDismiss: () => dismissed = true,
        ),
      ),
    );
    await tester.tap(find.text('昨天滴滴利润为什么下降'));
    await tester.tap(find.byKey(const ValueKey('nova-insight-dismiss')));
    expect(asked, ['昨天滴滴利润为什么下降']);
    expect(dismissed, isTrue);
  });
}
