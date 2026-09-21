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

  test('usageModuleLabel uses product names instead of internal codes', () {
    expect(usageModuleLabel('nova'), '小饕');
    expect(usageModuleLabel('NOVA'), '小饕');
    expect(usageModuleLabel('h5'), '网页应用');
    expect(usageModuleLabel('comm'), '通讯');
    expect(usageModuleLabel('unknown', '自定义'), '自定义');
    expect(usageModuleLabel('unknown', 'NOVA'), '小饕');
  });

  test('usageScreenName converts internal route IDs to readable labels', () {
    expect(usageScreenName('QJUH'), '使用热力');
    expect(usageScreenName('QJUHD'), '人员使用详情');
    expect(usageScreenName('AA1'), '审批助手');
    expect(usageScreenName('C1'), '消息');
    expect(usageScreenName('自定义页面'), '自定义页面');
    expect(usageScreenName('B10'), '提案详情');
  });

  test('usageScreenName hides prototype sample names and old English', () {
    expect(usageScreenName('C5'), '私聊');
    expect(usageScreenName('C2'), '群聊');
    expect(usageScreenName('C4'), '小饕');
    expect(usageScreenName('QJ'), '饕');
    expect(usageScreenName('C11'), '小饕对话历史');
    expect(usagePageLabel(screenName: '私聊·邓艳丽'), '私聊');
    expect(usagePageLabel(screenName: '私聊-邓艳丽'), '私聊');
    expect(usagePageLabel(screenName: 'NOVA'), '小饕');
    expect(usagePageLabel(screenName: '审批工作群'), '群聊');
    expect(usagePageLabel(screenId: 'C5', screenName: '私聊·邓艳丽'), '私聊');
    expect(usagePageLabel(screenId: 'QJSS'), '会话监管');
  });

  test('groupedUsagePages merges identical display names', () {
    final pages = groupedUsagePages([
      const AppUsagePageStay(
        screenId: 'C4',
        screenName: 'NOVA',
        moduleKey: 'nova',
        uv: 1,
        pv: 2,
        durationMs: 4000,
      ),
      const AppUsagePageStay(
        screenId: 'C5',
        screenName: '私聊·邓艳丽',
        moduleKey: 'comm',
        uv: 1,
        pv: 3,
        durationMs: 11000,
      ),
      const AppUsagePageStay(
        screenId: '',
        screenName: 'NOVA',
        moduleKey: 'nova',
        uv: 1,
        pv: 1,
        durationMs: 1000,
      ),
    ]);
    expect(pages.map((e) => e.screenName).toList(), ['私聊', '小饕']);
    expect(pages.first.durationMs, 11000);
    expect(pages.last.durationMs, 5000);
  });

  test('formatUsageStay', () {
    expect(formatUsageStay(0), '0分');
    expect(formatUsageStay(90 * 1000), '2分');
    expect(formatUsageStay(60 * 60 * 1000), '1小时');
    expect(formatUsageStay(90 * 60 * 1000), '1小时30分');
  });
}
