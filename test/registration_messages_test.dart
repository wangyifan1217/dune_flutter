import 'package:dunes_app/features/auth/registration_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('localizeRegistrationMessage maps known English errors', () {
    expect(
      localizeRegistrationMessage('registration disabled'),
      '当前暂不开放注册',
    );
    expect(
      localizeRegistrationMessage('invalid sms code'),
      '验证码不正确或已过期',
    );
  });

  test('localizeRegistrationMessage keeps Chinese text unchanged', () {
    const cn = '该手机号为组织用户，请直接登录';
    expect(localizeRegistrationMessage(cn), cn);
  });

  test('localizeRegistrationMessage uses fallback for unknown English', () {
    expect(
      localizeRegistrationMessage('something unknown', fallback: '默认提示'),
      '默认提示',
    );
  });
}
