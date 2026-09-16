import 'package:dunes_app/features/update/app_release_notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty notes fall back to default software-update copy', () {
    final parsed = parseReleaseNotes('');
    expect(parsed.headline, kDefaultReleaseHeadline);
    expect(parsed.summary, kDefaultReleaseSummary);
    expect(parsed.notices, kDefaultReleaseNotices);
  });

  test('force update uses 重要更新 headline', () {
    final parsed = parseReleaseNotes('', forceUpdate: true);
    expect(parsed.headline, kForceReleaseHeadline);
  });

  test('parses headline, summary and numbered notices', () {
    const raw = '''
系统重要补丁
亲爱的用户，本次更新优化了部分场景的使用体验，推荐您进行更新。

更新注意事项：
1. 本次更新不会删除您的用户数据，但仍建议您在更新前做好数据备份。
2. 软件更新包在更新后会自动删除，不占用存储空间。
''';
    final parsed = parseReleaseNotes(raw);
    expect(parsed.headline, '系统重要补丁');
    expect(parsed.summary, contains('亲爱的用户'));
    expect(parsed.notices, [
      '本次更新不会删除您的用户数据，但仍建议您在更新前做好数据备份。',
      '软件更新包在更新后会自动删除，不占用存储空间。',
    ]);
  });

  test('numbered lines without 注意事项 header still split', () {
    const raw = '''
通讯稳定性优化
修复会话偶发无法发送的问题
1. 请先备份重要资料
2. 安装完成后重启应用
''';
    final parsed = parseReleaseNotes(raw);
    expect(parsed.headline, '通讯稳定性优化');
    expect(parsed.summary, '修复会话偶发无法发送的问题');
    expect(parsed.notices, ['请先备份重要资料', '安装完成后重启应用']);
  });
}
