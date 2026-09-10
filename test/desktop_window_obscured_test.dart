import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/desktop/windows_desktop_tray.dart';

void main() {
  test('window obscured starts false and is not the same as inactive', () {
    expect(windowsTrayIsWindowObscured(), isFalse);
    expect(windowsTrayWindowObscuredListenable().value, isFalse);
    // 失焦会使 inactive=true，但 obscured 只看隐藏/最小化/occlusion。
    // 未初始化托盘时两者都是 false，仅保证 API 可调用且默认不冻动画。
    expect(windowsTrayIsWindowInactive(), isFalse);
  });
}
