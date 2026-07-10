/// 将注册相关 API 返回的英文/技术文案转为 App 端中文提示。
String localizeRegistrationMessage(
  String? message, {
  String fallback = '操作失败，请稍后重试',
}) {
  final raw = message?.trim();
  if (raw == null || raw.isEmpty) return fallback;
  if (_containsCjk(raw)) return raw;

  final key = raw.toLowerCase();
  return _registrationMessageMap[key] ?? fallback;
}

bool _containsCjk(String value) {
  return RegExp(r'[\u4e00-\u9fff]').hasMatch(value);
}

const _registrationMessageMap = <String, String>{
  'registration disabled': '当前暂不开放注册',
  'registration not found': '未找到注册记录',
  'registration pending review': '注册申请审核中，请耐心等待',
  'registration rejected': '审核已驳回，请修改资料后重新提交',
  'invalid phone': '手机号格式不正确',
  'invalid code': '验证码格式不正确',
  'invalid sms code': '验证码不正确或已过期',
  'displayname required': '请输入昵称',
  'sms send failed': '验证码发送失败，请稍后重试',
  'user not found': '用户不存在',
  'missing bearer token': '注册服务暂不可用，请稍后重试或联系管理员',
};
