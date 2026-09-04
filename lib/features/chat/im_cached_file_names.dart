// IM 本地同名附件命名：能覆盖就覆盖；Excel 占用等写失败时改为 `文件名(1).xlsx`。

String safeChatFileName(String fileName) {
  final trimmed = fileName.trim();
  if (trimmed.isEmpty) return 'download';
  return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

String chatFileBasename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final i = normalized.lastIndexOf('/');
  return i >= 0 ? normalized.substring(i + 1) : normalized;
}

({String base, String ext}) splitChatFileName(String fileName) {
  final safe = safeChatFileName(fileName);
  final dot = safe.lastIndexOf('.');
  if (dot <= 0) return (base: safe, ext: '');
  return (base: safe.substring(0, dot), ext: safe.substring(dot));
}

/// 已存在则 `预算.xlsx` → `预算(1).xlsx` → `预算(2).xlsx`。
String uniqueChatFileName(
  String fileName,
  bool Function(String candidate) exists,
) {
  final safe = safeChatFileName(fileName);
  if (!exists(safe)) return safe;
  final parts = splitChatFileName(safe);
  var i = 1;
  while (true) {
    final candidate = '${parts.base}($i)${parts.ext}';
    if (!exists(candidate)) return candidate;
    i += 1;
    if (i > 9999) return '${parts.base}(${DateTime.now().millisecondsSinceEpoch})${parts.ext}';
  }
}

/// 为某条消息分配落盘文件名。同一 objectKey 复用上次名字，便于覆盖；
/// 已被其他消息占用的名字则改成 `(1)`。
String allocateCachedChatFileName({
  required String fileName,
  required String cacheKey,
  required Map<String, String> index,
  required bool Function(String basename) exists,
}) {
  final key = cacheKey.trim();
  if (key.isNotEmpty) {
    final mapped = (index[key] ?? '').trim();
    if (mapped.isNotEmpty) return mapped;
  }
  final safe = safeChatFileName(fileName);
  if (!exists(safe)) return safe;
  final owner = _ownerOf(index, safe);
  if (owner.isEmpty || owner == key) return safe;
  return uniqueChatFileName(fileName, exists);
}

String _ownerOf(Map<String, String> index, String basename) {
  for (final e in index.entries) {
    if (e.value == basename) return e.key;
  }
  return '';
}

bool savedChatFileRenamed(String originalFileName, String savedPath) {
  final saved = chatFileBasename(savedPath);
  return saved.isNotEmpty && saved != safeChatFileName(originalFileName);
}
