import 'dart:async';
import 'dart:convert';

import 'package:dunes_app/features/attendance/attendance_models.dart';
import 'package:dunes_app/features/attendance/attendance_service.dart';
import 'package:dunes_app/features/attendance/native_attendance_page.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _session = AuthSession(
  phone: '13800138000',
  userId: 7,
  token: 'employee-token',
  apiBase: 'https://attendance.test/api/v1',
  roles: [],
  displayName: '测试员工',
);

http.Response _ok(Object data) => http.Response(
  jsonEncode({'success': true, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const locationChannels = [
    MethodChannel('flutter.baseflow.com/geolocator'),
    MethodChannel('flutter.baseflow.com/geolocator_android'),
    MethodChannel('dunes/attendance_wifi'),
  ];
  var gpsReads = 0;
  var reportedAccuracy = 10.0;
  setUp(() {
    gpsReads = 0;
    reportedAccuracy = 10;
    for (final channel in locationChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'currentNetwork':
                return {'ssid': 'Office', 'bssid': '11:22:33:44:55:66'};
              case 'isLocationServiceEnabled':
                return true;
              case 'checkPermission':
                return 2;
              case 'getCurrentPosition':
                gpsReads++;
                return {
                  'latitude': 31.0,
                  'longitude': 121.0,
                  'accuracy': reportedAccuracy,
                };
              default:
                return null;
            }
          });
    }
  });
  tearDown(() {
    for (final channel in locationChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets(
    'first punch enrolls in App then captures a separate verification photo',
    (tester) async {
      reportedAccuracy = 2000;
      var enrolled = false;
      var punched = false;
      var captures = 0;
      final sequence = <String>[];
      final service = AttendanceService(
        _session,
        client: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/today')) {
            return _ok({
              'date': '2026-11-09',
              'faceRequired': true,
              'sites': [
                {
                  'id': 1,
                  'name': '总部',
                  'latitude': 31,
                  'longitude': 121,
                  'radiusMeters': 200,
                  'maxAccuracyMeters': 100,
                },
              ],
              if (punched)
                'checkIn': {
                  'id': 1,
                  'type': 'check_in',
                  'punchedAt': '2026-11-09T01:00:00Z',
                },
            });
          }
          if (path.endsWith('/face/status')) {
            return _ok({'faceRequired': true, 'enrolled': enrolled});
          }
          if (path.endsWith('/face/enroll')) {
            expect(request.method, 'POST');
            expect(request.headers['authorization'], 'Bearer employee-token');
            expect(request.url.hasQuery, isFalse);
            expect(request.headers['content-type'], 'image/jpeg');
            expect(request.bodyBytes, [255, 216, 255, 1]);
            expect(punched, isFalse);
            sequence.add('enroll');
            enrolled = true;
            return _ok({'faceRequired': true, 'enrolled': true});
          }
          if (path.endsWith('/face/verify')) {
            expect(enrolled, isTrue);
            expect(request.bodyBytes, [255, 216, 255, 2]);
            sequence.add('verify');
            return _ok({
              'matched': true,
              'verificationToken': 'receipt',
              'expiresIn': 90,
            });
          }
          if (path.endsWith('/punch')) {
            sequence.add('punch');
            expect(gpsReads, 2);
            expect((jsonDecode(request.body) as Map)['accuracyMeters'], 2000);
            expect(
              (jsonDecode(request.body) as Map)['faceVerificationToken'],
              'receipt',
            );
            punched = true;
            return _ok({
              'id': 1,
              'type': 'check_in',
              'punchedAt': '2026-11-09T01:00:00Z',
            });
          }
          throw StateError('unexpected request: $path');
        }),
      );
      addTearDown(service.close);
      await tester.pumpWidget(
        MaterialApp(
          home: NativeAttendancePage(
            session: _session,
            service: service,
            captureFace: () async {
              captures++;
              sequence.add('capture-$captures');
              return AttendanceFacePhoto(
                Uint8List.fromList([255, 216, 255, captures]),
                'image/jpeg',
              );
            },
          ),
        ),
      );
      await _frames(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is Icon &&
              widget.icon == Icons.fingerprint_rounded &&
              widget.size == 36,
        ),
      );
      await _frames(tester);
      expect(
        find.text('录入本人脸'),
        findsOneWidget,
        reason:
            'gps=$gpsReads texts=${tester.widgetList<Text>(find.byType(Text)).map((e) => e.data).toList()}',
      );
      expect(punched, isFalse);
      final button = find.text('拍照录入本人脸');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await _frames(tester);
      expect(sequence, ['capture-1', 'enroll', 'capture-2', 'verify', 'punch']);
      expect(punched, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('standalone enrollment entry does not submit attendance', (
    tester,
  ) async {
    var enrolled = false;
    var captures = 0;
    final service = AttendanceService(
      _session,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/today')) {
          return _ok({'faceRequired': true, 'sites': []});
        }
        if (request.url.path.endsWith('/face/status')) {
          return _ok({'faceRequired': true, 'enrolled': enrolled});
        }
        if (request.url.path.endsWith('/face/enroll')) {
          enrolled = true;
          return _ok({'faceRequired': true, 'enrolled': true});
        }
        fail('standalone enrollment must not verify or punch');
      }),
    );
    addTearDown(service.close);
    await tester.pumpWidget(
      MaterialApp(
        home: NativeAttendancePage(
          session: _session,
          service: service,
          captureFace: () async {
            captures++;
            return AttendanceFacePhoto(
              Uint8List.fromList([255, 216, 255, 1]),
              'image/jpeg',
            );
          },
        ),
      ),
    );
    await _frames(tester);
    await tester.ensureVisible(find.text('录入人脸'));
    await tester.tap(find.text('录入人脸'));
    await _frames(tester);
    await tester.ensureVisible(find.text('拍照录入本人脸'));
    await tester.tap(find.text('拍照录入本人脸'));
    await _frames(tester);
    expect(enrolled, isTrue);
    expect(captures, 1);
    expect(gpsReads, 0);
    expect(find.text('考勤打卡'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'camera cancellation never enrolls or punches and permits retry',
    (tester) async {
      final capture = Completer<AttendanceFacePhoto?>();
      var captures = 0;
      final service = AttendanceService(
        _session,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/today')) {
            return _ok({
              'faceRequired': true,
              'sites': [
                {
                  'id': 1,
                  'name': '总部',
                  'latitude': 31,
                  'longitude': 121,
                  'radiusMeters': 200,
                },
              ],
            });
          }
          if (request.url.path.endsWith('/face/status')) {
            return _ok({'faceRequired': true, 'enrolled': false});
          }
          fail('cancelled enrollment must not call enroll, verify or punch');
        }),
      );
      addTearDown(service.close);
      await tester.pumpWidget(
        MaterialApp(
          home: NativeAttendancePage(
            session: _session,
            service: service,
            captureFace: () {
              captures++;
              return capture.future;
            },
          ),
        ),
      );
      await _frames(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is Icon &&
              widget.icon == Icons.fingerprint_rounded &&
              widget.size == 36,
        ),
      );
      await _frames(tester);
      final button = find.text('拍照录入本人脸');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(captures, 1);
      expect(find.text('正在处理'), findsOneWidget);
      final processing = tester.widget<FilledButton>(
        find.byType(FilledButton).first,
      );
      expect(processing.onPressed, isNull);
      capture.complete(null);
      await _frames(tester);
      expect(find.text('拍照录入本人脸'), findsOneWidget);
      await tester.pageBack();
      await _frames(tester);
      expect(find.text('考勤打卡'), findsOneWidget);
      expect(find.text('正在确认打卡'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
