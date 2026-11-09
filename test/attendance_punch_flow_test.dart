import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dunes_app/features/attendance/attendance_models.dart';
import 'package:dunes_app/features/attendance/attendance_punch_flow.dart';
import 'package:dunes_app/features/attendance/attendance_service.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const attendanceSession = AuthSession(
  phone: '13800138000',
  userId: 7,
  token: 'employee-token',
  apiBase: 'https://attendance.test/api/v1',
  roles: [],
);

http.Response ok(Object data) => http.Response(
  jsonEncode({'success': true, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object> get record => {
  'id': 1,
  'type': 'check_out',
  'punchedAt': '2026-11-09T10:00:00Z',
  'siteName': '总部',
  'wifiStatus': 'matched',
};

void main() {
  final photo = AttendanceFacePhoto(
    Uint8List.fromList([255, 216, 255, 1]),
    'image/jpeg',
  );
  const location = AttendancePunchLocation(
    latitude: 31,
    longitude: 121,
    accuracyMeters: 12,
    platform: 'ios',
    ssid: 'Office',
    bssid: '11:22:33:44:55:66',
  );

  Future<AttendancePunch?> run(
    AttendanceService service, {
    bool required = true,
    Future<AttendanceFacePhoto?> Function()? capture,
    Future<AttendancePunchLocation?> Function()? locate,
    bool Function()? active,
  }) => AttendancePunchFlow(service).submit(
    type: 'check_out',
    faceRequired: required,
    capture: capture ?? () async => photo,
    locate: locate ?? () async => location,
    isActive: active ?? () => true,
    onPhase: (_) {},
  );

  AttendanceService serviceWith(
    FutureOr<http.Response> Function(http.Request) handler,
  ) {
    final service = AttendanceService(
      attendanceSession,
      client: MockClient((request) async => handler(request)),
    );
    addTearDown(service.close);
    return service;
  }

  test('switch off keeps GPS/Wi-Fi flow and never opens camera', () async {
    var calls = 0;
    final service = serviceWith((request) {
      calls++;
      expect(request.url.path, '/api/v1/attendance/punch');
      final body = jsonDecode(request.body) as Map;
      expect(body.containsKey('faceVerificationToken'), isFalse);
      expect(body['ssid'], 'Office');
      expect(body['bssid'], location.bssid);
      expect(body['platform'], 'ios');
      return ok(record);
    });
    final result = await run(
      service,
      required: false,
      capture: () async {
        fail('camera must not be opened');
      },
    );
    expect(result?.id, 1);
    expect(calls, 1);
  });

  test(
    'uploads raw image with employee auth then submits fresh GPS with receipt',
    () async {
      final sequence = <String>[];
      final service = serviceWith((request) {
        expect(request.headers['authorization'], 'Bearer employee-token');
        if (request.url.path.endsWith('/face/verify')) {
          sequence.add('verify');
          expect(request.url.queryParameters, {'type': 'check_out'});
          expect(request.headers['content-type'], 'image/jpeg');
          expect(request.bodyBytes, photo.bytes);
          return ok({
            'matched': true,
            'verificationToken': 'single-use',
            'expiresIn': 90,
          });
        }
        sequence.add('punch');
        final body = jsonDecode(request.body) as Map;
        expect(body['faceVerificationToken'], 'single-use');
        expect(body['type'], 'check_out');
        expect(body['latitude'], 31);
        expect(body['accuracyMeters'], 12);
        return ok(record);
      });
      final result = await run(
        service,
        capture: () async {
          sequence.add('capture');
          return photo;
        },
        locate: () async {
          sequence.add('locate');
          return location;
        },
      );
      expect(result?.id, 1);
      expect(sequence, ['capture', 'verify', 'locate', 'punch']);
    },
  );

  test('cancelling camera stops before verification and punch', () async {
    final service = serviceWith(
      (_) => throw StateError('must not call server'),
    );
    expect(await run(service, capture: () async => null), isNull);
  });

  test('camera denial stops before verification and punch', () async {
    final service = serviceWith(
      (_) => throw StateError('must not call server'),
    );
    await expectLater(
      run(service, capture: () async => throw Exception('相机权限未开启')),
      throwsA(predicate((e) => '$e'.contains('相机权限'))),
    );
  });

  for (final value in [
    {'matched': false},
    {'matched': true, 'verificationToken': '', 'expiresIn': 90},
    {'matched': true, 'verificationToken': 'token', 'expiresIn': 0},
  ]) {
    test('invalid verification cannot reach GPS or punch: $value', () async {
      var calls = 0;
      final service = serviceWith((request) {
        calls++;
        expect(request.url.path.endsWith('/face/verify'), isTrue);
        return ok(value);
      });
      await expectLater(
        run(service, locate: () async => throw StateError('must not locate')),
        throwsException,
      );
      expect(calls, 1);
    });
  }

  for (final status in [404, 422, 503]) {
    test(
      'face service error $status never falls back to GPS-only punch',
      () async {
        var calls = 0;
        final service = serviceWith((_) {
          calls++;
          return http.Response(
            jsonEncode({'success': false, 'message': '请重试人脸核验'}),
            status,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        await expectLater(
          run(service),
          throwsA(predicate((e) => '$e'.contains('请重试人脸核验'))),
        );
        expect(calls, 1);
      },
    );
  }

  test(
    'too little receipt lifetime remaining requires another photo',
    () async {
      var calls = 0;
      final service = serviceWith((_) {
        calls++;
        return ok({
          'matched': true,
          'verificationToken': 'short',
          'expiresIn': 2,
        });
      });
      await expectLater(
        run(service),
        throwsA(predicate((e) => '$e'.contains('已过期'))),
      );
      expect(calls, 1);
    },
  );

  test('location failure after verification prevents punch', () async {
    var calls = 0;
    final service = serviceWith((_) {
      calls++;
      return ok({
        'matched': true,
        'verificationToken': 'token',
        'expiresIn': 90,
      });
    });
    expect(await run(service, locate: () async => null), isNull);
    expect(calls, 1);
  });

  test(
    'leaving page during verification stops before location and punch',
    () async {
      var active = true;
      final service = serviceWith((_) {
        active = false;
        return ok({
          'matched': true,
          'verificationToken': 'token',
          'expiresIn': 90,
        });
      });
      expect(
        await run(
          service,
          active: () => active,
          locate: () async => throw StateError('must not locate'),
        ),
        isNull,
      );
    },
  );

  test(
    'retry after failed punch captures and verifies again with a new receipt',
    () async {
      var captures = 0;
      var verifications = 0;
      final tokens = <String>[];
      final service = serviceWith((request) {
        if (request.url.path.endsWith('/face/verify')) {
          verifications++;
          return ok({
            'matched': true,
            'verificationToken': 'receipt-$verifications',
            'expiresIn': 90,
          });
        }
        tokens.add(
          (jsonDecode(request.body) as Map)['faceVerificationToken'] as String,
        );
        if (tokens.length == 1) {
          return http.Response(
            '{"success":false,"message":"保存失败"}',
            503,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return ok(record);
      });
      Future<AttendanceFacePhoto?> capture() async {
        captures++;
        return photo;
      }

      await expectLater(run(service, capture: capture), throwsException);
      expect((await run(service, capture: capture))?.id, 1);
      expect(captures, 2);
      expect(tokens, ['receipt-1', 'receipt-2']);
    },
  );
}
