import 'dart:async';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const session = AuthSession(
    phone: '13800138000',
    userId: 7,
    token: 'token',
    apiBase: 'http://example.test/api/v1',
    roles: [],
  );

  test(
    'concurrent identical dimension requests share one network call',
    () async {
      final firstResponse = Completer<http.Response>();
      var calls = 0;
      final service = LighthouseService(
        session: session,
        client: MockClient((request) {
          calls++;
          expect(request.url.path, '/api/v1/lighthouse/dimension');
          return calls == 1
              ? firstResponse.future
              : Future.value(http.Response('{"data":{"rows":[]}}', 200));
        }),
      );
      final first = service.fetchDimension(tab: 'supply', period: 'month');
      final second = service.fetchDimension(tab: 'supply', period: 'month');
      firstResponse.complete(http.Response('{"data":{"rows":[]}}', 200));
      await Future.wait([first, second]);
      expect(calls, 1);
      await service.fetchDimension(tab: 'supply', period: 'month');
      expect(calls, 2, reason: 'completed calls must not become stale cache');
      service.dispose();
    },
  );
}
