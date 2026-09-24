import 'dart:convert';
import 'dart:typed_data';

import 'travel_import_service.dart';

const travelExportSheets = ['机票', '酒店', '火车', '用车'];

String travelMatchLabel(String status) {
  switch (status) {
    case 'matched':
      return '已关联';
    case 'unmatched':
      return '未关联';
    case 'ambiguous':
      return '重名';
    default:
      return status;
  }
}

String _yuan(int fen) => (fen / 100).toStringAsFixed(2);

List<String> _commonTail(TravelOrderRow row) => [
  row.userDisplayName,
  row.deptName,
  row.sectorName,
  travelMatchLabel(row.matchStatus),
  _yuan(row.amountFen),
  _yuan(row.amountFenOrder),
  _yuan(row.rebookFeeFen),
  row.shared ? '是' : '否',
  row.companionNames,
  row.status,
];

const _commonHeaders = [
  '组织用户',
  '部门',
  '板块',
  '关联状态',
  '分摊金额',
  '订单金额',
  '改签费',
  '是否同行',
  '同行人',
  '订单状态',
];

List<List<String>> _sheetTable(String kind, List<TravelOrderRow> rows) {
  switch (kind) {
    case 'hotel':
      return [
        ['订单号', '入住人', '入住时间', '离店时间', '酒店名称', '所在城市', '所在省份', ..._commonHeaders],
        for (final row in rows)
          [
            row.orderId,
            row.travelerName,
            row.startAt,
            row.endAt,
            row.origin,
            row.destCity.isEmpty ? row.destination : row.destCity,
            row.destProvince.isEmpty ? row.originProvince : row.destProvince,
            ..._commonTail(row),
          ],
      ];
    case 'train':
      return [
        ['订单号', '出行人', '出发时间', '到达时间', '出发站', '到达站', '出发城市', '到达城市', '出发省份', '到达省份', ..._commonHeaders],
        for (final row in rows)
          [
            row.orderId,
            row.travelerName,
            row.startAt,
            row.endAt,
            row.origin,
            row.destination,
            row.originCity,
            row.destCity,
            row.originProvince,
            row.destProvince,
            ..._commonTail(row),
          ],
      ];
    case 'ground':
      return [
        ['订单号', '出行人', '开始时间', '结束时间', '上车地点', '下车地点', '用车城市', '省份', ..._commonHeaders],
        for (final row in rows)
          [
            row.orderId,
            row.travelerName,
            row.startAt,
            row.endAt,
            row.origin,
            row.destination,
            row.originCity.isEmpty ? row.destCity : row.originCity,
            row.originProvince,
            ..._commonTail(row),
          ],
      ];
    default:
      return [
        ['订单号', '票号', '出行人', '起飞时间', '到达时间', '出发地', '到达地', '出发城市', '到达城市', '出发省份', '到达省份', ..._commonHeaders],
        for (final row in rows)
          [
            row.orderId,
            row.ticketNo,
            row.travelerName,
            row.startAt,
            row.endAt,
            row.origin,
            row.destination,
            row.originCity,
            row.destCity,
            row.originProvince,
            row.destProvince,
            ..._commonTail(row),
          ],
      ];
  }
}

Uint8List buildTravelOrdersXlsx(List<TravelOrderRow> rows) {
  const kinds = ['flight', 'hotel', 'train', 'ground'];
  final tables = <String, List<List<String>>>{};
  for (var i = 0; i < kinds.length; i++) {
    tables[travelExportSheets[i]] = _sheetTable(
      kinds[i],
      [for (final row in rows) if (row.kind == kinds[i]) row],
    );
  }
  return _simpleXlsx(tables);
}

String _xml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

