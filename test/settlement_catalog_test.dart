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
    expect(await catalog.fetchProductCategoryL2(), isEmpty);
    expect(await catalog.fetchProductCategoryL3(), isEmpty);
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

  test('bill type tree flattens to level-3 leaves only', () {
    final rows = flattenBillTypeTree([
      {
        'id': 1,
        'code': 'ar',
        'name': '应收账单',
        'level': 1,
        'children': [
          {
            'id': 2,
            'code': 'ar_XSK',
            'name': '销售款',
            'level': 2,
            'children': [
              {
                'id': 3,
                'code': 'SUBSIDY_RECEIVABLE',
                'name': '电子券补贴销售款',
                'level': 3,
                'children': const [],
              },
              {
                'id': 4,
                'code': 'CASH_RECEIVABLE',
                'name': '电子券现金销售款',
                'level': 3,
              },
            ],
          },
          {
            'id': 5,
            'code': 'service_ar',
            'name': '服务费',
            'level': 2,
            'children': const [],
          },
        ],
      },
    ]);
    expect(rows.map((e) => e.displayPath).toList(), [
      '应收账单 / 销售款 / 电子券补贴销售款',
      '应收账单 / 销售款 / 电子券现金销售款',
    ]);
    expect(rows.map((e) => e.code).toList(), [
      'SUBSIDY_RECEIVABLE',
      'CASH_RECEIVABLE',
    ]);
    expect(rows.every((e) => e.name.contains('服务费') == false), isTrue);
  });

  test('bill type tree without level still keeps unlabeled leaves', () {
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
    expect(rows.map((e) => e.displayPath).toList(), ['销售 / 电子券销售款']);
    expect(rows.single.code, 'XS_DZ');
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

  test('product L2 catalog keeps snowflake ids as text', () {
    final ref = CatalogRef.fromJson({
      'id': '2070042866993868805',
      'code': 'GGCX_CXXTHY',
      'name': '小套-出行会员',
      'level': 2,
      'parentId': '2070042866993868804',
      'parentCode': 'GGCX',
      'parentName': '公共出行',
    });
    expect(ref.idText, '2070042866993868805');
    expect(ref.parentIdText, '2070042866993868804');
    expect(ref.parentCode, 'GGCX');
    expect(ref.parentName, '公共出行');
    expect(ref.toJson()['id'], '2070042866993868805');
    expect(ref.toJson()['parentId'], '2070042866993868804');
  });

  test('fetchProductCategoryL2 maps 资管二级分类 rows', () async {
    Uri? seen;
    final client = MockClient((request) async {
      seen = request.url;
      return http.Response(
        jsonEncode({
          'code': 200,
          'msg': '操作成功',
          'data': [
            {
              'id': '2070042866993868805',
              'code': 'GGCX_CXXTHY',
              'name': '小套-出行会员',
              'level': 2,
              'parentId': '2070042866993868804',
              'parentCode': 'GGCX',
              'parentName': '公共出行',
            },
            {
              'id': '2070042866993868810',
              'code': 'YYS_Hcz',
              'name': '小套-好车主会员',
              'level': 2,
              'parentId': '2070042866947731400',
              'parentCode': 'YYS',
              'parentName': '运营商',
            },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final catalog = SettlementCatalogService(client: client);
    addTearDown(catalog.dispose);
    final rows = await catalog.fetchProductCategoryL2();
    expect(seen?.path, contains('/out/shaqiu/catalog/product-category/l2'));
    expect(seen?.queryParameters.containsKey('parentId'), isFalse);
    expect(rows.map((e) => e.name).toList(), ['小套-出行会员', '小套-好车主会员']);
    expect(rows.first.idText, '2070042866993868805');
    expect(rows.last.parentCode, 'YYS');
  });

  test('fetchProductCategoryL3 maps 资管三级分类 rows', () async {
    Uri? seen;
    final client = MockClient((request) async {
      seen = request.url;
      return http.Response(
        jsonEncode({
          'code': 200,
          'msg': '操作成功',
          'data': [
            {
              'id': 3,
              'code': 'NY_JYQ_A',
              'name': '细类A',
              'level': 3,
              'parentId': 2,
              'parentCode': 'NY_JYQ',
              'parentName': '加油券',
            },
            {
              'id': '2070042866993868999',
              'code': 'GGCX_CXXTHY_A',
              'name': '出行会员-细类',
              'level': 3,
              'parentId': '2070042866993868805',
              'parentCode': 'GGCX_CXXTHY',
              'parentName': '小套-出行会员',
            },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final catalog = SettlementCatalogService(client: client);
    addTearDown(catalog.dispose);
    final rows = await catalog.fetchProductCategoryL3();
    expect(seen?.path, contains('/out/shaqiu/catalog/product-category/l3'));
    expect(seen?.queryParameters.containsKey('parentId'), isFalse);
    expect(rows.map((e) => e.name).toList(), ['细类A', '出行会员-细类']);
    expect(rows.first.parentCode, 'NY_JYQ');
    expect(rows.last.idText, '2070042866993868999');
  });

  test('fetchProductCategoryL3 can filter by 标签一 parentCode', () async {
    Uri? seen;
    final client = MockClient((request) async {
      seen = request.url;
      return http.Response(
        jsonEncode({
          'code': 200,
          'msg': '操作成功',
          'data': [
            {
              'id': 3,
              'code': 'NY_JYQ_A',
              'name': '细类A',
              'level': 3,
              'parentCode': 'NY_JYQ',
              'parentName': '中石化普惠现金券',
            },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final catalog = SettlementCatalogService(client: client);
    addTearDown(catalog.dispose);
    final rows = await catalog.fetchProductCategoryL3(parentCode: 'NY_JYQ');
    expect(seen?.queryParameters['parentCode'], 'NY_JYQ');
    expect(rows.map((e) => e.name).toList(), ['细类A']);
  });

  test('子分类 options come from 资管 product L3 filtered by 标签一', () {
    const l3A = CatalogRef(
      idText: '31',
      code: 'NY_JYQ_A',
      name: '细类A',
      parentCode: 'NY_JYQ',
      parentName: '中石化普惠现金券',
    );
    const l3B = CatalogRef(
      idText: '32',
      code: 'GGCX_CXXTHY_A',
      name: '出行会员-细类',
      parentCode: 'GGCX_CXXTHY',
      parentIdText: '2070042866993868805',
      parentName: '小套-出行会员',
    );
    const catalog = [l3A, l3B];
    expect(
      proposalIntakeProductL3ForProduct(
        catalog,
        product: const CatalogRef(code: 'NY_JYQ', name: '加油券'),
      ).map((e) => e.name).toList(),
      ['细类A'],
    );
    expect(
      proposalIntakeProductL3ForProduct(
        catalog,
        product: const CatalogRef(
          name: '中石化普惠现金券（交易）',
        ),
      ).map((e) => e.name).toList(),
      ['细类A'],
    );
    expect(
      proposalIntakeProductL3ForProduct(
        catalog,
        product: const CatalogRef(
          idText: '2070042866993868805',
          name: '小套-出行会员',
        ),
      ).map((e) => e.name).toList(),
      ['出行会员-细类'],
    );
    expect(
      proposalIntakeProductL3ForProduct(catalog, product: CatalogRef.empty),
      isEmpty,
    );
  });

  test('标签一 options come from 资管 product L2 filtered by sector', () {
    const travel = CatalogRef(
      idText: '1',
      code: 'GGCX_CXXTHY',
      name: '小套-出行会员',
      parentCode: 'GGCX',
      parentName: '公共出行',
    );
    const owner = CatalogRef(
      idText: '2',
      code: 'YYS_Hcz',
      name: '小套-好车主会员',
      parentCode: 'YYS',
      parentIdText: '99',
      parentName: '运营商',
    );
    const energy = CatalogRef(
      idText: '3',
      code: 'NY_XJQ',
      name: '中石油现金券',
      parentCode: 'NY',
      parentName: '能源',
    );
    const catalog = [travel, owner, energy];
    expect(
      proposalIntakeProductL2ForSector(
        catalog,
        sector: const CatalogRef(code: 'YYS', name: '运营商'),
      ).map((e) => e.name).toList(),
      ['小套-好车主会员'],
    );
    expect(
      proposalIntakeProductL2ForSector(
        catalog,
        sector: const CatalogRef(name: '能源'),
      ).map((e) => e.name).toList(),
      ['中石油现金券'],
    );
    expect(
      proposalIntakeProductL2ForSector(
        const [
          CatalogRef(
            idText: '4',
            code: 'FT_FF',
            name: '中石油返费',
            parentCode: 'fintech',
            parentName: 'fintech',
          ),
        ],
        sector: const CatalogRef(name: 'Fintech'),
      ).map((e) => e.name).toList(),
      ['中石油返费'],
    );
    expect(
      proposalIntakeProductL2ForSector(catalog, sector: CatalogRef.empty),
      isEmpty,
    );
  });

  test('fetchProductCategoryL1 maps 资管一级分类 rows', () async {
    Uri? seen;
    final client = MockClient((request) async {
      seen = request.url;
      return http.Response(
        jsonEncode({
          'code': 200,
          'msg': '操作成功',
          'data': [
            {'id': '2066420509628776449', 'code': 'MY', 'name': '民营', 'level': 1},
            {'id': '2070042866947731458', 'code': 'NY', 'name': '能源', 'level': 1},
            {'id': '1', 'code': 'fintech', 'name': 'fintech', 'level': 1},
          ],
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final catalog = SettlementCatalogService(client: client);
    addTearDown(catalog.dispose);
    final rows = await catalog.fetchProductCategoryL1();
    expect(seen?.path, contains('/out/shaqiu/catalog/product-category/l1'));
    expect(rows.map((e) => e.name).toList(), ['民营', '能源', 'fintech']);
    expect(rows[1].code, 'NY');
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

  test('ChannelProductHit.fromJson reads title aliases', () {
    final hit = ChannelProductHit.fromJson({
      'id': 11,
      'code': 'SKU-11',
      'title': '中石化加油券',
      'channel': '江苏中石化',
    });
    expect(hit.productName, '中石化加油券');
    expect(hit.productCode, 'SKU-11');
    expect(hit.channelName, '江苏中石化');
    expect(hit.label, '中石化加油券');
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

  test('fetchChannelProductPacketItems maps parent and child settlements', () async {
    Uri? seen;
    final client = MockClient((request) async {
      seen = request.url;
      return http.Response(
        jsonEncode({
          'code': 200,
          'msg': '操作成功',
          'data': {
            'id': 2086081200000000295,
            'productCode': 'YYS_XTMXLD_001',
            'productName': '明星来电(黄圣依等组合包)',
            'channelId': 10001,
            'channelName': '广东移动',
            'syncSource': 'YD',
            'submitStatus': 'EFFECTIVE',
            'settlementItems': [
              {
                'billTypeL3Code': 'QB_SALES',
                'billTypeL3Name': '券包销售款',
                'settleMethod': 1,
                'formulaContent': 1,
                'settlementRatio': 100,
                'sortNo': 1,
              },
            ],
            'items': [
              {
                'itemProductId': 10,
                'itemExternalId': 88001,
                'itemSyncSource': 'DIGITALG',
                'num': 2,
                'productCode': 'CP001',
                'productName': '中石油100',
                'channelId': 1,
                'channelName': '银联商务',
                'syncSource': 'DIGITALG',
                'submitStatus': 'EFFECTIVE',
                'settlementItems': [
                  {
                    'billTypeL3Code': 'E_COUPON_SALES',
                    'billTypeL3Name': '电子券销售款',
                    'settleMethod': 1,
                    'settlementRatio': 98.5,
                    'taxRateCode': '13%',
                    'invoiceTypeCode': '专票',
                    'sortNo': 1,
                  },
                ],
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
    expect(await catalog.fetchChannelProductPacketItems(0), isNull);
    final data = await catalog.fetchChannelProductPacketItems(10);
    expect(
      seen?.path,
      contains('/out/shaqiu/catalog/channel-product/packet-items'),
    );
    expect(seen?.queryParameters['id'], '10');
    expect(data?.product.productName, '明星来电(黄圣依等组合包)');
    expect(data?.parent.items.single.billTypeL3Code, 'QB_SALES');
    expect(data?.items, hasLength(1));
    expect(data?.items.single.quantity, 2);
    expect(data?.items.single.itemProductId, 10);
    expect(data?.items.single.product.productName, '中石油100');
    expect(data?.items.single.settlementItems.single.taxRateCode, '13%');
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
