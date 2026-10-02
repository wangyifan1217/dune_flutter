import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/chat/im_celebration.dart';
import 'package:dunes_app/features/chat/im_egg_visuals.dart';
import 'package:dunes_app/features/chat/im_egg_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _captureKey = Key('egg-capture');

Future<void> _capture(WidgetTester tester, String name) async {
  if (Platform.environment['DUNES_CAPTURE_PREVIEWS'] != '1') return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('.dart_tool/visual_checks')
      ..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Future.wait(imEggArtworkSpecs.keys.map(ImEggArtwork.load));
    if (Platform.environment['DUNES_CAPTURE_PREVIEWS'] == '1') {
      for (final (name, asset) in const [
        ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
        ('Geist', 'assets/fonts/Geist-Regular.ttf'),
        ('Noto Sans SC', 'assets/fonts/NotoSansSC-Regular.ttf'),
      ]) {
        await (FontLoader(name)..addFont(rootBundle.load(asset))).load();
      }
      final emoji = File('C:/Windows/Fonts/seguiemj.ttf');
      if (emoji.existsSync()) {
        final bytes = await emoji.readAsBytes();
        await (FontLoader(
          'Segoe UI Emoji',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'rain is transparent, tappable and newest effect replaces the old one',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;
      late BuildContext context;
      await tester.pumpWidget(
        RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: DunesTheme.light(),
            home: Builder(
              builder: (ctx) {
                context = ctx;
                return Scaffold(
                  appBar: AppBar(title: const Text('文件传输助手')),
                  body: Center(
                    child: FilledButton(
                      onPressed: () => taps++,
                      child: const Text('页面可点'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      showImEggEffect(
        context,
        const ImEggEffect(kind: ImEggEffectKind.birthday, phrase: '生日快乐'),
        seed: 42,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.byType(ImEggParticleField), findsOneWidget);
      // Emoji are cached Canvas paragraphs, so neither inherited text decoration
      // nor an opaque Material/modal barrier can leak into the effect.
      expect(
        find.descendant(
          of: find.byType(ImEggParticleField),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      await _capture(tester, 'im_birthday_rain');
      await tester.tap(find.text('页面可点'));
      expect(taps, 1);
      showImEggEffect(
        context,
        const ImEggEffect(kind: ImEggEffectKind.redEnvelope, phrase: '恭喜发财'),
        seed: 72,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));
      await _capture(tester, 'im_red_envelope_rain');
      showImEggEffect(
        context,
        const ImEggEffect(kind: ImEggEffectKind.nationalDay, phrase: '国庆快乐'),
        seed: 84,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.byType(ImEggParticleField), findsOneWidget);
      expect(
        tester
            .widget<ImEggParticleField>(find.byType(ImEggParticleField))
            .glyphs,
        ['🇨🇳'],
      );
      await _capture(tester, 'im_national_day_flags');
      await tester.pump(const Duration(seconds: 6));
      expect(find.byType(ImEggParticleField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'holiday welcome matches the preview scene and closes back to the app',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late BuildContext context;
      await tester.pumpWidget(
        RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: DunesTheme.light(),
            home: Builder(
              builder: (ctx) {
                context = ctx;
                return const Scaffold(body: Text('工作台'));
              },
            ),
          ),
        ),
      );
      showAppHolidayWelcome(
        context,
        '国庆节快乐',
        icon: '🇨🇳',
        message: '祝祖国繁荣昌盛，愿你和家人假期愉快',
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppHolidayWelcome), findsOneWidget);
      expect(find.text('收下祝福'), findsOneWidget);
      expect(find.text('稍后看看'), findsOneWidget);
      expect(find.text('CN'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(AppHolidayWelcome), findsOneWidget);
      await _capture(tester, 'holiday_national_day');
      await tester.tap(find.text('收下祝福'));
      await tester.pumpAndSettle();
      expect(find.byType(AppHolidayWelcome), findsNothing);
      expect(find.text('工作台'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('welcome fits a 320px screen, dark theme and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: DunesTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.4),
          ),
          child: AppHolidayWelcome(
            greeting: '中秋快乐',
            message: '愿你今晚有月可赏，有人可念。',
            icon: '🌕',
            onDismiss: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('收下祝福'), findsOneWidget);
  });

  testWidgets('reduced motion stops automatically without an animation loop', (
    tester,
  ) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ImEggParticleField(
            glyphs: const ['🎂'],
            count: 120,
            duration: const Duration(seconds: 5),
            onFinished: () => finished++,
          ),
        ),
      ),
    );
    // Asset loading completes before the static display's 1.8s timer begins.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(milliseconds: 1900));
    expect(finished, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(finished, 1);
    expect(tester.takeException(), isNull);
  });

  test('holiday date ranges include boundaries and share one period key', () {
    final settings = ImEggSettings.fromConfiguration({
      'holidays': {
        'dates': [
          {'date': '10-01', 'endDate': '10-07', 'name': '国庆', 'icon': 'CN'},
          {'date': '12-24', 'endDate': '01-02', 'name': '跨年', 'icon': '🎄'},
        ],
      },
    });
    final first = settings.holidayFor(DateTime(2026, 10, 1))!;
    expect(first['icon'], '🇨🇳');
    expect(
      settings.holidayFor(DateTime(2026, 10, 7))!['periodKey'],
      first['periodKey'],
    );
    expect(settings.holidayFor(DateTime(2026, 10, 8)), isNull);
    expect(
      settings.holidayFor(DateTime(2027, 1, 2))!['periodKey'],
      settings.holidayFor(DateTime(2026, 12, 24))!['periodKey'],
    );
  });

  testWidgets('entering repeatedly in one holiday period only welcomes once', (
    tester,
  ) async {
    late BuildContext context;
    final settings = ImEggSettings.fromConfiguration({
      'holidays': {
        'dates': [
          {'date': '01-01', 'endDate': '12-31', 'name': '祝福', 'icon': '🌕'},
        ],
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return const Scaffold();
          },
        ),
      ),
    );
    expect(await settings.maybeShowHolidayWelcome(context, 901), isTrue);
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(await settings.maybeShowHolidayWelcome(context, 901), isFalse);
    expect(find.byType(AppHolidayWelcome), findsNothing);
    for (var replay = 0; replay < 2; replay++) {
      final greeting = settings.holidayGreetings.single;
      showAppHolidayWelcome(
        context,
        greeting['name']!,
        message: greeting['message']!,
        icon: greeting['icon']!,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppHolidayWelcome), findsOneWidget);
      await tester.tap(find.text('收下祝福'));
      await tester.pumpAndSettle();
    }
    expect(await settings.maybeShowHolidayWelcome(context, 901), isFalse);
  });

  test(
    'manual greeting catalogue and theme guide retain server configuration',
    () {
      final settings = ImEggSettings.fromConfiguration({
        'theme': {'dayStart': '08:30', 'nightStart': '20:15'},
        'holidays': {
          'dates': [
            {
              'date': '10-01',
              'name': '国庆',
              'greeting': '假期快乐',
              'message': '平安顺遂',
            },
          ],
        },
      });
      expect(settings.holidayGreetings.single['greeting'], '假期快乐');
      expect(settings.holidayFor(DateTime(2026, 11, 1)), isNull);
      expect(settings.holidayGreetings, hasLength(1));
      expect(settings.themeGuide, contains('08:30'));
      expect(settings.themeGuide, contains('20:15'));
      final system = ImEggSettings.fromConfiguration({
        'theme': {'followSystem': true},
      });
      expect(system.themeGuide, contains('跟随手机系统'));
    },
  );

  test('APP and HTML use identical bundled artwork manifest', () {
    final manifest =
        jsonDecode(
              File('assets/images/im_eggs/manifest.json').readAsStringSync(),
            )
            as Map;
    for (final entry in imEggArtworkSpecs.entries) {
      expect(entry.value.$1, endsWith(manifest[entry.key]['file'] as String));
      expect(entry.value.$2, manifest[entry.key]['width']);
      expect(File(entry.value.$1).existsSync(), isTrue);
    }
  });
}
