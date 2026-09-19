import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/nova/nova_deliverable.dart';

void main() {
  group('normalizeNovaMarkdownLayout', () {
    test('does not split leading ## heading into orphan # line', () {
      const input = '## 标题\n\n正文内容';
      expect(normalizeNovaMarkdownLayout(input), input);
    });

    test('does not split leading ### heading into orphan # line', () {
      const input = '### 小节\n正文';
      expect(normalizeNovaMarkdownLayout(input), input);
    });

    test('normalizes heading without space after hashes', () {
      expect(normalizeNovaMarkdownLayout('##标题'), '## 标题');
    });

    test('splits mid-line heading after plain text', () {
      expect(normalizeNovaMarkdownLayout('正文 ## 小节'), '正文\n\n## 小节');
    });

    test('removes orphan heading marker lines', () {
      expect(normalizeNovaMarkdownLayout('#\n## 标题\n正文'), '## 标题\n正文');
    });

    test('splits compressed Chinese menu-style list items', () {
      expect(
        normalizeNovaMarkdownLayout('早食（过早）-热干面：碱面拌芝麻酱。 -豆皮：蛋皮糯米。 -面窝：外酥内嫩。'),
        '早食（过早）\n- 热干面：碱面拌芝麻酱。\n- 豆皮：蛋皮糯米。\n- 面窝：外酥内嫩。',
      );
    });

    test('does not split ordinary hyphenated text', () {
      const input = '武汉-北京的高铁大约四小时。';
      expect(normalizeNovaMarkdownLayout(input), input);
    });

    test('splits compressed weather labels stuck to previous clause', () {
      expect(
        normalizeNovaMarkdownLayout('夜间转中雨或小雨-气温：约 18°C。空气质量：轻度污染-风力：东风。'),
        contains('\n- 气温：'),
      );
      expect(
        normalizeNovaMarkdownLayout('夜间转中雨或小雨-气温：约 18°C。空气质量：轻度污染-风力：东风。'),
        contains('\n- 风力：'),
      );
    });

    test('splits compact bold field labels into Markdown list rows', () {
      expect(
        normalizeNovaMarkdownLayout(
          '明天适合出门-**天气：**多云-**气温：**23℃~29℃-**降水：**约6%',
        ),
        '明天适合出门\n- **天气：**多云\n- **气温：**23℃~29℃\n- **降水：**约6%',
      );
    });
  });
}
