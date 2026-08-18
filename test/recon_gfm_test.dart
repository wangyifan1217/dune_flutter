import 'package:dunes_app/features/reconciliation/recon_gfm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseReconGfmTable reads title header separator and data', () {
    const md = '''
## 标签二-中石油

| 省份 | 金额 |
| --- | ---: |
| 天津 | 1,234.00 |
| 山西 |  |
| 合计 | 1,234.00 |
''';
    final table = parseReconGfmTable(md);
    expect(table, isNotNull);
    expect(table!.title, '标签二-中石油');
    expect(table.headers, ['省份', '金额']);
    expect(table.rows.length, 3);
    expect(table.rows[0], ['天津', '1,234.00']);
    expect(table.rows[1], ['山西', '']);
    expect(table.rows[2], ['合计', '1,234.00']);
  });

  test('parseReconGfmTable keeps empty merge cells', () {
    const md = '''
| 集团 | 明细 | 金额 |
| --- | --- | --- |
| 产险 | 湖南中石油 | 系统 1 / 人工 2 / 合计 3 |
|  | 广东中石油 | 系统 4 / 人工 5 / 合计 9 |
''';
    final table = parseReconGfmTable(md)!;
    expect(table.rows[0][0], '产险');
    expect(table.rows[1][0], '');
    expect(table.rows[1][1], '广东中石油');
  });

  test('parseReconGfmTables splits multiple tables', () {
    const md = '''
## 能源

| 名称 | 金额 |
| --- | --- |
| A | 1 |

## 民营

| 名称 | 金额 |
| --- | --- |
| B | 2 |
''';
    final tables = parseReconGfmTables(md);
    expect(tables.length, 2);
    expect(tables[0].title, '能源');
    expect(tables[0].rows[0][0], 'A');
    expect(tables[1].title, '民营');
    expect(tables[1].rows[0][0], 'B');
  });

  test('parseReconGfmTable returns null for empty markdown', () {
    expect(parseReconGfmTable(''), isNull);
    expect(parseReconGfmTable('没有表格'), isNull);
  });
}
