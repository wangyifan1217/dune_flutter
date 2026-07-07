import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

import '../lib/features/auth/auth_session.dart';
import '../lib/features/meeting/meeting_audio_converter.dart';
import '../lib/features/meeting/native_meeting_service.dart';

const _apiBase = 'http://124.221.216.24:6090/api/v1';
const _phone = '15268642022';
const _code = '666666';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final out = StringBuffer('Meeting upload benchmark\n');
  try {
    final docs = await getApplicationDocumentsDirectory();
    final benchDir = Directory('${docs.path}/benchmark');
    await benchDir.create(recursive: true);
    await _ensureStorageAccess();

    final cases = <_BenchCase>[
      _BenchCase(label: '30min', wavName: 'test_30min.wav', durationSec: 1800),
      _BenchCase(label: '60min', wavName: 'test_60min.wav', durationSec: 3600),
    ];

    final session = await _login();
    final svc = NativeMeetingService(session: session);

    for (final c in cases) {
      final wavPath = await _ensureBenchFile(c.wavName, benchDir);
      final wav = File(wavPath);
      final wavMb = (await wav.length()) / (1024 * 1024);
      out.writeln('\n=== ${c.label} (${wavMb.toStringAsFixed(1)} MB wav) ===');

      final m4aPath =
          '${benchDir.path}/bench_${c.label}_${DateTime.now().millisecondsSinceEpoch}.m4a';

      final convertSw = Stopwatch()..start();
      final converted = await MeetingAudioConverter.prepareForUpload(
        wavPath,
        outputPath: m4aPath,
      );
      convertSw.stop();

      final uploadPath = converted;
      final m4a = File(uploadPath);
      final m4aMb =
          await m4a.exists() ? (await m4a.length()) / (1024 * 1024) : wavMb;

      final uploadSw = Stopwatch()..start();
      final upload = await svc.uploadAudioFile(
        filePath: uploadPath,
        fileName: m4a.uri.pathSegments.last,
        bucket: 'meeting-audio',
      );
      uploadSw.stop();

      final ratio = wavMb / (m4aMb <= 0 ? 1 : m4aMb);
      out.writeln('  compress: ${convertSw.elapsedMilliseconds} ms');
      out.writeln('  m4a size: ${m4aMb.toStringAsFixed(2)} MB (${ratio.toStringAsFixed(1)}x)');
      out.writeln('  upload:   ${uploadSw.elapsedMilliseconds} ms');
      out.writeln(
        '  total:    ${convertSw.elapsedMilliseconds + uploadSw.elapsedMilliseconds} ms',
      );
      out.writeln('  objectKey: ${upload['objectKey']}');

      if (uploadPath != wavPath && await m4a.exists()) {
        await m4a.delete();
      }
    }
  } catch (e, st) {
    out.writeln('ERROR: $e\n$st');
  }

  final result = out.toString();
  debugPrint(result);
  try {
    final docs = await getApplicationDocumentsDirectory();
    await File('${docs.path}/benchmark_result.txt').writeAsString(result);
  } catch (_) {}
  exit(result.contains('ERROR') ? 1 : 0);
}

class _BenchCase {
  const _BenchCase({
    required this.label,
    required this.wavName,
    required this.durationSec,
  });

  final String label;
  final String wavName;
  final int durationSec;
}

Future<void> _ensureStorageAccess() async {
  final statuses = await <Permission>[
    Permission.storage,
    Permission.manageExternalStorage,
    Permission.audio,
  ].request();
  if (statuses.values.every((s) => s.isDenied || s.isPermanentlyDenied)) {
    debugPrint('storage permission not granted, trying direct paths anyway');
  }
}

Future<String> _ensureBenchFile(String name, Directory benchDir) async {
  final dest = File('${benchDir.path}/$name');
  if (await dest.exists() && await dest.length() > 44) {
    return dest.path;
  }

  const candidates = <String>[
    '/storage/emulated/0/Download/meeting_benchmark',
    '/sdcard/Download/meeting_benchmark',
  ];
  for (final dir in candidates) {
    final src = File('$dir/$name');
    if (await src.exists()) {
      await src.copy(dest.path);
      return dest.path;
    }
  }
  throw Exception('missing benchmark file $name on device');
}

Future<AuthSession> _login() async {
  final resp = await http.post(
    Uri.parse('$_apiBase/auth/sms/token'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode(<String, dynamic>{
      'phone': _phone,
      'code': _code,
      'channel': 'app',
    }),
  );
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw Exception('login failed: ${resp.statusCode} ${resp.body}');
  }
  final body = jsonDecode(resp.body) as Map<String, dynamic>;
  final data = body['data'];
  if (data is! Map<String, dynamic>) {
    throw Exception('login missing data');
  }
  final token = (data['token'] ?? '').toString();
  if (token.isEmpty) throw Exception('login missing token');
  final userId = data['userId'];
  return AuthSession(
    phone: _phone,
    userId: userId is num ? userId.toInt() : 0,
    token: token,
    apiBase: _apiBase,
    roles: const <String>[],
  );
}
