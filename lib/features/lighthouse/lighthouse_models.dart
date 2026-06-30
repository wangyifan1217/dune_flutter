import 'package:flutter/foundation.dart';

enum LighthouseTab { product, supply, channel }

enum LighthousePeriod { day, week, month, quarter, year }

enum LighthouseSortField { profit, sales, gmv }

@immutable
class LighthouseDetailState {
  const LighthouseDetailState({
    required this.type,
    required this.keyName,
    required this.subTab,
  });

  final LighthouseTab type;
  final String keyName;
  final String subTab;
}

@immutable
class LighthouseMetric {
  const LighthouseMetric({
    required this.key,
    required this.label,
    required this.shortLabel,
  });

  final String key;
  final String label;
  final String shortLabel;
}

const kLighthouseMetricDefaults = <LighthouseTab, List<String>>{
  LighthouseTab.product: <String>[
    'sales',
    'gmv',
    'gmv2',
    'its',
    'itsAfter',
    'spread',
    'woa',
    'revenue',
    'totalCost',
    'cost',
    'tax',
  ],
  LighthouseTab.supply: <String>[
    'sales',
    'gmv',
    'cost',
    'tax',
    'spread',
    'saasFee',
    'woa',
    'projectCost',
    'deferred',
    'discount',
  ],
  LighthouseTab.channel: <String>[
    'sales',
    'gmv',
    'cost',
    'tax',
    'spread',
    'saasFee',
    'woa',
    'projectCost',
    'deferred',
  ],
};

LighthouseTab tabFromString(String tab) {
  switch (tab) {
    case 'supply':
      return LighthouseTab.supply;
    case 'channel':
      return LighthouseTab.channel;
    case 'product':
    default:
      return LighthouseTab.product;
  }
}

String tabToString(LighthouseTab tab) {
  switch (tab) {
    case LighthouseTab.product:
      return 'product';
    case LighthouseTab.supply:
      return 'supply';
    case LighthouseTab.channel:
      return 'channel';
  }
}
