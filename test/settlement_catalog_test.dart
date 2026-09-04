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
    expect(await catalog.fetchChannelCategoryL1(), isEmpty);
    expect(await catalog.fetchChannelCategoryL2(parentCode: 'YH'), isEmpty);
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

  test('fetchChannelCategoryL1 maps catalog rows', () async {
    Uri? seen;
    final client = MockClient((request) async {
      seen = request.url;
      return http.Response(
        jsonEncode({
          'code': 200,
          'msg': '操作成功',
          'data': [
            {'id': 11, 'code': 'YH', 'name': '银行', 'level': 1},
          ],
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final catalog = SettlementCatalogService(client: client);
    addTearDown(catalog.dispose);
    final rows = await catalog.fetchChannelCategoryL1();
    expect(seen?.path, contains('/out/shaqiu/catalog/channel-category/l1'));
    expect(rows, hasLength(1));
    expect(rows.single.code, 'YH');
    expect(rows.single.name, '银行');
    expect(rows.single.id, 11);
  });

  test('fetchChannelCategoryL2 filters by parentCode and keeps parent fields', () async {
    Uri? seen;
    final client = MockClient((request) async {
      seen = request.url;
      return http.Response(
        jsonEncode({
          'code': 200,
          'msg': '操作成功',
          'data': [
            {
              'id': 12,
              'code': 'YH_YL',
              'name': '银联',
              'level': 2,
              'parentId': 11,
              'parentCode': 'YH',
              'parentName': '银行',
            },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final catalog = SettlementCatalogService(client: client);
    addTearDown(catalog.dispose);
    final rows = await catalog.fetchChannelCategoryL2(parentCode: 'YH');
    expect(seen?.path, contains('/out/shaqiu/catalog/channel-category/l2'));
    expect(seen?.queryParameters['parentCode'], 'YH');
    expect(rows, hasLength(1));
    expect(rows.single.code, 'YH_YL');
    expect(rows.single.parentCode, 'YH');
    expect(rows.single.parentId, 11);
    expect(rows.single.parentName, '银行');
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

  test('fetchChannelProductSettlement maps settlement rows', () async {
    Uri? seen;
    final client = MockClient((request) async {
      seen = request.url;
      return http.Response(
        jsonEncode({
          'code': 200,
          'msg': '操作成功',
          'data': {
            'id': 10,
            'productCode': 'CP001',
            'productName': '中石油100',
            'channelId': 1,
            'channelName': '银联商务',
            'syncSource': 'DIGITALG',
            'submitStatus': 'EFFECTIVE',
            'settlementItems': [
              {
                'billTypeL1Code': 'AR',
                'billTypeL1Name': '应收账单',
                'billTypeL2Code': 'SALES',
                'billTypeL2Name': '销售款',
                'billTypeL3Code': 'E_COUPON_SALES',
                'billTypeL3Name': '电子券销售款',
                'settleMethod': 1,
                'formulaContent': 1,
                'settlementRatio': 98.5,
                'unitPrice': null,
                'invoiceTypeCode': '专票',
                'invoiceTypeName': '专票',
                'taxRateCode': '13%',
                'taxRateName': '13%',
                'ourEntity': '荷叶',
                'counterpartyEntity': '某某渠道',
                'effectiveTime': '2026-09-01 00:00:00',
                'expireTime': null,
                'sortNo': 1,
              },
            ],
          },
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final catalog = SettlementCatalogService(client: client);
    addTearDown(catalog.dispose);
    expect(await catalog.fetchChannelProductSettlement(0), isNull);
    final data = await catalog.fetchChannelProductSettlement(10);
    expect(seen?.path, contains('/out/shaqiu/catalog/channel-product/settlement'));
    expect(seen?.queryParameters['id'], '10');
    expect(data?.product.productName, '中石油100');
    expect(data?.items, hasLength(1));
    expect(data?.items.single.settleMethod, 1);
    expect(data?.items.single.billTypeRef?.displayPath, '应收账单 / 销售款 / 电子券销售款');
  });

  test('missing settlement payload returns null', () async {
    final catalog = SettlementCatalogService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({'code': 200, 'msg': '操作成功', 'data': null}),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(catalog.dispose);
    expect(await catalog.fetchChannelProductSettlement(10), isNull);
  });

  test('supplier json maps supplierCode to CatalogRef.code', () {
    final ref = CatalogRef.fromSupplier({
      'id': 8,
      'supplierCode': 'S001',
      'supplierName': '中石油',
      'shortName': '石油',
      'entityKind': 'SUPPLIER',
    });
    expect(ref.toJson(), {'id': 8, 'code': 'S001', 'name': '中石油'});
  });

  test('fetchSuppliers sends entityKind=SUPPLIER', () async {
    Uri? seen;
    final client = MockClient((request) async {
      seen = request.url;
      return http.Response(
        jsonEncode({
          'code': 200,
          'msg': '操作成功',
          'data': [
            {
              'id': 1,
              'supplierCode': 'S001',
              'supplierName': '中石油',
              'shortName': '石油',
              'syncSource': 'DIGITALG',
              'status': '0',
              'entityKind': 'SUPPLIER',
            },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final catalog = SettlementCatalogService(client: client);
    addTearDown(catalog.dispose);
    final rows = await catalog.fetchSuppliers(
      syncSource: 'DIGITALG',
      keyword: '中石油',
    );
    expect(seen?.path, contains('/out/shaqiu/catalog/supplier'));
    expect(seen?.queryParameters['syncSource'], 'DIGITALG');
    expect(seen?.queryParameters['keyword'], '中石油');
    expect(seen?.queryParameters['entityKind'], 'SUPPLIER');
    expect(rows, hasLength(1));
    expect(rows.single.code, 'S001');
    expect(rows.single.name, '中石油');
  });

  test('fetchSupplierProducts maps keyword hits', () async {
    Uri? seen;
    final client = MockClient((request) async {
      seen = request.url;
      return http.Response(
        jsonEncode({
          'code': 200,
          'msg': '操作成功',
          'data': [
            {
              'id': 20,
              'productCode': 'SP001',
              'productName': '中石油供给100',
              'supplierId': 8,
              'supplierCode': 'SUP-1',
              'supplierName': '中石油',
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
      await catalog.fetchSupplierProducts(syncSource: '', keyword: '中石油'),
      isEmpty,
    );
    final rows = await catalog.fetchSupplierProducts(
      syncSource: 'DIGITALG',
      keyword: '中石油',
    );
    expect(seen?.path, contains('/out/shaqiu/catalog/supplier-product'));
    expect(seen?.queryParameters['syncSource'], 'DIGITALG');
    expect(seen?.queryParameters['keyword'], '中石油');
    expect(rows, hasLength(1));
    expect(rows.single.productName, '中石油供给100');
    expect(rows.single.supplierRef?.code, 'SUP-1');
    expect(rows.single.supplierRef?.name, '中石油');
  });

  test('fetchSupplierProductSettlement maps settlement rows', () async {
    Uri? seen;
    final client = MockClient((request) async {
      seen = request.url;
      return http.Response(
        jsonEncode({
          'code': 200,
          'msg': '操作成功',
          'data': {
            'id': 20,
            'productCode': 'SP001',
            'productName': '中石油供给100',
            'supplierId': 8,
            'supplierName': '中石油',
            'syncSource': 'DIGITALG',
            'settlementItems': [
              {
                'billTypeL1Code': 'AP',
                'billTypeL1Name': '应付账单',
                'billTypeL2Code': 'PURCHASE',
                'billTypeL2Name': '采购款',
                'billTypeL3Code': 'E_COUPON_PURCHASE',
                'billTypeL3Name': '电子券采购款',
                'settleMethod': 1,
                'formulaContent': 1,
                'settlementRatio': 97,
                'invoiceTypeCode': '专票',
                'taxRateCode': '13%',
                'sortNo': 1,
              },
            ],
          },
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final catalog = SettlementCatalogService(client: client);
    addTearDown(catalog.dispose);
    final data = await catalog.fetchSupplierProductSettlement(20);
    expect(
      seen?.path,
      contains('/out/shaqiu/catalog/supplier-product/settlement'),
    );
    expect(seen?.queryParameters['id'], '20');
    expect(data?.product.productName, '中石油供给100');
    expect(data?.product.supplierRef?.name, '中石油');
    expect(data?.items, hasLength(1));
    expect(data?.items.single.billTypeRef?.displayPath, '应付账单 / 采购款 / 电子券采购款');
  });
}
