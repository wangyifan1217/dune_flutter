import 'package:flutter_test/flutter_test.dart';

/// 与后端 parseInviteCodeFromPayload 对齐的轻量解析（供扫码页本地兜底理解）。
String parseInviteCode(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  final upper = text.toUpperCase();
  if (upper.startsWith('DUNES_INVITE:')) {
    return text.substring('DUNES_INVITE:'.length).trim();
  }
  final codeIdx = text.indexOf('code=');
  if (codeIdx >= 0) {
    var code = text.substring(codeIdx + 5);
    final cut = code.indexOf(RegExp(r'[&?#]'));
    if (cut >= 0) code = code.substring(0, cut);
    return code.trim();
  }
  if (RegExp(r'^[0-9A-Za-z]{8,32}$').hasMatch(text)) return text;
  return '';
}

void main() {
  test('parse invite payload formats', () {
    expect(parseInviteCode('dunes://invite?code=ABCDEF12'), 'ABCDEF12');
    expect(parseInviteCode('DUNES_INVITE:ABCDEF12'), 'ABCDEF12');
    expect(parseInviteCode('ABCDEF12'), 'ABCDEF12');
    expect(parseInviteCode(''), '');
  });
}
