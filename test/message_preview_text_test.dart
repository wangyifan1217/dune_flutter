import 'package:dunes_app/features/conversation/message_preview_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('纯文本即使带图片后缀也不当成图片', () {
    expect(
      compactMessagePushPreview(kind: 'TEXT', body: '测试.jpg'),
      '测试.jpg',
    );
    expect(
      compactMessagePushPreview(kind: 'TEXT', body: 'xx.png'),
      'xx.png',
    );
    expect(
      compactMessagePushPreview(kind: 'TEXT', body: 'readme.md'),
      'readme.md',
    );
  });

  test('真正的图片消息仍显示发送了一张图片', () {
    expect(
      compactMessagePushPreview(kind: 'IMAGE', body: '测试.jpg'),
      '发送了一张图片',
    );
    expect(
      compactMessagePushPreview(kind: 'TEXT', body: '[图片] 测试.jpg'),
      '发送了一张图片',
    );
    expect(
      compactMessagePushPreview(kind: 'TEXT', body: '[相册]'),
      '发送了一张图片',
    );
  });
}
