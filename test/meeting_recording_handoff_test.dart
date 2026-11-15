import 'dart:io';

import 'package:dunes_app/features/meeting/meeting_audio_file_picker.dart';
import 'package:dunes_app/features/meeting/meeting_audio_converter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Use the platform interface supplied by path_provider, as in other filesystem tests.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dunes/audio_recorder');
  late Directory root;
  late PathProviderPlatform original;
  final acknowledgements = <String>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('meeting-handoff-');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    acknowledgements.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'acknowledgeSavedRecording') {
            // The durable destination must already contain all bytes at acknowledgement.
            final files = Directory(
              '${root.path}/meeting_local',
            ).listSync().whereType<File>();
            expect(files, hasLength(1));
            expect(await files.single.readAsBytes(), [1, 2, 3, 4]);
            acknowledgements.add((call.arguments as Map)['path'] as String);
          }
          return null;
        });
  });

  tearDown(() async {
    PathProviderPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  test(
    'local save acknowledges only after a complete copy and retains source',
    () async {
      final source = File('${root.path}/original.wav');
      await source.writeAsBytes([1, 2, 3, 4]);
      final path = await MeetingAudioFilePicker.keepRecordingLocal(source.path);
      expect(await File(path).readAsBytes(), [1, 2, 3, 4]);
      expect(await source.exists(), isTrue);
      expect(acknowledgements, [source.path]);
    },
  );

  test(
    'normal M4A upload reuses the existing file without invoking conversion',
    () async {
      const conversion = MethodChannel('dunes/meeting_audio');
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(conversion, (_) async {
            calls++;
            throw PlatformException(code: 'must-not-convert');
          });
      try {
        final source = File('${root.path}/normal.m4a');
        await source.writeAsBytes([1, 2, 3, 4]);
        expect(
          await MeetingAudioConverter.prepareForUpload(source.path),
          source.path,
        );
        expect(calls, 0);
        expect(await source.readAsBytes(), [1, 2, 3, 4]);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(conversion, null);
      }
    },
  );

  test('missing source never clears the recovery journal', () async {
    await expectLater(
      MeetingAudioFilePicker.keepRecordingLocal('${root.path}/missing.wav'),
      throwsException,
    );
    expect(acknowledgements, isEmpty);
  });

  test('destination failure never clears the recovery journal', () async {
    final source = File('${root.path}/original.wav');
    await source.writeAsBytes([1, 2, 3, 4]);
    await File('${root.path}/meeting_local').writeAsString('blocked directory');
    await expectLater(
      MeetingAudioFilePicker.keepRecordingLocal(source.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(acknowledgements, isEmpty);
    expect(await source.readAsBytes(), [1, 2, 3, 4]);
  });
}
