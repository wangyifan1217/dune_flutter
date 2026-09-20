import 'package:dunes_app/core/analytics/usage_module_map.dart';
import 'package:dunes_app/features/qianji/app_usage_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usageModuleKeyForScreen maps main tabs', () {
    expect(usageModuleKeyForScreen('C1'), 'comm');
    expect(usageModuleKeyForScreen('C4'), 'nova');
    expect(usageModuleKeyForScreen('QJ'), 'nova');
    expect(usageModuleKeyForScreen('QJUH'), 'nova');
    expect(usageModuleKeyForScreen('LH'), 'lighthouse');
    expect(usageModuleKeyForScreen('B2'), 'me');
    expect(usageModuleKeyForScreen('B1'), 'approval');
    expect(usageModuleKeyForScreen('K1'), 'kb');
    expect(usageModuleKeyForScreen('MM'), 'meeting');
    expect(usageModuleKeyForScreen('FD1'), 'drive');
    expect(usageModuleKeyForScreen('XR1'), 'h5');
    expect(usageModuleKeyForScreen('CT1'), 'h5');
  });

  test('usageScreenName converts internal route IDs to readable labels', () {
    expect(usageScreenName('QJUH'), '使用热力');
    expect(usageScreenName('QJUHD'), '人员使用详情');
    expect(usageScreenName('AA1'), '审批助手');
    expect(usageScreenName('C1'), '消息');
    expect(usageScreenName('自定义页面'), '自定义页面');
  });

  test('formatUsageStay', () {
    expect(formatUsageStay(0), '0分');
    expect(formatUsageStay(90 * 1000), '2分');
    expect(formatUsageStay(60 * 60 * 1000), '1小时');
    expect(formatUsageStay(90 * 60 * 1000), '1小时30分');
  });
}