Uint8List _simpleXlsx(Map<String, List<List<String>>> sheets) {
  final shared = <String>[];
  final indexOf = <String, int>{};
  int add(String value) {
    return indexOf.putIfAbsent(value, () {
      shared.add(value);
      return shared.length - 1;
    });
  }

  final sheetXml = <String>[];
  for (final rows in sheets.values) {
    final indexed = <List<int>>[
      for (final row in rows) [for (final cell in row) add(cell)],
    ];
    final sheet = StringBuffer()
      ..write(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>',
      );
    for (var r = 0; r < indexed.length; r++) {
      sheet.write('<row r="${r + 1}">');
      for (var c = 0; c < indexed[r].length; c++) {
        sheet.write(
          '<c r="${_col(c)}${r + 1}" t="s"><v>${indexed[r][c]}</v></c>',
        );
      }
      sheet.write('</row>');
    }
    sheet.write('</sheetData></worksheet>');
    sheetXml.add(sheet.toString());
  }

  final sst = StringBuffer()
    ..write(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'count="${shared.length}" uniqueCount="${shared.length}">',
    );
  for (final item in shared) {
    sst.write('<si><t>${_xml(item)}</t></si>');
  }
  sst.write('</sst>');

  final names = sheets.keys.toList();
  final n = names.length;
  final overrides = StringBuffer();
  final rels = StringBuffer()
    ..write(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
    );
  final workbookSheets = StringBuffer();
  for (var i = 0; i < n; i++) {
    final id = i + 1;
    overrides.write(
      '<Override PartName="/xl/worksheets/sheet$id.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
    );
    rels.write(
      '<Relationship Id="rId$id" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$id.xml"/>',
    );
    workbookSheets.write(
      '<sheet name="${_xml(names[i])}" sheetId="$id" r:id="rId$id"/>',
    );
  }
  rels.write(
    '<Relationship Id="rId${n + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>',
  );
  rels.write('</Relationships>');

  final files = <String, String>{
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '$overrides'
        '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
        '</Types>',
    '_rels/.rels':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/_rels/workbook.xml.rels': rels.toString(),
    'xl/workbook.xml':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>$workbookSheets</sheets></workbook>',
    'xl/sharedStrings.xml': sst.toString(),
  };
  for (var i = 0; i < sheetXml.length; i++) {
    files['xl/worksheets/sheet${i + 1}.xml'] = sheetXml[i];
  }
  return _zipStore(files);
}

String _col(int index) {
  var n = index;
  final chars = <String>[];
  while (true) {
    chars.add(String.fromCharCode(65 + (n % 26)));
    n = n ~/ 26 - 1;
    if (n < 0) break;
  }
  return chars.reversed.join();
}

/// ZIP with the store method (no compression). Enough for a small xlsx.
Uint8List _zipStore(Map<String, String> files) {
  final local = BytesBuilder();
  final central = BytesBuilder();
  var offset = 0;
  for (final entry in files.entries) {
    final name = utf8.encode(entry.key);
    final data = utf8.encode(entry.value);
    final crc = _crc32(data);
    final localHeader = BytesBuilder()
      ..add(_u32(0x04034b50))
      ..add(_u16(20))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u32(crc))
      ..add(_u32(data.length))
      ..add(_u32(data.length))
      ..add(_u16(name.length))
      ..add(_u16(0))
      ..add(name);
    local.add(localHeader.toBytes());
    local.add(data);
    central
      ..add(_u32(0x02014b50))
      ..add(_u16(20))
      ..add(_u16(20))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u32(crc))
      ..add(_u32(data.length))
      ..add(_u32(data.length))
      ..add(_u16(name.length))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u32(0))
      ..add(_u32(offset))
      ..add(name);
    offset += localHeader.length + data.length;
  }
  final centralBytes = central.toBytes();
  final localBytes = local.toBytes();
  final end = BytesBuilder()
    ..add(_u32(0x06054b50))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u16(files.length))
    ..add(_u16(files.length))
    ..add(_u32(centralBytes.length))
    ..add(_u32(localBytes.length))
    ..add(_u16(0));
  return Uint8List.fromList([
    ...localBytes,
    ...centralBytes,
    ...end.toBytes(),
  ]);
}

Uint8List _u16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ 0xEDB88320;
      } else {
        crc >>= 1;
      }
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
