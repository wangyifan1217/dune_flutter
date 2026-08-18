/// 资管对账 Markdown：标题 + GFM 表。行序与 list 的 rows 一致。
class ReconGfmTable {
  const ReconGfmTable({
    this.title = '',
    required this.headers,
    required this.rows,
  });

  final String title;
  final List<String> headers;
  final List<List<String>> rows;

  bool get isEmpty => headers.isEmpty && rows.isEmpty;
}

ReconGfmTable? parseReconGfmTable(String markdown) {
  final tables = parseReconGfmTables(markdown);
  if (tables.isEmpty) return null;
  return tables.first;
}

List<ReconGfmTable> parseReconGfmTables(String markdown) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final out = <ReconGfmTable>[];
  var title = '';
  List<String>? headers;
  var seenSep = false;
  var rows = <List<String>>[];

  void flush() {
    if (headers == null || headers!.isEmpty) {
      title = '';
      headers = null;
      seenSep = false;
      rows = [];
      return;
    }
    out.add(
      ReconGfmTable(title: title, headers: headers!, rows: rows),
    );
    title = '';
    headers = null;
    seenSep = false;
    rows = [];
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    final trimmed = line.trim();
    if (trimmed.startsWith('#')) {
      if (headers != null) flush();
      title = trimmed.replaceFirst(RegExp(r'^#+\s*'), '').trim();
      continue;
    }
    if (!_looksLikeTableRow(trimmed)) {
      if (headers != null && trimmed.isEmpty) flush();
      continue;
    }
    if (_isSeparatorRow(trimmed)) {
      seenSep = true;
      continue;
    }
    final cells = _splitCells(trimmed);
    if (headers == null) {
      headers = cells;
      seenSep = false;
      continue;
    }
    if (!seenSep) {
      headers = cells;
      continue;
    }
    rows.add(_padCells(cells, headers!.length));
  }
  flush();
  return out;
}

bool _looksLikeTableRow(String line) {
  if (line.isEmpty) return false;
  return line.contains('|');
}

bool _isSeparatorRow(String line) {
  final compact = line.replaceAll(' ', '').replaceAll('\t', '');
  return RegExp(r'^\|?(:?-+:?\|)+(:?-+:?)?\|?$').hasMatch(compact);
}

List<String> _splitCells(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|')) s = s.substring(0, s.length - 1);
  return s.split('|').map((e) => e.trim()).toList();
}

List<String> _padCells(List<String> cells, int width) {
  if (cells.length == width) return cells;
  if (cells.length > width) return cells.sublist(0, width);
  return [...cells, for (var i = cells.length; i < width; i++) ''];
}
