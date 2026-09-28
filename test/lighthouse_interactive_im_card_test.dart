import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dunes_app/features/conversation/conversation_service.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_card_share.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_feedback.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_gross_margin_label.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_shared_card_data.dart';
import 'lighthouse_interaction_test.dart' as f;

Finder charts([bool Function(dynamic widget)? match]) => find.byWidgetPredicate(
  (w) =>
      w.runtimeType.toString() == '_TrendChart' && (match == null || match(w)),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lighthouse.feedback.sound': false,
      'lighthouse.feedback.haptics': false,
    });
    await LighthouseFeedback.instance.load();
  });
  testWidgets(
    'all source forwarding icons are inside cards with no text footer',
    (tester) async {
      await f.mountPage(tester, width: 940);
      expect(find.text('转发 IM'), findsNothing);
      expect(find.text('转发'), findsNothing);
      for (final widget in tester.widgetList<LighthouseShareableCard>(
        find.byType(LighthouseShareableCard),
      )) {
        expect(widget.builder, isNotNull);
        expect(widget.data, isNotNull);
      }
      final target = f.card('满减券（交易）');
      final icon = find
          .descendant(of: target, matching: find.byTooltip('转发卡片'))
          .first;
      expect(tester.getRect(target).contains(tester.getCenter(icon)), isTrue);
      final source = tester.widget<LighthouseShareableCard>(target).data!();
      final json = source.toJson();
      expect(json['version'], 2);
      expect(json['row']['name'], '满减券（交易）');
      expect(json['row']['grossMarginBasis'], 'gmv');
      expect(json['row']['trend']['gmv'], [6000000, 8000000, 10000000]);
      expect(jsonEncode(json), isNot(contains('中石油')));
      expect(jsonEncode(json), isNot(contains('"token"')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'IM renders original ledger and GMV trend; numeric panels open on click',
    (tester) async {
      final data = f.sharedData();
      await f.mountShared(tester, data);
      expect(find.byType(Image), findsNothing);
      expect(find.text('灯塔 · 卡片快照'), findsNothing);
      final target = f.card('满减券（交易）');
      expect(
        find.descendant(of: target, matching: f.label('净利润')),
        findsNothing,
      );
      await tester.tap(find.descendant(of: target, matching: f.label('GMV')));
      await tester.pump(const Duration(milliseconds: 450));
      expect(
        find.descendant(of: target, matching: f.label('净利润')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: target, matching: f.label('项目成本')),
        findsOneWidget,
      );
      expect(
        charts((w) => w.scaleLabel == 'GMV' && w.scale.last == 10000000),
        findsOneWidget,
      );
      await f.mountShared(
        tester,
        LighthouseSharedCardData.fromPayload({
          'lighthouseCard': data.toJson(),
        })!,
      );
      expect(
        find.descendant(of: target, matching: f.label('净利润')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: target, matching: f.label('收入')).first,
      );
      await tester.pump(const Duration(milliseconds: 450));
      expect(charts((w) => w.soloKey == 'revenue'), findsOneWidget);
      expect(
        find.descendant(of: target, matching: f.label('项目成本')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('all live page levels show the actual margin denominator', (
    tester,
  ) async {
    await f.mountPage(tester, width: 390);
    final target = f.card('满减券（交易）');
    expect(
      find.descendant(of: target, matching: find.text('利润 ÷ GMV')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: f.card('中石油普惠现金券（交易）'),
        matching: find.text('利润 ÷ 核销额'),
      ),
      findsOneWidget,
    );
    final parentName = find
        .descendant(of: target, matching: f.label('满减券（交易）'))
        .first;
    await tester.ensureVisible(parentName);
    await tester.pump();
    await tester.tap(parentName);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(LighthouseGrossMarginLabel), findsWidgets);
    for (final caption in tester.widgetList<LighthouseGrossMarginLabel>(
      find.byType(LighthouseGrossMarginLabel),
    )) {
      expect(caption.formula, '利润 ÷ GMV');
    }
    final childName = f.label('湖北细分').first;
    await tester.ensureVisible(childName);
    await tester.pump();
    await tester.tap(childName);
    await tester.pump(const Duration(milliseconds: 700));
    final captions = tester.widgetList<LighthouseGrossMarginLabel>(
      find.byType(LighthouseGrossMarginLabel),
    );
    expect(captions, isNotEmpty);
    expect(captions.every((w) => w.formula == '利润 ÷ GMV'), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final entry in {
    'gmv': '利润 ÷ GMV',
    'verifiedSales': '利润 ÷ 核销额',
    'sales': '利润 ÷ 销售额',
  }.entries) {
    testWidgets('IM cards and margin trends show ${entry.value}', (
      tester,
    ) async {
      final json = f.sharedData().toJson();
      final product = entry.key == 'gmv' ? '满减券（交易）' : '普通产品';
      json['title'] = product;
      json['row']['name'] = product;
      json['row']['group'] = entry.key == 'sales' ? '运营商' : '能源';
      json['row']['grossMarginBasis'] = entry.key;
      json['row']['marginProduct'] = product;
      json['row']['children'] = [];
      await f.mountShared(tester, LighthouseSharedCardData.create(json));
      expect(find.text(entry.value), findsOneWidget);
      await tester.tapAt(tester.getCenter(f.label('销售额')));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text(entry.value), findsWidgets);
      final margin = f.label('毛利率').last;
      await tester.ensureVisible(margin);
      await tester.pump();
      await tester.tapAt(tester.getCenter(margin));
      await tester.pump(const Duration(milliseconds: 450));
      expect(
        charts((w) => w.grossMarginFormula == entry.value),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('IM subdivisions start closed, inherit GMV and expand locally', (
    tester,
  ) async {
    await f.mountShared(tester, f.sharedData());
    expect(f.card('湖北细分'), findsNothing);
    await tester.tap(find.text('展开'));
    await tester.pump(const Duration(milliseconds: 450));
    final child = f.card('湖北细分');
    expect(child, findsOneWidget);
    expect(find.descendant(of: child, matching: f.label('净利润')), findsNothing);
    final gmv = find.descendant(of: child, matching: f.label('GMV'));
    await tester.ensureVisible(gmv);
    await tester.pump();
    await tester.tap(gmv);
    await tester.pump(const Duration(milliseconds: 450));
    expect(
      find.descendant(of: child, matching: f.label('净利润')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final section in ['scale', 'cost', 'profit', 'cash']) {
    testWidgets(
      'IM $section panel reuses original component and is independently interactive',
      (tester) async {
        await f.mountShared(
          tester,
          f.sharedData(kind: 'panel', section: section),
        );
        expect(find.byType(LighthouseShareableCard), findsOneWidget);
        final metric = section == 'scale'
            ? 'GMV'
            : section == 'cost'
            ? '成本合计'
            : section == 'cash'
            ? '预收净增'
            : '收入';
        await tester.tapAt(tester.getCenter(f.label(metric)));
        await tester.pump(const Duration(milliseconds: 450));
        expect(charts(), findsOneWidget);
        expect(find.byType(LighthouseShareableCard), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final width in [320.0, 940.0]) {
    testWidgets('IM Hero retains original layout and chart at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width + 20, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await f.mountShared(tester, f.sharedData(kind: 'hero'), width: width);
      expect(find.byType(LighthouseShareableCard), findsNWidgets(4));
      expect(f.label('净利润'), findsWidgets);
      expect(charts(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final withViewport in [false, true]) {
    testWidgets(
      'IM Hero keeps seven visible points with loaded history ($withViewport)',
      (tester) async {
        final json = f.sharedData(kind: 'hero').toJson();
        final labels = List.generate(42, (i) => 'D${i + 1}');
        final trend = <String, dynamic>{
          'labels': labels,
          for (final entry in (json['row']['trend'] as Map).entries)
            if (entry.key != 'labels')
              entry.key.toString(): List.generate(
                42,
                (i) => (entry.value as List).last + i * 1000,
              ),
        };
        json['row']['trend'] = trend;
        json['metrics'] = {
          'heroSeriesLabels': labels,
          for (final entry in trend.entries)
            if (entry.key != 'labels') '${entry.key}Series': entry.value,
        };
        if (withViewport) {
          json['viewportCount'] = 7;
          json['historyCount'] = 35;
          json['viewEnd'] = 20.0;
          json['pointIndex'] = 18;
        }
        await f.mountShared(tester, LighthouseSharedCardData.create(json));
        final dynamic chart = tester.widget(charts().first);
        expect(chart.viewportCount, 7);
        expect(chart.historyHasMore, isFalse);
        final painters = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where(
              (w) => w.painter.runtimeType.toString() == '_TrendLinesPainter',
            );
        expect(painters, hasLength(1));
        final dynamic painter = painters.single.painter;
        // Includes at most one off-screen neighbour on each side for smooth lines.
        expect(painter.series.profit.length, lessThanOrEqualTo(9));
        expect(painter.series.profit.length, greaterThanOrEqualTo(7));
        if (withViewport) {
          expect(painter.series.profit.last, 221000);
          expect(chart.selectedIndex, 18);
          final reforward = tester
              .widget<LighthouseShareableCard>(
                find.byType(LighthouseShareableCard).first,
              )
              .data!()
              .toJson();
          expect(reforward['viewportCount'], 7);
          expect(reforward['viewEnd'], 20);
          expect(
            DateTime.parse(reforward['capturedAt'] as String),
            DateTime.parse(json['capturedAt'] as String),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test(
    'structured data round trip freezes share scope and rejects invalid messages',
    () {
      final data = f.sharedData();
      final json = data.toJson();
      expect(
        LighthouseSharedCardData.fromPayload({'lighthouseCard': json}),
        data,
      );
      json['row']['gmv'] = 0;
      expect(data.row['gmv'], 10000000);
      expect(
        LighthouseSharedCardData.fromPayload({
          'lighthouseCard': {'version': 2},
        }),
        isNull,
      );
      expect(
        LighthouseSharedCardData.fromPayload({
          'lighthouseCard': {
            ...data.toJson(),
            'row': {'profit': 'bad'},
          },
        }),
        isNull,
      );
      expect(
        LighthouseSharedCardData.fromPayload({
          'lighthouseCard': {...data.toJson(), 'title': 'x' * 600000},
        }),
        isNull,
      );
      for (final broken in [
        {
          'row': {
            ...data.row,
            'trend': {'profit': 'not-a-list'},
          },
        },
        {
          'metrics': {...data.metrics, 'profitSeries': 'not-a-list'},
        },
        {
          'metrics': {
            ...data.metrics,
            'profitSeries': [1, 'bad', 3],
          },
        },
        {
          'metrics': {...data.metrics, 'heroSeriesLabels': 'not-a-list'},
        },
      ]) {
        expect(
          LighthouseSharedCardData.fromPayload({
            'lighthouseCard': {...data.toJson(), ...broken},
          }),
          isNull,
        );
      }
    },
  );
  test(
    'interactive card sends a business TEXT payload, never a PNG upload',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'id': 1, 'kind': 'TEXT'},
          }),
          200,
        );
      });
      final service = ConversationService(session: f.session, client: client);
      final data = f.sharedData();
      await service.sendText(
        7,
        data.fallbackText,
        payload: {'lighthouseCard': data.toJson()},
      );
      expect(requests.length, 1);
      expect(requests.single.url.path, endsWith('/conversations/7/messages'));
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['kind'], 'TEXT');
      expect(body['payload']['lighthouseCard']['version'], 2);
      expect(
        body['payload']['lighthouseCard']['row']['trend']['gmv'],
        isNotEmpty,
      );
      service.close();
    },
  );
}
