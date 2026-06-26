import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';

/// 聊天消息引用（微信式 reply），存于 message.payload.quote。
class ChatMessageQuote {
  const ChatMessageQuote({
    required this.messageId,
    required this.senderUserId,
    required this.senderName,
    required this.kind,
    required this.bodyText,
    required this.preview,
  });

  final int messageId;
  final int senderUserId;
  final String senderName;
  final String kind;
  final String bodyText;
  final String preview;

  factory ChatMessageQuote.fromMessage(NativeChatMessage message) {
    return ChatMessageQuote(
      messageId: message.id,
      senderUserId: message.senderUserId,
      senderName: message.senderName,
      kind: message.kind,
      bodyText: message.bodyText,
      preview: previewForMessage(message),
    );
  }

  factory ChatMessageQuote.fromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return const ChatMessageQuote.empty();
    final raw = payload['quote'] ?? payload['reply'];
    if (raw is! Map) return const ChatMessageQuote.empty();
    final map = Map<String, dynamic>.from(raw);
    final id = _int(map['messageId'] ?? map['id']);
    if (id <= 0) return const ChatMessageQuote.empty();
    final kind = (map['kind'] ?? 'TEXT').toString();
    final body = (map['bodyText'] ?? map['text'] ?? map['preview'] ?? '').toString();
    final preview = (map['preview'] ?? body).toString().trim();
    return ChatMessageQuote(
      messageId: id,
      senderUserId: _int(map['senderUserId'] ?? map['senderId']),
      senderName: (map['senderName'] ?? map['sender'] ?? '').toString(),
      kind: kind,
      bodyText: body,
      preview: preview.isEmpty ? previewForKind(kind, body, map) : preview,
    );
  }

  const ChatMessageQuote.empty()
      : messageId = 0,
        senderUserId = 0,
        senderName = '',
        kind = '',
        bodyText = '',
        preview = '';

  bool get isEmpty => messageId <= 0;

  Map<String, dynamic> toPayloadMap() {
    return <String, dynamic>{
      'messageId': messageId,
      'senderUserId': senderUserId,
      'senderName': senderName,
      'kind': kind,
      'bodyText': bodyText,
      'preview': preview,
    };
  }

  static String previewForMessage(NativeChatMessage message) {
    return previewForKind(
      message.kind,
      message.bodyText,
      message.payload,
    );
  }

  static String previewForKind(
    String kind,
    String bodyText, [
    Map<String, dynamic>? payload,
  ]) {
    final upper = kind.toUpperCase();
    switch (upper) {
      case 'IMAGE':
        return '[图片]';
      case 'AUDIO':
        final sec = (payload?['durationSec'] as num?)?.toInt();
        return sec != null && sec > 0 ? '[语音] ${sec}s' : '[语音]';
      case 'FILE':
        final name = ConversationService.mediaFileName(
          payload,
          fallback: bodyText.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '').trim(),
        );
        return name.isEmpty ? '[文件]' : '[文件] $name';
      default:
        final text = bodyText.trim();
        if (text.isEmpty) return '[消息]';
        return text.length > 80 ? '${text.substring(0, 80)}…' : text;
    }
  }

  static int _int(dynamic raw) {
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}
