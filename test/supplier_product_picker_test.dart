import 'dart:convert';

import 'package:dunes_app/features/proposal_intake/settlement_catalog.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:dunes_app/features/proposal_intake/supplier_product_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('copied product and serialized product keep original code order', () {
    const row = ProposalSkuDetailRow(id: 'original', supplierCodes: 'B|A|无');
    final copy = proposalIntakeCloneSkuProduct(
      row,
      id: 'copy',
      parentSkuId: '',
    );
    expect(copy.supplierCodes, 'B|A|无');
    expect(copy.toJson()['supplierCodes'], 'B|A|无');
  });
  test('search uses keyword and reads supplier product codes', () async {
    final requests = <Uri>[];
    final service = SettlementCatalogService(
      assetBase: 'https://example.test',
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'code': 200,
              'data': [
                {'productCode': 'SP-1', 'productName': '产品一'},
              ],
            }),
          ),
          200,
        );
      }),
    );
    expect(await service.searchSupplierProductCodes(' '), isEmpty);
    expect(requests, isEmpty);
    final hits = await service.searchSupplierProductCodes('产品');
    expect(hits.single.productCode, 'SP-1');
    expect(requests.single.path, '/out/shaqiu/catalog/supplier-product');
    expect(requests.single.queryParameters, {'keyword': '产品'});
  });

  test(
    'search reports service failure instead of returning an empty list',
    () async {
      final service = SettlementCatalogService(
        assetBase: 'https://example.test',
        client: MockClient((_) async => http.Response('{"code":500}', 200)),
      );
      await expectLater(
        service.searchSupplierProductCodes('测试'),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'searches only after input and preserves selection order and old values',
    (tester) async {
      final calls = <String>[];
      var value = 'OLD-1|OLD-2';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SupplierProductPickerField(
                value: value,
                onChanged: (v) => setState(() => value = v),
                search: (q) async {
                  calls.add(q);
                  return const [
                    ChannelProductHit(
                      productCode: 'NEW-1',
                      productName: '测试产品',
                    ),
                  ];
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('supplier-product-picker')));
      await tester.pumpAndSettle();
      expect(find.text('若找不到供应商产品，请联系业务侧添加。'), findsOneWidget);
      expect(calls, isEmpty);
      expect(find.text('OLD-1'), findsOneWidget);
      await tester.tap(find.text('无').last);
      await tester.enterText(
        find.byKey(const ValueKey('supplier-product-search')),
        '测试',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(calls, ['测试']);
      await tester.tap(
        find.byKey(const ValueKey('supplier-product-option-NEW-1')),
      );
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(value, 'OLD-1|OLD-2|无|NEW-1');
    },
  );

  testWidgets('picker fits a small phone with the keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupplierProductPickerField(
            value: 'ONE|TWO|THREE',
            onChanged: (_) {},
            search: (_) async => [],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('supplier-product-picker')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
