import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/auth/auth_session_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AuthSession session(String token) => AuthSession(
  phone: '13800138000',
  userId: 1,
  token: token,
  apiBase: 'https://example.com/api/v1',
  roles: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('old token deletion cannot erase a newly saved login', () async {
    final storage = AuthSessionStorage();
    await storage.write(session('old'));
    final blocker = Completer<SharedPreferences>();
    final prefs = await SharedPreferences.getInstance();
    var calls = 0;
    final delayed = AuthSessionStorage(
      preferences: () {
        if (calls++ == 0) return blocker.future;
        return Future.value(prefs);
      },
    );
    final deletion = delayed.removeIfToken('old');
    final login = delayed.write(session('new'));
    blocker.complete(prefs);
    await Future.wait([deletion, login]);
    await delayed.removeIfToken('old');
    expect((jsonDecode((await delayed.read())!) as Map)['token'], 'new');
  });

  test(
    'refresh write followed by logout removes the refreshed token',
    () async {
      final storage = AuthSessionStorage();
      await storage.write(session('old'));
      final refresh = storage.write(session('refreshed'));
      final logout = storage.removeIfToken('refreshed');
      await Future.wait([refresh, logout]);
      expect(await storage.read(), isNull);
    },
  );

  test('repeated fresh storage instances retain the saved session', () async {
    await AuthSessionStorage().write(session('saved'));
    for (var i = 0; i < 2; i++) {
      final raw = await AuthSessionStorage().read();
      expect((jsonDecode(raw!) as Map)['token'], 'saved');
    }
  });

  test('preferences wipe falls back to the session file', () async {
    final dir = await Directory.systemTemp.createTemp('dunes-session');
    addTearDown(() => dir.delete(recursive: true));
    Future<Directory?> directory() async => dir;
    final storage = AuthSessionStorage(sessionDirectory: directory);
    await storage.write(session('kept'));
    final prefs = await SharedPreferences.getInstance();
    expect(await prefs.remove(AuthSessionStorage.key), isTrue);

    final raw = await AuthSessionStorage(sessionDirectory: directory).read();
    expect((jsonDecode(raw!) as Map)['token'], 'kept');
    expect(prefs.getString(AuthSessionStorage.key), contains('kept'));
  });

  test('corrupt session file falls back to the previous copy', () async {
    final dir = await Directory.systemTemp.createTemp('dunes-session-bak');
    addTearDown(() => dir.delete(recursive: true));
    Future<Directory?> directory() async => dir;
    final storage = AuthSessionStorage(sessionDirectory: directory);
    await storage.write(session('first'));
    await storage.write(session('second'));
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AuthSessionStorage.key);
    final file = File(
      '${dir.path}${Platform.pathSeparator}dunes_auth_session_v1.json',
    );
    await file.writeAsString('{');

    final raw = await storage.read();
    expect((jsonDecode(raw!) as Map)['token'], 'first');
  });
}
