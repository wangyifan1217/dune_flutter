import 'package:flutter/foundation.dart';

/// 知识库文档增删后通知其它页面刷新（如会议纪要上传状态）。
class KbDocumentCoordinator extends ChangeNotifier {
  KbDocumentCoordinator._();

  static final KbDocumentCoordinator instance = KbDocumentCoordinator._();

  void notifyChanged() => notifyListeners();
}
