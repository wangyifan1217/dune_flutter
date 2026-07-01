import 'dart:typed_data';

/// objectKey → presigned / proxy URL，跨会话页复用，避免滚出再滚入重复请求。
final Map<String, Future<String>> chatMediaResolvedUrlCache =
    <String, Future<String>>{};

/// objectKey → 附件字节，供 URL 不可用或解码失败时回退。
final Map<String, Future<Uint8List>> chatMediaBytesCache =
    <String, Future<Uint8List>>{};

Future<String> cachedChatMediaUrl(
  String cacheKey,
  Future<String> Function() resolver,
) {
  final key = cacheKey.trim();
  if (key.isEmpty) return resolver();
  return chatMediaResolvedUrlCache.putIfAbsent(key, resolver);
}

Future<Uint8List> cachedChatMediaBytes(
  String cacheKey,
  Future<Uint8List> Function() loader,
) {
  final key = cacheKey.trim();
  if (key.isEmpty) return loader();
  return chatMediaBytesCache.putIfAbsent(key, loader);
}

void invalidateChatMediaCache({String? objectKey}) {
  final key = objectKey?.trim() ?? '';
  if (key.isEmpty) return;
  chatMediaResolvedUrlCache.remove(key);
  chatMediaBytesCache.remove(key);
}
