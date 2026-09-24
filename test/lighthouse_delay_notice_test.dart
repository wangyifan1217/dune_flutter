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
    expect(
      lighthouseDelayNoticesOrPreview(const [], preview: false),
      isEmpty,
    );
    final previewed = lighthouseDelayNoticesOrPreview(const [], preview: true);
    expect(previewed, hasLength(1));
    expect(previewed.single.sourceCode, 'SINOPEC');
    expect(previewed.single.message, LighthouseDelayNotice.previewSinopec.message);
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
}
