import 'dart:typed_data';

import 'package:dunes_app/features/chat/chat_image_utils.dart';
import 'package:dunes_app/features/conversation/conversation_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gif messages keep the original file instead of the jpeg still', () {
    final payload = <String, dynamic>{
      'url': 'https://image.heunion.com/zdfiles/im/chat/meme.gif',
      'objectKey': 'im/chat/meme.gif',
      'previewUrl': 'https://image.heunion.com/zdfiles/im/chat/meme-preview.jpg',
      'previewObjectKey': 'im/chat/meme-preview.jpg',
      'fileName': 'meme.gif',
      'mimeType': 'image/gif',
    };

    expect(ConversationService.mediaIsGif(payload), isTrue);
    expect(ConversationService.previewMediaPayload(payload), same(payload));
    expect(
      ConversationService.mediaPublicImageUrl(payload),
      'https://image.heunion.com/zdfiles/im/chat/meme.gif',
    );
  });

  test('still images keep using the jpeg preview', () {
    final payload = <String, dynamic>{
      'url': 'https://image.heunion.com/zdfiles/im/chat/photo.jpg',
      'objectKey': 'im/chat/photo.jpg',
      'previewUrl': 'https://image.heunion.com/zdfiles/im/chat/photo-preview.jpg',
      'previewObjectKey': 'im/chat/photo-preview.jpg',
      'fileName': 'photo.jpg',
      'mimeType': 'image/jpeg',
    };

    final preview = ConversationService.previewMediaPayload(payload);
    expect(preview?['objectKey'], 'im/chat/photo-preview.jpg');
    expect(
      ConversationService.mediaPublicImageUrl(payload),
      'https://image.heunion.com/zdfiles/im/chat/photo-preview.jpg',
    );
  });

  test('gif bytes are not flattened into a jpeg preview', () async {
    final preview = await buildChatImagePreview(
      Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0, 1]),
      fileName: 'meme.gif',
    );
    expect(preview, isNull);
  });

  test('gif stickers use a fixed box instead of the photo bubble', () {
    const photo = Size(200, 240);
    final cap = chatGifBubbleMaxSize(photo);
    expect(cap, kChatGifBubbleMaxSize);

    final meme = chatImageBubbleDisplaySize(
      480,
      320,
      maxWidth: cap.width,
      maxHeight: cap.height,
    );
    expect(meme.width, 120);
    expect(meme.height, 80);

    final small = chatImageBubbleDisplaySize(
      80,
      80,
      maxWidth: cap.width,
      maxHeight: cap.height,
    );
    expect(small, const Size(80, 80));

    final phone = chatGifBubbleMaxSize(const Size(100, 118));
    expect(phone, const Size(100, 118));
  });
}
