import 'package:flutter/foundation.dart';

import '../auth/auth_session.dart';
import '../conversation/conversation_service.dart';

/// 不依赖聊天页面生命周期的文件上传任务。
///
/// 聊天页退出时会关闭其 [ConversationService]，因此不能由页面自身持有上传请求；
/// 该协调器为每个任务创建独立的 service，确保切换到通讯录后上传不中断。
class ChatFileUploadJob {
  ChatFileUploadJob({required this.conversationId, required this.fileName});

  final int conversationId;
  final String fileName;
  double progress = 0;
}

class ChatFileUploadCoordinator extends ChangeNotifier {
  ChatFileUploadCoordinator._();

  static final ChatFileUploadCoordinator instance =
      ChatFileUploadCoordinator._();

  final List<ChatFileUploadJob> _jobs = <ChatFileUploadJob>[];

  ChatFileUploadJob? jobForConversation(int conversationId) {
    for (final job in _jobs.reversed) {
      if (job.conversationId == conversationId) return job;
    }
    return null;
  }

  Future<void> sendFile({
    required AuthSession session,
    required int conversationId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final job = ChatFileUploadJob(
      conversationId: conversationId,
      fileName: fileName,
    );
    _jobs.add(job);
    notifyListeners();

    final service = ConversationService(session: session);
    try {
      await service.sendFile(
        conversationId: conversationId,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        onProgress: (progress) {
          job.progress = progress.clamp(0.0, 1.0);
          notifyListeners();
        },
      );
    } finally {
      service.close();
      _jobs.remove(job);
      notifyListeners();
    }
  }
}
