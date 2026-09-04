import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('comment attachment fromJson keeps public url as objectKey', () {
    final att = ApprovalCommentAttachment.fromJson({
      'name': '截图',
      'url': 'https://image.heunion.com/zdfiles/proposals/202609/1/a.png',
      'mimeType': '',
    });
    expect(att.objectKey, contains('proposals/'));
    expect(att.isImage, isTrue);
    expect(att.toFileItem()['url'], startsWith('https://'));
  });

  test('comment attachment isImage reads extension from objectKey', () {
    final att = ApprovalCommentAttachment.fromJson({
      'name': '附件',
      'objectKey': 'proposals/202609/1/123-shot.PNG',
    });
    expect(att.isImage, isTrue);
  });
}
