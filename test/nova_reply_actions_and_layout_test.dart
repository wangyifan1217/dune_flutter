import 'package:dunes_app/features/nova/nova_deliverable.dart';
import 'package:dunes_app/features/nova/nova_reply_presentation.dart';
import 'package:dunes_app/features/nova/nova_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _missing =
    '查询对象：出行\n日期范围：2026-10-26（Asia/Shanghai，按天）\n指标：利润\n数据来源：灯塔产品\n灯塔里没有「出行」。没有拿别的名称充数。';

void main() {
  test(
    'lighthouse presentation puts the result before lightweight source metadata',
    () {
      final reply = NovaLighthouseReplyPresentation.tryParse(_missing)!;
      expect(reply.empty, isTrue);
      expect(reply.body, '当前查询范围内，未找到「出行」对应的数据。');
      expect(reply.scope, '灯塔产品 · 出行 · 利润');
      expect(reply.period, '2026-10-26（按天）');
      final copy = novaAssistantCopyText(_missing);
      expect(copy, startsWith('暂未找到匹配数据'));
      expect(copy, contains('灯塔产品 · 出行 · 利润'));
      expect(copy, isNot(contains('充数')));
    },
  );

  test('normal answers and incomplete metadata remain untouched', () {
    expect(
      NovaLighthouseReplyPresentation.tryParse('查询对象：请解释这个概念\n正文'),
      isNull,
    );
    expect(novaAssistantCopyText('**通用回复**\n\n这里是正文。'), '**通用回复**\n\n这里是正文。');
    final success = NovaLighthouseReplyPresentation.tryParse(
      '查询对象：整体\n期间：本月\n数据来源：灯塔汇总\n本月利润为 12 万。',
    )!;
    expect(success.empty, isFalse);
    expect(success.body, '本月利润为 12 万。');
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'lighthouse result layout is compact and conclusion first at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: NovaC4MessageRow(mine: false, text: _missing),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('暂未找到匹配数据'), findsOneWidget);
        expect(find.text('灯塔产品 · 出行 · 利润'), findsOneWidget);
        expect(find.textContaining('数据来源：'), findsNothing);
        expect(
          tester.getTopLeft(find.text('暂未找到匹配数据')).dy,
          lessThan(tester.getTopLeft(find.text('灯塔产品 · 出行 · 利润')).dy),
        );
        if (width > 800)
          expect(
            tester.getSize(find.byType(NovaC4AiBubble)).width,
            lessThanOrEqualTo(680),
          );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final streaming in [false, true]) {
    for (final kind in ['TEXT', 'AI_ASSISTANT']) {
      testWidgets(
        'general answer supports copy and forwarding ($kind, streaming=$streaming)',
        (tester) async {
          var copied = '';
          var forwarded = '';
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData')
                copied = (call.arguments as Map)['text'] as String;
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          const text = '这是通用问答的回复。';
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: NovaC4MessageRow(
                    mine: false,
                    text: text,
                    kind: kind,
                    streaming: streaming,
                    onCopyReply: () => Clipboard.setData(
                      ClipboardData(text: novaAssistantCopyText(text)),
                    ),
                    onForwardReply: () =>
                        forwarded = novaAssistantCopyText(text),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(SelectionArea), findsOneWidget);
          await tester.tap(find.byTooltip('复制'));
          await tester.pump();
          expect(copied, text);
          await tester.tap(find.byTooltip('转发到 IM'));
          expect(forwarded, text);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
