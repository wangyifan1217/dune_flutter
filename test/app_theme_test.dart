import 'dart:io';
import 'dart:ui' as ui;

import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/chat/im_celebration.dart';
import 'package:dunes_app/features/conversation/inbox_widgets.dart';
import 'package:dunes_app/features/tasks/task_widgets.dart';
import 'package:dunes_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _cardKey = Key('theme-regression-card');
const _captureKey = Key('theme-capture');

class _ThemePage extends StatelessWidget {
  const _ThemePage();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          ChatInboxHeader(
            onOpenContacts: () {},
            showNovaLeading: false,
            onQuickMeeting: () {},
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Container(
              key: _cardKey,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: DunesColors.resolve(
                  context,
                  Colors.white,
                  role: DunesColorRole.surface,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: DunesColors.resolve(context, DunesColors.border),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '任务与日报',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.resolve(context, DunesColors.text),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '按月查看 · 今天的工作进展',
                    style: TextStyle(
                      color: DunesColors.resolve(context, DunesColors.text2),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const TextField(
                    decoration: InputDecoration(hintText: '搜索任务、员工'),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(onPressed: () {}, child: const Text('查看详情')),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (Platform.environment['DUNES_CAPTURE_PREVIEWS'] != '1') return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('.dart_tool/visual_checks')
      ..createSync(recursive: true);
    File(
      '${directory.path}/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['DUNES_CAPTURE_PREVIEWS'] == '1') {
      for (final (name, asset) in const [
        ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
        ('Geist', 'assets/fonts/Geist-Regular.ttf'),
        ('Noto Sans SC', 'assets/fonts/NotoSansSC-Regular.ttf'),
      ]) {
        await (FontLoader(name)..addFont(rootBundle.load(asset))).load();
      }
    }
    SharedPreferences.setMockInitialValues({});
    await AppEggThemeController.instance.load();
  });
  setUp(() async {
    await AppEggThemeController.instance.setOverride('day');
  });

  testWidgets(
    'root theme updates cached page, actual inbox header and surfaces',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const RepaintBoundary(
          key: _captureKey,
          child: DunesApp(home: _ThemePage()),
        ),
      );
      await tester.pumpAndSettle();
      final dayInk = tester.widget<Text>(find.text('消息')).style!.color;
      final dayCard = tester.widget<Container>(find.byKey(_cardKey));
      expect((dayCard.decoration! as BoxDecoration).color, Colors.white);
      await _capture(tester, 'app_theme_day');

      await AppEggThemeController.instance.setOverride('night');
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(_ThemePage));
      expect(Theme.of(context).brightness, Brightness.dark);
      final nightCard = tester.widget<Container>(find.byKey(_cardKey));
      expect(
        (nightCard.decoration! as BoxDecoration).color,
        DunesPalette.night.surface,
      );
      expect(tester.widget<Text>(find.text('消息')).style!.color, isNot(dayInk));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'app_theme_night');

      await AppEggThemeController.instance.setOverride('day');
      await tester.pumpAndSettle();
      expect(Theme.of(context).brightness, Brightness.light);
      expect(tester.widget<Text>(find.text('消息')).style!.color, dayInk);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('task date picker and menus inherit night brightness', (
    tester,
  ) async {
    late ThemeData taskTheme;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: DunesTheme.dark(),
        home: TaskTheme(
          child: Builder(
            builder: (context) {
              taskTheme = Theme.of(context);
              return const Scaffold(body: Text('task'));
            },
          ),
        ),
      ),
    );
    expect(taskTheme.brightness, Brightness.dark);
    expect(
      taskTheme.datePickerTheme.backgroundColor,
      DunesPalette.night.surface,
    );
    expect(
      taskTheme.dropdownMenuTheme.menuStyle!.backgroundColor!.resolve({}),
      DunesPalette.night.surface,
    );
    expect(
      taskTheme.datePickerTheme.dayForegroundColor!.resolve({}),
      DunesPalette.night.text,
    );
    expect(
      taskTheme.datePickerTheme.dayBackgroundColor!.resolve({
        WidgetState.selected,
      }),
      kTaskPurple,
    );
  });

  testWidgets(
    'theme resolution preserves day colors and filled-button contrast',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: DunesTheme.light(),
          home: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(DunesColors.resolve(context, DunesColors.text), DunesColors.text);
      expect(
        DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        Colors.white,
      );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: DunesTheme.dark(),
          home: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        DunesColors.resolve(context, DunesColors.text),
        DunesPalette.night.text,
      );
      expect(DunesColors.resolve(context, Colors.white), Colors.white);
      for (final color in [
        DunesColors.text,
        DunesColors.text2,
        DunesColors.text3,
      ]) {
        final resolved = DunesColors.resolve(context, color);
        expect(DunesColors.resolve(context, resolved), resolved);
      }
      expect(
        DunesColors.resolve(
          context,
          DunesColors.brandPurple,
          role: DunesColorRole.surface,
        ),
        DunesColors.brandPurple,
      );
      final scheme = Theme.of(context).colorScheme;
      final contrast =
          (scheme.primary.computeLuminance() + .05) /
          (scheme.onPrimary.computeLuminance() + .05);
      expect(contrast, greaterThan(4.5));
    },
  );
}
