import 'package:dunes_app/features/conversation/conversation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('私有 flow-go key 不能伪装成 CDN 公网地址', () {
    final resolved = ConversationService.resolvePublicStorageUrl(
      '',
      'flow-go/12/123-photo.jpg',
    );
    expect(resolved, isEmpty);
  });

  test('公网 im/ 相对路径可拼 CDN', () {
    final resolved = ConversationService.resolvePublicStorageUrl(
      '',
      'im/301/202608/12/123-photo.jpg',
    );
    expect(
      resolved,
      'https://image.heunion.com/zdfiles/im/301/202608/12/123-photo.jpg',
    );
  });

  test('原图解析优先真实 HTTPS，不回退 preview', () {
    final url = ConversationService.mediaOriginalPublicImageUrl({
      'url': 'https://image.heunion.com/zdfiles/im/a-original.jpg',
      'objectKey': 'https://image.heunion.com/zdfiles/im/a-original.jpg',
      'previewUrl': 'https://image.heunion.com/zdfiles/im/a-preview.jpg',
      'previewObjectKey': 'https://image.heunion.com/zdfiles/im/a-preview.jpg',
    });
    expect(url, 'https://image.heunion.com/zdfiles/im/a-original.jpg');
  });

  test('私有原图没有公网直链时返回 null，交给鉴权下载', () {
    final url = ConversationService.mediaOriginalPublicImageUrl({
      'url': '',
      'objectKey': 'flow-go/12/123-photo.jpg',
      'previewObjectKey': 'flow-go/12/123-photo-preview.jpg',
    });
    expect(url, isNull);
  });
}
