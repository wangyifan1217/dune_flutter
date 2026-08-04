import 'package:flutter/foundation.dart';

import '../auth/auth_session.dart';
import '../conversation/conversation_service.dart';

/// 不依赖聊天页面生命周期的文件上传任务。
///
/// 聊天页退出时会关闭其 [ConversationService]，因此不能由页面自身持有上传请求；
/// 该协调器为每个任务创建独立的 service，确保切换到通讯录后上传不中断。
class ChatFileUploadJob {
  ChatFileUploadJob({
    required this.conversationId,
    required this.fileName,
    ChatUploadCancelToken? cancelToken,
  }) : cancelToken = cancelToken ?? ChatUploadCancelToken();

  final int conversationId;
  final String fileName;
  final ChatUploadCancelToken cancelToken;
  double progress = 0;
  ConversationService? _service;

  void bindService(ConversationService service) {
    _service = service;
  }

  void cancel() {
    cancelToken.cancel();
    final service = _service;
    _service = null;
    if (service != null) {
      try {
        service.close();
      } catch (_) {}
    }
  }
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

  /// 取消指定会话当前文件上传；返回是否命中任务。
  bool cancelForConversation(int conversationId) {
    final job = jobForConversation(conversationId);
    if (job == null) return false;
    job.cancel();
    return true;
  }

  Future<void> sendFile({
    required AuthSession session,
    required int conversationId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    ChatUploadCancelToken? cancelToken,
  }) async {
    final job = ChatFileUploadJob(
      conversationId: conversationId,
      fileName: fileName,
      cancelToken: cancelToken,
    );
    _jobs.add(job);
    notifyListeners();

    final service = ConversationService(session: session);
    job.bindService(service);
    try {
      job.cancelToken.throwIfCancelled();
      await service.sendFile(
        conversationId: conversationId,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        cancelToken: job.cancelToken,
        onProgress: (progress) {
          job.progress = progress.clamp(0.0, 1.0);
          notifyListeners();
        },
      );
    } on ChatUploadCancelledException {
      rethrow;
    } catch (e) {
      if (job.cancelToken.isCancelled) {
        throw const ChatUploadCancelledException();
      }
      rethrow;
    } finally {
      try {
        service.close();
      } catch (_) {}
      _jobs.remove(job);
      notifyListeners();
    }
  }
}
