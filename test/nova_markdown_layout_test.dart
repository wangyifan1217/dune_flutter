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
      expect(
        normalizeNovaMarkdownLayout('##标题'),
        '## 标题',
      );
    });

    test('splits mid-line heading after plain text', () {
      expect(
        normalizeNovaMarkdownLayout('正文 ## 小节'),
        '正文\n\n## 小节',
      );
    });

    test('removes orphan heading marker lines', () {
      expect(
        normalizeNovaMarkdownLayout('#\n## 标题\n正文'),
        '## 标题\n正文',
      );
    });
  });
}
