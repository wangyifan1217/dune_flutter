import 'dart:async';

/// 把任意异常转换为「面向用户的中文提示」，避免把英文/技术细节原样抛给用户。
///
/// 规则：
/// - 已包含中文（通常是后端 message / 业务异常）：原样返回；
/// - 常见网络 / 超时 / 解析类异常：映射为统一中文文案；
/// - 其余纯英文技术错误：返回 [fallback] 兜底，不暴露英文堆栈/类名。
///
/// 仅依赖 `dart:async`，可安全用于 Web 与移动端。
String friendlyErrorText(Object? error, {String fallback = '操作失败，请稍后重试'}) {
  if (error == null) return fallback;
  if (error is TimeoutException) return '请求超时，请稍后重试';

  var msg = error.toString().trim();
  for (final prefix in const ['Exception: ', 'Error: ', 'HttpException: ']) {
    if (msg.startsWith(prefix)) {
      msg = msg.substring(prefix.length).trim();
      break;
    }
  }
  if (msg.isEmpty) return fallback;

  // 含中文一般是后端可读提示或业务异常，直接展示。
  if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(msg)) return msg;

  final low = msg.toLowerCase();
  if (low.contains('failed host lookup') ||
      low.contains('network is unreachable') ||
      low.contains('connection refused') ||
      low.contains('connection closed') ||
      low.contains('connection reset') ||
      low.contains('connection error') ||
      low.contains('socketexception') ||
      low.contains('clientexception') ||
      low.contains('handshakeexception') ||
      low.contains('xmlhttprequest')) {
    return '网络连接失败，请检查网络后重试';
  }
  if (low.contains('timeout') || low.contains('timed out')) {
    return '请求超时，请稍后重试';
  }
  if (low.contains('formatexception')) {
    return '数据解析失败，请稍后重试';
  }
  // 其它纯英文技术错误统一兜底，不直接暴露给用户。
  return fallback;
}
