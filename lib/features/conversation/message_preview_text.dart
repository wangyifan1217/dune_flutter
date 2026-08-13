/// 推送/会话列表用的消息摘要文案（与 im-go pushPreviewForMessage 对齐）。
String compactMessagePushPreview({
  required String kind,
  required String body,
}) {
  final trimmed = body.trim();
  final upperKind = kind.toUpperCase();

  if (upperKind == 'IMAGE' || _isImageLikeBody(trimmed)) {
    return '发送了一张图片';
  }
  if (upperKind == 'VIDEO' || trimmed.startsWith('[视频]')) {
    return '发送了一个视频';
  }
  if (upperKind == 'AUDIO' ||
      upperKind == 'VOICE' ||
      trimmed.startsWith('[语音]')) {
    return '发送了一条语音';
  }
  if (upperKind == 'FILE' || trimmed.startsWith('[文件]')) {
    return '发送了一个文件';
  }
  if (upperKind == 'WEEKLY_SUMMARY') {
    return trimmed.isEmpty ? '[一周小结]' : trimmed;
  }
  if (upperKind == 'RECONCILIATION' ||
      upperKind == 'RECONCILIATION_ASSISTANT') {
    return trimmed.isEmpty ? '每日对账 · 待你确认' : trimmed;
  }
  if (upperKind == 'RECONCILIATION_REMIND') {
    return trimmed.isEmpty ? '对账催办' : trimmed;
  }
  if (trimmed.isEmpty) {
    switch (upperKind) {
      case 'IMAGE':
        return '发送了一张图片';
      case 'VIDEO':
        return '发送了一个视频';
      case 'FILE':
        return '发送了一个文件';
      case 'AUDIO':
      case 'VOICE':
        return '发送了一条语音';
      default:
        return '您有新消息';
    }
  }
  return trimmed;
}

bool _isImageLikeBody(String text) {
  if (text.isEmpty) return false;
  final lower = text.toLowerCase();
  for (final prefix in ['[相册]', '[拍照]', '[图片]', '[gif]']) {
    if (lower.startsWith(prefix)) return true;
  }
  final name = _attachmentName(text);
  return RegExp(
    r'\.(png|jpe?g|gif|webp|bmp|heic|heif)$',
    caseSensitive: false,
  ).hasMatch(name);
}

String _attachmentName(String text) {
  final idx = text.indexOf(']');
  if (idx >= 0 && idx + 1 < text.length) {
    return text.substring(idx + 1).trim();
  }
  return text.trim();
}
