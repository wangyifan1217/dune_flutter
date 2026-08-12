import '../auth/auth_session.dart';
import 'chat_image_preview_models.dart';

bool isDesktopImagePreviewWindowArgs(List<String> args) => false;

Future<bool> isDesktopImagePreviewEngine() async => false;

Future<void> warmDesktopChatImagePreviewWindow() async {}

Future<void> openDesktopChatImagePreviewWindow({
  required AuthSession session,
  required List<ChatImagePreviewItem> items,
  int initialIndex = 0,
  int? conversationId,
}) async {}

Future<void> runDesktopImagePreviewWindow([List<String>? args]) async {}
