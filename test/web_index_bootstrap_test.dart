import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web/index.html starts Flutter even if pdf.js CDN is unreachable', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html.contains("import('./flutter_bootstrap.js')"), isTrue);
    expect(
      RegExp(
        r"import\s+\*\s+as\s+pdfjsLib\s+from\s+'https://cdn\.jsdelivr",
      ).hasMatch(html),
      isFalse,
      reason: '静态 import jsDelivr 会在 CDN/代理失败时整页白屏',
    );
  });
}
