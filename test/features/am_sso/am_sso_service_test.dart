import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/am_sso/am_sso_service.dart';

void main() {
  test('AmSsoLoginUrl.fromJson keeps ticket URL intact', () {
    final login = AmSsoLoginUrl.fromJson({
      'url':
          'https://sel-prod.djien-qr.com/se-prod/sso/enter?ticket=abc',
      'expiresAt': '2026-09-04T01:05:00Z',
    });
    expect(
      login.url,
      'https://sel-prod.djien-qr.com/se-prod/sso/enter?ticket=abc',
    );
    expect(login.expiresAt, isNotNull);
  });

  test('WorkbenchSsoApp.fromJson reads key and title', () {
    final app = WorkbenchSsoApp.fromJson({
      'appKey': 'oa',
      'title': '资管1.0',
      'subtitle': '资金 · 账单 · 对账',
    });
    expect(app.appKey, 'oa');
    expect(app.title, '资管1.0');
    expect(app.subtitle, '资金 · 账单 · 对账');
  });

  test('amSsoTargetForUrl maps 资管对账页到免登 target', () {
    final tag2 = Uri.parse(
      'https://sel-prod.djien-qr.com/infoReport/cnpc-shucai-tag2-supplier',
    );
    final tag3 = Uri.parse(
      'https://sel-prod.djien-qr.com/infoReport/shucai-tag3-v2',
    );
    expect(isAmReconPageUrl(tag2), isTrue);
    expect(isAmReconPageUrl(tag3), isTrue);
    expect(amSsoTargetForUrl(tag2), kAmReconTag2Path);
    expect(amSsoTargetForUrl(tag3), kAmReconTag3Path);
    expect(
      amSsoTargetForUrl(Uri.parse('https://example.com/other')),
      isNull,
    );
  });
}
