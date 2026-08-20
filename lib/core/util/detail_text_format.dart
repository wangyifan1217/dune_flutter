/// 详情长文：按句号、中文条款序号拆段，避免挤成一整块。
String formatDetailPlainText(String raw) {
  var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (text.isEmpty || text == '—') return text;

  text = text.replaceAllMapped(
    RegExp(r'。[ \t]*(?=[^”’」』）)\s\n])'),
    (m) => '。\n',
  );
  text = text.replaceAllMapped(
    RegExp(r'(?<=[^\n])([一二三四五六七八九十百]+、)'),
    (m) => '\n${m[1]}',
  );
  text = text.replaceAllMapped(
    RegExp(r'(?<=[^\n])(\d{1,2}、)'),
    (m) => '\n${m[1]}',
  );
  text = text.replaceAllMapped(
    RegExp(r'(?<=[^\n])([（(][一二三四五六七八九十百\d]{1,3}[）)])'),
    (m) => '\n${m[1]}',
  );
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

bool isLongDetailPlainText(String text) {
  if (text.isEmpty || text == '—') return false;
  return text.contains('\n') || text.length > 36;
}
