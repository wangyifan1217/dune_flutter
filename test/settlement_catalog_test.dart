import 'dart:convert';

import 'package:dunes_app/features/proposal_intake/settlement_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('offline catalog returns empty lists', () async {
    final catalog = SettlementCatalogService.offline();
    expect(await catalog.fetchSyncSources(), isEmpty);
    expect(await catalog.fetchProductCategoryL1(), isEmpty);
    expect(await catalog.fetchProjects(keyword: '星和'), isEmpty);
    expect(
      await catalog.fetchBillTypes(syncSource: 'YD', productSource: 'CHANNEL'),
      isEmpty,
    );
  });

  test('POINTS_REBATE rows stay distinct by name', () {
    const a = CatalogRef(code: 'POINTS_REBATE', name: '能源积分');
    const b = CatalogRef(code: 'POINTS_REBATE', name: '能源返费');
    expect(a.identity, isNot(b.identity));
    expect({a, b}, hasLength(2));
  });

  test('bill type tree flattens path for dropdown labels', () {
    final rows = flattenBillTypeTree([
      {
        'id': 1,
        'code': 'XS',
        'name': '销售',
        'children': [
          {
            'id': 2,
            'code': 'XS_DZ',
            'name': '电子券销售款',
            'children': const [],
          },
        ],
      },
    ]);
    expect(rows.map((e) => e.displayPath).toList(), [
      '销售',
      '销售 / 电子券销售款',
    ]);
    expect(rows.last.code, 'XS_DZ');
    expect(rows.last.id, 2);
  });

  test('channel json maps channelCode to CatalogRef.code', () {
    final ref = CatalogRef.fromChannel({
      'id': 1,
      'channelCode': 'C001',
      'channelName': '银联商务',
    });
    expect(ref.toJson(), {'id': 1, 'code': 'C001', 'name': '银联商务'});
  });

  test('channel json accepts string snowflake ids from asset catalog', () {
    final ref = CatalogRef.fromChannel({
      'id': '2070026713580023809',
      'channelCode': 'APP',
      'channelName': 'APP渠道',
      'syncSource': 'DIGITALG',
    });
    expect(ref.code, 'APP');
    expect(ref.name, 'APP渠道');
    expect(ref.id, 2070026713580023809);
    expect(ref.isEmpty, isFalse);
  });

  test('catalog ref keeps displayPath in json snapshot', () {
    const ref = CatalogRef(
      id: 2,
      code: 'ar_XSK_DZQXSK',
      name: '电子券销售款',
      displayPath: '应收账单 / 销售款 / 电子券销售款',
    );
    final roundtrip = CatalogRef.fromJson(ref.toJson());
    expect(roundtrip.displayPath, '应收账单 / 销售款 / 电子券销售款');
    expect(roundtrip.label, '应收账单 / 销售款 / 电子券销售款');
  });

  test('fetchChannels maps production channel payload without throwing', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'code': 200,
          'msg': '操作成功',
          'data': [
            {
              'id': '2070026713580023809',
              'channelCode': 'APP',
              'channelName': 'APP渠道',
              'channelShortName': 'APP渠道',
              'syncSource': 'DIGITALG',
              'status': '0',
            },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final catalog = SettlementCatalogService(client: client);
    addTearDown(catalog.dispose);
    final rows = await catalog.fetchChannels(syncSource: 'DIGITALG');
    expect(rows, hasLength(1));
    expect(rows.single.code, 'APP');
    expect(rows.single.name, 'APP渠道');
  });

  test('fetchChannelProducts maps keyword hits', () async {
    Uri? seen;
    final client = MockClient((request) async {
      seen = request.url;
      return http.Response(
        jsonEncode({
          'code': 200,
          'msg': '操作成功',
          'data': [
            {
              'id': 10,
              'productCode': 'CP001',
              'productName': '中石油100',
              'channelId': 1,
              'channelName': '银联商务',
              'syncSource': 'DIGITALG',
              'submitStatus': 'EFFECTIVE',
            },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final catalog = SettlementCatalogService(client: client);
    addTearDown(catalog.dispose);
    expect(
      await catalog.fetchChannelProducts(syncSource: '', keyword: '中石油'),
      isEmpty,
    );
    final rows = await catalog.fetchChannelProducts(
      syncSource: 'DIGITALG',
      keyword: '中石油',
    );
    expect(seen?.path, contains('/out/shaqiu/catalog/channel-product'));
    expect(seen?.queryParameters['syncSource'], 'DIGITALG');
    expect(seen?.queryParameters['keyword'], '中石油');
    expect(rows, hasLength(1));
    expect(rows.single.productName, '中石油100');
    expect(rows.single.channelRef?.name, '银联商务');
  });
}
