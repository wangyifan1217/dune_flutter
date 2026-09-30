import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_data.dart';

void main() {
  test('横幅正文就是 message 原文', () {
    const notice = LighthouseDelayNotice(
      sourceCode: 'SINOPEC',
      message: '中石化结算回传延迟，今日经营数尚未补齐。',
    );
    expect(notice.message, '中石化结算回传延迟，今日经营数尚未补齐。');
    expect(notice.isEmpty, isFalse);
  });

  test('空列表 + 预览开关才下发预览条', () {
    expect(lighthouseDelayNoticesOrPreview(const [], preview: false), isEmpty);
    final previewed = lighthouseDelayNoticesOrPreview(const [], preview: true);
    expect(previewed, hasLength(1));
    expect(previewed.single.sourceCode, 'SINOPEC');
    expect(
      previewed.single.message,
      LighthouseDelayNotice.previewSinopec.message,
    );
  });

  test('真数据在时预览不能盖过去', () {
    const live = LighthouseDelayNotice(
      sourceCode: 'SINOPEC',
      message: '资管原文，不许改。',
    );
    final out = lighthouseDelayNoticesOrPreview([live], preview: true);
    expect(out, hasLength(1));
    expect(out.single.message, '资管原文，不许改。');
  });

  test('服务器测活预警保留部门与原始正文', () {
    final notice = LighthouseDelayNotice.fromJson({
      'sourceCode': 'SERVER_PROBE',
      'bizDeptCode': 'CX',
      'bizDeptName': '出行',
      'message': '服务器测活失败，请相关同事排查',
      'raisedAt': '2026-09-30 09:10:00',
    });

    expect(notice.isServerProbe, isTrue);
    expect(notice.bizDeptCode, 'CX');
    expect(notice.bizDeptName, '出行');
    expect(notice.message, '服务器测活失败，请相关同事排查');
  });

  test('服务器测活兼容数据库下划线字段', () {
    final notice = LighthouseDelayNotice.fromJson({
      'source_code': 'SERVER_PROBE',
      'biz_dept_code': 'DIGITALG',
      'biz_dept_name': '数商',
      'message': '数商服务不可用',
    });

    expect(notice.sourceCode, 'SERVER_PROBE');
    expect(notice.bizDeptName, '数商');
  });
}
