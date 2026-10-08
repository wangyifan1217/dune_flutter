import 'package:dunes_app/features/qianji/native_qianji_daily_report_supervise_page.dart';
import 'package:dunes_app/features/tasks/task_models.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:dunes_app/features/profile/native_user_work_profile_page.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/contacts/contact_models.dart';
import 'package:dunes_app/features/contacts/native_contact_profile_page.dart';
import 'package:dunes_app/features/chat/group_info_widgets.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment['DUNES_CAPTURE_NIGHT'] != '1') return;
    for (final entry in {
      'Geist': 'assets/fonts/Geist-Regular.ttf',
      'Geist Mono': 'assets/fonts/GeistMono-Regular.ttf',
      'Noto Sans SC': 'assets/fonts/NotoSansSC-Regular.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });
  testWidgets('radar follows live theme changes and repaints its labels', (
    tester,
  ) async {
    CustomPainter? previous;
    for (final theme in [
      DunesTheme.light(),
      DunesTheme.dark(),
      DunesTheme.light(),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: WorkProfileRadarCard(
                monthLabel: '2026-10',
                dimensions: [
                  UserWorkProfileDimension(
                    label: '任务',
                    value: 3,
                    cap: 10,
                    unit: '项',
                    period: '本月',
                  ),
                  UserWorkProfileDimension(
                    label: '会议',
                    value: 2,
                    cap: 10,
                    unit: '次',
                    period: '本月',
                  ),
                  UserWorkProfileDimension(
                    label: '知识',
                    value: 4,
                    cap: 10,
                    unit: '篇',
                    period: '本月',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<CustomPainter>()
          .firstWhere(
            (p) => p.runtimeType.toString() == '_WorkProfileRadarPainter',
          );
      expect((painter as dynamic).brightness, theme.brightness);
      if (previous != null) expect(painter.shouldRepaint(previous), isTrue);
      previous = painter;
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('night daily report sheet keeps card and body readable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DunesTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showQianjiDailyReportDetail(
                context: context,
                userName: '测试联系人',
                departmentName: '产品部',
                report: const TaskDailyReport(
                  reportDate: '2026-10-08',
                  summary: '今天的工作总结',
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final body = find.text('今天的工作总结');
    final text = tester.widget<Text>(body);
    final container = tester
        .widgetList<Container>(
          find.ancestor(of: body, matching: find.byType(Container)),
        )
        .firstWhere(
          (widget) =>
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color != null,
        );
    final background = (container.decoration as BoxDecoration).color!;
    expect(background.computeLuminance(), lessThan(.1));
    final a = text.style!.color!.computeLuminance(),
        b = background.computeLuminance();
    expect((math.max(a, b) + .05) / (math.min(a, b) + .05), greaterThan(4.5));
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(body, findsNothing);
    expect(tester.takeException(), isNull);
  });
  const session = AuthSession(
    token: '',
    userId: 1,
    phone: '',
    apiBase: '',
    roles: [],
  );
  for (final theme in [DunesTheme.dark(), DunesTheme.light()]) {
    testWidgets(
      'profile is readable and preserves actions in ${theme.brightness}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        var chat = 0;
        var groups = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: RepaintBoundary(
              key: const Key('profile-preview'),
              child: NativeContactProfilePage(
                session: session,
                contactHint: const NativeContact(
                  userId: 2,
                  displayName: '联系人姓名',
                  phone: '13800000000',
                  department: '很长的部门名称用于验证窄屏资料布局是否稳定',
                  title: '产品经理',
                ),
                onBack: () {},
                onOpenPrivateChat: (id) => chat = id,
                onCreateGroupWithContact: (_) => groups++,
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(find.text('联系人姓名'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('添加成员发起群聊'));
        expect(groups, 1);
        if (theme.brightness == Brightness.dark &&
            Platform.environment['DUNES_CAPTURE_NIGHT'] == '1') {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('profile-preview')),
            );
            final raster = await boundary.toImage(pixelRatio: 2);
            final data = await raster.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('.dart_tool/visual_checks/app_night_profile.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            raster.dispose();
          });
        }
        await tester.scrollUntilVisible(find.text('发消息'), 200);
        await tester.tap(find.text('发消息'));
        expect(chat, 2);
        if (theme.brightness == Brightness.dark) {
          final color = tester
              .widget<ColoredBox>(find.byType(ColoredBox).first)
              .color;
          expect(color.computeLuminance(), lessThan(.1));
          final title = tester.widget<Text>(find.text('部门'));
          final textColor = title.style!.color!;
          final bg = DunesPalette.night.surface;
          final a = textColor.computeLuminance(), b = bg.computeLuminance();
          expect(
            (math.max(a, b) + .05) / (math.min(a, b) + .05),
            greaterThan(4.5),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );
  }
  testWidgets('night group shell is dark and toggle thumb stays visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DunesTheme.dark(),
        home: Scaffold(
          body: groupInfoPageShell(
            child: const Column(
              children: [
                GroupInfoToggle(value: false),
                GroupInfoToggle(value: true),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<ColoredBox>(find.byType(ColoredBox).first)
          .color
          .computeLuminance(),
      lessThan(.1),
    );
    final whiteThumbs = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (w) =>
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle &&
              (w.decoration as BoxDecoration).color == Colors.white,
        );
    expect(whiteThumbs.length, 2);
    expect(tester.takeException(), isNull);
  });
}
