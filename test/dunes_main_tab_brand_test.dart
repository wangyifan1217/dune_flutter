import 'package:dunes_app/features/nova/nova_icon.dart';
import 'package:dunes_app/features/nova/nova_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('side rail brand uses 韬管理 and the original τ tab mark', () {
    expect(kNovaName, '韬管理');
    expect(kNovaIdentityReply, '我是韬');
    expect(kNovaName.contains('饕'), isFalse);
    expect(kNovaIdentityReply.contains('饕'), isFalse);
    expect(NovaIcon.tabAssetPath, 'assets/images/tau_tab_icon.png');
  });
}
