import 'package:dunes_app/features/reconciliation/reconciliation_shucai_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('withFilledGroupNames copies project onto following empty rows', () {
    final report = ShucaiReport(
      columns: [
        ShucaiColumn(field: 'groupName', label: '项目名称'),
        ShucaiColumn(field: 'detailName', label: '对方主体'),
      ],
      rows: [
        {
          'rowType': 'DETAIL',
          'groupKey': '平安石油',
          'groupName': '平安石油',
          'detailName': '广州亿力',
        },
        {
          'rowType': 'DETAIL',
          'groupKey': '平安石油',
          'groupName': '',
          'detailName': '北海星和',
        },
        {
          'rowType': 'DETAIL',
          'groupKey': '广州半山',
          'groupName': '广州半山',
          'detailName': '上海安壹通',
        },
      ],
    );
    final filled = report.withFilledGroupNames.rows;
    expect(filled[0]['groupName'], '平安石油');
    expect(filled[1]['groupName'], '平安石油');
    expect(filled[2]['groupName'], '广州半山');
  });

  test('withFilledGroupNames does not copy into grand total', () {
    final report = ShucaiReport(
      columns: [ShucaiColumn(field: 'groupName', label: '项目名称')],
      rows: [
        {'rowType': 'DETAIL', 'groupName': '平安石油'},
        {'rowType': 'TOTAL', 'rowKey': '__TOTAL__', 'groupName': '合计'},
      ],
    );
    final filled = report.withFilledGroupNames.rows;
    expect(filled[1]['groupName'], '合计');
  });

  test('shucaiRowKey prefers rowKey then fallback', () {
    expect(
      shucaiRowKey({'rowKey': 'abc', 'groupName': 'x'}, 3),
      'abc',
    );
    expect(
      shucaiRowKey({
        'groupName': '平安石油',
        'detailName': '广州亿力',
        'thirdName': '深圳万里通',
      }, 2),
      'idx:2|平安石油|广州亿力|深圳万里通',
    );
  });

  test('energy consecutive group blanks first column', () {
    final report = ShucaiReport(
      tab: 'energy',
      columns: [
        ShucaiColumn(field: 'groupName', label: '项目名称'),
        ShucaiColumn(field: 'detailName', label: '对方主体'),
      ],
      rows: [
        {
          'rowType': 'DETAIL',
          'groupKey': '平安石油',
          'groupName': '平安石油',
          'detailName': '广州亿力',
        },
        {
          'rowType': 'DETAIL',
          'groupKey': '平安石油',
          'groupName': '平安石油',
          'detailName': '北海星和',
        },
        {
          'rowType': 'DETAIL',
          'groupKey': '广州半山',
          'groupName': '广州半山',
          'detailName': '上海安壹通',
        },
      ],
    );
    expect(shucaiMergedBlank(report, 0, 0), isFalse);
    expect(shucaiMergedBlank(report, 1, 0), isTrue);
    expect(shucaiMergedBlank(report, 1, 1), isFalse);
    expect(shucaiMergedBlank(report, 2, 0), isFalse);
  });

  test('operator group total hides first column on detail rows', () {
    final report = ShucaiReport(
      tab: 'operator',
      columns: [
        ShucaiColumn(field: 'groupName', label: '运营商'),
        ShucaiColumn(field: 'detailName', label: '项目名称'),
        ShucaiColumn(field: 'monthPaid', label: '当月实收'),
        ShucaiColumn(field: 'monthReceivableDiff', label: '累计应收差额'),
      ],
      rows: [
        {
          'rowType': 'GROUP_TOTAL',
          'groupKey': '产险',
          'groupName': '产险',
          'detailName': '合计',
        },
        {
          'rowType': 'DETAIL',
          'groupKey': '产险',
          'groupName': '产险',
          'detailName': '湖南中石油',
        },
        {
          'rowType': 'GROUP_TOTAL',
          'groupKey': '出行订阅',
          'groupName': '出行订阅',
          'detailName': '合计',
        },
        {
          'rowType': 'DETAIL',
          'groupKey': '出行订阅',
          'groupName': '出行订阅',
          'detailName': '江苏',
        },
      ],
    );
    expect(shucaiMergedBlank(report, 0, 0), isFalse);
    expect(shucaiMergedBlank(report, 1, 0), isTrue);
    expect(shucaiMergedBlank(report, 1, 2), isFalse);
    expect(shucaiMergedBlank(report, 2, 2), isFalse);
    expect(shucaiMergedBlank(report, 3, 2), isTrue);
    expect(shucaiMergedBlank(report, 3, 3), isTrue);
  });

  test('tag2 never merges province column', () {
    final report = ShucaiReport(
      tab: 'tag2',
      columns: [
        ShucaiColumn(field: 'provinceName', label: '省份'),
        ShucaiColumn(field: 'prepayment', label: '期末预付款余额'),
      ],
      rows: [
        {'rowType': 'DETAIL', 'provinceName': '广东省', 'rowKey': '广东省'},
        {'rowType': 'TOTAL', 'provinceName': '合计', 'rowKey': '__TOTAL__'},
      ],
    );
    expect(shucaiMergedBlank(report, 0, 0), isFalse);
    expect(shucaiMergedBlank(report, 1, 0), isFalse);
  });
}
