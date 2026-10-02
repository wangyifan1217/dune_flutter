import 'dart:math' as math;

import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/chat/chat_widgets.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_period_bar.dart';
import 'package:dunes_app/features/nova/nova_markdown.dart';
import 'package:dunes_app/features/robots/robot_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lighthouse_interaction_test.dart' as lighthouse;

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

Iterable<TextSpan> spans(InlineSpan span) sync* {
  if (span is TextSpan) {
    if (span.text?.isNotEmpty == true) yield span;
    for (final child in span.children ?? <InlineSpan>[]) {
      yield* spans(child);
    }
  }
}

void main() {
  testWidgets(
    'received IM body, mentions and links are readable in both themes',
    (tester) async {
      for (final theme in [DunesTheme.light(), DunesTheme.dark()]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: ChatTextBubble(
                text: '对方的消息 @张三 https://example.com',
                mine: false,
                enableSelection: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final bubble = find.byType(ChatTextBubble);
        final background = tester
            .widgetList<Container>(
              find.descendant(of: bubble, matching: find.byType(Container)),
            )
            .map((widget) => widget.decoration)
            .whereType<BoxDecoration>()
            .first
            .color!;
        final rich = tester.widget<RichText>(
          find.descendant(of: bubble, matching: find.byType(RichText)).first,
        );
        for (final span in spans(rich.text)) {
          expect(
            contrast(span.style!.color!, background),
            greaterThan(4.5),
            reason: '${theme.brightness}: ${span.text}',
          );
        }
        if (theme.brightness == Brightness.light) {
          expect(spans(rich.text).first.style!.color, const Color(0xFF111111));
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('Nova text and cached robot markdown follow theme changes', (
    tester,
  ) async {
    for (final theme in [
      DunesTheme.light(),
      DunesTheme.dark(),
      DunesTheme.light(),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Column(
              children: [
                NovaMarkdownBody(text: '小饕回复正文'),
                RobotMarkdown(markdown: '机器人回复正文 **重要信息**'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      final color = markdown.styleSheet!.p!.color!;
      final nova = tester.widget<SelectableText>(
        find
            .descendant(
              of: find.byType(NovaMarkdownBody),
              matching: find.byType(SelectableText),
            )
            .first,
      );
      if (theme.brightness == Brightness.dark) {
        expect(contrast(color, DunesPalette.night.surface), greaterThan(4.5));
        expect(
          spans(nova.textSpan!).first.style?.color ??
              nova.textSpan!.style!.color,
          DunesPalette.night.text,
        );
      } else {
        expect(color.computeLuminance(), lessThan(.5));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'actual lighthouse date sheet inherits night and selected days contrast',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await lighthouse.mountPage(tester, theme: DunesTheme.dark());
      final period = tester.widget<LhPeriodBar>(find.byType(LhPeriodBar));
      expect(period.trackColor.computeLuminance(), lessThan(.15));
      for (final color in period.pillGradient) {
        expect(color.computeLuminance(), lessThan(.15));
      }
      await tester.ensureVisible(find.text('选区间').first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('选区间').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('开始'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.text('开始'))).brightness,
        Brightness.dark,
      );
      final grid = find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(GridView),
          )
          .last;
      final firstDay = find.descendant(of: grid, matching: find.text('1'));
      expect(firstDay.hitTestable(), findsOneWidget);
      await tester.tap(firstDay);
      await tester.pump(const Duration(milliseconds: 150));
      final day = tester.widget<Text>(firstDay);
      final background = tester
          .widgetList<Container>(
            find.ancestor(of: firstDay, matching: find.byType(Container)),
          )
          .map((widget) => widget.decoration)
          .whereType<BoxDecoration>()
          .first
          .color!;
      expect(background.a, 1);
      expect(contrast(day.style!.color!, background), greaterThan(4.5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
}
