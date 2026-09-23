import 'package:dunes_app/core/analytics/usage_analytics.dart';
import 'package:dunes_app/core/analytics/usage_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final analytics = UsageAnalytics.instance;

  setUp(analytics.debugBind);
  tearDown(analytics.debugReset);

  test('workbench background still excludes idle time', () {
    var now = DateTime.utc(2026, 9, 23, 8);
    analytics.debugSetClock(() => now);
    analytics.trackScreen('QJA');
    analytics.beginExternalHandoff();
    now = now.add(const Duration(seconds: 4));
    analytics.onLifecycle(foreground: false, suspended: true);
    now = now.add(const Duration(minutes: 10));
    analytics.onLifecycle(foreground: true);

    final leave = _leaves();
    expect(leave, hasLength(1));
    expect(leave.single.moduleKey, 'workbench');
    expect(leave.single.durationMs, 4000);
  });

  test('enterprise webview background does not keep counting', () {
    var now = DateTime.utc(2026, 9, 23, 8);
    analytics.debugSetClock(() => now);
    analytics.trackScreen('CT1');
    now = now.add(const Duration(seconds: 2));
    analytics.onLifecycle(foreground: false, suspended: true);
    now = now.add(const Duration(minutes: 5));

    final leave = _leaves();
    expect(leave, hasLength(1));
    expect(leave.single.moduleKey, 'h5:ctrip');
    expect(leave.single.durationMs, 2000);
  });

  test('browser handoff keeps time until the user returns', () {
    var now = DateTime.utc(2026, 9, 23, 8);
    analytics.debugSetClock(() => now);
    analytics.trackScreen('XR1');
    analytics.beginExternalHandoff();
    now = now.add(const Duration(seconds: 1));
    analytics.onLifecycle(foreground: false, suspended: false);
    now = now.add(const Duration(seconds: 20));
    analytics.onLifecycle(foreground: false, suspended: true);
    now = now.add(const Duration(minutes: 8));
    analytics.onLifecycle(foreground: true);

    final leave = _leaves();
    expect(leave, hasLength(1));
    expect(leave.single.screenId, 'XR1');
    expect(leave.single.moduleKey, 'h5:xrxs');
    expect(leave.single.durationMs, const Duration(minutes: 8, seconds: 21).inMilliseconds);
    expect(
      analytics.debugEvents.where((e) => e.eventType == 'page_enter'),
      hasLength(2),
    );
  });

  test('leaving the sso page while the browser is open settles that app', () {
    var now = DateTime.utc(2026, 9, 23, 8);
    analytics.debugSetClock(() => now);
    analytics.primeScreen(
      screenId: 'AM:digital-center',
      screenName: '三桶油-数字中心',
      moduleKey: 'h5:digital-center',
    );
    analytics.trackScreen('AM1');
    analytics.beginExternalHandoff();
    now = now.add(const Duration(seconds: 3));
    analytics.onLifecycle(foreground: false, suspended: true);
    now = now.add(const Duration(minutes: 4));
    analytics.trackScreen('QJA');

    final leave = _leaves();
    expect(leave, hasLength(1));
    expect(leave.single.screenId, 'AM:digital-center');
    expect(leave.single.screenName, '三桶油-数字中心');
    expect(leave.single.moduleKey, 'h5:digital-center');
    expect(leave.single.durationMs, const Duration(minutes: 4, seconds: 3).inMilliseconds);
  });
}

List<UsageEvent> _leaves() {
  return UsageAnalytics.instance.debugEvents
      .where((event) => event.eventType == 'page_leave')
      .toList(growable: false);
}
