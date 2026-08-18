import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/chat/chat_markdown_preview.dart';

void main() {
  group('chatPayloadIsMarkdown', () {
    test('recognizes markdown extensions case-insensitively', () {
      expect(chatPayloadIsMarkdown(null, '说明.md'), isTrue);
      expect(chatPayloadIsMarkdown(null, 'README.MARKDOWN'), isTrue);
    });

    test('recognizes markdown mime types', () {
      expect(
        chatPayloadIsMarkdown(const {
          'mimeType': 'text/markdown',
        }, 'attachment'),
        isTrue,
      );
      expect(
        chatPayloadIsMarkdown(const {
          'mimeType': 'text/x-markdown',
        }, 'attachment'),
        isTrue,
      );
    });

    test('does not intercept other file types', () {
      expect(
        chatPayloadIsMarkdown(const {
          'mimeType': 'application/pdf',
        }, 'report.pdf'),
        isFalse,
      );
      expect(
        chatPayloadIsMarkdown(const {
          'mimeType': 'application/vnd.ms-excel',
        }, 'report.xls'),
        isFalse,
      );
    });
  });
}
