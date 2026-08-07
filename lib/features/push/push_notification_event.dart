import 'dart:convert';

/// A push notification click delivered by the native push provider.
///
/// The event keeps the provider payload intact while exposing the IM routing
/// fields that are safe for the Flutter layer to consume.  Non-IM pushes are
/// still delivered to the same handler, but [isConversation] is false so the
/// conversation host can leave them on their existing route.
class PushNotificationClick {
  const PushNotificationClick({
    required this.messageId,
    required this.title,
    required this.body,
    required this.customContent,
    required this.eventType,
    required this.conversationId,
  });

  final int messageId;
  final String title;
  final String body;
  final String customContent;
  final String eventType;
  final int conversationId;

  bool get isConversation => eventType.toLowerCase() == 'im' && conversationId > 0;

  static PushNotificationClick? fromMethodArguments(Object? arguments) {
    if (arguments is! Map) return null;
    final raw = <Object?, Object?>{}..addAll(arguments);
    final customContent = raw['customContent']?.toString().trim() ?? '';
    Map<String, dynamic> custom = const <String, dynamic>{};
    if (customContent.isNotEmpty) {
      try {
        final decoded = jsonDecode(customContent);
        if (decoded is Map) {
          custom = decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      } catch (_) {
        // A malformed/non-JSON custom payload is not an IM routing event.
      }
    }
    return PushNotificationClick(
      messageId: _toInt(raw['messageId']),
      title: raw['title']?.toString() ?? '',
      body: raw['body']?.toString() ?? '',
      customContent: customContent,
      eventType: custom['eventType']?.toString().trim() ?? '',
      conversationId: _toInt(custom['conversationId']),
    );
  }

  static int _toInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '') ?? 0;
  }
}
