import 'dart:async';

import 'ai_summary_models.dart';

/// 本地广播总结状态（创建/重新生成时立刻刷新列表，不依赖 WS）。
class AiSummaryStatusBus {
  AiSummaryStatusBus._();

  static final AiSummaryStatusBus instance = AiSummaryStatusBus._();

  final StreamController<AiSummaryItem> _controller =
      StreamController<AiSummaryItem>.broadcast();

  Stream<AiSummaryItem> get stream => _controller.stream;

  void publish(AiSummaryItem item) {
    if (item.id <= 0) return;
    if (!_controller.isClosed) _controller.add(item);
  }
}
