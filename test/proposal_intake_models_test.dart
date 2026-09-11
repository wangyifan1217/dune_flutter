import 'package:dunes_app/features/proposal_intake/proposal_cost_estimate.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:dunes_app/features/proposal_intake/settlement_catalog.dart';
import 'package:dunes_app/features/xflow/approval_chat_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('list library stats parse total week month and sectors', () {
    final result = ProposalIntakeListResult.fromJson({
      'items': [],
      'total': 2,
      'stats': {
        'total': 128,
        'day': 2,
        'week': 6,
        'month': 22,
        'sectors': [
          {'name': '能源', 'count': 10},
          {'name': '未填写', 'count': 2},
        ],
      },
    });
    expect(result.total, 2);
    expect(result.stats.total, 128);
    expect(result.stats.day, 2);
    expect(result.stats.week, 6);
    expect(result.stats.month, 22);
    expect(kProposalIntakePeriodFilters.map((item) => item.$1).toList(), [
      '',
      'day',
      'week',
      'month',
    ]);
    expect(kProposalIntakePeriodFilters.map((item) => item.$2).toList(), [
      '库内提案',
      '本日提案',
      '本周提案',
      '本月提案',
    ]);
    expect(ProposalIntakeListResult.fromJson({'items': []}).stats.total, 0);
    final chips = proposalIntakeSectorCountRows(
      catalog: const ['能源', 'Fintech', '运营商', '公共出行', '未知'],
      counts: result.stats.sectors,
    );
    expect(chips.map((item) => '${item.$1}:${item.$2}').toList(), [
      '能源:10',
      'Fintech:0',
      '运营商:0',
      '公共出行:0',
      '未知:0',
      '未填写:2',
    ]);
    expect(
      proposalIntakeSectorCountRows(
        catalog: const ['能源'],
        counts: const [
          ProposalIntakeSectorStat(name: '能源', count: 1),
          ProposalIntakeSectorStat(name: '自定义', count: 4),
          ProposalIntakeSectorStat(name: '未填写', count: 0),
        ],
      ).map((item) => '${item.$1}:${item.$2}').toList(),
      ['能源:1', '自定义:4'],
    );
  });

  test('list groups by update day and counts open days', () {
    final now = DateTime(2026, 9, 7, 13, 0);
    final today = ProposalIntakeRow.fromJson({
      'code': 'TA-20260907-000001',
      'createdAt': '2026-09-07T10:00:00',
      'updatedAt': '2026-09-07T15:32:00',
      'form': {'createdByName': '黄永刚'},
    });
    final older = ProposalIntakeRow.fromJson({
      'code': 'TA-20260903-000104',
      'createdAt': '2026-09-03T09:00:00',
      'updatedAt': '2026-09-04T15:32:00',
      'form': {'createdByName': '朱子姝'},
    });
    expect(proposalIntakeDaysOpen(today, now: now), 1);
    expect(proposalIntakeDaysOpenLabel(today, now: now), '今天打开');
    expect(proposalIntakeDaysOpen(older, now: now), 5);
    expect(proposalIntakeDaysOpenLabel(older, now: now), '已开 5 天');
    final groups = groupProposalIntakeRowsByDate([older, today], now: now);
    expect(groups.map((g) => g.label).toList(), ['今天', '9月4日']);
    expect(groups.first.rows.single.code, 'TA-20260907-000001');
    expect(groups.last.rows.single.code, 'TA-20260903-000104');
  });

  test('list sector filter reads form name or catalog ref', () {
    expect(
      proposalIntakeSectorName(
        ProposalIntakeRow.fromJson({
          'form': {'sector': '能源'},
        }),
      ),
      '能源',
    );
    expect(
      proposalIntakeSectorName(
        ProposalIntakeRow.fromJson({
          'form': {
            'sectorRef': {'id': 1, 'code': 'NY', 'name': 'Fintech'},
          },
        }),
      ),
      'Fintech',
    );
    expect(proposalIntakeSectorName(ProposalIntakeRow.fromJson({})), '');
    final filters = proposalIntakeSectorFilters(['能源', ' Fintech ', '能源']);
    expect(filters.map((item) => item.$1).toList(), [
      '',
      '能源',
      'Fintech',
      kProposalIntakeSectorBlankFilter,
    ]);
    expect(filters.last.$2, '未填写');
    final energy = ProposalIntakeRow.fromJson({
      'form': {'sector': '能源'},
    });
    final blank = ProposalIntakeRow.fromJson({});
    expect(proposalIntakeMatchesSectorFilter(energy, ''), isTrue);
    expect(proposalIntakeMatchesSectorFilter(energy, '能源'), isTrue);
    expect(proposalIntakeMatchesSectorFilter(energy, '运营商'), isFalse);
    expect(
      proposalIntakeMatchesSectorFilter(
        blank,
        kProposalIntakeSectorBlankFilter,
      ),
      isTrue,
    );
    expect(
      proposalIntakeMatchesSectorFilter(
        energy,
        kProposalIntakeSectorBlankFilter,
      ),
      isFalse,
    );
  });

  test('list fill progress is 0% on empty sales and purchase rows', () {
    final sales = ProposalIntakeRow.fromJson({'kind': 'sales', 'form': {}});
    final purchase = ProposalIntakeRow.fromJson({
      'kind': 'purchase',
      'form': {},
    });
    final salesProgress = proposalIntakeFillProgress(sales);
    final purchaseProgress = proposalIntakeFillProgress(purchase);
    expect(salesProgress.total, _fillMissingCount(sales));
    expect(purchaseProgress.total, _fillMissingCount(purchase));
    expect(salesProgress.total, greaterThan(0));
    expect(purchaseProgress.total, greaterThan(0));
    expect(salesProgress.total, isNot(purchaseProgress.total));
    expect(salesProgress.filled, 0);
    expect(purchaseProgress.filled, 0);
    expect(salesProgress.filledPercent, 0);
    expect(purchaseProgress.filledPercent, 0);
    expect(salesProgress.label, '已填 0%');
    expect(
      const ProposalIntakeFillProgress(filled: 1, total: 3).filledPercent,
      33,
    );
    expect(
      const ProposalIntakeFillProgress(filled: 2, total: 3).filledPercent,
      67,
    );
  });

  test(
    'list fill progress counts filled sales fields and stays consistent',
    () {
      final row = ProposalIntakeRow.fromJson({
        'kind': 'sales',
        'form': {'sector': '能源', 'proposalName': '充电补贴'},
      });
      final progress = proposalIntakeFillProgress(row);
      expect(progress.filled, greaterThan(0));
      expect(progress.filledPercent, greaterThan(0));
      expect(progress.filledPercent, lessThan(100));
      expect(progress.missing, _fillMissingCount(row));
      expect(progress.filled + progress.missing, progress.total);
      expect(progress.label, '已填 ${progress.filledPercent}%');
    },
  );

  test('sales fill progress reaches 100% when required slots are filled', () {
    final form = <String, dynamic>{
      'sector': '能源',
      'proposalName': '充电补贴',
      'proposalType': '新增业务提案',
      'product': '现金券',
      'projectName': '项目甲',
      'supplies': ['供给A'],
      'channels': ['渠道A'],
      'supplierPolicy': '供货政策',
      'channelPolicy': '渠道政策',
      'executionPlan': '执行计划',
      'riskPoints': '风险点',
      'profitModes': ['返点'],
      'profitFormula': '公式',
      'purchaseMode': '已签署合同',
      'purchaseNo': 'CG-1',
      'purchaseName': '采购合同',
      'purchaseSignDate': '2026-01-01',
      'purchaseOurParty': '我方',
      'purchaseCounterparty': '对方',
      'purchaseValidPeriod': '1年',
      'purchaseCoreTerms': '条款',
      'salesMode': '已签署合同',
      'salesNo': 'XS-1',
      'salesName': '销售合同',
      'salesSignDate': '2026-01-01',
      'salesOurParty': '我方',
      'salesCounterparty': '对方',
      'salesValidPeriod': '1年',
      'salesCoreTerms': '条款',
      'technologyPlatform': '能源平台',
      'technologyCapabilities': ['发放'],
      'outputForms': ['API'],
      'developmentTypes': ['全新开发'],
      'hasRdCost': '否',
      'deliveryDate': '2026-12-01',
      'skuDetails': [
        {
          'id': 'sku-1',
          'settlements': [
            {'id': 'st-1', 'scale': '1'},
          ],
        },
      ],
    };
    for (final field in kProposalSalesFinanceFillFields) {
      form[field.$1] = '1';
    }
    final row = ProposalIntakeRow.fromJson({'kind': 'sales', 'form': form});
    final progress = proposalIntakeFillProgress(row);
    expect(_fillMissingCount(row), 0);
    expect(progress.filledPercent, 100);
    expect(progress.missing, 0);
    expect(progress.label, '已填 100%');
  });

  test('open day can fall back to TA-YYYYMMDD in the code', () {
    final row = ProposalIntakeRow.fromJson({'code': 'TA-20260901-000009'});
    expect(proposalIntakeDaysOpen(row, now: DateTime(2026, 9, 7)), 7);
  });

  test('proposal intake kind normalizes sales vs purchase', () {
    expect(normalizeProposalIntakeKind(''), 'sales');
    expect(normalizeProposalIntakeKind('purchase-proposal'), 'purchase');
    expect(proposalIntakeIsPurchase('purchase'), isTrue);
    expect(proposalIntakeUntitledTitle('sales'), '未命名销售业务提案');
    expect(proposalIntakeUntitledTitle('purchase'), '未命名采购业务提案');
    expect(ProposalIntakeRow.fromJson({'kind': 'purchase'}).kind, 'purchase');
    expect(ProposalIntakeRow.fromJson({}).kind, 'sales');
  });

  test('proposal options parse linked choices and rating thresholds', () {
    final options = ProposalIntakeOptions.fromJson({
      'market': {
        'sectors': ['能源'],
        'products': [
          {
            'value': '现金券',
            'projects': ['项目甲', '项目乙'],
          },
        ],
      },
      'technology': {
        'platforms': [
          {
            'value': '能源平台',
            'capabilities': ['发放', '核销'],
          },
        ],
        'financeInterfaces': [
          {
            'key': 'face',
            'label': '面值',
            'required': true,
            'defaultChecked': true,
          },
        ],
      },
      'rules': {'ratingS': 5000, 'ratingA': 2000, 'ratingB': 500},
    });

    expect(options.products.single.children, ['项目甲', '项目乙']);
    expect(options.platforms.single.children, ['发放', '核销']);
    expect(options.financeInterfaces.single.required, isTrue);
    expect(options.ratingFor(5000), 'S');
    expect(options.ratingFor(2000), 'A');
    expect(options.ratingFor(500), 'B');
    expect(options.ratingFor(499), 'C');
  });

  test('proposal options parse institution label and code', () {
    final options = ProposalIntakeOptions.fromJson({
      'market': {
        'institutions': [
          {'label': '卓悦C', 'code': 'ZYC'},
          {'name': '天琨', 'key': 'TK'},
          '力先|LX',
        ],
      },
    });
    expect(options.institutions.map((item) => item.code).toList(), [
      'ZYC',
      'TK',
      'LX',
    ]);
    expect(options.institutions.first.name, '卓悦C');
  });

  test('purchase options parse supply brands and rebate modes', () {
    final options = ProposalIntakeOptions.fromJson({
      'market': {
        'supplyBrands': ['中石油', '中石化'],
        'rebateModes': ['消费返', '核销返'],
      },
    });
    expect(options.supplyBrands, ['中石油', '中石化']);
    expect(options.rebateModes, ['消费返', '核销返']);
  });

  test('sku keeps institution snapshot', () {
    final sku = ProposalSkuDetailRow.fromJson({
      'id': 'sku-1',
      'productName': '中石油100元',
      'institutionRef': {'code': 'ZYC', 'name': '卓悦C'},
    });
    expect(sku.institutionCode, 'ZYC');
    expect(sku.toJson()['institution'], '卓悦C');
  });

  test('sku keeps channel snapshot and lift from old settlements', () {
    final sku = ProposalSkuDetailRow.fromJson({
      'id': 'sku-1',
      'productName': '中石油100元',
      'channelRef': {
        'id': '2070026713580023809',
        'code': 'C001',
        'name': '银联商务',
      },
      'settlements': [
        {'id': 'st-1', 'billType': '电子券销售款'},
      ],
    });
    expect(sku.channelCode, 'C001');
    expect(sku.toJson()['channel'], '银联商务');
    expect(sku.toJson()['settlements'][0]['channelRef']['code'], 'C001');

    final lifted = ProposalSkuDetailRow.fromJson({
      'id': 'sku-2',
      'productName': '中石油50元',
      'settlements': [
        {
          'id': 'st-1',
          'channelRef': {'code': 'C002', 'name': '微信'},
        },
      ],
    });
    expect(lifted.channelRef?.name, '微信');
    expect(lifted.toJson()['channelCode'], 'C002');
  });

  test('existing built sku requires catalog product instead of name', () {
    expect(
      proposalIntakeSkuSettleIssues({
        'skuDetails': [
          {'id': 'sku-1', 'existingBuilt': '是'},
        ],
      }),
      contains('渠道产品第1条请搜索并选择已建产品'),
    );
    final sku = ProposalSkuDetailRow.fromJson({
      'id': 'sku-1',
      'existingBuilt': '是',
      'assetProduct': {
        'id': 10,
        'productCode': 'CP001',
        'productName': '中石油100',
        'channelId': 1,
        'channelName': '银联商务',
      },
    });
    expect(sku.isExistingBuilt, isTrue);
    expect(sku.productName, '中石油100');
    expect(sku.toJson()['assetProduct']['productCode'], 'CP001');

    expect(
      proposalIntakeSkuSettleIssues({
        'isExistingBuilt': true,
        'skuDetails': [
          {'id': 'sku-1'},
        ],
      }),
      containsAll(['渠道产品第1条请选择业务平台', '渠道产品第1条请搜索并选择已建产品']),
    );

    final outbound = ProposalSkuDetailRow.fromJson({
      'id': 'sku-2',
      'isExistingProduct': true,
      'productName': '中石油 100 元现金券',
      'syncSource': {'code': 'POINTS_REBATE', 'name': '能源积分'},
    });
    expect(outbound.isExistingBuilt, isTrue);
    expect(outbound.syncSourceRef?.name, '能源积分');
    expect(outbound.assetProduct?.label, '中石油 100 元现金券');

    final restoredSkus = proposalIntakeSkuDetails({
      'isExistingBuilt': true,
      'skuDetails': [
        {'id': 'sku-1'},
        {'id': 'sku-2'},
        {'id': 'sku-3'},
      ],
      'products': [
        {
          'id': 'sku-1',
          'productName': '渠道现金券A',
          'syncSource': {'code': 'DIGITALG', 'name': '能源'},
        },
        {'id': 'sku-2', 'name': '渠道现金券B', 'isExistingProduct': true},
        {'id': 'sku-3', 'productCode': 'CP-3', 'existingBuilt': '是'},
      ],
    });
    expect(restoredSkus.map((row) => row.productName).toList(), [
      '渠道现金券A',
      '渠道现金券B',
      'CP-3',
    ]);
    expect(restoredSkus[0].syncSourceRef?.name, '能源');
    expect(restoredSkus[1].assetProduct?.label, '渠道现金券B');
    expect(restoredSkus[2].assetProduct?.label, 'CP-3');

    final synced = proposalIntakeSettlementsFromChannelCatalog(
      ChannelProductSettlement.fromJson({
        'id': 10,
        'productName': '中石油100',
        'channelId': 1,
        'channelName': '银联商务',
        'settlementItems': [
          {
            'billTypeL1Name': '应收账单',
            'billTypeL2Name': '销售款',
            'billTypeL3Code': 'E_COUPON_SALES',
            'billTypeL3Name': '电子券销售款',
            'settleMethod': 1,
            'formulaContent': 1,
            'settlementRatio': 98.5,
            'invoiceTypeCode': '专票',
            'taxRateCode': '13%',
            'ourEntity': '荷叶',
            'counterpartyEntity': '某某渠道',
            'effectiveTime': '2026-09-01 00:00:00',
            'sortNo': 1,
          },
        ],
      }),
    );
    expect(synced, hasLength(1));
    expect(synced.single.terms.settleModeRef?.code, '1');
    expect(synced.single.terms.settleRatio, '98.5%');
    expect(synced.single.terms.taxRate, '13%');
    expect(synced.single.terms.invoiceType, '专票');
    expect(synced.single.terms.ourParty, '荷叶');
    expect(synced.single.terms.billTypeRef?.name, '电子券销售款');
    expect(synced.single.terms.effectiveTime, '2026-09-01');
    expect(proposalIntakeSettleUsesRatio(synced.single.terms), isTrue);
    expect(synced.single.terms.formulaRef?.name, '1');

    final named = proposalIntakeSettlementsFromChannelCatalog(
      ChannelProductSettlement.fromJson({
        'id': 10,
        'settlementItems': [
          {
            'billTypeL3Code': 'E_COUPON_SALES',
            'billTypeL3Name': '电子券销售款',
            'settleMethod': 1,
            'formulaContent': 1,
            'settlementRatio': 98.5,
            'taxRateCode': '13%',
          },
        ],
      }),
      formulas: const [
        CatalogRef(
          code: '1',
          name: '销售额×结算比例',
          formulaExpression: 'amount * ratio',
          settleMethod: '1',
          productSource: 'CHANNEL',
        ),
      ],
    );
    expect(named.single.terms.formula, '销售额×结算比例');

    final applied = const ProposalSkuDetailRow(id: 'sku-1').applyAssetProduct(
      const ChannelProductHit(id: 10, productName: '中石油100'),
      settlements: synced,
    );
    expect(applied.productName, '中石油100');
    expect(applied.settlements.single.terms.taxRate, '13%');
  });

  test('proposal options parse configured presidents', () {
    final options = ProposalIntakeOptions.fromJson({
      'people': {
        'presidentUserIds': [21, '22'],
        'presidents': [
          {'userId': 21, 'name': '张三'},
        ],
      },
    });
    expect(options.presidentUserIds, [21, 22]);
    expect(options.isConfiguredPresident(21), isTrue);
    expect(options.isConfiguredPresident(9), isFalse);
    expect(options.presidentDisplayNames(const []), '张三、用户22');
  });

  test('wan thresholds stay wan', () {
    final options = ProposalIntakeOptions.fromJson({
      'rules': {
        'ratingS': 5000,
        'ratingA': 2000,
        'ratingB': 500,
        'minimumScale': 500,
      },
    });
    expect(options.minimumScale, 500);
    expect(options.ratingS, 5000);
  });

  test('finance cost headers parse project and business buckets', () {
    final options = ProposalIntakeOptions.fromJson({
      'finance': {
        'costItems': ['平台服务费', '支付手续费'],
        'businessCostItems': ['员工提成'],
        'businessCostRules': '提成按规则累计',
        'operatingCostRules': '差旅不超过收入 2%',
      },
    });
    expect(options.costItems, ['平台服务费', '支付手续费']);
    expect(options.businessCostItems, ['员工提成']);
    expect(options.businessCostRules, '提成按规则累计');
    expect(options.operatingCostRules, '差旅不超过收入 2%');
  });

  test('project cost chips follow finance header order and alias 平台服务费', () {
    expect(kProposalProjectCostItems, [
      '机构返佣',
      '万里通返佣',
      '补贴款分润',
      '平台交易服务费',
      '渠道服务费分润',
      '支付手续费',
      '推广费',
    ]);
    expect(proposalProjectCostDisplayName('平台服务费'), '平台交易服务费');
    expect(kProposalOperatingCostItems, ['差旅成本', '招待费']);
    expect(kProposalTaxCostItems, [
      '增值税及附加（能源）',
      '增值税及附加（运营商+公共出行）',
      '印花税',
      '所得税',
    ]);
    expect(
      proposalCostAmountId('平台交易服务费', const [
        ProposalCostItemOption(code: 'ap_FW_PTF', name: '平台服务费'),
      ]),
      'ap_FW_PTF',
    );
  });

  test('finance cost item options keep codes from asset', () {
    final options = ProposalIntakeOptions.fromJson({
      'finance': {
        'costItems': ['机构返佣'],
        'costItemSource': 'asset',
        'costItemOptions': [
          {
            'code': 'ap_YFFY_JGFY',
            'name': '机构返佣',
            'l2': '返佣',
            'category': 'PROJECT_COST',
          },
        ],
        'businessCostItemOptions': [
          {'code': 'ap_YWCB_GJCH', 'name': '供给侧H', 'category': 'BUSINESS_COST'},
        ],
      },
    });
    expect(options.costItemSource, 'asset');
    expect(options.costItemOptions.single.code, 'ap_YFFY_JGFY');
    expect(options.businessCostItemOptions.single.name, '供给侧H');
  });

  test('selected cost items keep expected amounts and sum the total', () {
    const catalog = [
      ProposalCostItemOption(code: 'ap_FW_PTF', name: '平台服务费'),
      ProposalCostItemOption(code: 'ap_YFFY_JGFY', name: '机构返佣'),
    ];
    var form = proposalSyncCostSelection(
      form: {
        'costItemAmounts': {'ap_FW_PTF': 10, 'ap_YFFY_JGFY': 2.5},
      },
      names: ['平台服务费', '机构返佣'],
      catalog: catalog,
      namesKey: 'costItems',
      codesKey: 'costItemCodes',
      amountsKey: 'costItemAmounts',
      totalKey: 'projectCost',
    );
    expect(form['costItemCodes'], ['ap_FW_PTF', 'ap_YFFY_JGFY']);
    expect(form['projectCost'], 12.5);

    form = proposalSyncCostSelection(
      form: form,
      names: ['平台服务费'],
      catalog: catalog,
      namesKey: 'costItems',
      codesKey: 'costItemCodes',
      amountsKey: 'costItemAmounts',
      totalKey: 'projectCost',
    );
    expect(form['costItems'], ['平台服务费']);
    expect(form['costItemAmounts'], {'ap_FW_PTF': 10});
    expect(form['projectCost'], 10);
  });

  test('selected project cost items do not require own settle terms', () {
    const catalog = [
      ProposalCostItemOption(code: 'ap_YFFY_JGFY', name: '机构返佣'),
    ];
    expect(
      proposalIntakeCostItemSettleIssues({
        'costItems': ['机构返佣'],
      }, catalog: catalog),
      isEmpty,
    );

    var form = proposalSyncCostSelection(
      form: {
        'costItemSettleTerms': {
          'ap_YFFY_JGFY': {
            'settlePrice': '1.2%',
            'settleRule': '核销结算',
            'counterparty': '中石化',
            'ourParty': '沙丘',
            'taxRate': '6%',
          },
          'ap_FW_PTF': {
            'settlePrice': '2%',
            'settleRule': '月结',
            'counterparty': '中石油',
            'ourParty': '沙丘',
            'taxRate': '6%',
          },
        },
      },
      names: ['机构返佣'],
      catalog: catalog,
      namesKey: 'costItems',
      codesKey: 'costItemCodes',
      amountsKey: 'costItemAmounts',
      totalKey: 'projectCost',
      settleTermsKey: 'costItemSettleTerms',
    );
    expect(form['costItemSettleTerms'].keys, ['ap_YFFY_JGFY']);
    expect(proposalIntakeCostItemSettleIssues(form, catalog: catalog), isEmpty);
  });

  test('selected business cost items require settlement terms', () {
    const catalog = [
      ProposalCostItemOption(code: 'ap_YWCB_GJCH', name: '供给侧H'),
    ];
    expect(
      proposalIntakeCostItemSettleIssues({
        'businessCostItems': ['供给侧H'],
      }, businessCatalog: catalog),
      ['业务成本「供给侧H」请填写结算比例或单价'],
    );

    var form = proposalSyncCostSelection(
      form: {
        'businessCostItemSettleTerms': {
          'ap_YWCB_GJCH': {
            'settlePrice': '3%',
            'settleRule': '核销结算',
            'counterparty': '渠道方',
            'ourParty': '沙丘',
            'taxRate': '6%',
          },
          'ap_YWCB_OTHER': {
            'settlePrice': '1%',
            'settleRule': '月结',
            'counterparty': '其他',
            'ourParty': '沙丘',
            'taxRate': '6%',
          },
        },
      },
      names: ['供给侧H'],
      catalog: catalog,
      namesKey: 'businessCostItems',
      codesKey: 'businessCostItemCodes',
      amountsKey: 'businessCostItemAmounts',
      totalKey: 'businessCost',
      settleTermsKey: 'businessCostItemSettleTerms',
    );
    expect(form['businessCostItemSettleTerms'].keys, ['ap_YWCB_GJCH']);
    expect(
      proposalIntakeCostItemSettleIssues(form, businessCatalog: catalog),
      isEmpty,
    );
  });

  test('finance cost rules fall back when missing', () {
    final options = ProposalIntakeOptions.fromJson({});
    expect(options.operatingCostRules, contains('2%'));
    expect(options.businessCostRules, contains('员工提成'));
  });

  test(
    'finance cost estimates fill selected rows and keep manual overrides',
    () {
      expect(proposalParseTaxRate('6%'), 0.06);
      expect(proposalParseTaxRate(6), 0.06);
      expect(proposalParseTaxRate(0.13), 0.13);
      expect(
        proposalBusinessCostFormulaOf('供给侧BN'),
        ProposalBusinessCostFormula.bn,
      );
      expect(
        proposalBusinessCostFormulaOf('渠道侧N'),
        ProposalBusinessCostFormula.bn,
      );
      expect(
        proposalBusinessCostFormulaOf('供给侧U'),
        ProposalBusinessCostFormula.u,
      );
      expect(proposalBusinessCostFormulaOf('供给侧H'), isNull);

      var form = proposalApplyEstimatedFinanceCosts({
        'revenue': 100,
        'couponProcurementCost': 80,
        'projectCost': 5,
        'salesScale': 200,
        'skuDetails': [
          {
            'id': 'sku-1',
            'settlements': [
              {'id': 'st-1', 'taxRate': '6%'},
            ],
          },
        ],
        'operatingCostItems': ['差旅成本', '招待费'],
        'businessCostItems': ['供给侧BN', '渠道侧U'],
        'taxCostItems': ['增值税及附加（能源）', '印花税', '所得税'],
      });
      expect(form['operatingCostItemAmounts']['差旅成本'], 0.3);
      expect(form['operatingCostItemAmounts']['招待费'], 0.3);
      expect(form['operatingCost'], 0.6);
      expect(form['businessCostItemAmounts']['供给侧BN'], 1.44);
      expect(form['businessCostItemAmounts']['渠道侧U'], 6.48);
      expect(form['salesScale'], 200);
      expect(form['revenue'], 100);
      expect(form['profit'], isNull);
      expect(form['margin'], isNull);
      expect(form['taxCostItemAmounts']['增值税及附加（能源）'], 1.01);
      expect(form['taxCostItemAmounts']['印花税'], 0.12);
      expect(form['taxCostItemAmounts']['所得税'], 1.62);

      expect(
        proposalTurnoverCashAmount({'salesScale': 100, 'turnoverTimes': 4}),
        2.08,
      );
      expect(
        proposalApplyTurnoverCash({
          'salesScale': 100,
          'turnoverTimes': 4,
        })['turnoverCash'],
        2.08,
      );
      expect(proposalTurnoverCashAmount({'salesScale': 100}), isNull);
      expect(
        proposalCostFormulaText(ProposalCostEstimateKind.stamp),
        '销售规模 × 0.0006',
      );
      expect(
        proposalCostFormulaText(ProposalCostEstimateKind.operating),
        '(收入 − 采购 − 项目) × 2%',
      );
      expect(kProposalProjectCostFormula, contains('年化规模 × 结算比例'));

      form = proposalApplyEstimatedFinanceCosts(
        proposalMarkCostAmountManual(
          {...form, 'revenue': 200},
          amountsKey: 'operatingCostItemAmounts',
          id: '差旅成本',
        ),
      );
      expect(form['operatingCostItemAmounts']['差旅成本'], 0.3);
      expect(form['operatingCostItemAmounts']['招待费'], 2.3);

      final help = proposalCostFormulaHelpOf(
        name: '差旅成本',
        form: {'revenue': 100, 'couponProcurementCost': 80, 'projectCost': 5},
      );
      expect(help?.formula, contains('× 2%'));
      expect(help?.substitution, contains('0.30 万元'));
    },
  );

  test(
    'settlement scale rolls into sales, revenue, profit, margin and tax',
    () {
      const terms = ProposalFinanceSettleTerms(
        scale: '100',
        settleRatio: '0.926',
      );
      expect(terms.isBlank, isFalse);
      expect(terms.toJson()['scale'], '100');
      expect(ProposalFinanceSettleTerms.fromJson(terms.toJson()).scale, '100');
      expect(
        ProposalFinanceSettleTerms.fromJson({'salesScale': '50'}).scale,
        '50',
      );
      expect(
        const ProposalFinanceSettleTerms(scale: '1').fingerprint,
        isNot(const ProposalFinanceSettleTerms(scale: '2').fingerprint),
      );

      var form = proposalApplyEstimatedFinanceCosts({
        'couponProcurementCost': 80,
        'projectCost': 5,
        'salesScale': 999,
        'revenue': 888,
        'profit': 1,
        'margin': 1,
        'skuDetails': [
          {
            'id': 'sku-1',
            'settlements': [
              {
                'id': 'st-1',
                'scale': '100',
                'settleRatio': '0.926',
                'taxRate': '6%',
              },
            ],
          },
          {
            'id': 'sku-2',
            'settlements': [
              {'id': 'st-2', 'scale': '200', 'settleRatio': '90%'},
            ],
          },
        ],
        'taxCostItems': ['增值税及附加（能源）', '印花税'],
      });
      expect(form['salesScale'], 300);
      expect(form['revenue'], 272.6);
      expect(form['profit'], 187.6);
      expect(form['margin'], 68.82);
      expect(form['taxCostItemAmounts']['印花税'], 0.18);
      expect(form['taxCostItemAmounts']['增值税及附加（能源）'], 12.61);

      form = proposalApplyEstimatedFinanceCosts({
        'isCouponPack': true,
        'skuDetails': [
          {
            'id': 'sku-1',
            'settlements': [
              {'id': 'st-sku', 'scale': '100', 'settleRatio': '0.9'},
            ],
          },
        ],
        'couponPacks': [
          {
            'id': 'pack-1',
            'name': '券包',
            'settlements': [
              {'id': 'st-pack', 'scale': '999', 'settleRatio': '0.1'},
            ],
          },
        ],
      });
      expect(form['salesScale'], 100);
      expect(form['revenue'], 90);

      form = proposalApplyEstimatedFinanceCosts({
        'skuDetails': [
          {
            'id': 'sku-1',
            'settlements': [
              {'id': 'st-1', 'scale': '100'},
            ],
          },
        ],
      });
      expect(form['salesScale'], 100);
      expect(form['revenue'], 100);
      expect(form['profit'], 100);
      expect(form['margin'], 100);

      expect(
        proposalTurnoverCashAmount({
          'turnoverTimes': 4,
          'skuDetails': [
            {
              'id': 'sku-1',
              'settlements': [
                {'id': 'st-1', 'scale': '200'},
              ],
            },
          ],
        }),
        4.17,
      );
      expect(
        proposalIntakeSalesFinanceFillIssues({
          'skuDetails': [
            {
              'id': 'sku-1',
              'settlements': [
                {'id': 'st-1', 'scale': '100'},
              ],
            },
          ],
        }),
        isNot(contains('请填写销售规模目标（年·万元）')),
      );
      expect(
        proposalIntakeSalesFinanceFillIssues({
          'skuDetails': [
            {
              'id': 'sku-1',
              'settlements': [
                {'id': 'st-1', 'scale': '100'},
              ],
            },
          ],
        }),
        isNot(contains('请填写收入（万元）')),
      );
    },
  );

  test('vat uses sales output rate and purchase input rate per settlement', () {
    expect(
      proposalCostFormulaText(ProposalCostEstimateKind.vat),
      contains('销项'),
    );

    var form = proposalApplyEstimatedFinanceCosts({
      'couponProcurementCost': 80,
      'projectCost': 10,
      'skuDetails': [
        {
          'id': 'sku-1',
          'settlements': [
            {
              'id': 'st-1',
              'scale': '100',
              'settleRatio': '1',
              'taxRate': '13%',
            },
          ],
        },
        {
          'id': 'sku-2',
          'settlements': [
            {'id': 'st-2', 'scale': '100', 'settleRatio': '1', 'taxRate': '6%'},
          ],
        },
      ],
      'supplyProducts': [
        {
          'id': 'sup-1',
          'supplierCode': 'ZYC',
          'settlements': [
            {'id': 'sst-1', 'taxRate': '9%', 'invoiceType': '增值税专用发票'},
          ],
        },
      ],
      'costItemSettleTerms': {
        '机构返佣': {'taxRate': '6%', 'invoiceType': '增值税专用发票'},
      },
      'taxCostItems': ['增值税及附加（能源）'],
    });
    // 销项 100×13% + 100×6% = 19；进项 80×9% + 10×6% = 7.8；(19−7.8)×1.12 = 12.544
    expect(form['taxCostItemAmounts']['增值税及附加（能源）'], 12.54);

    form = proposalApplyEstimatedFinanceCosts({
      'revenue': 100,
      'couponProcurementCost': 80,
      'projectCost': 5,
      'skuDetails': [
        {
          'id': 'sku-1',
          'settlements': [
            {'id': 'st-1', 'taxRate': '13%'},
          ],
        },
      ],
      'taxCostItems': ['增值税及附加（能源）'],
    });
    // 无供给税率时进销一致： (100−80−5)×13%×1.12 = 2.184
    expect(form['taxCostItemAmounts']['增值税及附加（能源）'], 2.18);

    form = proposalApplyEstimatedFinanceCosts({
      'revenue': 100,
      'couponProcurementCost': 80,
      'skuDetails': [
        {
          'id': 'sku-1',
          'settlements': [
            {'id': 'st-1', 'taxRate': '13%'},
          ],
        },
      ],
      'supplyProducts': [
        {
          'id': 'sup-1',
          'supplierCode': 'ZYC',
          'settlements': [
            {'id': 'sst-1', 'taxRate': '9%', 'invoiceType': '增值税专用发票'},
          ],
        },
      ],
      'taxCostItems': ['增值税及附加（能源）'],
    });
    // 无规模：销项 100×13%，进项 80×9%；(13−7.2)×1.12 = 6.496
    expect(form['taxCostItemAmounts']['增值税及附加（能源）'], 6.5);

    final help = proposalCostFormulaHelpOf(
      name: '增值税及附加（能源）',
      form: {
        'couponProcurementCost': 80,
        'skuDetails': [
          {
            'id': 'sku-1',
            'settlements': [
              {
                'id': 'st-1',
                'scale': '100',
                'settleRatio': '1',
                'taxRate': '13%',
              },
            ],
          },
        ],
        'supplyProducts': [
          {
            'id': 'sup-1',
            'supplierCode': 'ZYC',
            'settlements': [
              {'id': 'sst-1', 'taxRate': '9%'},
            ],
          },
        ],
      },
    );
    expect(help?.substitution, contains('销项'));
    expect(help?.substitution, contains('进项'));
  });

  test('shared sales settlement applies one ratio to each sku scale', () {
    final form = proposalApplyEstimatedFinanceCosts({
      'skuDetails': [
        {
          'id': 'sku-1',
          'productName': '现金券100',
          'faceValue': '100',
          'settlements': [
            {'id': 'st-1', 'scale': '100'},
          ],
        },
        {
          'id': 'sku-2',
          'productName': '现金券200',
          'faceValue': '200',
          'settlements': [
            {'id': 'st-2', 'scale': '200'},
          ],
        },
      ],
      'sharedSettlements': [
        {
          'id': 'ss-1',
          'skuIds': ['sku-1', 'sku-2'],
          'settleRatio': '0.926',
          'taxRate': '13%',
          'formula': '规模×比例',
        },
      ],
    });
    expect(form['salesScale'], 300);
    expect(form['revenue'], 277.8);
    expect(
      proposalIntakeSkuSettleReviewKeys({
        'skuDetails': [
          {
            'id': 'sku-1',
            'settlements': [
              {'id': 'st-1'},
            ],
          },
        ],
        'sharedSettlements': [
          {
            'id': 'ss-1',
            'skuIds': ['sku-1'],
          },
        ],
      }),
      kProposalSharedSettleEnabled
          ? contains('sharedSettle:ss-1:ss-1')
          : isNot(contains('sharedSettle:ss-1:ss-1')),
    );
  });

  test('monthly scale is annualised across every derived figure', () {
    final form = proposalApplyEstimatedFinanceCosts({
      'skuDetails': [
        {
          'id': 'sku-1',
          'settlements': [
            {
              'id': 'st-1',
              'scale': '50',
              'scalePeriod': '月',
              'settleRatio': '0.926',
              'taxRate': '13%',
            },
          ],
        },
      ],
      'turnoverTimes': '12',
    });
    expect(form['salesScale'], 600);
    expect(form['revenue'], 555.6);
    expect(form['taxCostItemAmounts']['印花税'], 0.36);
    expect(form['turnoverCash'], 4.17);
  });

  test(
    'procurement cost splits by the channel products each supply rule covers',
    () {
      final form = proposalApplyEstimatedFinanceCosts({
        'skuDetails': [
          {
            'id': 'sku-1',
            'settlements': [
              {
                'id': 'st-1',
                'scale': '400',
                'settleRatio': '0.926',
                'taxRate': '13%',
              },
            ],
          },
          {
            'id': 'sku-2',
            'settlements': [
              {
                'id': 'st-2',
                'scale': '200',
                'settleRatio': '0.926',
                'taxRate': '13%',
              },
            ],
          },
        ],
        'supplyProducts': [
          {
            'id': 'sup-1',
            'settlements': [
              {
                'id': 'sst-1',
                'skuIds': ['sku-1'],
                'settleRatio': '0.9',
                'taxRate': '9%',
              },
              {
                'id': 'sst-2',
                'skuIds': ['sku-2'],
                'settleRatio': '0.85',
                'taxRate': '9%',
              },
            ],
          },
        ],
      });
      // 400×0.9 + 200×0.85 = 530；旧口径按第一条比例会算成 600×0.9 = 540。
      expect(form['couponProcurementCost'], 530);
    },
  );

  test('vat item defaults to the operator kind for operator sectors', () {
    final form = proposalApplyEstimatedFinanceCosts({
      'sector': '运营商',
      'skuDetails': [
        {
          'id': 'sku-1',
          'settlements': [
            {
              'id': 'st-1',
              'scale': '600',
              'settleRatio': '0.926',
              'taxRate': '13%',
            },
          ],
        },
      ],
    });
    expect(form['taxCostItems'], contains('增值税及附加（运营商+公共出行）'));
    expect(form['taxCostItems'], isNot(contains('增值税及附加（能源）')));
  });

  test('procurement and tax and project cost follow settlement rules', () {
    var form = proposalApplyEstimatedFinanceCosts({
      'skuDetails': [
        {
          'id': 'sku-1',
          'faceValue': '100',
          'settlements': [
            {
              'id': 'st-1',
              'scale': '600',
              'settleRatio': '0.926',
              'taxRate': '13%',
              'billType': '应收账单 / 销售款 / 电子券销售款',
            },
            {
              'id': 'st-2',
              'billType': '应付账单 / 服务费 / 平台服务费',
              'settleRatio': '0.004',
              'settleUnitPrice': '100',
              'taxRate': '6%',
            },
          ],
        },
      ],
      'supplyProducts': [
        {
          'id': 'sup-1',
          'supplierCode': 'ZYC',
          'settlements': [
            {'id': 'sst-1', 'settleRatio': '0.9', 'taxRate': '9%'},
          ],
        },
      ],
    });
    expect(form['couponProcurementCost'], 540);
    expect(form['costItems'], contains('平台交易服务费'));
    expect(form['costItemAmounts']['平台交易服务费'], 2.4);
    expect(form['projectCost'], 2.4);
    expect(form['profit'], 13.2);
    expect(form['taxCostItems'], contains('印花税'));
    expect(form['taxCostItems'], contains('增值税及附加（能源）'));
    expect(form['taxCostItems'], isNot(contains('所得税')));
    expect(form['taxCostItemAmounts']['印花税'], 0.36);

    form = proposalApplyEstimatedFinanceCosts({
      'revenue': 100,
      'couponProcurementCost': 80,
      'projectCost': 5,
      'skuDetails': [
        {
          'id': 'sku-1',
          'settlements': [
            {'id': 'st-1', 'taxRate': '6%'},
          ],
        },
      ],
      'taxCostItems': ['增值税及附加（运营商+公共出行）'],
    });
    expect(form['taxCostItems'], contains('增值税及附加（运营商+公共出行）'));
    expect(form['taxCostItems'], isNot(contains('增值税及附加（能源）')));
    expect(form['taxCostItemAmounts']['增值税及附加（运营商+公共出行）'], 1.01);

    form = proposalApplyEstimatedFinanceCosts(
      proposalMarkCostAmountManual(
        {
          'costItems': ['机构返佣'],
          'costItemAmounts': {'机构返佣': 10},
          'skuDetails': [
            {
              'id': 'sku-1',
              'faceValue': '100',
              'settlements': [
                {
                  'id': 'st-1',
                  'scale': '100',
                  'billType': '应付账单 / 返佣 / 机构返佣',
                  'settleRatio': '0.01',
                  'settleUnitPrice': '100',
                },
              ],
            },
          ],
        },
        amountsKey: 'costItemAmounts',
        id: '机构返佣',
      ),
    );
    expect(form['costItemAmounts']['机构返佣'], 10);
  });

  test('project cost matches payable L3 and sums scale times ratio', () {
    final form = proposalApplyEstimatedFinanceCosts({
      'skuDetails': [
        {
          'id': 'sku-1',
          'productName': '云南中石油100元电子券',
          'faceValue': '100',
          'settlements': [
            {'id': 'st-1', 'scale': '10'},
          ],
        },
        {
          'id': 'sku-2',
          'productName': '云南中石油200元电子券',
          'faceValue': '200',
          'settlements': [
            {'id': 'st-2', 'scale': '20'},
          ],
        },
      ],
      'sharedSettlements': [
        {
          'id': 'ss-sale',
          'skuIds': ['sku-1', 'sku-2'],
          'billType': '应收账单 / 销售款 / 电子券销售款',
          'settleRatio': '0.926',
          'settleUnitPrice': '100',
        },
        {
          'id': 'ss-fee',
          'skuIds': ['sku-1', 'sku-2'],
          'billType': '应付账单 / 服务费 / 平台服务费',
          'settleRatio': '0.004',
          'settleUnitPrice': '100',
        },
      ],
    });
    expect(form['costItems'], ['平台交易服务费']);
    expect(form['costItemAmounts']['平台交易服务费'], 0.12);
    expect(form['projectCost'], 0.12);
    expect(form['costItems'], isNot(contains('电子券销售款')));
    expect(
      proposalProjectCostFormulaSubstitution(form, '平台交易服务费'),
      '(10 + 20) × 0.004 = 0.12 万元',
    );
  });

  test('project cost on one sku still uses shared sales scale sum', () {
    final form = proposalApplyEstimatedFinanceCosts({
      'skuDetails': [
        {
          'id': 'sku-1',
          'productName': '云南中石油100元电子券',
          'faceValue': '100',
          'settlements': [
            {'id': 'st-1', 'scale': '200'},
            {
              'id': 'st-pay',
              'billType': '应付账单 / 服务费 / 平台服务费',
              'settleRatio': '0.004',
            },
          ],
        },
        {
          'id': 'sku-2',
          'productName': '云南中石油200元电子券',
          'faceValue': '200',
          'settlements': [
            {'id': 'st-2', 'scale': '400'},
          ],
        },
      ],
      'sharedSettlements': [
        {
          'id': 'ss-sale',
          'skuIds': ['sku-1', 'sku-2'],
          'billType': '应收账单 / 销售款 / 电子券销售款',
          'settleRatio': '0.926',
        },
      ],
    });
    expect(form['costItemAmounts']['平台交易服务费'], 2.4);
    expect(form['projectCost'], 2.4);
    expect(
      proposalProjectCostFormulaSubstitution(form, '平台交易服务费'),
      '(200 + 400) × 0.004 = 2.40 万元',
    );
  });

  test('project cost keeps per-sku ratio when both products fill payable', () {
    final form = proposalApplyEstimatedFinanceCosts({
      'skuDetails': [
        {
          'id': 'sku-1',
          'settlements': [
            {'id': 'st-1', 'scale': '200'},
            {
              'id': 'st-pay',
              'billType': '应付账单 / 服务费 / 平台服务费',
              'settleRatio': '0.004',
            },
          ],
        },
        {
          'id': 'sku-2',
          'settlements': [
            {'id': 'st-2', 'scale': '400'},
            {
              'id': 'st-pay',
              'billType': '应付账单 / 服务费 / 平台服务费',
              'settleRatio': '0.005',
            },
          ],
        },
      ],
    });
    // 200×0.004 + 400×0.005 = 2.8
    expect(form['costItemAmounts']['平台交易服务费'], 2.8);
    expect(
      proposalProjectCostFormulaSubstitution(form, '平台交易服务费'),
      '200 × 0.004 + 400 × 0.005 = 2.80 万元',
    );
  });

  test('receivable bill type does not fill project cost', () {
    final form = proposalApplyEstimatedFinanceCosts({
      'skuDetails': [
        {
          'id': 'sku-1',
          'faceValue': '100',
          'settlements': [
            {
              'id': 'st-1',
              'billType': '应收账单 / 销售款 / 电子券销售款',
              'settleRatio': '0.926',
              'settleUnitPrice': '100',
              'scale': '10',
            },
          ],
        },
      ],
    });
    expect(form['costItems'] ?? const [], isEmpty);
    expect(form['projectCost'] ?? 0, 0);
  });

  test('shared settlement covers sku completeness', () {
    final issues = proposalIntakeSkuSettleIssues({
      'skuDetails': [
        {
          'id': 'sku-1',
          'productName': '现金券100',
          'settlements': [
            {'id': 'st-1'},
          ],
        },
      ],
      'sharedSettlements': [
        {
          'id': 'ss-1',
          'skuIds': ['sku-1'],
          'settleRatio': '0.926',
          'formula': '规模×比例',
          'taxRate': '13%',
        },
      ],
    });
    if (kProposalSharedSettleEnabled) {
      expect(issues, isEmpty);
    } else {
      expect(issues, contains('渠道产品「现金券100」结算一未填完结算方式对应金额、计算公式、税率'));
    }
  });

  test('historical values remain available in proposal row form', () {
    final row = ProposalIntakeRow.fromJson({
      'id': 7,
      'code': 'TA-20260819-000007',
      'status': 'draft',
      'form': {'sector': '已从配置删除的板块'},
      'review': {'marketCompleted': false},
    });

    expect(row.form['sector'], '已从配置删除的板块');
    expect(row.review['marketCompleted'], isFalse);
  });

  test('proposal list helpers resolve initiator and stakeholders', () {
    final row = ProposalIntakeRow.fromJson({
      'id': 9,
      'code': 'TA-20260820-000009',
      'status': 'draft',
      'createdBy': 11,
      'form': {
        'marketOwner2': '王奕凡',
        'marketOwner2UserId': 11,
        'operator': '李运营',
        'operatorUserId': 31,
      },
    });
    const people = [
      ProposalPerson(userId: 11, name: '王奕凡', positionName: '市场部负责人二'),
      ProposalPerson(userId: 21, name: '赵总裁', positionName: '总裁'),
    ];
    expect(row.initiatorDisplayName(people), '王奕凡');
    expect(
      row
          .copyWith(
            form: {
              ...row.form,
              'marketOwner2': '吴姝瑶',
              'marketOwner2UserId': 99,
            },
          )
          .initiatorDisplayName(people),
      '王奕凡',
    );
    expect(row.canDeleteBy(11), isTrue);
    expect(row.canDeleteBy(31), isFalse);
    final lines = row.stakeholderLines(
      people: people,
      options: ProposalIntakeOptions.fromJson({
        'people': {
          'presidentUserIds': [21],
          'presidents': [
            {'userId': 21, 'name': '赵总裁'},
          ],
        },
      }),
    );
    expect(
      lines.map((item) => '${item.role}:${item.name}').toList(),
      containsAll([
        '创建人:王奕凡',
        '市场部负责人二:王奕凡',
        '运营:李运营',
        '市场部负责人一:未指定',
        '最终确认人:赵总裁',
      ]),
    );

    final reviewing = row.copyWith(status: 'reviewing');
    expect(reviewing.canDeleteBy(11), isTrue);
    expect(
      reviewing.copyWith(status: 'pending_president').canDeleteBy(11),
      isFalse,
    );
    expect(reviewing.copyWith(status: 'done').canDeleteBy(11), isFalse);
  });

  test('proposal row reads stage and myAction', () {
    final row = ProposalIntakeRow.fromJson({
      'id': 8,
      'code': 'TA-20260820-000008',
      'title': '华东渠道合作',
      'status': 'reviewing',
      'myAction': 'review_market',
      'review': {'stage': 'reviewing'},
    });
    expect(row.resolvedStage, 'reviewing');
    expect(row.myAction, 'review_market');
    expect(proposalIntakeActionLabel('submit_president'), '待通知最终人');
    expect(proposalIntakeActionLabel('fill'), '待填写');
    expect(proposalIntakeActionLabel('fill_finance_interface'), '待填写财务技术接口');
    expect(proposalIntakeActionLabel('review_finance_interface'), '待复核财务技术接口');
    expect(proposalIntakeActionLabel('revise'), '最终人已驳回请从头填写');
    expect(proposalIntakeActionLabel('revise_module'), '板块已驳回请修改');
  });

  test('notify recipients list names for tech handoff', () {
    final row = ProposalIntakeRow.fromJson({
      'createdBy': 2,
      'form': {
        'technologyOwner': '张科技',
        'technologyOwnerUserId': 3,
        'financeOwner2': '李财务',
        'financeOwner2UserId': 5,
      },
      'review': {'stage': 'filling'},
    });
    final items = proposalIntakeNotifyRecipients(
      action: 'notify_tech',
      row: row,
    );
    expect(items.map((item) => item.line).toList(), [
      '科技部负责人 张科技 · 请填写科技部内容',
      '财务部负责人二 李财务 · 请填写财务技术接口',
    ]);
    expect(proposalIntakeNotifiedToast(items), '已通知：张科技（科技部负责人）、李财务（财务部负责人二）');
    final write = ProposalIntakeWriteResult.fromJson({
      'id': 8,
      'notified': [
        {'userId': 3, 'role': '科技部负责人', 'name': '张科技', 'task': '请填写科技部内容'},
      ],
    });
    expect(write.row.id, 8);
    expect(write.notified.single.name, '张科技');
  });

  test('remind recipients skip finished reviewers', () {
    final row = ProposalIntakeRow.fromJson({
      'createdBy': 2,
      'kind': 'sales',
      'status': 'reviewing',
      'form': {
        'createdByName': '朱子姝',
        'marketOwner1': '黄永刚',
        'marketOwner1UserId': 4,
        'marketOwner2UserId': 21,
        'technologyOwnerUserId': 3,
        'financeOwner2UserId': 5,
        'financeOwner1UserId': 6,
      },
      'review': {
        'stage': 'reviewing',
        'technologyCompleted': true,
        'financeInterfaceCompleted': true,
        'purchaseContractCompleted': true,
        'salesContractCompleted': true,
      },
    });
    final items = proposalIntakeRemindRecipients(row: row);
    expect(items.map((item) => item.userId).toSet(), {4, 5, 6});
    expect(items.first.line, '市场部负责人一 黄永刚 · 请复核市场部板块');
  });

  test('remind filling only pings the submitter, not all assigned people', () {
    final row = ProposalIntakeRow.fromJson({
      'createdBy': 1,
      'status': 'filling',
      'form': {
        'createdByName': '朱子姝',
        'technologyOwner': '吴小姣',
        'technologyOwnerUserId': 10,
        'financeOwner2': '朱子姝',
        'financeOwner2UserId': 1,
        'marketOwner1': '黄永刚',
        'marketOwner1UserId': 4,
      },
      'review': {'stage': 'filling'},
    });
    final items = proposalIntakeRemindRecipients(row: row);
    expect(items.map((item) => item.userId).toSet(), {1});
    expect(items.single.line, '提交人 朱子姝 · 请填写');
  });

  test('remind pending president includes configured presidents', () {
    final options = ProposalIntakeOptions.fromJson({
      'people': {
        'presidentUserIds': [88],
        'presidents': [
          {'userId': 88, 'name': '许正阳'},
        ],
      },
    });
    final row = ProposalIntakeRow.fromJson({
      'kind': 'sales',
      'status': 'pending_president',
      'createdBy': 1,
      'form': {'createdByName': '朱子姝', 'technologyOwnerUserId': 10},
      'review': {'stage': 'pending_president'},
    });
    final items = proposalIntakeRemindRecipients(row: row, options: options);
    expect(items.map((item) => item.userId).toSet(), {88});
    expect(items.single.line, '最终确认人 许正阳 · 请查看提案并给出意见');
  });

  test('review complete notifies submitter only after last flag', () {
    final row = ProposalIntakeRow.fromJson({
      'createdBy': 2,
      'kind': 'sales',
      'form': {'createdByName': '朱子姝'},
      'review': {
        'stage': 'reviewing',
        'marketCompleted': true,
        'technologyCompleted': true,
        'financeInterfaceCompleted': true,
        'financeCompleted': true,
        'purchaseContractCompleted': true,
      },
    });
    expect(
      proposalIntakeAfterReviewNotifyRecipients(
        row: row,
        flag: 'salesContractCompleted',
        approved: true,
      ).single.line,
      '提交人 朱子姝 · 请通知最终人',
    );
    expect(
      proposalIntakeAfterReviewNotifyRecipients(
        row: row,
        flag: 'financeCompleted',
        approved: true,
      ),
      isEmpty,
    );
  });

  test('review action labels use reviewer name only', () {
    expect(proposalIntakeActionLabel('review_market'), '待复核市场部');
    expect(proposalIntakeActionLabel('review_finance'), '待复核财务');
    expect(
      proposalIntakeActionLabel(
        'review_market',
        row: ProposalIntakeRow.fromJson({
          'form': {'marketOwner1': '黄永刚', 'marketOwner1UserId': 8},
        }),
      ),
      '待黄永刚复核',
    );
    expect(
      proposalIntakeActionLabel(
        'review_tech',
        row: ProposalIntakeRow.fromJson({
          'form': {'marketOwner2UserId': 9},
        }),
        people: const [
          ProposalPerson(userId: 9, name: '李市场', positionName: ''),
        ],
      ),
      '待李市场复核',
    );
    expect(
      proposalIntakeActionLabel(
        'review_finance',
        row: ProposalIntakeRow.fromJson({
          'form': {'financeOwner2': '财务乙'},
        }),
      ),
      '待财务乙复核',
    );
    expect(
      proposalIntakeActionLabel(
        'review_finance_module',
        row: ProposalIntakeRow.fromJson({
          'form': {'financeOwner1UserId': 3},
        }),
      ),
      '待整板块复核财务',
    );
    expect(
      proposalIntakeActionLabel(
        'review_finance_module',
        row: ProposalIntakeRow.fromJson({
          'form': {'financeOwner1': '刘雨滴', 'financeOwner1UserId': 3},
        }),
      ),
      '待刘雨滴复核',
    );
    final pending = proposalIntakePendingReviewLabels(
      ProposalIntakeRow.fromJson({
        'status': 'reviewing',
        'kind': 'sales',
        'form': {'marketOwner1': '黄永刚', 'financeOwner2': '财务乙'},
        'review': {'stage': 'reviewing'},
      }),
    );
    expect(pending, ['待黄永刚复核', '待复核科技', '待财务乙复核']);
    expect(
      proposalIntakeListActionText(
        ProposalIntakeRow.fromJson({
          'status': 'reviewing',
          'myAction': 'review_market',
          'form': {'marketOwner1UserId': 8},
          'review': {
            'stage': 'reviewing',
            'marketCompleted': false,
            'technologyCompleted': true,
            'financeCompleted': true,
          },
        }),
      ),
      '待复核市场部',
    );
    expect(
      proposalIntakeListActionText(
        ProposalIntakeRow.fromJson({
          'status': 'reviewing',
          'form': {'marketOwner1': '王一凡', 'marketOwner2': '刘雨滴'},
          'review': {
            'stage': 'reviewing',
            'marketCompleted': false,
            'technologyCompleted': false,
            'financeCompleted': true,
          },
        }),
      ),
      '待王一凡复核  ·  待刘雨滴复核',
    );
  });

  test('clearing contract review does not reset other modules', () {
    final next = proposalIntakeClearContractReview({
      'marketCompleted': true,
      'technologyCompleted': true,
      'financeInterfaceCompleted': true,
      'financeCompleted': true,
      'purchaseContractCompleted': true,
      'salesContractCompleted': true,
      'contractItems': {'purchase.Name': true, 'sales.Name': true},
    }, prefix: 'sales');
    expect(next['marketCompleted'], isTrue);
    expect(next['technologyCompleted'], isTrue);
    expect(next['financeInterfaceCompleted'], isTrue);
    expect(next['financeCompleted'], isTrue);
    expect(next['purchaseContractCompleted'], isTrue);
    expect(next['salesContractCompleted'], isFalse);
    expect(next['contractsCompleted'], isFalse);
    expect((next['contractItems'] as Map)['purchase.Name'], isTrue);
    expect((next['contractItems'] as Map).containsKey('sales.Name'), isFalse);
  });

  test('proposal intake card shows submitter and needed action', () {
    final card = ApprovalChatShare(
      businessType: 'PROPOSAL_INTAKE',
      businessId: 8,
      title: '测试',
      status: 'reviewing',
      submitterName: '王奕凡',
      actionLabel: '请复核',
    );
    expect(card.proposalCardLine, '王奕凡 提交 · 请复核');
    expect(
      ApprovalChatShare(
        businessType: 'PROPOSAL_INTAKE',
        businessId: 8,
        title: '测试',
        status: 'reviewing',
      ).proposalCardLine,
      '协作提案 · 复核中',
    );
  });

  test('proposal intake share card payload is IM-ready', () {
    final card = ApprovalChatShare.fromProposalIntake(
      id: 8,
      title: '  ',
      status: 'filling',
      code: 'TA-2026-0008',
      submitterName: '王奕凡',
    );
    expect(card.businessType, 'PROPOSAL_INTAKE');
    expect(card.templateKey, 'proposal-intake');
    expect(card.title, '未命名销售业务提案');
    expect(card.toMessagePayload()['approvalCard'], {
      'businessType': 'PROPOSAL_INTAKE',
      'businessId': 8,
      'title': '未命名销售业务提案',
      'status': 'filling',
      'templateKey': 'proposal-intake',
      'code': 'TA-2026-0008',
      'submitterName': '王奕凡',
    });
    expect(
      ApprovalChatShare.fromListItem(card.toListItem()).isProposalIntake,
      isTrue,
    );
  });

  test('proposal intake assistant keeps instruction text besides the card', () {
    final card = ApprovalChatShare(
      businessType: 'PROPOSAL_INTAKE',
      businessId: 8,
      title: '未命名提案',
      status: 'filling',
      submitterName: '王奕凡',
      actionLabel: '请填写',
    );
    expect(
      ApprovalChatShare.proposalIntakeInstruction(
        share: card,
        bodyText: 'TA-20260820-000004 未命名提案：请填写科技部内容',
      ),
      'TA-20260820-000004 未命名提案：请填写科技部内容',
    );
    expect(
      ApprovalChatShare.proposalIntakeInstruction(
        share: card,
        bodyText: '未命名提案',
        payload: {'instruction': '请填写科技部内容。提案 TA-1「未命名提案」，请点下方名片进入。'},
      ),
      '请填写科技部内容。提案 TA-1「未命名提案」，请点下方名片进入。',
    );
    expect(
      ApprovalChatShare.proposalIntakeInstruction(
        share: card,
        bodyText: '未命名提案',
      ),
      isNull,
    );
    expect(
      ApprovalChatShare.proposalIntakeInstruction(
        share: ApprovalChatShare(
          businessType: 'PROPOSAL',
          businessId: 1,
          title: '销售提案',
        ),
        bodyText: '请审批',
      ),
      isNull,
    );
  });

  test('selecting a signed contract copies proposal-related fields', () {
    final patch = proposalIntakePatchFromContract(
      prefix: 'purchase',
      detail: {
        'id': 91,
        'contractNo': 'CG-2026-0001',
        'contractName': '框架采购合同',
        'partyA': '沙丘科技',
        'partyB': '供应商甲',
        'signDate': '2026-03-01',
        'endDate': '2027-03-01',
        'proposalRelated': {
          'purchaseName': '现金券采购合同',
          'purchaseCoreTerms': '月结 15 日',
          'supplierPolicy': '预付后供货',
          'supplySettleMode': '预付 + 月结',
          'supplyPayer': '广州宇天供应链科技有限公司',
        },
      },
    );

    expect(patch['purchaseContractId'], 91);
    expect(patch['purchaseName'], '现金券采购合同');
    expect(patch['purchaseNo'], 'CG-2026-0001');
    expect(patch['purchaseOurParty'], '沙丘科技');
    expect(patch['supplierPolicy'], '预付后供货');
    expect(patch['supplySettleMode'], '预付 + 月结');
    expect(patch['supplyPayer'], '广州宇天供应链科技有限公司');
    expect(patch['supplySettleCycle'], '');
    expect(patch['supplyPayAccount'], '');
    expect(patch.containsKey('channelPolicy'), isFalse);
    expect(patch['purchaseFileName'], '');
    expect(patch['purchaseObjectKey'], '');
  });

  test('selecting a signed contract copies the register source file', () {
    final patch = proposalIntakePatchFromContract(
      prefix: 'sales',
      detail: {
        'id': 22,
        'contractNo': 'XS-1',
        'contractName': '销售框架合同',
        'partyA': '沙丘科技',
        'partyB': '渠道甲',
        'files': [
          {
            'fileName': '已签销售合同.pdf',
            'objectKey': 'contracts/sales.pdf',
            'url': 'https://files/sales.pdf',
          },
        ],
      },
    );
    expect(patch['salesFileName'], '已签销售合同.pdf');
    expect(patch['salesObjectKey'], 'contracts/sales.pdf');
    expect(patch['salesFileUrl'], 'https://files/sales.pdf');
  });

  test(
    'selected contract number stays the register number, not AI purchaseNo',
    () {
      final patch = proposalIntakePatchFromContract(
        prefix: 'purchase',
        detail: {
          'id': 91,
          'contractNo': '2026-23-YW-00001',
          'contractName': '宣传推广服务协议',
          'proposalRelated': {
            'purchaseNo': 'Z07—3-Yw-000',
            'purchaseName': '宣传推广服务协议',
          },
        },
      );
      expect(patch['purchaseNo'], '2026-23-YW-00001');
      expect(patch['purchaseName'], '宣传推广服务协议');
    },
  );

  test('switching contracts clears previous grab fields', () {
    final first = proposalIntakePatchFromContract(
      prefix: 'purchase',
      detail: {
        'id': 91,
        'contractNo': 'CG-2026-0001',
        'contractName': '框架采购合同',
        'partyA': '沙丘科技',
        'partyB': '供应商甲',
        'signDate': '2026-03-01',
        'endDate': '2027-03-01',
        'proposalRelated': {
          'purchaseName': '现金券采购合同',
          'purchaseCoreTerms': '月结 15 日',
          'supplierPolicy': '预付后供货',
          'supplyPayer': '广州宇天供应链科技有限公司',
        },
      },
    );
    final second = proposalIntakePatchFromContract(
      prefix: 'purchase',
      detail: {
        'id': 92,
        'contractNo': 'CG-2026-0002',
        'contractName': '另一份采购合同',
        'partyA': '新甲方',
        'partyB': '新乙方',
        'signDate': '2026-06-01',
        'endDate': '2026-12-31',
      },
    );
    final form = {...first, ...second};

    expect(form['purchaseContractId'], 92);
    expect(form['purchaseNo'], 'CG-2026-0002');
    expect(form['purchaseName'], '另一份采购合同');
    expect(form['purchaseOurParty'], '新甲方');
    expect(form['purchaseCounterparty'], '新乙方');
    expect(form['purchaseSignDate'], '2026-06-01');
    expect(form['purchaseValidPeriod'], '2026-12-31');
    expect(form['purchaseCoreTerms'], '');
    expect(form['supplierPolicy'], '');
    expect(form['supplyPayer'], '');
  });

  test('confirmed contract edits keep original vs current for reviewers', () {
    final matched = proposalIntakeRememberContractSnapshot(
      form: proposalIntakePatchFromContract(
        prefix: 'purchase',
        detail: {
          'id': 91,
          'contractNo': 'CG-2026-0001',
          'contractName': '框架采购合同',
          'partyA': '沙丘科技',
          'partyB': '供应商甲',
          'proposalRelated': {'purchaseName': '现金券采购合同'},
        },
      ),
      prefix: 'purchase',
    );
    matched['purchaseName'] = '用户改过的合同名称';
    final confirmed = proposalIntakeConfirmContractEdits(matched);
    final edit = proposalIntakeContractEdit(confirmed, 'purchaseName');
    expect(edit, isNotNull);
    expect(edit!.original, '现金券采购合同');
    expect(edit.current, '用户改过的合同名称');
    expect(proposalIntakeContractEdit(confirmed, 'purchaseNo'), isNull);
  });

  test(
    'sales can fill purchase contract from an approved purchase proposal',
    () {
      expect(
        proposalIntakeHasExistingPurchaseProposal({
          'hasExistingPurchaseProposal': true,
        }),
        isTrue,
      );
      expect(
        proposalIntakeSalesMarketIssues({'hasExistingPurchaseProposal': true}),
        contains('请搜索并选择已审核通过的采购提案'),
      );
      expect(
        proposalIntakeSalesMarketIssues({'hasExistingPurchaseProposal': true}),
        isNot(contains('请选择采购合同状态')),
      );

      final patch = proposalIntakePatchFromApprovedPurchase(
        const ProposalApprovedPurchaseHit(
          id: 8,
          code: 'CG-2026-0008',
          title: '中石油供给采购',
          purchaseMode: '已签署合同',
          purchaseNo: 'CG-9',
          purchaseName: '中石油采购合同',
          purchaseSignDate: '2026-01-01',
          purchaseOurParty: '我方',
          purchaseCounterparty: '中石油',
          purchaseValidPeriod: '1年',
          purchaseCoreTerms: '月结',
          supplierPolicy: '预付后供货',
        ),
      );
      expect(patch['linkedPurchaseProposalId'], 8);
      expect(patch['purchaseName'], '中石油采购合同');
      expect(patch['purchaseNo'], 'CG-9');
      expect(patch['supplierPolicy'], '预付后供货');
      expect(patch['hasExistingPurchaseProposal'], isTrue);
    },
  );

  test('resetting contract fields clears grabbed values but keeps mode', () {
    final filled = proposalIntakePatchFromContract(
      prefix: 'purchase',
      detail: {
        'id': 91,
        'contractNo': 'CG-2026-0001',
        'contractName': '框架采购合同',
        'partyA': '沙丘科技',
        'partyB': '供应商甲',
        'signDate': '2026-03-01',
        'endDate': '2027-03-01',
        'proposalRelated': {
          'purchaseName': '现金券采购合同',
          'supplierPolicy': '预付后供货',
        },
      },
    );
    final form = <String, dynamic>{
      ...filled,
      'purchaseMode': '已签署合同',
      'purchaseFileName': 'old.pdf',
    }..addAll(proposalIntakeResetContractFields('purchase'));
    form['purchaseMode'] = '未签署合同';

    expect(form['purchaseMode'], '未签署合同');
    expect(form['purchaseContractId'], isNull);
    expect(form['purchaseName'], '');
    expect(form['purchaseOurParty'], '');
    expect(form['purchaseCounterparty'], '');
    expect(form['purchaseSignDate'], '');
    expect(form['purchaseValidPeriod'], '');
    expect(form['supplierPolicy'], '');
    expect(form['purchaseFileName'], '');
  });

  test('next proposal skips the current item and does not wrap', () {
    ProposalIntakeRow row(int id) => ProposalIntakeRow.fromJson({
      'id': id,
      'code': 'TA-$id',
      'status': 'pending_president',
    });
    final items = [row(1), row(2), row(3)];
    expect(nextProposalIntake(items: items, currentId: 1)?.id, 2);
    expect(nextProposalIntake(items: items, currentId: 3), isNull);
    expect(
      nextProposalIntake(items: items, currentId: 1, afterDecision: true)?.id,
      2,
    );
    expect(
      nextProposalIntake(items: items, currentId: 9, afterDecision: true)?.id,
      1,
    );
    expect(
      nextProposalIntake(items: [row(1)], currentId: 1, afterDecision: true),
      isNull,
    );
  });

  test('proposal list time converts utc to local without Z', () {
    expect(formatProposalIntakeDateTime(''), '');
    final formatted = formatProposalIntakeDateTime('2026-08-20T13:26:19.123Z');
    expect(formatted.contains('Z'), isFalse);
    expect(formatted.contains('T'), isFalse);
    final local = DateTime.parse('2026-08-20T13:26:19Z').toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    expect(
      formatted,
      '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}',
    );
  });

  test('review assignees are required before handoff', () {
    expect(missingProposalReviewAssignees({}), [
      '科技部负责人',
      '市场部负责人二',
      '市场部负责人一',
      '财务部负责人一',
      '财务部负责人二',
      '运营',
    ]);
    expect(
      missingProposalReviewAssignees({
        'technologyOwnerUserId': '3',
        'marketOwner2UserId': '2',
        'marketOwner1UserId': '4',
        'financeOwner1UserId': '6',
        'financeOwner2UserId': '5',
        'operatorUserId': '7',
      }),
      isEmpty,
    );
    expect(
      missingProposalReviewAssignees({
        'technologyOwnerUserId': '3',
      }, includeTech: false),
      ['市场部负责人二', '市场部负责人一', '财务部负责人一', '财务部负责人二', '运营'],
    );
    expect(
      missingProposalReviewAssignees({
        'technologyOwnerUserId': '3',
        'marketOwner2UserId': '2',
        'marketOwner1UserId': '4',
        'financeOwner1UserId': '6',
        'financeOwner2UserId': '5',
      }, purchase: true),
      ['运营'],
    );
    expect(
      missingProposalReviewAssignees({
        'technologyOwnerUserId': '3',
        'marketOwner2UserId': '2',
        'marketOwner1UserId': '4',
        'financeOwner1UserId': '6',
        'financeOwner2UserId': '5',
        'operatorUserId': '8',
      }, purchase: true),
      isEmpty,
    );
    expect(missingProposalReviewAssignees({}, purchase: true), [
      '科技部负责人',
      '市场部负责人二',
      '市场部负责人一',
      '财务部负责人一',
      '财务部负责人二',
      '运营',
    ]);
  });

  test('auto-filled owner alone is not enough to create a draft', () {
    final row = ProposalIntakeRow.fromJson({
      'id': 0,
      'status': 'draft',
      'form': {
        'marketOwner2': '王奕凡',
        'marketOwner2UserId': 11,
        'supplies': <String>[],
        'channels': <String>[],
        'profitModes': <String>[],
        'technologyCapabilities': <String>[],
        'outputForms': <String>[],
        'developmentTypes': <String>[],
        'costItems': <String>[],
        'purchaseProducts': <String>[],
        'financeInterfaces': <String, dynamic>{},
      },
    });
    expect(proposalIntakeHasMeaningfulContent(row), isFalse);
  });

  test('filled proposal name or title can create a draft', () {
    expect(
      proposalIntakeHasMeaningfulContent(
        ProposalIntakeRow.fromJson({
          'form': {'marketOwner2': '王奕凡', 'proposalName': '智能投放试点'},
        }),
      ),
      isTrue,
    );
    expect(
      proposalIntakeHasMeaningfulContent(
        ProposalIntakeRow.fromJson({'title': '智能投放试点'}),
      ),
      isTrue,
    );
    expect(
      proposalIntakeHasMeaningfulContent(
        ProposalIntakeRow.fromJson({
          'form': {
            'marketOwner2': '王奕凡',
            'supplies': ['头部媒体供给'],
          },
        }),
      ),
      isTrue,
    );
  });

  test('done proposal keeps tech revision stage from review', () {
    final row = ProposalIntakeRow.fromJson({
      'id': 8,
      'status': 'done',
      'form': {
        'technologyRecords': [
          {'id': 'rec_1', 'title': '对接程序1', 'technologyPlatform': '能源平台'},
        ],
        'technologyHistory': [
          {'round': 1, 'technologyPlatform': '旧平台'},
        ],
      },
      'review': {'stage': 'tech_revising', 'techRevisionRound': 2},
    });
    expect(row.resolvedStage, 'tech_revising');
    expect(row.techRevisionRound, 2);
    expect(row.isTechRevising, isTrue);
    expect(row.isTechReviewing, isFalse);
    expect(proposalIntakeTechnologyRecords(row.form).single.title, '对接程序1');
    expect(proposalIntakeTechnologyHistory(row.form).single.platform, '旧平台');
  });

  test('append technology record copies the live tech snapshot', () {
    final next = proposalIntakeAppendTechnologyRecord({
      'technologyPlatform': '能源平台',
      'technologyCapabilities': ['发放'],
      'deliveryDate': '2026-09-01',
      'financeInterfaces': {'face': true},
    });
    final records = proposalIntakeTechnologyRecords(next);
    expect(records, hasLength(1));
    expect(records.single.title, '对接记录1');
    expect(records.single.platform, '能源平台');
    expect(records.single.capabilities, ['发放']);
  });

  test('market review waits for technology during tech revision', () {
    expect(
      proposalIntakeMarketReviewBlocked({
        'stage': 'tech_reviewing',
        'technologyCompleted': false,
      }),
      isTrue,
    );
    expect(
      proposalIntakeMarketReviewBlocked({
        'stage': 'tech_reviewing',
        'technologyCompleted': true,
      }),
      isFalse,
    );
    expect(
      proposalIntakeMarketReviewBlocked({
        'stage': 'reviewing',
        'technologyCompleted': false,
      }),
      isFalse,
    );
  });

  test('unchanged finance interfaces skip finance re-review', () {
    expect(
      proposalIntakeFinanceInterfacesUnchanged(
        form: {
          'financeInterfaces': {'face': true},
        },
        review: {
          'lastFinanceInterfaces': {'face': true},
        },
      ),
      isTrue,
    );
    expect(
      proposalIntakeFinanceInterfacesUnchanged(
        form: {
          'financeInterfaces': {'face': true, 'settle': true},
        },
        review: {
          'lastFinanceInterfaces': {'face': true},
        },
      ),
      isFalse,
    );
  });

  test('tech revision action labels', () {
    expect(proposalIntakeActionLabel('start_tech_revision'), '待发起科技变更');
    expect(proposalIntakeActionLabel('fill_tech'), '待填写科技');
    expect(proposalIntakeActionLabel('fill_finance_interface'), '待填写财务技术接口');
    expect(proposalIntakeActionLabel('review_finance_interface'), '待复核财务技术接口');
  });

  test('launch row without channel links or reuses finance module', () {
    const row = ProposalLaunchRow(
      id: 'lr-1',
      province: '河南',
      faceValue: '100',
      needFinanceModule: true,
    );
    final created = proposalIntakeLinkFinanceModule(
      rows: const [row],
      modules: const [],
      launchRowId: 'lr-1',
    );
    expect(created.modules, hasLength(1));
    expect(created.rows.single.financeModuleId, created.modules.single.id);

    final associated = proposalIntakeLinkFinanceModule(
      rows: [
        const ProposalLaunchRow(
          id: 'lr-2',
          province: '广东',
          faceValue: '100',
          needFinanceModule: true,
        ),
      ],
      modules: created.modules,
      launchRowId: 'lr-2',
      associateModuleId: created.modules.single.id,
    );
    expect(associated.modules, hasLength(1));
    expect(associated.rows.single.financeModuleId, created.modules.single.id);
  });

  test('settlement terms map bill-type fields and keep legacy price/rule', () {
    final legacy = ProposalFinanceSettleTerms.fromJson({
      'settlePrice': '1.2%',
      'settleRule': '核销结算',
      'counterparty': '中石化',
      'ourParty': '沙丘',
      'taxRate': '6%',
    });
    expect(legacy.displayRatio, '1.2%');
    expect(legacy.displayFormula, '核销结算');
    expect(legacy.isComplete, isTrue);

    final next = ProposalFinanceSettleTerms.fromJson({
      'billType': '电子券销售款',
      'settleMode': '按结算比例',
      'settleRatio': '8%',
      'formula': '销售额*比例',
      'invoiceType': '专票',
      'taxRate': '6%',
      'effectiveTime': '2026-08-01',
      'expireTime': '2026-12-31',
      'counterparty': '中石化',
      'ourParty': '沙丘',
    });
    expect(next.resolvedPrice, '8%');
    expect(next.toJson()['settlePrice'], '8%');
    expect(next.toJson()['settleRule'], '销售额*比例');
    expect(next.toJson()['billType'], '电子券销售款');
  });

  test('each product gets one settlement and can add more', () {
    const sku = ProposalSkuDetailRow(id: 'sku-1', productName: '中石油100元');
    final first = proposalIntakeSkuSettlements(sku);
    expect(first, hasLength(1));
    expect(first.single.id, 'sku-1-st-1');
    expect(proposalIntakeSettleLabel(0), '结算一');
    expect(proposalIntakeSettleLabel(1), '结算二');

    final saved = sku.copyWith(
      settlements: [
        const ProposalSkuSettleRow(id: 'st-a'),
        const ProposalSkuSettleRow(id: 'st-b'),
      ],
    );
    expect(proposalIntakeSkuSettlements(saved), hasLength(2));
    expect(
      proposalIntakeSkuSettleReviewKeys({
        'skuDetails': [saved.toJson()],
      }),
      ['skuSettle:sku-1:st-a', 'skuSettle:sku-1:st-b'],
    );
  });

  test('existing built sku name is not treated as extra manual details', () {
    const named = ProposalSkuDetailRow(
      id: 'sku-1',
      productName: '江苏中石油300元电子券（北京中抚）',
      existingBuilt: '是',
      assetProduct: ChannelProductHit(
        id: 88,
        productName: '江苏中石油300元电子券（北京中抚）',
      ),
    );
    expect(proposalIntakeSkuHasManualDetails(named), isFalse);
    expect(
      proposalIntakeSkuHasManualDetails(named.copyWith(faceValue: '300')),
      isTrue,
    );
  });

  test('sku settle issues match backend required fields', () {
    expect(
      proposalIntakeSkuSettleIssues({
        'skuDetails': [
          {'id': 'sku-1', 'productName': ''},
        ],
      }),
      isEmpty,
    );
    expect(
      proposalIntakeSkuSettleIssues({'isExistingBuilt': true}),
      contains('已勾选已建产品，请至少添加一条渠道产品并搜索选择已建产品'),
    );
    expect(
      proposalIntakeSkuSettleIssues({
        'skuDetails': [
          {'id': 'sku-1', 'productName': '中石油100元'},
        ],
      }),
      contains('渠道产品「中石油100元」结算一未填完结算方式对应金额、计算公式、税率'),
    );
    expect(
      proposalIntakeSkuSettleIssues({
        'skuDetails': [
          {
            'id': 'sku-1',
            'productName': '中石油100元',
            'settlements': [
              {
                'id': 'st-1',
                'settleMode': '按结算比例',
                'settleRatio': '8%',
                'formula': '销售额*比例',
                'taxRate': '6%',
              },
            ],
          },
        ],
      }),
      isEmpty,
    );
  });

  test('legacy coupon pack json does not change sku settlement review', () {
    final form = {
      'isCouponPack': true,
      'skuDetails': [
        {
          'id': 'sku-1',
          'productName': '中石油100元',
          'settlements': [
            {
              'id': 'st-a',
              'settleMode': '按结算比例',
              'settleRatio': '8%',
              'formula': '销售额*比例',
              'taxRate': '6%',
            },
            {'id': 'st-b'},
          ],
        },
      ],
      'couponPacks': [
        {
          'id': 'pack-1',
          'name': '中石油加油券包',
          'skuIds': ['sku-1'],
          'settlements': [
            {
              'id': 'st-a',
              'settleMode': '按结算比例',
              'settleRatio': '8%',
              'formula': '销售额*比例',
              'taxRate': '6%',
            },
          ],
        },
      ],
    };
    expect(proposalIntakeSkuSettleReviewKeys(form), [
      'skuSettle:sku-1:st-a',
      'skuSettle:sku-1:st-b',
    ]);
    expect(
      proposalIntakeSkuSettleIssues(form),
      contains('渠道产品「中石油100元」结算二未填完结算方式对应金额、计算公式、税率'),
    );
    expect(
      proposalIntakeSkuSettleIssues({
        'isExistingBuilt': true,
        'isCouponPack': true,
      }),
      contains('已勾选已建产品，请至少添加一条渠道产品并搜索选择已建产品'),
    );
    expect(
      proposalIntakeSkuSettleIssues({
        'isCouponPack': true,
        'skuDetails': [
          {'id': 'sku-1', 'productName': '中石油100元'},
        ],
      }),
      isNot(contains('券包')),
    );
  });

  test('same settlement fingerprint can be reused', () {
    const terms = ProposalFinanceSettleTerms(
      settlePrice: '1.2%',
      settleRule: '核销结算',
      counterparty: '中石化',
      ourParty: '沙丘科技',
      taxRate: '6%',
    );
    const a = ProposalFinanceModule(id: 'fm-a', revenue: terms);
    const b = ProposalFinanceModule(id: 'fm-b', revenue: terms);
    expect(proposalIntakeMatchingFinanceModule([a], b), a);
    expect(
      proposalIntakeMatchingFinanceModule([
        a,
      ], const ProposalFinanceModule(id: 'fm-c')),
      isNull,
    );
  });

  test('finance modules are validated without launch rows', () {
    expect(
      proposalIntakeLaunchFinanceIssues({
        'launchRows': [
          {
            'id': 'lr-1',
            'province': '河南',
            'faceValue': '100',
            'needFinanceModule': true,
          },
        ],
      }),
      isEmpty,
    );
  });

  test('finance module period is required and parsed from json', () {
    final natural = ProposalFinanceModule.fromJson({
      'id': 'fm-1',
      'title': '模块甲',
      'naturalMonth': true,
      'revenue': {
        'settlePrice': '1.2%',
        'settleRule': '核销结算',
        'counterparty': '中石化',
        'ourParty': '沙丘',
        'taxRate': '6%',
      },
    });
    expect(natural.naturalMonth, '是');
    expect(natural.periodComplete, isTrue);
    expect(natural.usesProjectPeriod, isFalse);

    final missingPeriod = ProposalFinanceModule.fromJson({
      'id': 'fm-2',
      'title': '模块乙',
      'naturalMonth': '否',
    });
    expect(missingPeriod.usesProjectPeriod, isTrue);
    expect(missingPeriod.periodComplete, isFalse);

    final withPeriod = missingPeriod.copyWith(
      projectPeriodStart: '2026-01-15',
      projectPeriodEnd: '2026-02-14',
    );
    expect(withPeriod.periodComplete, isTrue);
    expect(withPeriod.projectPeriodLabel, '2026-01-15 ~ 2026-02-14');
    expect(
      proposalIntakeLaunchFinanceIssues({
        'financeModules': [missingPeriod.toJson()],
      }),
      contains('财务模块「模块乙」非自然月请选择项目周期'),
    );
    expect(
      proposalIntakeLaunchFinanceIssues({
        'financeModules': [
          {'id': 'fm-1', 'title': '模块甲'},
        ],
      }),
      contains('财务模块「模块甲」请选择是否自然月'),
    );
  });

  test('natural month vs project period do not share fingerprint', () {
    const terms = ProposalFinanceSettleTerms(
      settlePrice: '1.2%',
      settleRule: '核销结算',
      counterparty: '中石化',
      ourParty: '沙丘科技',
      taxRate: '6%',
    );
    const natural = ProposalFinanceModule(
      id: 'fm-a',
      naturalMonth: '是',
      revenue: terms,
    );
    const project = ProposalFinanceModule(
      id: 'fm-b',
      naturalMonth: '否',
      projectPeriodStart: '2026-01-15',
      projectPeriodEnd: '2026-02-14',
      revenue: terms,
    );
    expect(proposalIntakeMatchingFinanceModule([natural], project), isNull);
    expect(
      proposalIntakeMatchingFinanceModule(
        [natural],
        const ProposalFinanceModule(
          id: 'fm-c',
          naturalMonth: '是',
          revenue: terms,
        ),
      ),
      natural,
    );
  });

  test('catalog refs round-trip with id/code/name for third-party export', () {
    const sector = CatalogRef(id: 1, code: 'NY', name: '能源');
    const pointsA = CatalogRef(code: 'POINTS_REBATE', name: '能源积分');
    const pointsB = CatalogRef(code: 'POINTS_REBATE', name: '能源返费');
    expect(pointsA == pointsB, isFalse);

    final terms = ProposalFinanceSettleTerms(
      billType: '电子券销售款',
      billTypeRef: const CatalogRef(id: 8, code: 'XS', name: '电子券销售款'),
      channelRef: const CatalogRef(id: 1, code: 'C001', name: '银联商务'),
      settleMode: '按结算比例结算',
      settleModeRef: const CatalogRef(code: '1', name: '按结算比例结算'),
      settleRatio: '8%',
      formula: '按比例',
      formulaRef: const CatalogRef(
        code: '101',
        name: '按比例',
        formulaExpression: '结算金额=面值×比例',
        productSource: 'CHANNEL',
      ),
      taxRate: '6%',
    );
    final json = terms.toJson();
    expect(json['billTypeRef'], {'id': 8, 'code': 'XS', 'name': '电子券销售款'});
    expect(json['channelRef'], {'id': 1, 'code': 'C001', 'name': '银联商务'});
    expect(json['settleModeRef'], {'code': '1', 'name': '按结算比例结算'});
    expect(json['formulaRef'], {
      'code': '101',
      'name': '按比例',
      'formulaExpression': '结算金额=面值×比例',
      'productSource': 'CHANNEL',
    });

    final restored = ProposalFinanceSettleTerms.fromJson(json);
    expect(restored.billTypeRef?.id, 8);
    expect(restored.channelRef?.code, 'C001');
    expect(restored.settleModeRef?.code, '1');
    expect(restored.formulaRef?.formulaExpression, '结算金额=面值×比例');
    expect(proposalIntakeSettleUsesRatio(restored), isTrue);

    final sku = ProposalSkuDetailRow(
      id: 'sku-1',
      productName: '中石油100元',
      syncSourceRef: const CatalogRef(code: 'DIGITALG', name: '能源'),
    );
    expect(sku.toJson()['syncSource'], 'DIGITALG');
    expect(sku.toJson()['syncSourceRef']['name'], '能源');
    expect(sector.toJson()['code'], 'NY');

    final categorized = ProposalSkuDetailRow.fromJson({
      'id': 'sku-2',
      'productName': '出行券',
      'channelCategoryL1': '出行',
      'channelCategoryL2Ref': {
        'code': 'CXQYJ',
        'name': '出行权益金',
        'parentCode': 'CX',
        'parentName': '出行',
      },
    });
    expect(categorized.resolvedChannelCategoryL1?.name, '出行');
    expect(categorized.toJson()['channelCategoryL2'], '出行权益金');
    expect(
      proposalIntakeChannelCategoryChildOf(
        categorized.resolvedChannelCategoryL2!,
        categorized.resolvedChannelCategoryL1!,
      ),
      isTrue,
    );
  });

  test(
    'purchase supply product maps productId to supplierCode and default settlements',
    () {
      final created = proposalIntakeNewSupplyProduct();
      expect(created.supplierCode, isEmpty);
      expect(created.settlements, hasLength(1));
      expect(created.settlements.single.terms.billType, isEmpty);

      final restored = ProposalSupplyProductRow.fromJson({
        'id': 'supply-1',
        'productId': 'SP-001',
        'productCode': 'NY-100',
        'thresholdAmount': '100',
        'supplierRef': {'id': 8, 'code': 'SUP-1', 'name': '中石油'},
        'assetProduct': {
          'id': 20,
          'productName': '中石油供给100',
          'productCode': 'NY-100',
          'supplierCode': 'SUP-1',
          'supplierName': '中石油',
        },
        'settlements': [
          {'id': 'st-1', 'billType': '电子券采购款'},
        ],
      });
      expect(restored.supplierCode, 'SP-001');
      expect(restored.productCode, 'NY-100');
      expect(restored.toJson()['productCode'], 'NY-100');
      expect(restored.supplierRef?.name, '中石油');
      expect(restored.assetProduct?.productName, '中石油供给100');
      expect(
        proposalIntakeSupplyProducts({
          'supplyProducts': [restored.toJson()],
        }),
        hasLength(1),
      );
    },
  );

  test('purchase required fields fail until filled', () {
    expect(proposalIntakePurchaseMarketIssues({}), isNotEmpty);
    expect(proposalIntakePurchaseTechIssues({}), contains('请填写τ-标签一'));
    expect(proposalIntakePurchaseHunIssue({}), '请填写 HUN ID');
    final form = <String, dynamic>{
      'proposalType': '新增',
      'supplies': ['头部媒体供给'],
      'supplyBrand': '中石油',
      'bizContact': '张三',
      'financeContact': '李四',
      'invoiceTypes': ['增值税专用发票'],
      'supplierPolicy': '供货政策',
      'salesPolicy': '销售政策',
      'executionPlan': '执行计划',
      'riskPoints': '风险点',
      'financeRemark': '财务备注',
      'hunId': 'HUN-1',
      'purchaseMode': '已签署合同',
      'purchaseNo': 'CG-1',
      'purchaseName': '采购合同',
      'purchaseSignDate': '2026-01-01',
      'purchaseOurParty': '我方',
      'purchaseCounterparty': '对方',
      'purchaseValidPeriod': '1年',
      'purchaseCoreTerms': '条款',
      'technologyPlatform': '数据智能平台',
      'technologyCapabilities': ['人群圈选能力'],
      'outputForms': ['API接口'],
      'developmentTypes': ['运营配置'],
      'hasRdCost': '否',
      'deliveryDate': '2026-12-01',
      'supplyProducts': [
        {
          'id': 's1',
          'supplierCode': 'SUP-1',
          'productCode': 'SP-100',
          'syncSource': 'P1',
          'thresholdAmount': '100',
          'isYuantongCoupon': '否',
          'isStandaloneRebate': '否',
          'isLowDiscountCoupon': '否',
          'rebateMode': '消费返',
          'oilCategory': '汽油',
          'effectiveDate': '2026-01-01',
          'expireDate': '2026-12-31',
          'settlements': [
            {
              'id': 'st-1',
              'billType': '电子券采购款',
              'settleMode': '比例',
              'settleRatio': '3%',
              'formula': '销售额*比例',
              'invoiceType': '增值税专用发票',
              'taxRate': '6%',
              'effectiveTime': '2026-01-01',
              'expireTime': '2026-12-31',
            },
          ],
        },
      ],
    };
    expect(proposalIntakePurchaseMarketIssues(form), isEmpty);
    expect(proposalIntakePurchaseTechIssues(form), isEmpty);
    expect(proposalIntakePurchaseHunIssue(form), isNull);
  });

  test(
    'purchase supply products skip empty cards unless existing or started',
    () {
      expect(
        proposalIntakePurchaseSupplyIssues({
          'supplyProducts': [
            {'id': 's1'},
          ],
        }),
        isEmpty,
      );
      expect(
        proposalIntakePurchaseSupplyIssues({'isExistingSupplyProduct': true}),
        contains('已勾选已有供给产品，请至少添加一条并搜索选择已建供给产品'),
      );
      expect(
        proposalIntakePurchaseSupplyIssues({
          'isExistingSupplyProduct': true,
          'supplyProducts': [
            {'id': 's1', 'syncSource': 'P1'},
          ],
        }),
        contains('供给产品 1 请搜索并选择已建供给产品'),
      );
      expect(
        proposalIntakePurchaseSupplyIssues({
          'supplyProducts': [
            {
              'id': 's1',
              'syncSource': 'P1',
              'supplierRef': {'id': 8, 'code': 'SUP-1', 'name': '中石油'},
            },
          ],
        }),
        contains('供给产品 1 请填写门槛金额'),
      );
      expect(
        proposalIntakePurchaseSupplyIssues({
          'supplyProducts': [
            {
              'id': 's1',
              'syncSource': 'P1',
              'supplierRef': {'id': 8, 'code': 'SUP-1', 'name': '中石油'},
            },
          ],
        }),
        contains('供给产品 1 请填写产品编码'),
      );
      expect(
        proposalIntakePurchaseSupplyIssues({
          'isExistingSupplyProduct': true,
          'supplyProducts': [
            {
              'id': 's1',
              'syncSource': 'P1',
              'assetProduct': {
                'id': 10,
                'productName': '中石油供给',
                'supplierCode': 'SUP-1',
                'supplierName': '中石油',
              },
              'settlements': [
                {
                  'id': 'st-1',
                  'billType': '电子券采购款',
                  'settleMode': '比例',
                  'settleRatio': '3%',
                  'formula': '销售额*比例',
                  'invoiceType': '增值税专用发票',
                  'taxRate': '6%',
                  'effectiveTime': '2026-01-01',
                  'expireTime': '2026-12-31',
                },
              ],
            },
          ],
        }),
        isEmpty,
      );
    },
  );

  test('purchase supply settle lists only missing fields', () {
    final form = <String, dynamic>{
      'isExistingSupplyProduct': true,
      'supplyProducts': [
        {
          'id': 's1',
          'syncSource': 'P1',
          'assetProduct': {
            'id': 10,
            'productName': '团油',
            'supplierCode': 'SUP-1',
            'supplierName': '中石油',
          },
          'settlements': [
            {
              'id': 'st-1',
              'billType': '应付账单 / 采购款 / 团油采购款',
              'settleMode': '按结算比例结算',
              'settleModeRef': {'code': '1', 'name': '按结算比例结算'},
              'settleRatio': '1%',
              'formula': '团油供货价*结算比',
              'invoiceType': '电子专用发票',
              'taxRate': '6%',
              'effectiveTime': '2025-12-20',
            },
          ],
        },
      ],
    };
    expect(
      proposalIntakePurchaseSupplyIssues(form),
      contains('供给产品 1 结算一未填完：失效时间'),
    );
    expect(
      proposalIntakePurchaseSupplyIssues(form).join(),
      isNot(contains('账单类型')),
    );
  });

  test('sales fill fields are required except optional products', () {
    final empty = proposalIntakeSalesMarketIssues({});
    expect(empty, contains('请选择业务板块'));
    expect(empty, contains('请填写产品提案名称'));
    expect(empty, isNot(contains('请填写子标题')));
    expect(empty, contains('请选择产品（标签一）'));
    expect(empty, contains('请选择供给（标签二）'));
    expect(empty, isNot(contains('请选择渠道（标签三）')));
    expect(empty, contains('请填写盈利计算说明'));
    expect(empty, contains('请选择采购合同状态'));
    expect(empty, contains('请选择销售合同状态'));
    expect(
      proposalIntakeTechFillIssues({}, purchase: false),
      contains('请填写τ-标签一'),
    );
    expect(
      proposalIntakeSalesFinanceFillIssues({}),
      contains('请在产品结算中填写规模（万元）'),
    );
    expect(
      proposalIntakeSalesFinanceFillIssues({}),
      isNot(contains('请填写销售规模目标（年·万元）')),
    );
    expect(proposalIntakeSalesFinanceFillIssues({}), isNot(contains('请填写税率')));
    expect(
      proposalIntakeSalesFinanceFillIssues({}),
      isNot(contains('请填写核销金额（万元）')),
    );
    expect(
      proposalIntakeSalesFinanceFillIssues({}),
      isNot(contains('请填写发票（万元）')),
    );
    expect(proposalIntakeSalesFinanceFillIssues({}), contains('请填写结算账户一'));
    expect(proposalIntakeSkuSettleIssues({}), isEmpty);

    final form = <String, dynamic>{
      'sector': '数字营销事业部',
      'proposalName': '销售提案',
      'proposalType': '新增业务提案',
      'product': '智能投放平台',
      'projectName': '华东区域智能投放项目',
      'supplies': ['头部媒体供给'],
      'channels': ['直客渠道'],
      'supplierPolicy': '供货政策',
      'channelPolicy': '渠道政策',
      'executionPlan': '执行计划',
      'riskPoints': '风险点',
      'profitModes': ['返点差价'],
      'profitFormula': '按核销结算',
      'purchaseMode': '已签署合同',
      'purchaseNo': 'CG-1',
      'purchaseName': '采购合同',
      'purchaseSignDate': '2026-01-01',
      'purchaseOurParty': '我方',
      'purchaseCounterparty': '对方',
      'purchaseValidPeriod': '1年',
      'purchaseCoreTerms': '条款',
      'salesMode': '已签署合同',
      'salesNo': 'XS-1',
      'salesName': '销售合同',
      'salesSignDate': '2026-01-01',
      'salesOurParty': '我方',
      'salesCounterparty': '对方',
      'salesValidPeriod': '1年',
      'salesCoreTerms': '条款',
      'technologyPlatform': '数据智能平台',
      'technologyCapabilities': ['人群圈选能力'],
      'outputForms': ['API 接口'],
      'developmentTypes': ['全新开发'],
      'hasRdCost': '否',
      'deliveryDate': '2026-12-01',
      'salesScale': '100',
      'revenue': '80',
      'couponProcurementCost': '60',
      'profit': '10',
      'margin': '12',
      'turnoverTimes': '2',
      'supplySettleMode': '月结',
      'supplySettleCycle': 'T+15',
      'supplyPayer': '荷叶',
      'supplyPayAccount': '账户A',
      'channelSettleMode': '月结',
      'channelSettleCycle': 'T+15',
      'channelPayee': '渠道',
      'channelReceiveAccount': '账户B',
      'generalBusinessAccount': '普通账',
      'prepaidAccount': '预收账',
      'financeRemark': '备注',
      'rollback': '不回滚',
      'skuDetails': [
        {
          'id': 'sku-1',
          'settlements': [
            {'id': 'st-1', 'scale': '100'},
          ],
        },
      ],
    };
    expect(proposalIntakeSalesMarketIssues(form), isEmpty);
    expect(proposalIntakeTechFillIssues(form, purchase: false), isEmpty);
    expect(proposalIntakeSalesFinanceFillIssues(form), isEmpty);
    expect(proposalIntakeSkuSettleIssues(form), isEmpty);
  });

  test('progress timeline marks filling as the current submitter step', () {
    final people = [
      const ProposalPerson(userId: 1, name: '朱子姝', positionName: ''),
      const ProposalPerson(userId: 2, name: '李思', positionName: ''),
    ];
    final row = ProposalIntakeRow.fromJson({
      'id': 11,
      'kind': 'sales',
      'status': 'filling',
      'createdBy': 1,
      'createdAt': '2026-09-04T02:48:00Z',
      'form': {
        'createdByName': '朱子姝',
        'technologyOwner': '李思',
        'financeOwner2': '胡珏',
      },
      'review': {'stage': 'filling'},
    });
    final steps = proposalIntakeProgressSteps(row: row, people: people);
    expect(_progressById(steps, 'initiate').title, '朱子姝 发起');
    expect(
      _progressById(steps, 'initiate').state,
      ProposalIntakeProgressState.current,
    );
    expect(_progressById(steps, 'initiate').statusText, '填写中');
    expect(
      _progressById(steps, 'initiate').time,
      formatProposalIntakeProgressTime('2026-09-04T02:48:00Z'),
    );
    expect(
      _progressById(steps, 'fill_tech').state,
      ProposalIntakeProgressState.pending,
    );
    expect(_progressById(steps, 'review_finance_module').role, '财务部负责人一');
    expect(steps.any((item) => item.id == 'review_finance_interface'), isFalse);
    expect(_progressById(steps, 'review_tech').action, '逐条复核科技（含财务技术接口）');
    expect(
      steps
          .where((item) => item.state == ProposalIntakeProgressState.current)
          .length,
      1,
    );
  });

  test(
    'progress timeline keeps purchase without whole-module finance review',
    () {
      final row = ProposalIntakeRow.fromJson({
        'id': 12,
        'kind': 'purchase',
        'status': 'reviewing',
        'createdBy': 1,
        'form': {
          'createdByName': '朱子姝',
          'marketOwner1': '许正阳',
          'marketOwner2': '刘雨滴',
          'technologyOwner': '李思',
          'financeOwner2': '胡珏',
        },
        'review': {
          'stage': 'reviewing',
          'marketCompleted': true,
          'technologyCompleted': false,
        },
      });
      final steps = proposalIntakeProgressSteps(row: row);
      expect(steps.any((item) => item.id == 'review_finance_module'), isFalse);
      expect(
        _progressById(steps, 'initiate').state,
        ProposalIntakeProgressState.done,
      );
      expect(
        _progressById(steps, 'fill_tech').state,
        ProposalIntakeProgressState.done,
      );
      expect(
        _progressById(steps, 'review_market').state,
        ProposalIntakeProgressState.done,
      );
      expect(_progressById(steps, 'review_market').statusText, '已通过');
      expect(
        _progressById(steps, 'review_tech').state,
        ProposalIntakeProgressState.current,
      );
      expect(_progressById(steps, 'review_tech').name, '刘雨滴');
      expect(
        _progressById(steps, 'president').state,
        ProposalIntakeProgressState.pending,
      );
      expect(
        _progressById(steps, 'end').state,
        ProposalIntakeProgressState.pending,
      );
    },
  );

  test('progress timeline marks pending president and completed end', () {
    final options = ProposalIntakeOptions.fromJson({
      'people': {
        'presidents': [
          {'userId': 9, 'displayName': '最终人甲'},
        ],
      },
    });
    final pending = ProposalIntakeRow.fromJson({
      'id': 13,
      'kind': 'sales',
      'status': 'pending_president',
      'createdBy': 1,
      'form': {'createdByName': '朱子姝', 'financeOwner1': '财务甲'},
      'review': {
        'stage': 'pending_president',
        'marketCompleted': true,
        'technologyCompleted': true,
        'financeInterfaceCompleted': true,
        'financeCompleted': true,
        'purchaseContractCompleted': true,
        'salesContractCompleted': true,
      },
    });
    final pendingSteps = proposalIntakeProgressSteps(
      row: pending,
      options: options,
    );
    expect(
      _progressById(pendingSteps, 'notify_president').state,
      ProposalIntakeProgressState.done,
    );
    expect(
      _progressById(pendingSteps, 'president').state,
      ProposalIntakeProgressState.current,
    );
    expect(_progressById(pendingSteps, 'president').name, '最终人甲');
    expect(
      _progressById(pendingSteps, 'end').state,
      ProposalIntakeProgressState.pending,
    );

    final done = pending.copyWith(
      status: 'done',
      stage: 'done',
      review: {
        ...pending.review,
        'stage': 'done',
        'presidentDecidedAt': '2026-09-04T03:10:00Z',
      },
    );
    final doneSteps = proposalIntakeProgressSteps(row: done, options: options);
    expect(
      _progressById(doneSteps, 'president').state,
      ProposalIntakeProgressState.done,
    );
    expect(
      _progressById(doneSteps, 'end').state,
      ProposalIntakeProgressState.done,
    );
    expect(_progressById(doneSteps, 'end').title, '审批结束');
    expect(
      _progressById(doneSteps, 'president').time,
      formatProposalIntakeProgressTime('2026-09-04T03:10:00Z'),
    );
  });

  test('progress timeline marks rejected reviewer and president', () {
    final module = ProposalIntakeRow.fromJson({
      'id': 14,
      'kind': 'sales',
      'status': 'filling',
      'createdBy': 1,
      'form': {'createdByName': '朱子姝', 'marketOwner1': '许正阳'},
      'review': {
        'stage': 'filling',
        'reviewRejected': true,
        'reviewRejectSection': 'marketCompleted',
        'technologyCompleted': true,
      },
    });
    final moduleSteps = proposalIntakeProgressSteps(row: module);
    expect(
      _progressById(moduleSteps, 'initiate').state,
      ProposalIntakeProgressState.current,
    );
    expect(
      _progressById(moduleSteps, 'review_market').state,
      ProposalIntakeProgressState.rejected,
    );
    expect(_progressById(moduleSteps, 'review_market').statusText, '已驳回');
    expect(
      _progressById(moduleSteps, 'review_tech').state,
      ProposalIntakeProgressState.done,
    );
    expect(
      _progressById(moduleSteps, 'president').state,
      ProposalIntakeProgressState.pending,
    );

    final president = ProposalIntakeRow.fromJson({
      'id': 15,
      'kind': 'sales',
      'status': 'filling',
      'createdBy': 1,
      'form': {'createdByName': '朱子姝', 'president': '最终人甲'},
      'review': {'stage': 'filling', 'presidentRejected': true},
    });
    final presidentSteps = proposalIntakeProgressSteps(row: president);
    expect(
      _progressById(presidentSteps, 'initiate').state,
      ProposalIntakeProgressState.current,
    );
    expect(
      _progressById(presidentSteps, 'president').state,
      ProposalIntakeProgressState.rejected,
    );
    expect(
      _progressById(presidentSteps, 'end').state,
      ProposalIntakeProgressState.pending,
    );
  });

  test('progress headline lists people currently in the step', () {
    final row = ProposalIntakeRow.fromJson({
      'id': 16,
      'kind': 'sales',
      'status': 'filling',
      'createdBy': 1,
      'form': {
        'createdByName': '朱子姝',
        'technologyOwner': '李思',
        'financeOwner2': '胡珏',
      },
      'review': {'stage': 'awaiting_tech'},
    });
    final steps = proposalIntakeProgressSteps(row: row);
    expect(proposalIntakeProgressHeadline(steps), '科技部负责人 · 李思、财务部负责人二 · 胡珏');
  });

  test('configured presidents are recognized without hiding progress', () {
    final options = ProposalIntakeOptions.fromJson({
      'people': {
        'presidents': [
          {'userId': 88, 'displayName': '许正阳'},
        ],
      },
    });
    expect(options.isConfiguredPresident(88), isTrue);
    expect(options.isConfiguredPresident(11), isFalse);
    expect(options.presidentDisplayNames(const []), '许正阳');
  });

  test('nav section maps filler and reviewer actions to departments', () {
    expect(
      proposalIntakeNavSectionForAction('fill'),
      ProposalIntakeNavSection.market,
    );
    expect(
      proposalIntakeNavSectionForAction('review_market'),
      ProposalIntakeNavSection.market,
    );
    expect(
      proposalIntakeNavSectionForAction('review_tech'),
      ProposalIntakeNavSection.tech,
    );
    expect(
      proposalIntakeNavSectionForAction('fill_finance_interface'),
      ProposalIntakeNavSection.tech,
    );
    expect(
      proposalIntakeNavSectionForAction('review_finance'),
      ProposalIntakeNavSection.finance,
    );
    expect(
      proposalIntakeNavSectionForAction('review_contract'),
      ProposalIntakeNavSection.finance,
    );
    expect(proposalIntakeNavSectionForAction('president_confirm'), isNull);
    expect(proposalIntakeNavSectionLabel(ProposalIntakeNavSection.toc), '目录');
    expect(proposalIntakeNavJumpLabel('president_confirm'), '去底部确认');
    expect(proposalIntakeTaskBannerTitle('president_confirm'), '待你最终确认');
    expect(proposalIntakeTaskBannerBody('president_confirm'), contains('审批进度'));
    expect(proposalIntakeNavJumpLabel('review_tech'), '去科技部复核');
    expect(proposalIntakeNavJumpLabel('review_market'), '去底部确认');
    expect(proposalIntakeNavJumpLabel('review_finance_module'), '去底部确认');
    expect(proposalIntakeNavJumpLabel('fill'), '去市场部填写');
    expect(proposalIntakeActionIsModuleReview('review_market'), isTrue);
    expect(proposalIntakeActionIsModuleReview('review_tech'), isFalse);
    expect(proposalIntakeTaskBannerTitle('review_market'), '待你整板块复核市场部');
    expect(proposalIntakeTaskBannerTitle('review_tech'), '待你逐条复核科技部');
    expect(proposalIntakeTaskBannerBody('review_market'), contains('整个板块复核通过'));
    expect(proposalIntakeTaskBannerBody('review_tech'), contains('财务技术接口'));
    expect(proposalIntakeTaskBannerBody('review_tech'), contains('检查遗漏'));
    final techDone = {
      'technologyItems': {
        for (final key in kProposalTechnologyReviewFields) key: true,
      },
    };
    expect(
      proposalIntakeAwaitingModuleConfirm('review_tech', techDone),
      isTrue,
    );
    expect(
      proposalIntakeTaskBannerTitle('review_tech', awaitingModuleConfirm: true),
      '逐条已完成，请确认科技部板块',
    );
    expect(
      proposalIntakeTaskBannerBody('review_tech', awaitingModuleConfirm: true),
      contains('点保存不会结束复核'),
    );
    expect(
      proposalIntakeNavJumpLabel('review_tech', awaitingModuleConfirm: true),
      '去底部确认',
    );
    expect(proposalIntakeTechnologyReviewGaps(const {}), contains('财务技术接口'));
    expect(
      proposalIntakeTechnologyReviewGaps({
        'technologyItems': {
          for (final key in kProposalTechnologyReviewFields) key: true,
        },
      }),
      isEmpty,
    );
  });

  test(
    'child products stay off skuDetails and add merged tech review keys',
    () {
      final form = {
        'skuDetails': [
          {
            'id': 'sku-1',
            'productName': '主权益',
            'settlements': [
              {
                'id': 'st-1',
                'settleMode': '按结算比例',
                'settleRatio': '8%',
                'formula': '销售额*比例',
                'taxRate': '6%',
                'scale': '100',
              },
            ],
          },
        ],
        'childProducts': [
          {
            'id': 'child-1',
            'productName': '加油100',
            'settlements': [
              {
                'id': 'st-c',
                'settleMode': '按结算比例',
                'settleRatio': '4%',
                'formula': '面值*比例',
                'taxRate': '6%',
                'scale': '50',
              },
            ],
          },
        ],
      };
      expect(proposalIntakeHasChildProducts(form), isTrue);
      expect(proposalIntakeSkuDetails(form).single.id, 'sku-1');
      expect(proposalIntakeChildProducts(form).single.id, 'child-1');
      expect(proposalIntakeSkuSettleReviewKeys(form), [
        'skuSettle:sku-1:st-1',
        'skuSettle:child-1:st-c',
      ]);
      expect(
        proposalIntakeTechnologyReviewItemKeys(form),
        contains('children:technologyPlatform'),
      );
      expect(
        proposalIntakeTechnologyReviewGaps(const {}, form: form),
        contains('子产品τ-标签一'),
      );
      final synced = proposalIntakeSyncChildProductMeta(form);
      expect(synced['isCouponPack'], isTrue);
      expect(synced['financeModules'], isNull);
      expect(
        proposalIntakeProductFinance(
          synced,
          owner: kProposalProductFinanceChildren,
        ),
        isEmpty,
      );
      final outbound = proposalIntakeSalesOutboundJson(
        form: synced,
        id: 8,
        code: 'TA-1',
        title: '权益提案',
      );
      expect(outbound['isCouponPack'], isTrue);
      expect((outbound['products'] as List).single['id'], 'child-1');
      expect((outbound['packs'] as List).single['skuIds'], ['child-1']);
      expect((outbound['packs'] as List).single['skuQuantities'], {
        'child-1': 1,
      });
      expect(proposalProductScaleRollup(form)?.salesScale, 150);
      expect(proposalProductScaleRollup(form)?.revenue, 10);
    },
  );

  test('child product quantities are retained on the main product pack', () {
    final synced = proposalIntakeSyncChildProductMeta({
      'benefitProduct': {
        'id': 'benefit-1',
        'name': '权益包',
        'skuQuantities': {'child-1': 3, 'removed-child': 9},
      },
      'childProducts': [
        {'id': 'child-1', 'productName': '加油100'},
        {'id': 'child-2', 'productName': '洗车券'},
      ],
    });
    final benefit = synced['benefitProduct'] as Map;
    expect(benefit['relatedSkuIds'], ['child-1', 'child-2']);
    expect(benefit['skuQuantities'], {'child-1': 3, 'child-2': 1});
    expect(proposalIntakeChildProductQuantity(synced, 'child-1'), 3);
    expect(proposalIntakeChildProductQuantity(synced, 'child-2'), 1);
  });

  test('child products require an associated main product', () {
    final form = {
      'skuDetails': [
        {'id': 'main-1', 'productName': '权益主产品'},
      ],
      'childProducts': [
        {'id': 'child-1', 'productName': '加油券'},
      ],
    };
    expect(
      proposalIntakeSkuSettleIssues(form, includeSettlements: false),
      contains('子产品「加油券」请选择关联主产品'),
    );
    final child = ProposalSkuDetailRow.fromJson({
      'id': 'child-1',
      'parentSkuId': 'main-1',
    });
    expect(child.parentSkuId, 'main-1');
    expect(child.toJson()['parentSkuId'], 'main-1');
  });

  test('legacy multi sku details are not auto-promoted to child products', () {
    final form = {
      'skuDetails': [
        {'id': 'sku-1', 'productName': '券A'},
        {'id': 'sku-2', 'productName': '券B'},
      ],
    };
    expect(proposalIntakeHasChildProducts(form), isFalse);
    expect(proposalIntakeSkuDetails(form), hasLength(2));
    expect(proposalIntakeChildTechFillIssues(form), isEmpty);
    final outbound = proposalIntakeSalesOutboundJson(
      form: form,
      id: 1,
      code: 'TA-1',
      title: '旧单',
    );
    expect(outbound['isCouponPack'], isFalse);
    expect(outbound['packs'], isEmpty);
    expect((outbound['products'] as List), hasLength(2));
  });

  test('product finance keeps main and child totals isolated', () {
    final legacy = <String, dynamic>{
      'revenue': 100,
      'projectCost': 10,
      'financeRemark': '旧单主产品财务',
    };
    expect(
      proposalIntakeProductFinance(
        legacy,
        owner: kProposalProductFinanceMain,
      )['revenue'],
      100,
    );
    expect(
      proposalIntakeProductFinance(
        legacy,
        owner: kProposalProductFinanceChildren,
      ),
      isEmpty,
    );

    final grouped = proposalIntakeWriteProductFinance(
      legacy,
      owner: kProposalProductFinanceChildren,
      finance: const {'revenue': 40, 'projectCost': 4, 'financeRemark': '子产品'},
    );
    expect(grouped['revenue'], 100);
    expect(
      proposalIntakeProductFinance(
        grouped,
        owner: kProposalProductFinanceMain,
      )['projectCost'],
      10,
    );
    expect(
      proposalIntakeProductFinance(
        grouped,
        owner: kProposalProductFinanceChildren,
      ),
      {'revenue': 40, 'projectCost': 4, 'financeRemark': '子产品'},
    );
  });

  test('product finance scope calculates only its own products', () {
    final form = {
      'skuDetails': [
        {
          'id': 'main-1',
          'settlements': [
            {'id': 's-main', 'scale': '100', 'settleRatio': '0.9'},
          ],
        },
      ],
      'childProducts': [
        {
          'id': 'child-1',
          'settlements': [
            {'id': 's-child', 'scale': '50', 'settleRatio': '0.8'},
          ],
        },
      ],
      'productFinance': {
        'main': {'projectCost': 10},
        'children': {'projectCost': 4},
      },
    };
    final main = proposalIntakeProductFinanceScope(form, owner: 'main');
    final children = proposalIntakeProductFinanceScope(form, owner: 'children');
    expect(proposalProductScaleRollup(main)?.salesScale, 100);
    expect(proposalProductScaleRollup(main)?.revenue, 90);
    expect(proposalProductScaleRollup(children)?.salesScale, 50);
    expect(proposalProductScaleRollup(children)?.revenue, 40);
    expect(proposalEstimatedProfitAmount(main, revenue: 90), 80);
    expect(proposalEstimatedProfitAmount(children, revenue: 40), 36);
  });

  test('child finance metrics ignore main-product costs and use the same formulas', () {
    final form = {
      'skuDetails': [
        {
          'id': 'main-1',
          'settlements': [
            {'id': 's-main', 'scale': '1000', 'settleRatio': '1'},
          ],
        },
      ],
      'childProducts': [
        {
          'id': 'child-1',
          'settlements': [
            {'id': 's-child', 'scale': '200', 'settleRatio': '1'},
          ],
        },
      ],
      'projectCost': 1000,
      'couponProcurementCost': 80,
      'turnoverTimes': 2,
      'productFinance': {
        'main': {
          'projectCost': 1000,
          'couponProcurementCost': 80,
          'turnoverTimes': 2,
        },
      },
    };
    final childScope = proposalIntakeProductFinanceScope(
      form,
      owner: kProposalProductFinanceChildren,
    );
    expect(childScope['projectCost'], isNull);
    expect(childScope['couponProcurementCost'], isNull);
    expect(childScope['turnoverTimes'], isNull);
    expect(proposalProductScaleRollup(childScope)?.salesScale, 200);
    expect(proposalProductScaleRollup(childScope)?.revenue, 200);
    expect(proposalEstimatedProfitAmount(childScope, revenue: 200), 200);
    expect(proposalTurnoverCashAmount(childScope), isNull);

    final estimated = proposalApplyEstimatedFinanceCosts({
      ...form,
      'productFinance': {
        'main': (form['productFinance'] as Map)['main'],
        'children': {'turnoverTimes': 2},
      },
    });
    expect(estimated['salesScale'], 1000);
    expect(estimated['turnoverCash'], 41.67);
    final childFinance = proposalIntakeProductFinance(
      estimated,
      owner: kProposalProductFinanceChildren,
    );
    expect(childFinance['salesScale'], 200);
    expect(childFinance['revenue'], 200);
    expect(childFinance['turnoverCash'], 8.33);
    expect(childFinance['profit'], isNot(-880));
  });

  test('rating and top-level scale follow main products, not children', () {
    final form = proposalApplyEstimatedFinanceCosts({
      'skuDetails': [
        {
          'id': 'main-1',
          'productName': '主产品',
          'settlements': [
            {'id': 's-main', 'scale': '400', 'settleRatio': '1'},
          ],
        },
      ],
      'childProducts': [
        {
          'id': 'child-1',
          'productName': '子产品',
          'settlements': [
            {'id': 's-child', 'scale': '8000', 'settleRatio': '1'},
          ],
        },
      ],
      'products': [
        {
          'id': 'child-1',
          'productName': '子产品',
          'settlements': [
            {'id': 's-child', 'scale': '8000', 'settleRatio': '1'},
          ],
        },
      ],
      'turnoverTimes': '2',
    });
    expect(proposalIntakeMainProductScale(form), 400);
    expect(form['salesScale'], 400);
    expect(form['turnoverCash'], 16.67);
    expect(
      proposalProductScaleRollup(
        proposalIntakeProductFinanceScope(
          form,
          owner: kProposalProductFinanceChildren,
        ),
      )?.salesScale,
      8000,
    );
    expect(
      proposalIntakeProductFinance(
        form,
        owner: kProposalProductFinanceChildren,
      )['turnoverCash'],
      isNull,
    );
    expect(proposalProductScaleRollup(form)?.salesScale, 8400);
  });
}

int _fillMissingCount(ProposalIntakeRow row) {
  final form = row.form;
  if (proposalIntakeIsPurchase(row.kind)) {
    return proposalIntakePurchaseMarketIssues(form).length +
        proposalIntakePurchaseTechIssues(form).length;
  }
  return proposalIntakeSalesMarketIssues(form).length +
      proposalIntakeTechFillIssues(form, purchase: false).length +
      proposalIntakeChildTechFillIssues(form).length +
      proposalIntakeSalesFinanceFillIssues(form).length +
      proposalIntakeLaunchFinanceIssues(form).length +
      proposalIntakeSkuSettleIssues(form).length;
}

ProposalIntakeProgressStep _progressById(
  List<ProposalIntakeProgressStep> steps,
  String id,
) {
  return steps.firstWhere((item) => item.id == id);
}
