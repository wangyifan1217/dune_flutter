import 'package:flutter/material.dart';

/// 按 URL 缓存网络头像，URL 未变时不重复触发加载动画。
class CachedDunesNetworkImage extends StatelessWidget {
  const CachedDunesNetworkImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  final String url;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final Widget Function()? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      url,
      key: ValueKey<String>(url),
      width: width,
      height: height,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) =>
          errorBuilder?.call() ?? const SizedBox.shrink(),
    );
    if (borderRadius == null) return image;
    return ClipRRect(borderRadius: borderRadius!, child: image);
  }
}

/// objectKey → 解析后的头像 URL 内存缓存。
final Map<String, String> dunesAvatarResolvedUrlCache = <String, String>{};

Future<String> resolveCachedAvatarUrl(
  Future<String> Function() resolver,
  String cacheKey,
) {
  final cached = dunesAvatarResolvedUrlCache[cacheKey];
  if (cached != null && cached.isNotEmpty) {
    return Future<String>.value(cached);
  }
  return resolver().then((url) {
    if (url.isNotEmpty) {
      dunesAvatarResolvedUrlCache[cacheKey] = url;
    }
    return url;
  });
}

void invalidateAvatarUrlCache({String? objectKey, String? url}) {
  if (objectKey != null && objectKey.isNotEmpty) {
    dunesAvatarResolvedUrlCache.remove(objectKey);
  }
  if (url != null && url.isNotEmpty) {
    dunesAvatarResolvedUrlCache.removeWhere((_, value) => value == url);
  }
}

/// 用户资料头像签名，用于判断 avatar 是否需要重新解析 URL。
String avatarSourceSignature({
  String preset = '',
  String objectKey = '',
  String directUrl = '',
}) {
  return '${preset.trim()}|${objectKey.trim()}|${directUrl.trim()}';
}

/// 「我的」页资料缓存（按 userId），切换 Tab 后仍保留头像 URL，避免重复加载闪烁。
class CachedMyPageProfile {
  const CachedMyPageProfile({
    required this.displayName,
    required this.phone,
    required this.departmentName,
    required this.title,
    required this.avatarPreset,
    required this.avatarObjectKey,
    required this.avatarUrl,
    required this.signature,
  });

  final String displayName;
  final String phone;
  final String departmentName;
  final String title;
  final String avatarPreset;
  final String avatarObjectKey;
  final String avatarUrl;
  final String signature;
}

final Map<int, CachedMyPageProfile> _myPageProfileByUser =
    <int, CachedMyPageProfile>{};

CachedMyPageProfile? getCachedMyPageProfile(int userId) {
  return _myPageProfileByUser[userId];
}

void cacheMyPageProfile(int userId, CachedMyPageProfile profile) {
  _myPageProfileByUser[userId] = profile;
  if (profile.avatarUrl.isNotEmpty) {
    dunesAvatarResolvedUrlCache[profile.signature] = profile.avatarUrl;
  }
}

void invalidateMyPageProfile(int userId) {
  final prev = _myPageProfileByUser.remove(userId);
  if (prev != null) {
    invalidateAvatarUrlCache(
      objectKey: prev.avatarObjectKey,
      url: prev.avatarUrl,
    );
  }
}

String? cachedMyPageAvatarUrl(int userId, String signature) {
  final cached = _myPageProfileByUser[userId];
  if (cached != null && cached.signature == signature && cached.avatarUrl.isNotEmpty) {
    return cached.avatarUrl;
  }
  return dunesAvatarResolvedUrlCache[signature];
}
