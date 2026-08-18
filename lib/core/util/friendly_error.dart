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
  if (low.contains('transcribe job') ||
      low.contains('transcribe-file') ||
      low.contains('transcript not ready') ||
      low.contains('meeting has no transcript')) {
    return '转写任务失败或尚未完成，请稍后重试';
  }
  if (low.contains('会议纪要服务未更新') ||
      low.contains('无法存草稿') ||
      low.contains('服务端未支持存草稿') ||
      low.contains('未支持存草稿')) {
    return '暂不能保存草稿，请联系管理员更新会议纪要服务';
  }
  if (low.contains('draft-audio') ||
      low.contains('not in draft') ||
      low.contains('audio file not found') ||
      low.contains('未支持存草稿') ||
      low.contains('服务端未支持存草稿')) {
    return '草稿保存失败，请检查网络后重试';
  }
  if (low.contains('pending approval not found')) {
    return '暂无可撤回的审批流，请稍后重试或刷新页面';
  }
  if (low.contains('only creator can delete draft') ||
      low.contains('only creator can delete')) {
    return '仅创建人可删除草稿';
  }
  if (low.contains('only draft can be deleted')) {
    return '仅草稿状态可删除';
  }
  if (low.contains('xflow submission not found') ||
      low.contains('submission not found')) {
    return '未找到该审批单，请刷新后重试';
  }
  if (low.contains('only creator can void') ||
      low.contains('only creator can resubmit')) {
    return '仅提交人可作废或重新提交';
  }
  if (low.contains('only rejected proposal can be voided') ||
      low.contains('only rejected submission can be voided') ||
      low.contains('proposal not rejected') ||
      low.contains('submission not rejected')) {
    return '仅已驳回的单据可作废';
  }
  if (low.contains('proposal already closed') ||
      low.contains('proposal voided') ||
      low.contains('submission already closed') ||
      low.contains('submission voided')) {
    return '该单据已关闭，无法作废';
  }
  if (low.contains('only creator can withdraw') ||
      low.contains('only approval initiator can withdraw')) {
    return '仅发起人可撤回';
  }
  if (low.contains('cannot be withdrawn after review')) {
    return '审批已开始处理，无法撤回';
  }
  if (low.contains('only pending') && low.contains('withdraw')) {
    return '仅审批中的单据可撤回';
  }
  if (low.contains('template has no') ||
      low.contains('no human approval steps')) {
    return '审批流程未配置完整，请联系管理员';
  }
  if (low.contains('move is limited to the same space')) {
    return '移动仅限同一空间，跨空间请使用复制';
  }
  if (low.contains('value too long') ||
      low.contains('character varying') ||
      low.contains('varchar')) {
    return '该文档尚未同步到本地存储，请稍后重试或下拉刷新';
  }
  if (low.contains('invalid cardtype') ||
      low.contains('invalid card type')) {
    return '对账板块无效，请从工作台重新进入';
  }
  return fallback;
}
