/// flow-go `/storage/multipart/*` 规划：分片大小与后端 `partSize` 一致（S3 最小 5MB）。
abstract final class MeetingStorageMultipart {
  static const int defaultPartSize = 5 * 1024 * 1024;

  static bool shouldUse(int fileSize, {int partSize = defaultPartSize}) {
    return fileSize > partSize;
  }

  static bool isUnsupported(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('does not support multipart') ||
        text.contains('ftp mode');
  }

  static List<MeetingStoragePartPlan> planParts(
    int fileSize, {
    int partSize = defaultPartSize,
  }) {
    if (fileSize <= 0) return const [];
    final size = partSize <= 0 ? defaultPartSize : partSize;
    final parts = <MeetingStoragePartPlan>[];
    var offset = 0;
    var number = 1;
    while (offset < fileSize) {
      final remaining = fileSize - offset;
      final length = remaining > size ? size : remaining;
      parts.add(
        MeetingStoragePartPlan(
          partNumber: number,
          offset: offset,
          length: length,
        ),
      );
      offset += length;
      number++;
    }
    return parts;
  }

  static String? etagFromHeaders(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'etag') {
        return normalizeEtag(entry.value);
      }
    }
    return null;
  }

  static String normalizeEtag(String raw) {
    var value = raw.trim();
    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
      value = value.substring(1, value.length - 1);
    }
    return value.trim();
  }
}

class MeetingStoragePartPlan {
  const MeetingStoragePartPlan({
    required this.partNumber,
    required this.offset,
    required this.length,
  });

  final int partNumber;
  final int offset;
  final int length;
}
