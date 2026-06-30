import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/nova/native_nova_service.dart';

void main() {
  test('reconcileMisclassifiedNovaRoles restores alternating user/assistant', () {
    final at = DateTime.utc(2026, 6, 1, 10);
    final rows = [
      NativeNovaMessage(
        id: 1,
        role: 'assistant',
        text: '你好',
        createdAt: at,
      ),
      NativeNovaMessage(
        id: 2,
        role: 'assistant',
        text: '你好，我是 NOVA',
        createdAt: at.add(const Duration(seconds: 1)),
      ),
    ];

    final fixed = reconcileMisclassifiedNovaRoles(rows);

    expect(fixed[0].role, 'user');
    expect(fixed[0].text, '你好');
    expect(fixed[1].role, 'assistant');
  });

  test('reconcileMisclassifiedNovaRoles keeps rows when user already present', () {
    final at = DateTime.utc(2026, 6, 1, 10);
    final rows = <NativeNovaMessage>[
      NativeNovaMessage(id: 1, role: 'user', text: 'hi', createdAt: at),
      NativeNovaMessage(
        id: 2,
        role: 'assistant',
        text: 'hello',
        createdAt: at.add(const Duration(seconds: 1)),
      ),
    ];
    final fixed = reconcileMisclassifiedNovaRoles(rows);
    expect(fixed[0].role, 'user');
    expect(fixed[1].role, 'assistant');
  });
}
