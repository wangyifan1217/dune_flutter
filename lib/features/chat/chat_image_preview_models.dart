import 'package:flutter/foundation.dart';

/// 图片预览图集中的一项（支持左右切换）。
class ChatImagePreviewItem {
  const ChatImagePreviewItem({
    required this.payload,
    required this.fileName,
    this.messageId,
    this.onLocateInChat,
  });

  final Map<String, dynamic>? payload;
  final String fileName;
  final int? messageId;
  final VoidCallback? onLocateInChat;
}
