import 'dart:convert';
import 'dart:io';

import 'package:dunes_app/features/travel_import/travel_import_service.dart';
import 'package:dunes_app/features/travel_import/travel_order_xlsx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('travel export xlsx uses Chinese headers', () async {
    final bytes = buildTravelOrdersXlsx([
      const TravelOrderRow(
        id: 1,
        kind: 'flight',
        orderId: '113254',
        ticketNo: 'T1',
        travelerName: '郑咏熹',
        userDisplayName: '郑咏熹',
        deptName: '运营',
        sectorName: '运营中心',
        matchStatus: 'matched',
        startAt: '2026-09-24 16:55',
        endAt: '2026-09-24 19:10',
        origin: '长沙',
        destination: '常州',
        originCity: '长沙',
        destCity: '常州',
        originProvince: '湖南',
        destProvince: '江苏',
        amountFen: 90597,
        amountFenOrder: 90597,
        shared: false,
        status: '已出票',
      ),
    ]);
    final file = File('${Directory.systemTemp.path}/travel-export-test.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    final extracted = Directory('${Directory.systemTemp.path}/travel-export-test');
    if (extracted.existsSync()) extracted.deleteSync(recursive: true);
    final result = await Process.run('tar', ['-xf', file.path, '-C', Directory.systemTemp.path]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final workbook = File('${Directory.systemTemp.path}/xl/workbook.xml').readAsStringSync();
    final sst = File('${Directory.systemTemp.path}/xl/sharedStrings.xml').readAsStringSync();
    expect(workbook, contains('机票'));
    expect(workbook, contains('酒店'));
    expect(workbook, contains('火车'));
    expect(workbook, contains('用车'));
    expect(sst, contains('起飞时间'));
    expect(sst, contains('入住时间'));
    expect(sst, contains('郑咏熹'));
    await file.delete();
  });
}
