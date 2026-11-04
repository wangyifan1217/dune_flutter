import 'dart:async';

import 'package:dunes_app/features/qianji_admin/workbench_access_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fast permissions publish while a separate request is pending', () async {
    final slow = Completer<bool>();
    final fast = Completer<bool>();
    final published = <String>[];
    final slowJob = publishWorkbenchAccessProbe(slow.future,
        isCurrent: () => true, onResult: (_) => published.add('slow'));
    final fastJob = publishWorkbenchAccessProbe(fast.future,
        isCurrent: () => true, onResult: (_) => published.add('fast'));
    fast.complete(true);
    await fastJob;
    expect(published, ['fast']);
    slow.complete(true);
    await slowJob;
    expect(published, ['fast', 'slow']);
  });

  test('obsolete and failed results never update permissions', () async {
    final pending = Completer<bool>();
    var current = true;
    var updates = 0;
    final job = publishWorkbenchAccessProbe(pending.future,
        isCurrent: () => current, onResult: (_) => updates++);
    current = false;
    pending.complete(true);
    await job;
    await publishWorkbenchAccessProbe<bool>(Future.error(StateError('offline')),
        isCurrent: () => true, onResult: (_) => updates++);
    expect(updates, 0);
  });
}
