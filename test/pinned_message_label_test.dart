import 'package:dunes_app/features/conversation/conversation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NativePinnedMessage pin({
    required String kind,
    String bodyText = '',
    String previewText = '',
    String senderName = '李凡伊',
    Map<String, dynamic>? payload,
  }) {
    return NativePinnedMessage(
      id: 1,
      conversationId: 1,
      messageId: 2,
      kind: kind,
      bodyText: bodyText,
      previewText: previewText,
      senderName: senderName,
      pinnedByDisplayName: '王奕凡',
      payload: payload,
    );
  }

  test('图片置顶显示 [图片]，不用推送口吻', () {
    final item = pin(
      kind: 'IMAGE',
      previewText: '发送了一张图片',
    );
    expect(item.pinnedActionLabel, '王奕凡置顶了');
    expect(item.contentLabel, '李凡伊：[图片]');
  });

  test('文件置顶显示文件名', () {
    final item = pin(
      kind: 'FILE',
      bodyText: '预算.xlsx',
      previewText: '发送了一个文件',
      payload: const {'fileName': '预算.xlsx'},
    );
    expect(item.contentLabel, '李凡伊：[文件] 预算.xlsx');
  });

  test('文本置顶保留正文', () {
    final item = pin(
      kind: 'TEXT',
      bodyText: '算了 我问天才程序员',
      previewText: '算了 我问天才程序员',
    );
    expect(item.contentLabel, '李凡伊：算了 我问天才程序员');
  });
}
