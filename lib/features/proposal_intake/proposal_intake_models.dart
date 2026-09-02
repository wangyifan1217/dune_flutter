import 'dart:convert';

import 'settlement_catalog.dart';

String normalizeProposalIntakeKind(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'purchase':
    case 'procurement':
    case 'purchase-proposal':
    case 'procurement-proposal':
    case '采购':
    case '采购提案':
      return 'purchase';
    default:
      return 'sales';
  }
}

bool proposalIntakeIsPurchase(String kind) =>
    normalizeProposalIntakeKind(kind) == 'purchase';

String proposalIntakeUntitledTitle(String kind) => proposalIntakeIsPurchase(kind)
    ? '未命名采购业务提案'
    : '未命名销售业务提案';

String proposalIntakeKindEyebrow(String kind) =>
    proposalIntakeIsPurchase(kind) ? '采购业务提案' : '销售业务提案';

class ProposalIntakeAccess {
  const ProposalIntakeAccess({
    required this.view,
    required this.fill,
    required this.review,
  });

  final bool view;
  final bool fill;
  final bool review;

  factory ProposalIntakeAccess.fromJson(Map<String, dynamic> json) =>
      ProposalIntakeAccess(
        view: json['view'] == true,
        fill: json['fill'] == true,
        review: json['review'] == true,
      );
}

class ProposalIntakeUploadedFile {
  const ProposalIntakeUploadedFile({
    required this.fileName,
    required this.objectKey,
    required this.url,
    required this.sizeBytes,
    required this.mimeType,
  });

  final String fileName;
  final String objectKey;
  final String url;
  final int sizeBytes;
  final String mimeType;
}

class ProposalPerson {
  const ProposalPerson({
    required this.userId,
    required this.name,
    required this.positionName,
    this.username = '',
    this.departmentName = '',
  });

  final int userId;
  final String name;
  final String positionName;
  final String username;
  final String departmentName;

  factory ProposalPerson.fromJson(Map<String, dynamic> json) {
    final name =
        '${json['displayName'] ?? json['name'] ?? json['username'] ?? ''}'
            .trim();
    return ProposalPerson(
      userId:
          (json['userId'] as num?)?.toInt() ??
          (json['id'] as num?)?.toInt() ??
          0,
      name: name,
      positionName: '${json['positionName'] ?? json['title'] ?? ''}'.trim(),
      username: '${json['username'] ?? ''}'.trim(),
      departmentName: '${json['departmentName'] ?? ''}'.trim(),
    );
  }
}

class ProposalApprovedPurchaseHit {
  const ProposalApprovedPurchaseHit({
    required this.id,
    required this.code,
    required this.title,
    this.purchaseMode = '',
    this.purchaseContractId,
    this.purchaseNo = '',
    this.purchaseName = '',
    this.purchaseSignDate = '',
    this.purchaseOurParty = '',
    this.purchaseCounterparty = '',
    this.purchaseValidPeriod = '',
    this.purchaseCoreTerms = '',
    this.purchaseFileName = '',
    this.purchaseObjectKey = '',
    this.purchaseFileUrl = '',
    this.supplierPolicy = '',
    this.supplySettleMode = '',
    this.supplySettleCycle = '',
    this.supplyPayer = '',
    this.supplyPayAccount = '',
    this.purchaseProducts = const [],
  });

  final int id;
  final String code;
  final String title;
  final String purchaseMode;
  final int? purchaseContractId;
  final String purchaseNo;
  final String purchaseName;
  final String purchaseSignDate;
  final String purchaseOurParty;
  final String purchaseCounterparty;
  final String purchaseValidPeriod;
  final String purchaseCoreTerms;
  final String purchaseFileName;
  final String purchaseObjectKey;
  final String purchaseFileUrl;
  final String supplierPolicy;
  final String supplySettleMode;
  final String supplySettleCycle;
  final String supplyPayer;
  final String supplyPayAccount;
  final List<String> purchaseProducts;

  String get label {
    if (title.isNotEmpty && code.isNotEmpty) return '$code · $title';
    if (title.isNotEmpty) return title;
    return code;
  }

  factory ProposalApprovedPurchaseHit.fromJson(Map<String, dynamic> json) {
    final products = json['purchaseProducts'];
    return ProposalApprovedPurchaseHit(
      id: (json['id'] as num?)?.toInt() ?? 0,
      code: '${json['code'] ?? ''}'.trim(),
      title: '${json['title'] ?? json['proposalName'] ?? ''}'.trim(),
      purchaseMode: '${json['purchaseMode'] ?? ''}'.trim(),
      purchaseContractId: (json['purchaseContractId'] as num?)?.toInt(),
      purchaseNo: '${json['purchaseNo'] ?? ''}'.trim(),
      purchaseName: '${json['purchaseName'] ?? ''}'.trim(),
      purchaseSignDate: '${json['purchaseSignDate'] ?? ''}'.trim(),
      purchaseOurParty: '${json['purchaseOurParty'] ?? ''}'.trim(),
      purchaseCounterparty: '${json['purchaseCounterparty'] ?? ''}'.trim(),
      purchaseValidPeriod: '${json['purchaseValidPeriod'] ?? ''}'.trim(),
      purchaseCoreTerms: '${json['purchaseCoreTerms'] ?? ''}'.trim(),
      purchaseFileName: '${json['purchaseFileName'] ?? ''}'.trim(),
      purchaseObjectKey: '${json['purchaseObjectKey'] ?? ''}'.trim(),
      purchaseFileUrl: '${json['purchaseFileUrl'] ?? ''}'.trim(),
      supplierPolicy: '${json['supplierPolicy'] ?? ''}'.trim(),
      supplySettleMode: '${json['supplySettleMode'] ?? ''}'.trim(),
      supplySettleCycle: '${json['supplySettleCycle'] ?? ''}'.trim(),
      supplyPayer: '${json['supplyPayer'] ?? ''}'.trim(),
      supplyPayAccount: '${json['supplyPayAccount'] ?? ''}'.trim(),
      purchaseProducts: products is List
          ? [
              for (final item in products)
                '$item'.trim(),
            ].where((item) => item.isNotEmpty).toList(growable: false)
          : const [],
    );
  }
}

bool proposalIntakeHasExistingPurchaseProposal(Map<String, dynamic> form) {
  final raw = form['hasExistingPurchaseProposal'];
  if (raw is bool) return raw;
  final text = '$raw'.trim().toLowerCase();
  return text == 'true' || text == '1' || text == '是' || text == 'yes';
}

int proposalIntakeLinkedPurchaseProposalId(Map<String, dynamic> form) {
  return int.tryParse('${form['linkedPurchaseProposalId'] ?? ''}'.trim()) ?? 0;
}

Map<String, dynamic> proposalIntakePatchFromApprovedPurchase(
  ProposalApprovedPurchaseHit hit,
) {
  final patch = proposalIntakeResetContractFields('purchase');
  patch['hasExistingPurchaseProposal'] = true;
  patch['linkedPurchaseProposalId'] = hit.id;
  patch['linkedPurchaseProposalCode'] = hit.code;
  patch['linkedPurchaseProposalTitle'] = hit.title;
  patch['purchaseMode'] = hit.purchaseMode;
  patch['purchaseContractId'] = hit.purchaseContractId;
  _putField(patch, 'purchaseNo', hit.purchaseNo);
  _putField(patch, 'purchaseName', hit.purchaseName);
  _putField(patch, 'purchaseSignDate', hit.purchaseSignDate);
  _putField(patch, 'purchaseOurParty', hit.purchaseOurParty);
  _putField(patch, 'purchaseCounterparty', hit.purchaseCounterparty);
  _putField(patch, 'purchaseValidPeriod', hit.purchaseValidPeriod);
  _putField(patch, 'purchaseCoreTerms', hit.purchaseCoreTerms);
  _putField(patch, 'purchaseFileName', hit.purchaseFileName);
  _putField(patch, 'purchaseObjectKey', hit.purchaseObjectKey);
  _putField(patch, 'purchaseFileUrl', hit.purchaseFileUrl);
  _putField(patch, 'supplierPolicy', hit.supplierPolicy);
  _putField(patch, 'supplySettleMode', hit.supplySettleMode);
  _putField(patch, 'supplySettleCycle', hit.supplySettleCycle);
  _putField(patch, 'supplyPayer', hit.supplyPayer);
  _putField(patch, 'supplyPayAccount', hit.supplyPayAccount);
  if (hit.purchaseProducts.isNotEmpty) {
    patch['purchaseProducts'] = hit.purchaseProducts;
  }
  return patch;
}

class ProposalContractChoice {
  const ProposalContractChoice({
    required this.id,
    required this.contractNo,
    required this.contractName,
    required this.partyA,
    required this.partyB,
    required this.signDate,
    required this.endDate,
  });

  final int id;
  final String contractNo;
  final String contractName;
  final String partyA;
  final String partyB;
  final String signDate;
  final String endDate;

  String get label =>
      contractName.isEmpty ? contractNo : '$contractNo · $contractName';

  factory ProposalContractChoice.fromJson(Map<String, dynamic> json) =>
      ProposalContractChoice(
        id: (json['id'] as num?)?.toInt() ?? 0,
        contractNo: '${json['contractNo'] ?? ''}'.trim(),
        contractName: '${json['contractName'] ?? ''}'.trim(),
        partyA: '${json['partyA'] ?? ''}'.trim(),
        partyB: '${json['partyB'] ?? ''}'.trim(),
        signDate: '${json['signDate'] ?? ''}'.trim(),
        endDate: '${json['endDate'] ?? ''}'.trim(),
      );
}

class ProposalIntakeRow {
  const ProposalIntakeRow({
    required this.id,
    required this.code,
    required this.title,
    required this.status,
    required this.form,
    required this.review,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    this.kind = 'sales',
    this.stage = '',
    this.myAction = '',
  });

  final int id;
  final String code;
  final String title;
  final String kind;
  final String status;
  final Map<String, dynamic> form;
  final Map<String, dynamic> review;
  final int createdBy;
  final String createdAt;
  final String updatedAt;
  final int version;
  final String stage;
  final String myAction;

  factory ProposalIntakeRow.fromJson(Map<String, dynamic> json) {
    final review = _map(json['review']);
    return ProposalIntakeRow(
      id: (json['id'] as num?)?.toInt() ?? 0,
      code: '${json['code'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      kind: normalizeProposalIntakeKind('${json['kind'] ?? ''}'),
      status: '${json['status'] ?? 'draft'}'.trim(),
      form: _map(json['form']),
      review: review,
      createdBy: (json['createdBy'] as num?)?.toInt() ?? 0,
      createdAt: '${json['createdAt'] ?? ''}'.trim(),
      updatedAt: '${json['updatedAt'] ?? ''}'.trim(),
      version: (json['version'] as num?)?.toInt() ?? 1,
      stage: '${json['stage'] ?? review['stage'] ?? ''}'.trim(),
      myAction: '${json['myAction'] ?? ''}'.trim(),
    );
  }

  String get resolvedStage {
    if (stage.isNotEmpty) return stage;
    final fromReview = '${review['stage'] ?? ''}'.trim();
    if (fromReview.isNotEmpty) return fromReview;
    return switch (status) {
      'done' => 'done',
      'pending_president' => 'pending_president',
      'reviewing' => 'reviewing',
      _ => 'filling',
    };
  }

  int get techRevisionRound {
    final raw = review['techRevisionRound'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw'.trim()) ?? 0;
  }

  bool get isTechRevising => resolvedStage == 'tech_revising';

  bool get isTechReviewing => resolvedStage == 'tech_reviewing';

  bool get techRevisionOpen => isTechRevising || isTechReviewing;

  ProposalIntakeRow copyWith({
    String? title,
    String? status,
    Map<String, dynamic>? form,
    Map<String, dynamic>? review,
    int? version,
    String? stage,
    String? myAction,
  }) => ProposalIntakeRow(
    id: id,
    code: code,
    title: title ?? this.title,
    kind: kind,
    status: status ?? this.status,
    form: form ?? this.form,
    review: review ?? this.review,
    createdBy: createdBy,
    createdAt: createdAt,
    updatedAt: updatedAt,
    version: version ?? this.version,
    stage: stage ?? this.stage,
    myAction: myAction ?? this.myAction,
  );

  String initiatorDisplayName(List<ProposalPerson> people) {
    if (createdBy > 0) {
      for (final person in people) {
        if (person.userId == createdBy && person.name.isNotEmpty) {
          return person.name;
        }
      }
    }
    final fromForm = '${form['createdByName'] ?? form['initiatorName'] ?? ''}'
        .trim();
    if (fromForm.isNotEmpty) return fromForm;
    return '未指定';
  }

  bool get isDeletableStatus =>
      status != 'pending_president' && status != 'done';

  bool canDeleteBy(int userId) {
    if (userId <= 0 || !isDeletableStatus) return false;
    if (createdBy == userId) return true;
    final owner =
        int.tryParse('${form['marketOwner2UserId'] ?? ''}'.trim()) ?? 0;
    return owner == userId;
  }

  List<ProposalStakeholderLine> stakeholderLines({
    required List<ProposalPerson> people,
    ProposalIntakeOptions? options,
  }) {
    String named(String nameKey, String idKey) {
      final fromForm = '${form[nameKey] ?? ''}'.trim();
      if (fromForm.isNotEmpty) return fromForm;
      final id = int.tryParse('${form[idKey] ?? ''}'.trim()) ?? 0;
      if (id <= 0) return '未指定';
      for (final person in people) {
        if (person.userId == id && person.name.isNotEmpty) {
          return person.name;
        }
      }
      return '用户$id';
    }

    var president = named('president', 'presidentUserId');
    final configured = options?.presidentDisplayNames(people).trim() ?? '';
    if (configured.isNotEmpty) {
      president = president == '未指定' ? configured : '$president、$configured';
    }

    return [
      ProposalStakeholderLine(role: '创建人', name: initiatorDisplayName(people)),
      ProposalStakeholderLine(
        role: '市场部负责人二',
        name: named('marketOwner2', 'marketOwner2UserId'),
      ),
      ProposalStakeholderLine(
        role: '市场部负责人一',
        name: named('marketOwner1', 'marketOwner1UserId'),
      ),
      ProposalStakeholderLine(
        role: '运营',
        name: named('operator', 'operatorUserId'),
      ),
      ProposalStakeholderLine(
        role: '科技部负责人',
        name: named('technologyOwner', 'technologyOwnerUserId'),
      ),
      ProposalStakeholderLine(
        role: '财务部负责人一',
        name: named('financeOwner1', 'financeOwner1UserId'),
      ),
      ProposalStakeholderLine(
        role: '财务部负责人二',
        name: named('financeOwner2', 'financeOwner2UserId'),
      ),
      ProposalStakeholderLine(role: '最终确认人', name: president),
    ];
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }
}

class ProposalStakeholderLine {
  const ProposalStakeholderLine({required this.role, required this.name});

  final String role;
  final String name;
}

class ProposalIntakeListResult {
  const ProposalIntakeListResult({required this.items, required this.total});

  final List<ProposalIntakeRow> items;
  final int total;

  factory ProposalIntakeListResult.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List? ?? const [];
    return ProposalIntakeListResult(
      items: raw
          .whereType<Map>()
          .map(
            (item) =>
                ProposalIntakeRow.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      total: (json['total'] as num?)?.toInt() ?? raw.length,
    );
  }
}

class ProposalLinkedOption {
  const ProposalLinkedOption({required this.value, this.children = const []});

  final String value;
  final List<String> children;

  factory ProposalLinkedOption.fromJson(
    Object? raw, {
    required String childKey,
  }) {
    if (raw is String) return ProposalLinkedOption(value: raw);
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    return ProposalLinkedOption(
      value: '${map['value'] ?? ''}'.trim(),
      children: _strings(map[childKey]),
    );
  }
}

class ProposalFinanceInterface {
  const ProposalFinanceInterface({
    required this.key,
    required this.label,
    required this.required,
    required this.defaultChecked,
  });

  final String key;
  final String label;
  final bool required;
  final bool defaultChecked;

  factory ProposalFinanceInterface.fromJson(Object? raw) {
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    return ProposalFinanceInterface(
      key: '${map['key'] ?? ''}'.trim(),
      label: '${map['label'] ?? ''}'.trim(),
      required: map['required'] == true,
      defaultChecked: map['defaultChecked'] == true,
    );
  }
}

/// 协作提案「项目成本」表头，顺序与财务口径一致。
const kProposalProjectCostItems = [
  '机构返佣',
  '万里通返佣',
  '补贴款分润',
  '平台交易服务费',
  '渠道服务费分润',
  '支付手续费',
  '推广费',
];

/// 协作提案「经营成本」表头。
const kProposalOperatingCostItems = ['差旅成本', '招待费'];

/// 协作提案「税务成本」表头。
const kProposalTaxCostItems = [
  '增值税及附加（能源）',
  '增值税及附加（运营商+公共出行）',
  '印花税',
  '所得税',
];

String proposalProjectCostDisplayName(String name) {
  final text = name.trim();
  if (text == '平台服务费') return '平台交易服务费';
  return text;
}

Set<String> proposalProjectCostNamesOf(String name) {
  final canonical = proposalProjectCostDisplayName(name);
  if (canonical == '平台交易服务费') {
    return {'平台交易服务费', '平台服务费'};
  }
  return {canonical};
}

class ProposalCostItemOption {
  const ProposalCostItemOption({
    required this.code,
    required this.name,
    this.l1 = '',
    this.l2 = '',
    this.category = '',
  });

  final String code;
  final String name;
  final String l1;
  final String l2;
  final String category;

  factory ProposalCostItemOption.fromJson(Object? raw) {
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    return ProposalCostItemOption(
      code: '${map['code'] ?? ''}'.trim(),
      name: '${map['name'] ?? ''}'.trim(),
      l1: '${map['l1'] ?? ''}'.trim(),
      l2: '${map['l2'] ?? ''}'.trim(),
      category: '${map['category'] ?? ''}'.trim(),
    );
  }
}

String proposalCostAmountId(
  String name, [
  List<ProposalCostItemOption> catalog = const [],
]) {
  final aliases = proposalProjectCostNamesOf(name);
  for (final item in catalog) {
    if (aliases.contains(item.name) && item.code.isNotEmpty) return item.code;
  }
  return proposalProjectCostDisplayName(name).isEmpty
      ? name
      : proposalProjectCostDisplayName(name);
}

double proposalCostAmountValue(Object? raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse('$raw'.trim()) ?? 0;
}

Map<String, double> proposalCostAmountMap(Object? raw) {
  if (raw is! Map) return {};
  final out = <String, double>{};
  for (final entry in raw.entries) {
    final id = '${entry.key}'.trim();
    if (id.isEmpty) continue;
    out[id] = proposalCostAmountValue(entry.value);
  }
  return out;
}

double proposalCostAmountTotal(Object? raw) => proposalCostAmountMap(
  raw,
).values.fold<double>(0, (sum, value) => sum + value);

Map<String, dynamic> proposalSyncCostSelection({
  required Map<String, dynamic> form,
  required List<String> names,
  required List<ProposalCostItemOption> catalog,
  required String namesKey,
  required String codesKey,
  required String amountsKey,
  required String totalKey,
  String settleTermsKey = '',
}) {
  final catalogCodes = {for (final item in catalog) item.code};
  final codes = [
    for (final name in names)
      proposalCostAmountId(name, catalog),
  ].where(catalogCodes.contains).toList();
  final keep = <String>{
    for (final name in names) ...proposalProjectCostNamesOf(name),
    for (final name in names) proposalCostAmountId(name, catalog),
  };
  final amounts = proposalCostAmountMap(form[amountsKey])
    ..removeWhere((id, _) => !keep.contains(id));
  final next = Map<String, dynamic>.from(form)
    ..[namesKey] = names
    ..[codesKey] = codes
    ..[amountsKey] = {
      for (final entry in amounts.entries) entry.key: entry.value,
    }
    ..[totalKey] = proposalCostAmountTotal(amounts);
  if (settleTermsKey.isNotEmpty) {
    final terms = proposalCostSettleTermsMap(form[settleTermsKey])
      ..removeWhere((id, _) => !keep.contains(id));
    next[settleTermsKey] = {
      for (final entry in terms.entries) entry.key: entry.value.toJson(),
    };
  }
  return next;
}

Map<String, ProposalFinanceSettleTerms> proposalCostSettleTermsMap(
  Object? raw,
) {
  if (raw is! Map) return {};
  final out = <String, ProposalFinanceSettleTerms>{};
  for (final entry in raw.entries) {
    final id = '${entry.key}'.trim();
    if (id.isEmpty) continue;
    out[id] = ProposalFinanceSettleTerms.fromJson(entry.value);
  }
  return out;
}

ProposalFinanceSettleTerms proposalCostSettleTermsOf({
  required Map<String, ProposalFinanceSettleTerms> terms,
  required String name,
  required String id,
}) => terms[id] ?? terms[name] ?? const ProposalFinanceSettleTerms();

List<String> proposalIntakeNamedCostSettleIssues(
  Map<String, dynamic> form, {
  required String namesKey,
  required String termsKey,
  required String label,
  List<ProposalCostItemOption> catalog = const [],
}) {
  final raw = form[namesKey];
  if (raw is! List) return const [];
  final names = [
    for (final item in raw)
      if ('$item'.trim().isNotEmpty) '$item'.trim(),
  ];
  if (names.isEmpty) return const [];
  final terms = proposalCostSettleTermsMap(form[termsKey]);
  final issues = <String>[];
  for (final name in names) {
    final id = proposalCostAmountId(name, catalog);
    if (!proposalCostSettleTermsOf(
      terms: terms,
      name: name,
      id: id,
    ).isComplete) {
      issues.add('$label「$name」请填写结算比例或单价、计算公式、对方主体、我方主体、税率');
    }
  }
  return issues;
}

List<String> proposalIntakeCostItemSettleIssues(
  Map<String, dynamic> form, {
  List<ProposalCostItemOption> catalog = const [],
  List<ProposalCostItemOption> businessCatalog = const [],
}) => [
  ...proposalIntakeNamedCostSettleIssues(
    form,
    namesKey: 'costItems',
    termsKey: 'costItemSettleTerms',
    label: '项目成本',
    catalog: catalog,
  ),
  ...proposalIntakeNamedCostSettleIssues(
    form,
    namesKey: 'businessCostItems',
    termsKey: 'businessCostItemSettleTerms',
    label: '业务成本',
    catalog: businessCatalog,
  ),
];

class ProposalIntakeOptions {
  const ProposalIntakeOptions({
    required this.sectors,
    required this.proposalTypes,
    required this.products,
    required this.supplies,
    required this.channels,
    this.institutions = const [],
    required this.profitModes,
    this.supplyBrands = const [],
    this.rebateModes = const [],
    required this.platforms,
    required this.outputForms,
    required this.developmentTypes,
    required this.financeInterfaces,
    required this.costItems,
    this.costItemOptions = const [],
    this.businessCostItems = const [],
    this.businessCostItemOptions = const [],
    this.businessCostRules = '',
    this.operatingCostRules = '',
    this.costItemSource = '',
    required this.rollbackOptions,
    required this.ratingS,
    required this.ratingA,
    required this.ratingB,
    required this.minimumScale,
    required this.minimumMargin,
    this.presidentUserIds = const [],
    this.presidents = const [],
  });

  final List<String> sectors;
  final List<String> proposalTypes;
  final List<ProposalLinkedOption> products;
  final List<String> supplies;
  final List<String> channels;
  final List<CatalogRef> institutions;
  final List<String> profitModes;
  final List<String> supplyBrands;
  final List<String> rebateModes;
  final List<ProposalLinkedOption> platforms;
  final List<String> outputForms;
  final List<String> developmentTypes;
  final List<ProposalFinanceInterface> financeInterfaces;
  final List<String> costItems;
  final List<ProposalCostItemOption> costItemOptions;
  final List<String> businessCostItems;
  final List<ProposalCostItemOption> businessCostItemOptions;
  final String businessCostRules;
  final String operatingCostRules;
  final String costItemSource;
  final List<String> rollbackOptions;
  final double ratingS;
  final double ratingA;
  final double ratingB;
  final double minimumScale;
  final double minimumMargin;
  final List<int> presidentUserIds;
  final List<ProposalPerson> presidents;

  factory ProposalIntakeOptions.fromJson(Map<String, dynamic> json) {
    final market = _map(json['market']);
    final technology = _map(json['technology']);
    final finance = _map(json['finance']);
    final rules = _map(json['rules']);
    final people = _map(json['people']);
    final presidents = _list(people['presidents'])
        .whereType<Map>()
        .map((item) => ProposalPerson.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.userId > 0)
        .toList(growable: false);
    final presidentIds = <int>{
      ..._ints(people['presidentUserIds']),
      ...presidents.map((item) => item.userId),
    };
    return ProposalIntakeOptions(
      sectors: _strings(market['sectors']),
      proposalTypes: _strings(market['proposalTypes']),
      products: _list(market['products'])
          .map(
            (item) => ProposalLinkedOption.fromJson(item, childKey: 'projects'),
          )
          .where((item) => item.value.isNotEmpty)
          .toList(growable: false),
      supplies: _strings(market['supplies']),
      channels: _strings(market['channels']),
      institutions: _catalogChoices(market['institutions']),
      profitModes: _strings(market['profitModes']),
      supplyBrands: _strings(market['supplyBrands']),
      rebateModes: _strings(market['rebateModes']),
      platforms: _list(technology['platforms'])
          .map(
            (item) =>
                ProposalLinkedOption.fromJson(item, childKey: 'capabilities'),
          )
          .where((item) => item.value.isNotEmpty)
          .toList(growable: false),
      outputForms: _strings(technology['outputForms']),
      developmentTypes: _strings(technology['developmentTypes']),
      financeInterfaces: _list(technology['financeInterfaces'])
          .map(ProposalFinanceInterface.fromJson)
          .where((item) => item.key.isNotEmpty && item.label.isNotEmpty)
          .toList(growable: false),
      costItems: _strings(finance['costItems']),
      costItemOptions: _costItemOptions(finance['costItemOptions']),
      businessCostItems: _strings(finance['businessCostItems']),
      businessCostItemOptions: _costItemOptions(
        finance['businessCostItemOptions'],
      ),
      businessCostRules: _nonEmpty(
        finance['businessCostRules'],
        '员工提成等按公司已定规则累计。提案只勾选适用表头，不填发生额。',
      ),
      operatingCostRules: _nonEmpty(
        finance['operatingCostRules'],
        '差旅、小额营销按项目收入的 2% 为阈值：以内直接批，超过另走新流程。提案阶段不填发生额。',
      ),
      costItemSource: '${finance['costItemSource'] ?? ''}'.trim(),
      rollbackOptions: _strings(finance['rollbackOptions']),
      // 金额口径为万元。
      ratingS: _number(rules['ratingS'], 5000),
      ratingA: _number(rules['ratingA'], 2000),
      ratingB: _number(rules['ratingB'], 500),
      minimumScale: _number(rules['minimumScale'], 500),
      minimumMargin: _number(rules['minimumMargin'], 4.5),
      presidentUserIds: presidentIds.toList(growable: false),
      presidents: presidents,
    );
  }

  String ratingFor(double scale) {
    if (scale >= ratingS) return 'S';
    if (scale >= ratingA) return 'A';
    if (scale >= ratingB) return 'B';
    return 'C';
  }

  bool isConfiguredPresident(int userId) =>
      userId > 0 && presidentUserIds.contains(userId);

  String presidentDisplayNames(List<ProposalPerson> directory) {
    if (presidentUserIds.isEmpty) {
      return '';
    }
    return presidentUserIds
        .map((id) {
          for (final person in presidents) {
            if (person.userId == id && person.name.isNotEmpty) {
              return person.name;
            }
          }
          for (final person in directory) {
            if (person.userId == id && person.name.isNotEmpty) {
              return person.name;
            }
          }
          return '用户$id';
        })
        .join('、');
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Object?> _list(Object? value) =>
    value is List ? List<Object?>.from(value) : const [];

List<int> _ints(Object? value) {
  final seen = <int>{};
  final out = <int>[];
  for (final item in _list(value)) {
    var id = 0;
    if (item is num) {
      id = item.toInt();
    } else if (item is Map) {
      id =
          (item['userId'] as num?)?.toInt() ??
          (item['id'] as num?)?.toInt() ??
          0;
    } else {
      id = int.tryParse('$item'.trim()) ?? 0;
    }
    if (id > 0 && seen.add(id)) {
      out.add(id);
    }
  }
  return List<int>.unmodifiable(out);
}

List<ProposalCostItemOption> _costItemOptions(Object? value) => _list(value)
    .map(ProposalCostItemOption.fromJson)
    .where((item) => item.code.isNotEmpty && item.name.isNotEmpty)
    .toList(growable: false);

List<String> _strings(Object? value) => _list(value)
    .map((item) => '$item'.trim())
    .where((item) => item.isNotEmpty)
    .toList(growable: false);

List<CatalogRef> _catalogChoices(Object? raw) {
  final out = <CatalogRef>[];
  for (final item in _list(raw)) {
    if (item is String) {
      final parts = item.split('|');
      final name = parts.first.trim();
      final code = parts.length > 1 ? parts[1].trim() : '';
      if (name.isEmpty && code.isEmpty) continue;
      out.add(
        CatalogRef(
          code: code.isEmpty ? name : code,
          name: name.isEmpty ? code : name,
        ),
      );
      continue;
    }
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);
    final name =
        '${map['label'] ?? map['name'] ?? map['value'] ?? ''}'.trim();
    final code = '${map['code'] ?? map['key'] ?? ''}'.trim();
    if (name.isEmpty && code.isEmpty) continue;
    out.add(
      CatalogRef(
        code: code.isEmpty ? name : code,
        name: name.isEmpty ? code : name,
      ),
    );
  }
  return List<CatalogRef>.unmodifiable(out);
}

String _nonEmpty(Object? value, String fallback) {
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return fallback;
  return text;
}

double _number(Object? value, double fallback) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

String _contractText(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = '${source[key] ?? ''}'.trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

void _putField(Map<String, dynamic> form, String key, String value) {
  form[key] = value.trim();
}

List<String> proposalIntakeContractFillKeys(String prefix) {
  final keys = <String>[
    '${prefix}No',
    '${prefix}Name',
    '${prefix}SignDate',
    '${prefix}OurParty',
    '${prefix}Counterparty',
    '${prefix}ValidPeriod',
    '${prefix}CoreTerms',
  ];
  if (prefix == 'purchase') {
    keys.addAll(const [
      'supplierPolicy',
      'supplySettleMode',
      'supplySettleCycle',
      'supplyPayer',
      'supplyPayAccount',
    ]);
  } else {
    keys.addAll(const [
      'channelPolicy',
      'channelSettleMode',
      'channelSettleCycle',
      'channelPayee',
      'channelReceiveAccount',
    ]);
  }
  return keys;
}

/// 切换已签/未签时清空该合同抓取字段，避免上一份合同内容残留。
Map<String, dynamic> proposalIntakeResetContractFields(String prefix) {
  return <String, dynamic>{
    '${prefix}ContractId': null,
    '${prefix}FileName': '',
    '${prefix}ObjectKey': '',
    '${prefix}FileUrl': '',
    '${prefix}FileSize': null,
    for (final key in proposalIntakeContractFillKeys(prefix)) key: '',
  };
}

/// 从合同归集详情取出第一个源文件，写入提案表单，供内部 PDF 预览。
Map<String, dynamic> proposalIntakeFilePatchFromContractDetail(
  String prefix,
  Map<String, dynamic> detail,
) {
  final files = detail['files'];
  if (files is! List || files.isEmpty) return <String, dynamic>{};
  Map<String, dynamic>? first;
  for (final item in files) {
    if (item is Map) {
      first = Map<String, dynamic>.from(item);
      break;
    }
  }
  if (first == null) return <String, dynamic>{};
  final name = '${first['fileName'] ?? ''}'.trim();
  final objectKey = '${first['objectKey'] ?? ''}'.trim();
  final url = '${first['url'] ?? ''}'.trim();
  if (name.isEmpty && objectKey.isEmpty && url.isEmpty) {
    return <String, dynamic>{};
  }
  return <String, dynamic>{
    '${prefix}FileName': name,
    '${prefix}ObjectKey': objectKey,
    '${prefix}FileUrl': url,
    '${prefix}FileSize': first['sizeBytes'],
  };
}

/// 把合同归集详情和提案相关字段写入提案表单。
/// 新合同没有的抓取字段会写成空字符串，避免上一份合同的内容残留。
Map<String, dynamic> proposalIntakePatchFromContract({
  required String prefix,
  required Map<String, dynamic> detail,
}) {
  final related = detail['proposalRelated'] is Map
      ? Map<String, dynamic>.from(detail['proposalRelated'] as Map)
      : <String, dynamic>{};
  String pick(List<String> keys) {
    final fromRelated = _contractText(related, keys);
    if (fromRelated.isNotEmpty) return fromRelated;
    return _contractText(detail, keys);
  }

  final patch = <String, dynamic>{'${prefix}ContractId': detail['id']};
  for (final key in proposalIntakeContractFillKeys(prefix)) {
    patch[key] = '';
  }
  // 合同编号必须用合同归集编号；AI 抽到的对方文号不能盖掉所选合同。
  final registerNo = _contractText(detail, ['contractNo']);
  _putField(
    patch,
    '${prefix}No',
    registerNo.isNotEmpty ? registerNo : pick(['${prefix}No']),
  );
  _putField(patch, '${prefix}Name', pick(['${prefix}Name', 'contractName']));
  _putField(
    patch,
    '${prefix}SignDate',
    pick(['${prefix}SignDate', 'signDate']),
  );
  _putField(patch, '${prefix}OurParty', pick(['${prefix}OurParty', 'partyA']));
  _putField(
    patch,
    '${prefix}Counterparty',
    pick(['${prefix}Counterparty', 'partyB']),
  );
  _putField(
    patch,
    '${prefix}ValidPeriod',
    pick(['${prefix}ValidPeriod', 'endDate']),
  );
  _putField(patch, '${prefix}CoreTerms', pick(['${prefix}CoreTerms']));

  if (prefix == 'purchase') {
    _putField(patch, 'supplierPolicy', pick(['supplierPolicy']));
    _putField(patch, 'supplySettleMode', pick(['supplySettleMode']));
    _putField(patch, 'supplySettleCycle', pick(['supplySettleCycle']));
    _putField(patch, 'supplyPayer', pick(['supplyPayer']));
    _putField(patch, 'supplyPayAccount', pick(['supplyPayAccount']));
  } else {
    _putField(patch, 'channelPolicy', pick(['channelPolicy']));
    _putField(patch, 'channelSettleMode', pick(['channelSettleMode']));
    _putField(patch, 'channelSettleCycle', pick(['channelSettleCycle']));
    _putField(patch, 'channelPayee', pick(['channelPayee']));
    _putField(patch, 'channelReceiveAccount', pick(['channelReceiveAccount']));
  }
  patch['${prefix}FileName'] = '';
  patch['${prefix}ObjectKey'] = '';
  patch['${prefix}FileUrl'] = '';
  patch['${prefix}FileSize'] = null;
  patch.addAll(proposalIntakeFilePatchFromContractDetail(prefix, detail));
  return patch;
}

const kProposalContractSnapshotKey = 'contractFieldSnapshots';
const kProposalContractEditsKey = 'contractFieldEdits';

/// 只作废指定合同板块复核，不牵连市场、科技、财务等其他板块。
Map<String, dynamic> proposalIntakeClearContractReview(
  Map<String, dynamic> review, {
  required String prefix,
}) {
  final flag = '${prefix}ContractCompleted';
  final contractItems = review['contractItems'] is Map
      ? Map<String, dynamic>.from(review['contractItems'] as Map)
      : <String, dynamic>{};
  contractItems.removeWhere((key, _) => key.startsWith('$prefix.'));
  return Map<String, dynamic>.from(review)
    ..[flag] = false
    ..['contractsCompleted'] = false
    ..['contractItems'] = contractItems;
}

Map<String, String> proposalIntakeContractSnapshotValues(
  String prefix,
  Map<String, dynamic> form,
) {
  return <String, String>{
    for (final key in proposalIntakeContractFillKeys(prefix))
      key: '${form[key] ?? ''}'.trim(),
  };
}

Map<String, dynamic> proposalIntakeRememberContractSnapshot({
  required Map<String, dynamic> form,
  required String prefix,
}) {
  final next = Map<String, dynamic>.from(form);
  final snapshots = next[kProposalContractSnapshotKey] is Map
      ? Map<String, dynamic>.from(next[kProposalContractSnapshotKey] as Map)
      : <String, dynamic>{};
  snapshots[prefix] = proposalIntakeContractSnapshotValues(prefix, next);
  next[kProposalContractSnapshotKey] = snapshots;
  final edits = next[kProposalContractEditsKey] is Map
      ? Map<String, dynamic>.from(next[kProposalContractEditsKey] as Map)
      : <String, dynamic>{};
  for (final key in proposalIntakeContractFillKeys(prefix)) {
    edits.remove(key);
  }
  next[kProposalContractEditsKey] = edits;
  return next;
}

Map<String, dynamic> proposalIntakeConfirmContractEdits(
  Map<String, dynamic> form,
) {
  final snapshots = form[kProposalContractSnapshotKey] is Map
      ? Map<String, dynamic>.from(form[kProposalContractSnapshotKey] as Map)
      : const <String, dynamic>{};
  final edits = <String, dynamic>{};
  for (final prefix in const ['purchase', 'sales']) {
    final raw = snapshots[prefix];
    if (raw is! Map) continue;
    final original = Map<String, dynamic>.from(raw);
    for (final key in proposalIntakeContractFillKeys(prefix)) {
      final before = '${original[key] ?? ''}'.trim();
      final after = '${form[key] ?? ''}'.trim();
      if (before == after) continue;
      edits[key] = <String, String>{'original': before, 'current': after};
    }
  }
  final next = Map<String, dynamic>.from(form);
  next[kProposalContractEditsKey] = edits;
  return next;
}

ProposalContractFieldEdit? proposalIntakeContractEdit(
  Map<String, dynamic> form,
  String key,
) {
  final raw = form[kProposalContractEditsKey];
  if (raw is! Map) return null;
  final item = raw[key];
  if (item is! Map) return null;
  final original = '${item['original'] ?? ''}'.trim();
  final current = '${item['current'] ?? ''}'.trim();
  if (original == current) return null;
  return ProposalContractFieldEdit(
    key: key,
    original: original,
    current: current,
  );
}

class ProposalContractFieldEdit {
  const ProposalContractFieldEdit({
    required this.key,
    required this.original,
    required this.current,
  });

  final String key;
  final String original;
  final String current;
}

const _proposalIntakeAutoFormKeys = <String>{
  'marketOwner2',
  'marketOwner2UserId',
};

/// 仅当用户真正填写了业务内容时才算可以生成草稿。
/// 当前登录人自动带出的市场部负责人二不计入。
bool proposalIntakeHasMeaningfulContent(ProposalIntakeRow row) {
  if (row.title.trim().isNotEmpty) return true;
  return _formHasUserInput(row.form);
}

bool _formHasUserInput(Map<String, dynamic> form) {
  for (final entry in form.entries) {
    if (_proposalIntakeAutoFormKeys.contains(entry.key)) continue;
    if (_valueHasUserInput(entry.value)) return true;
  }
  return false;
}

bool _valueHasUserInput(Object? value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is bool) return value;
  if (value is num) return true;
  if (value is List) return value.any(_valueHasUserInput);
  if (value is Map) return value.values.any(_valueHasUserInput);
  return true;
}

String proposalIntakeActionLabel(String action) {
  return switch (action) {
    'fill' => '待填写',
    'fill_tech' => '待填写科技',
    'fill_finance_interface' => '待填写财务技术接口',
    'start_review' => '待重新提交复核',
    'review_market' => '待复核市场部',
    'review_tech' => '待复核科技',
    'review_finance' => '待复核财务',
    'review_finance_interface' => '待复核财务技术接口',
    'review_finance_module' => '待整板块复核财务',
    'review_contract' => '待审核合同',
    'submit_president' => '待通知最终人',
    'president_confirm' => '待最终确认',
    'start_tech_revision' => '待发起科技变更',
    'revise' => '最终人已驳回请从头填写',
    'revise_module' => '板块已驳回请修改',
    _ => '',
  };
}

String proposalIntakeStatusLabel(String status) {
  return switch (status) {
    'done' => '已完成',
    'pending_president' => '待最终确认',
    'reviewing' => '复核中',
    'filling' => '填写中',
    _ => '草稿',
  };
}

/// 把后端 UTC 时间转成本地时间，去掉 `Z` / 毫秒，列表展示用。
String formatProposalIntakeDateTime(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) {
    return text
        .replaceFirst('T', ' ')
        .replaceAll(RegExp(r'[Zz]$'), '')
        .split('.')
        .first
        .trim();
  }
  final local = parsed.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class ProposalTechnologyRecord {
  const ProposalTechnologyRecord({
    required this.id,
    required this.title,
    required this.platform,
    required this.capabilities,
    required this.outputForms,
    required this.developmentTypes,
    required this.hasRdCost,
    required this.rdAmount,
    required this.deliveryDate,
    required this.round,
    this.raw = const {},
  });

  final String id;
  final String title;
  final String platform;
  final List<String> capabilities;
  final List<String> outputForms;
  final List<String> developmentTypes;
  final String hasRdCost;
  final String rdAmount;
  final String deliveryDate;
  final int round;
  final Map<String, dynamic> raw;

  factory ProposalTechnologyRecord.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) {
      if (value is List) {
        return [
          for (final item in value)
            if ('$item'.trim().isNotEmpty) '$item'.trim(),
        ];
      }
      return const [];
    }

    int asInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value'.trim()) ?? 0;
    }

    return ProposalTechnologyRecord(
      id: '${json['id'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      platform: '${json['technologyPlatform'] ?? json['platform'] ?? ''}'
          .trim(),
      capabilities: strings(
        json['technologyCapabilities'] ?? json['capabilities'],
      ),
      outputForms: strings(json['outputForms']),
      developmentTypes: strings(json['developmentTypes']),
      hasRdCost: '${json['hasRdCost'] ?? ''}'.trim(),
      rdAmount: '${json['rdAmount'] ?? ''}'.trim(),
      deliveryDate: '${json['deliveryDate'] ?? ''}'.trim(),
      round: asInt(json['round']),
      raw: Map<String, dynamic>.from(json),
    );
  }
}

const proposalTechnologySnapshotKeys = <String>[
  'technologyPlatform',
  'technologyCapabilities',
  'outputForms',
  'developmentTypes',
  'hasRdCost',
  'rdAmount',
  'deliveryDate',
  'financeInterfaces',
  'onlineProductFiles',
];

Map<String, dynamic> proposalIntakeTechnologySnapshot(
  Map<String, dynamic> form,
) {
  final snap = <String, dynamic>{};
  for (final key in proposalTechnologySnapshotKeys) {
    if (!form.containsKey(key)) continue;
    final value = form[key];
    if (value is Map) {
      snap[key] = Map<String, dynamic>.from(value);
    } else if (value is List) {
      snap[key] = [...value];
    } else {
      snap[key] = value;
    }
  }
  return snap;
}

List<ProposalTechnologyRecord> proposalIntakeTechnologyRecords(
  Map<String, dynamic> form,
) {
  final raw = form['technologyRecords'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map)
        ProposalTechnologyRecord.fromJson(Map<String, dynamic>.from(item)),
  ];
}

List<ProposalTechnologyRecord> proposalIntakeTechnologyHistory(
  Map<String, dynamic> form,
) {
  final raw = form['technologyHistory'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map)
        ProposalTechnologyRecord.fromJson(Map<String, dynamic>.from(item)),
  ];
}

Map<String, dynamic> proposalIntakeAppendTechnologyRecord(
  Map<String, dynamic> form,
) {
  final records = [
    for (final item
        in (form['technologyRecords'] is List
            ? form['technologyRecords'] as List
            : const []))
      if (item is Map) Map<String, dynamic>.from(item),
  ];
  final snap = proposalIntakeTechnologySnapshot(form);
  records.add({
    'id': 'rec_${DateTime.now().microsecondsSinceEpoch}',
    'title': '对接记录${records.length + 1}',
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    ...snap,
  });
  return {...form, 'technologyRecords': records};
}

bool proposalIntakeMarketReviewBlocked(Map<String, dynamic> review) {
  final stage = '${review['stage'] ?? ''}'.trim();
  if (stage != 'tech_reviewing') return false;
  return review['technologyCompleted'] != true;
}

bool proposalIntakeFinanceInterfacesUnchanged({
  required Map<String, dynamic> form,
  required Map<String, dynamic> review,
}) {
  return _proposalJsonEqual(
    form['financeInterfaces'],
    review['lastFinanceInterfaces'],
  );
}

bool _proposalJsonEqual(Object? left, Object? right) {
  return jsonEncode(left ?? <String, dynamic>{}) ==
      jsonEncode(right ?? <String, dynamic>{});
}

/// 复核相关负责人：没选就不能通知科技 / 提交复核。
/// 销售和采购填写环节都要指定运营。
List<String> missingProposalReviewAssignees(
  Map<String, dynamic> form, {
  bool includeTech = true,
  bool purchase = false,
}) {
  int idOf(String key) => int.tryParse('${form[key] ?? ''}'.trim()) ?? 0;
  final missing = <String>[];
  void require(String key, String label) {
    if (idOf(key) <= 0) missing.add(label);
  }

  if (includeTech) require('technologyOwnerUserId', '科技部负责人');
  require('marketOwner2UserId', '市场部负责人二');
  require('marketOwner1UserId', '市场部负责人一');
  require('financeOwner1UserId', '财务部负责人一');
  require('financeOwner2UserId', '财务部负责人二');
  require('operatorUserId', '运营');
  return missing;
}

ProposalIntakeRow? nextProposalIntake({
  required List<ProposalIntakeRow> items,
  required int currentId,
  bool afterDecision = false,
}) {
  if (items.isEmpty) return null;
  if (afterDecision) {
    for (final item in items) {
      if (item.id != currentId) return item;
    }
    return null;
  }
  final index = items.indexWhere((item) => item.id == currentId);
  if (index < 0) {
    for (final item in items) {
      if (item.id != currentId) return item;
    }
    return null;
  }
  if (index + 1 >= items.length) return null;
  return items[index + 1];
}

CatalogRef? proposalIntakeFormRef(Map<String, dynamic> form, String key) =>
    catalogRefOrNull(form[key]);

/// 产品/券包上的结算渠道：优先自身 [channelRef]，否则从结算明细提升（兼容旧单）。
CatalogRef? proposalIntakeChannelRefFromJson(Map raw) {
  var ref = catalogRefOrNull(raw['channelRef']);
  if (ref != null && ref.isNotEmpty) return ref;
  final name = '${raw['channel'] ?? raw['channelName'] ?? ''}'.trim();
  final code = '${raw['channelCode'] ?? ''}'.trim();
  if (name.isNotEmpty || code.isNotEmpty) {
    return CatalogRef(
      code: code.isEmpty ? name : code,
      name: name.isEmpty ? code : name,
    );
  }
  final settlements = raw['settlements'];
  if (settlements is List) {
    for (final item in settlements) {
      if (item is! Map) continue;
      final fromSettle = catalogRefOrNull(item['channelRef']);
      if (fromSettle != null && fromSettle.isNotEmpty) return fromSettle;
    }
  }
  return null;
}

bool proposalIntakeSettleUsesRatio(ProposalFinanceSettleTerms terms) {
  final code = terms.settleModeRef?.code.trim();
  if (code == '1' || code == '5') return true;
  final mode = terms.settleMode;
  return mode.contains('比例') && !mode.contains('单价');
}

bool proposalIntakeSettleUsesUnitPrice(ProposalFinanceSettleTerms terms) {
  final code = terms.settleModeRef?.code.trim();
  if (code == '2' || code == '5') return true;
  return terms.settleMode.contains('单价');
}

bool proposalIntakeSettleIsTier(ProposalFinanceSettleTerms terms) {
  final code = terms.settleModeRef?.code.trim();
  if (code == '3') return true;
  return terms.settleMode.contains('阶梯');
}

/// 结算条款：收入或单条成本共用，字段对齐结算单「结算一」。
class ProposalFinanceSettleTerms {
  const ProposalFinanceSettleTerms({
    this.billType = '',
    this.billTypeRef,
    this.channelRef,
    this.settleMode = '',
    this.settleModeRef,
    this.settleRatio = '',
    this.settleUnitPrice = '',
    this.formula = '',
    this.formulaRef,
    this.invoiceType = '',
    this.taxRate = '',
    this.effectiveTime = '',
    this.expireTime = '',
    this.settlePrice = '',
    this.settleRule = '',
    this.counterparty = '',
    this.ourParty = '',
  });

  final String billType;
  final CatalogRef? billTypeRef;
  final CatalogRef? channelRef;
  final String settleMode;
  final CatalogRef? settleModeRef;
  final String settleRatio;
  final String settleUnitPrice;
  final String formula;
  final CatalogRef? formulaRef;
  final String invoiceType;
  final String taxRate;
  final String effectiveTime;
  final String expireTime;

  /// 旧字段：结算单价/比例。新数据优先写 settleRatio / settleUnitPrice。
  final String settlePrice;

  /// 旧字段：结算规则。新数据优先写 formula。
  final String settleRule;
  final String counterparty;
  final String ourParty;

  String get displayRatio {
    if (settleRatio.isNotEmpty) return settleRatio;
    if (settleUnitPrice.isEmpty &&
        (proposalIntakeSettleUsesRatio(this) || settlePrice.contains('%'))) {
      return settlePrice;
    }
    return '';
  }

  String get displayUnitPrice {
    if (settleUnitPrice.isNotEmpty) return settleUnitPrice;
    if (settleRatio.isEmpty &&
        settlePrice.isNotEmpty &&
        !proposalIntakeSettleUsesRatio(this) &&
        !settlePrice.contains('%')) {
      return settlePrice;
    }
    return '';
  }

  String get displayFormula {
    if (formulaRef != null && formulaRef!.isNotEmpty) {
      return formulaRef!.name.isNotEmpty
          ? formulaRef!.name
          : formulaRef!.formulaExpression;
    }
    return formula.isNotEmpty ? formula : settleRule;
  }

  String get resolvedPrice {
    if (proposalIntakeSettleUsesUnitPrice(this) &&
        !proposalIntakeSettleUsesRatio(this)) {
      return displayUnitPrice.isNotEmpty ? displayUnitPrice : settlePrice;
    }
    if (proposalIntakeSettleUsesRatio(this) &&
        !proposalIntakeSettleUsesUnitPrice(this)) {
      return displayRatio.isNotEmpty ? displayRatio : settlePrice;
    }
    if (displayRatio.isNotEmpty) return displayRatio;
    if (displayUnitPrice.isNotEmpty) return displayUnitPrice;
    return settlePrice;
  }

  String get resolvedRule => displayFormula;

  bool get isBlank =>
      billType.isEmpty &&
      (billTypeRef == null || billTypeRef!.isEmpty) &&
      (channelRef == null || channelRef!.isEmpty) &&
      settleMode.isEmpty &&
      (settleModeRef == null || settleModeRef!.isEmpty) &&
      settleRatio.isEmpty &&
      settleUnitPrice.isEmpty &&
      formula.isEmpty &&
      (formulaRef == null || formulaRef!.isEmpty) &&
      invoiceType.isEmpty &&
      taxRate.isEmpty &&
      effectiveTime.isEmpty &&
      expireTime.isEmpty &&
      settlePrice.isEmpty &&
      settleRule.isEmpty &&
      counterparty.isEmpty &&
      ourParty.isEmpty;

  bool get isComplete =>
      resolvedPrice.isNotEmpty &&
      resolvedRule.isNotEmpty &&
      counterparty.isNotEmpty &&
      ourParty.isNotEmpty &&
      taxRate.isNotEmpty;

  bool get isSkuComplete {
    if (taxRate.isEmpty || resolvedRule.isEmpty) return false;
    if (proposalIntakeSettleIsTier(this)) return true;
    if (proposalIntakeSettleUsesRatio(this) &&
        proposalIntakeSettleUsesUnitPrice(this)) {
      return displayRatio.isNotEmpty && displayUnitPrice.isNotEmpty;
    }
    return resolvedPrice.isNotEmpty;
  }

  String get fingerprint => [
    billTypeRef?.identity ?? billType,
    channelRef?.identity ?? '',
    settleModeRef?.identity ?? settleMode,
    displayRatio,
    displayUnitPrice,
    formulaRef?.identity ?? resolvedRule,
    invoiceType,
    taxRate,
    effectiveTime,
    expireTime,
    counterparty,
    ourParty,
  ].join('|');

  ProposalFinanceSettleTerms copyWith({
    String? billType,
    Object? billTypeRef = _catalogUnset,
    Object? channelRef = _catalogUnset,
    String? settleMode,
    Object? settleModeRef = _catalogUnset,
    String? settleRatio,
    String? settleUnitPrice,
    String? formula,
    Object? formulaRef = _catalogUnset,
    String? invoiceType,
    String? taxRate,
    String? effectiveTime,
    String? expireTime,
    String? settlePrice,
    String? settleRule,
    String? counterparty,
    String? ourParty,
  }) => ProposalFinanceSettleTerms(
    billType: billType ?? this.billType,
    billTypeRef: identical(billTypeRef, _catalogUnset)
        ? this.billTypeRef
        : billTypeRef as CatalogRef?,
    channelRef: identical(channelRef, _catalogUnset)
        ? this.channelRef
        : channelRef as CatalogRef?,
    settleMode: settleMode ?? this.settleMode,
    settleModeRef: identical(settleModeRef, _catalogUnset)
        ? this.settleModeRef
        : settleModeRef as CatalogRef?,
    settleRatio: settleRatio ?? this.settleRatio,
    settleUnitPrice: settleUnitPrice ?? this.settleUnitPrice,
    formula: formula ?? this.formula,
    formulaRef: identical(formulaRef, _catalogUnset)
        ? this.formulaRef
        : formulaRef as CatalogRef?,
    invoiceType: invoiceType ?? this.invoiceType,
    taxRate: taxRate ?? this.taxRate,
    effectiveTime: effectiveTime ?? this.effectiveTime,
    expireTime: expireTime ?? this.expireTime,
    settlePrice: settlePrice ?? this.settlePrice,
    settleRule: settleRule ?? this.settleRule,
    counterparty: counterparty ?? this.counterparty,
    ourParty: ourParty ?? this.ourParty,
  );

  ProposalFinanceSettleTerms clearedCatalog({required bool keepManual}) {
    return copyWith(
      channelRef: null,
      billType: keepManual ? billType : '',
      billTypeRef: null,
      settleMode: keepManual ? settleMode : '',
      settleModeRef: null,
      formula: keepManual ? formula : '',
      formulaRef: null,
    );
  }

  Map<String, dynamic> toJson() => {
    'billType': billTypeRef?.name ?? billType,
    'billTypeRef': catalogRefToJson(billTypeRef),
    'channelRef': catalogRefToJson(channelRef),
    'settleMode': settleModeRef?.name ?? settleMode,
    'settleModeRef': catalogRefToJson(settleModeRef),
    'settleRatio': settleRatio,
    'settleUnitPrice': settleUnitPrice,
    'formula': displayFormula,
    'formulaRef': catalogRefToJson(formulaRef),
    'invoiceType': invoiceType,
    'taxRate': taxRate,
    'effectiveTime': effectiveTime,
    'expireTime': expireTime,
    'settlePrice': resolvedPrice,
    'settleRule': resolvedRule,
    'counterparty': counterparty,
    'ourParty': ourParty,
  };

  factory ProposalFinanceSettleTerms.fromJson(Object? raw) {
    if (raw is! Map) return const ProposalFinanceSettleTerms();
    String read(String key) => '${raw[key] ?? ''}'.trim();
    return ProposalFinanceSettleTerms(
      billType: read('billType'),
      billTypeRef: catalogRefOrNull(raw['billTypeRef']),
      channelRef: catalogRefOrNull(raw['channelRef']),
      settleMode: read('settleMode'),
      settleModeRef: catalogRefOrNull(raw['settleModeRef']),
      settleRatio: read('settleRatio'),
      settleUnitPrice: read('settleUnitPrice'),
      formula: read('formula'),
      formulaRef: catalogRefOrNull(raw['formulaRef']),
      invoiceType: read('invoiceType'),
      taxRate: read('taxRate'),
      effectiveTime: read('effectiveTime'),
      expireTime: read('expireTime'),
      settlePrice: read('settlePrice'),
      settleRule: read('settleRule'),
      counterparty: read('counterparty'),
      ourParty: read('ourParty'),
    );
  }
}

const Object _catalogUnset = Object();

class ProposalFinanceCostLine {
  const ProposalFinanceCostLine({
    required this.id,
    this.name = '',
    this.terms = const ProposalFinanceSettleTerms(),
  });

  final String id;
  final String name;
  final ProposalFinanceSettleTerms terms;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, ...terms.toJson()};

  factory ProposalFinanceCostLine.fromJson(Object? raw) {
    if (raw is! Map) {
      return const ProposalFinanceCostLine(id: '');
    }
    return ProposalFinanceCostLine(
      id: '${raw['id'] ?? ''}'.trim(),
      name: '${raw['name'] ?? ''}'.trim(),
      terms: ProposalFinanceSettleTerms.fromJson(raw),
    );
  }
}

class ProposalFinanceModule {
  const ProposalFinanceModule({
    required this.id,
    this.title = '',
    this.naturalMonth = '',
    this.projectPeriodStart = '',
    this.projectPeriodEnd = '',
    this.revenue = const ProposalFinanceSettleTerms(),
    this.projectCosts = const [],
    this.businessCosts = const [],
  });

  final String id;
  final String title;

  /// 是 / 否。否时必须填写项目周期。
  final String naturalMonth;
  final String projectPeriodStart;
  final String projectPeriodEnd;
  final ProposalFinanceSettleTerms revenue;
  final List<ProposalFinanceCostLine> projectCosts;
  final List<ProposalFinanceCostLine> businessCosts;

  bool get usesProjectPeriod => naturalMonth == '否';

  String get projectPeriodLabel {
    if (projectPeriodStart.isEmpty && projectPeriodEnd.isEmpty) return '';
    if (projectPeriodStart.isNotEmpty && projectPeriodEnd.isNotEmpty) {
      return '$projectPeriodStart ~ $projectPeriodEnd';
    }
    return projectPeriodStart.isNotEmpty
        ? projectPeriodStart
        : projectPeriodEnd;
  }

  String get fingerprint {
    final costs = [
      for (final line in projectCosts)
        'P:${line.name}:${line.terms.fingerprint}',
      for (final line in businessCosts)
        'B:${line.name}:${line.terms.fingerprint}',
    ]..sort();
    final period = usesProjectPeriod
        ? '$naturalMonth|$projectPeriodStart|$projectPeriodEnd'
        : naturalMonth;
    return '${revenue.fingerprint}#${costs.join(';')}#$period';
  }

  bool get hasIdentity => !revenue.isBlank;

  bool get revenueComplete => revenue.isComplete;

  bool get periodComplete {
    if (naturalMonth != '是' && naturalMonth != '否') return false;
    if (usesProjectPeriod) {
      return projectPeriodStart.isNotEmpty && projectPeriodEnd.isNotEmpty;
    }
    return true;
  }

  bool get costsComplete {
    for (final line in [...projectCosts, ...businessCosts]) {
      if (line.name.isEmpty || !line.terms.isComplete) return false;
    }
    return true;
  }

  ProposalFinanceModule copyWith({
    String? title,
    String? naturalMonth,
    String? projectPeriodStart,
    String? projectPeriodEnd,
    ProposalFinanceSettleTerms? revenue,
    List<ProposalFinanceCostLine>? projectCosts,
    List<ProposalFinanceCostLine>? businessCosts,
  }) => ProposalFinanceModule(
    id: id,
    title: title ?? this.title,
    naturalMonth: naturalMonth ?? this.naturalMonth,
    projectPeriodStart: projectPeriodStart ?? this.projectPeriodStart,
    projectPeriodEnd: projectPeriodEnd ?? this.projectPeriodEnd,
    revenue: revenue ?? this.revenue,
    projectCosts: projectCosts ?? this.projectCosts,
    businessCosts: businessCosts ?? this.businessCosts,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'naturalMonth': naturalMonth,
    'projectPeriodStart': usesProjectPeriod ? projectPeriodStart : '',
    'projectPeriodEnd': usesProjectPeriod ? projectPeriodEnd : '',
    'revenue': revenue.toJson(),
    'projectCosts': [for (final line in projectCosts) line.toJson()],
    'businessCosts': [for (final line in businessCosts) line.toJson()],
  };

  factory ProposalFinanceModule.fromJson(Object? raw) {
    if (raw is! Map) return const ProposalFinanceModule(id: '');
    List<ProposalFinanceCostLine> lines(Object? value) {
      if (value is! List) return const [];
      return [
        for (final item in value)
          if (item is Map) ProposalFinanceCostLine.fromJson(item),
      ].where((line) => line.id.isNotEmpty || line.name.isNotEmpty).toList();
    }

    return ProposalFinanceModule(
      id: '${raw['id'] ?? ''}'.trim(),
      title: '${raw['title'] ?? ''}'.trim(),
      naturalMonth: _naturalMonthChoice(raw['naturalMonth']),
      projectPeriodStart: '${raw['projectPeriodStart'] ?? ''}'.trim(),
      projectPeriodEnd: '${raw['projectPeriodEnd'] ?? ''}'.trim(),
      revenue: ProposalFinanceSettleTerms.fromJson(raw['revenue']),
      projectCosts: lines(raw['projectCosts']),
      businessCosts: lines(raw['businessCosts']),
    );
  }
}

class ProposalLaunchRow {
  const ProposalLaunchRow({
    required this.id,
    this.province = '',
    this.faceValue = '',
    this.needFinanceModule = false,
    this.financeModuleId = '',
  });

  final String id;
  final String province;
  final String faceValue;
  final bool needFinanceModule;
  final String financeModuleId;

  bool get isBlank =>
      province.isEmpty && faceValue.isEmpty && !needFinanceModule;

  ProposalLaunchRow copyWith({
    String? province,
    String? faceValue,
    bool? needFinanceModule,
    String? financeModuleId,
  }) => ProposalLaunchRow(
    id: id,
    province: province ?? this.province,
    faceValue: faceValue ?? this.faceValue,
    needFinanceModule: needFinanceModule ?? this.needFinanceModule,
    financeModuleId: financeModuleId ?? this.financeModuleId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'province': province,
    'faceValue': faceValue,
    'needFinanceModule': needFinanceModule,
    'financeModuleId': financeModuleId,
  };

  factory ProposalLaunchRow.fromJson(Object? raw) {
    if (raw is! Map) return const ProposalLaunchRow(id: '');
    return ProposalLaunchRow(
      id: '${raw['id'] ?? ''}'.trim(),
      province: '${raw['province'] ?? ''}'.trim(),
      faceValue: '${raw['faceValue'] ?? ''}'.trim(),
      needFinanceModule: _asBool(raw['needFinanceModule']),
      financeModuleId: '${raw['financeModuleId'] ?? ''}'.trim(),
    );
  }
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  final text = '$value'.trim().toLowerCase();
  return text == 'true' || text == '1' || text == '需要' || text == 'yes';
}

String _naturalMonthChoice(Object? value) {
  if (value is bool) return value ? '是' : '否';
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return '';
  final lower = text.toLowerCase();
  if (lower == 'true' || lower == '1' || text == '是' || lower == 'yes') {
    return '是';
  }
  if (lower == 'false' || lower == '0' || text == '否' || lower == 'no') {
    return '否';
  }
  return text;
}

List<ProposalLaunchRow> proposalIntakeLaunchRows(Map<String, dynamic> form) {
  final raw = form['launchRows'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) ProposalLaunchRow.fromJson(item),
  ].where((row) => row.id.isNotEmpty).toList();
}

List<ProposalFinanceModule> proposalIntakeFinanceModules(
  Map<String, dynamic> form,
) {
  final raw = form['financeModules'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) ProposalFinanceModule.fromJson(item),
  ].where((item) => item.id.isNotEmpty).toList();
}

String proposalIntakeNewLaunchId() =>
    'lr-${DateTime.now().microsecondsSinceEpoch}';

class ProposalSkuSettleRow {
  const ProposalSkuSettleRow({
    required this.id,
    this.terms = const ProposalFinanceSettleTerms(),
  });

  final String id;
  final ProposalFinanceSettleTerms terms;

  ProposalSkuSettleRow copyWith({ProposalFinanceSettleTerms? terms}) =>
      ProposalSkuSettleRow(id: id, terms: terms ?? this.terms);

  Map<String, dynamic> toJson() => {'id': id, ...terms.toJson()};

  factory ProposalSkuSettleRow.fromJson(Object? raw) {
    if (raw is! Map) return const ProposalSkuSettleRow(id: '');
    final id = '${raw['id'] ?? ''}'.trim();
    return ProposalSkuSettleRow(
      id: id,
      terms: ProposalFinanceSettleTerms.fromJson(raw),
    );
  }
}

String proposalIntakeNewSkuSettleId() =>
    'st-${DateTime.now().microsecondsSinceEpoch}';

String proposalIntakeSettleLabel(int index) {
  const names = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
  if (index >= 0 && index < names.length) return '结算${names[index]}';
  return '结算${index + 1}';
}

List<ProposalSkuSettleRow> proposalIntakeSettlementsOf({
  required String id,
  required List<ProposalSkuSettleRow> settlements,
}) {
  if (settlements.isNotEmpty) return settlements;
  return [ProposalSkuSettleRow(id: '$id-st-1')];
}

List<ProposalSkuSettleRow> proposalIntakeSkuSettlements(
  ProposalSkuDetailRow row,
) => proposalIntakeSettlementsOf(id: row.id, settlements: row.settlements);

ProposalFinanceSettleTerms proposalIntakeTermsFromChannelSettlementItem(
  ChannelProductSettlementItem item, {
  CatalogRef? channelRef,
  List<CatalogRef> formulas = const [],
  List<CatalogRef> billTypes = const [],
}) {
  final settleModeRef = item.settleModeRef;
  final billTypeRef = catalogMatchByCode(item.billTypeRef, billTypes);
  final formulaRef = catalogMatchFormula(
    formulaContent: item.formulaContent,
    settleMethod: item.settleMethod,
    formulas: formulas,
  );
  final invoice = item.invoiceTypeCode.isNotEmpty
      ? item.invoiceTypeCode
      : item.invoiceTypeName;
  final tax = item.taxRateCode.isNotEmpty ? item.taxRateCode : item.taxRateName;
  final ratio = catalogScalarText(item.settlementRatio, percent: true);
  final unitPrice = catalogScalarText(item.unitPrice);
  return ProposalFinanceSettleTerms(
    billType: billTypeRef?.name ?? '',
    billTypeRef: billTypeRef,
    channelRef: channelRef,
    settleMode: settleModeRef?.name ?? '',
    settleModeRef: settleModeRef,
    settleRatio: ratio,
    settleUnitPrice: unitPrice,
    formula: formulaRef?.name ?? '',
    formulaRef: formulaRef,
    invoiceType: invoice,
    taxRate: tax,
    effectiveTime: catalogDateText(item.effectiveTime),
    expireTime: catalogDateText(item.expireTime),
    settlePrice: ratio.isNotEmpty ? ratio : unitPrice,
    settleRule: formulaRef?.name ?? '',
    counterparty: item.counterpartyEntity,
    ourParty: item.ourEntity,
  );
}

List<ProposalSkuSettleRow> proposalIntakeSettlementsFromChannelCatalog(
  ChannelProductSettlement data, {
  CatalogRef? fallbackChannel,
  List<CatalogRef> formulas = const [],
  List<CatalogRef> billTypes = const [],
}) {
  final channel = data.channelRef ?? fallbackChannel;
  if (data.items.isEmpty) {
    return [
      ProposalSkuSettleRow(
        id: proposalIntakeNewSkuSettleId(),
        terms: ProposalFinanceSettleTerms(channelRef: channel),
      ),
    ];
  }
  return [
    for (var i = 0; i < data.items.length; i++)
      ProposalSkuSettleRow(
        id: 'st-asset-${data.id ?? 0}-${data.items[i].sortNo}-$i',
        terms: proposalIntakeTermsFromChannelSettlementItem(
          data.items[i],
          channelRef: channel,
          formulas: formulas,
          billTypes: billTypes,
        ),
      ),
  ];
}

bool proposalIntakeIsCouponPack(Map<String, dynamic> form) {
  final raw = form['isCouponPack'];
  if (raw is bool) return raw;
  final text = '$raw'.trim().toLowerCase();
  return text == 'true' || text == '1' || text == '是' || text == 'yes';
}

bool proposalIntakeIsExistingBuilt(Map<String, dynamic> form) {
  return proposalIntakeExistingBuiltOverride(form) ??
      (proposalIntakeSkuDetails(form).any((item) => item.isExistingBuilt) ||
          proposalIntakeCouponPacks(form).any((item) => item.isExistingBuilt));
}

bool? proposalIntakeExistingBuiltOverride(Map<String, dynamic> form) {
  final raw = form['isExistingBuilt'];
  if (raw is bool) return raw;
  final text = '$raw'.trim().toLowerCase();
  if (text == 'true' || text == '1' || text == '是' || text == 'yes') {
    return true;
  }
  if (text == 'false' || text == '0' || text == '否' || text == 'no') {
    return false;
  }
  return null;
}

List<ProposalSkuSettleRow> proposalIntakePackSettlements(
  ProposalCouponPackRow pack,
) => proposalIntakeSettlementsOf(id: pack.id, settlements: pack.settlements);

List<String> proposalIntakeSkuSettleReviewKeys(Map<String, dynamic> form) {
  if (proposalIntakeIsCouponPack(form)) {
    return [
      for (final pack in proposalIntakeCouponPacks(form))
        for (final settle in proposalIntakePackSettlements(pack))
          'packSettle:${pack.id}:${settle.id}',
    ];
  }
  return [
    for (final sku in proposalIntakeSkuDetails(form))
      for (final settle in proposalIntakeSkuSettlements(sku))
        'skuSettle:${sku.id}:${settle.id}',
  ];
}

bool proposalIntakeSkuStarted(ProposalSkuDetailRow sku) {
  return sku.productName.trim().isNotEmpty ||
      (sku.assetProduct != null && sku.assetProduct!.isNotEmpty);
}

bool proposalIntakePackStarted(ProposalCouponPackRow pack) {
  return pack.name.trim().isNotEmpty ||
      (pack.assetProduct != null && pack.assetProduct!.isNotEmpty) ||
      pack.skuIds.isNotEmpty;
}

List<String> proposalIntakeSkuSettleIssues(
  Map<String, dynamic> form, {
  bool includeSettlements = true,
}) {
  final issues = <String>[];
  final channel = proposalIntakeSkuDetails(form);
  final existingBuilt = proposalIntakeExistingBuiltOverride(form) == true;
  final couponPack = proposalIntakeIsCouponPack(form);
  if (existingBuilt) {
    if (couponPack) {
      if (proposalIntakeCouponPacks(form).isEmpty) {
        issues.add('已勾选已建产品，请至少添加一条券包并搜索选择已建券包');
      }
    } else if (channel.isEmpty) {
      issues.add('已勾选已建产品，请至少添加一条渠道产品并搜索选择已建产品');
    }
  }
  for (var i = 0; i < channel.length; i++) {
    final sku = channel[i];
    if (existingBuilt || sku.isExistingBuilt) {
      if (sku.syncSourceCode.isEmpty) {
        issues.add('渠道产品第${i + 1}条请选择业务平台');
      }
      if (sku.assetProduct == null || sku.assetProduct!.isEmpty) {
        issues.add('渠道产品第${i + 1}条请搜索并选择已建产品');
      }
    }
  }
  if (couponPack) {
    final packs = proposalIntakeCouponPacks(form);
    final skuIds = {for (final sku in channel) sku.id};
    for (var i = 0; i < packs.length; i++) {
      final pack = packs[i];
      final existing = existingBuilt || pack.isExistingBuilt;
      if (existing) {
        if (pack.syncSourceCode.isEmpty) {
          issues.add('券包第${i + 1}条请选择业务平台');
        }
        if (pack.assetProduct == null || pack.assetProduct!.isEmpty) {
          issues.add('券包第${i + 1}条请搜索并选择已建券包');
        }
      } else if (proposalIntakePackStarted(pack)) {
        if (pack.name.isEmpty) {
          issues.add('券包第${i + 1}条请填写券包名称');
        }
        final selected = [
          for (final id in pack.skuIds)
            if (skuIds.contains(id)) id,
        ];
        if (selected.isEmpty) {
          final name = pack.name.isEmpty ? '第${i + 1}条' : pack.name;
          issues.add('券包「$name」请选择包含的渠道产品');
        }
      }
      if (!includeSettlements) continue;
      if (!existing && !proposalIntakePackStarted(pack)) continue;
      final label = pack.name.isEmpty ? '第${i + 1}条' : pack.name;
      final settlements = proposalIntakePackSettlements(pack);
      for (var j = 0; j < settlements.length; j++) {
        if (!settlements[j].terms.isSkuComplete) {
          issues.add(
            '券包「$label」${proposalIntakeSettleLabel(j)}未填完结算方式对应金额、计算公式、税率',
          );
        }
      }
    }
    return issues;
  }
  if (!includeSettlements) return issues;
  for (var i = 0; i < channel.length; i++) {
    final sku = channel[i];
    if (!existingBuilt && !sku.isExistingBuilt && !proposalIntakeSkuStarted(sku)) {
      continue;
    }
    final name = sku.productName.isEmpty ? '第${i + 1}条' : sku.productName;
    final settlements = proposalIntakeSkuSettlements(sku);
    for (var j = 0; j < settlements.length; j++) {
      if (!settlements[j].terms.isSkuComplete) {
        issues.add(
          '渠道产品「$name」${proposalIntakeSettleLabel(j)}未填完结算方式对应金额、计算公式、税率',
        );
      }
    }
  }
  return issues;
}

class ProposalSkuDetailRow {
  const ProposalSkuDetailRow({
    required this.id,
    this.productName = '',
    this.faceValue = '',
    this.productCategoryL1 = '',
    this.productCategoryL2 = '',
    this.channelCategoryL1 = '',
    this.channelCategoryL2 = '',
    this.syncZhongyouHaoke = '',
    this.effectiveDate = '',
    this.expireDate = '',
    this.supplierCodes = '',
    this.inventoryQty = '',
    this.syncSourceRef,
    this.institutionRef,
    this.channelRef,
    this.existingBuilt = '',
    this.assetProduct,
    this.settlements = const [],
  });

  final String id;
  final String productName;
  final String faceValue;
  final String productCategoryL1;
  final String productCategoryL2;
  final String channelCategoryL1;
  final String channelCategoryL2;
  final String syncZhongyouHaoke;
  final String effectiveDate;
  final String expireDate;
  final String supplierCodes;
  final String inventoryQty;
  final CatalogRef? syncSourceRef;
  final CatalogRef? institutionRef;
  final CatalogRef? channelRef;
  final String existingBuilt;
  final ChannelProductHit? assetProduct;
  final List<ProposalSkuSettleRow> settlements;

  String get syncSourceCode => (syncSourceRef?.code ?? '').trim();
  String get institutionCode => (institutionRef?.code ?? '').trim();
  String get institutionName => (institutionRef?.name ?? '').trim();
  String get channelCode => (channelRef?.code ?? '').trim();
  String get channelName => (channelRef?.name ?? '').trim();
  bool get isExistingBuilt => existingBuilt.trim() == '是';

  bool get isBlank =>
      productName.isEmpty &&
      faceValue.isEmpty &&
      productCategoryL1.isEmpty &&
      productCategoryL2.isEmpty &&
      channelCategoryL1.isEmpty &&
      channelCategoryL2.isEmpty &&
      syncZhongyouHaoke.isEmpty &&
      effectiveDate.isEmpty &&
      expireDate.isEmpty &&
      supplierCodes.isEmpty &&
      inventoryQty.isEmpty &&
      (syncSourceRef == null || syncSourceRef!.isEmpty) &&
      (institutionRef == null || institutionRef!.isEmpty) &&
      (channelRef == null || channelRef!.isEmpty) &&
      existingBuilt.isEmpty &&
      (assetProduct == null || assetProduct!.isEmpty);

  ProposalSkuDetailRow copyWith({
    String? productName,
    String? faceValue,
    String? productCategoryL1,
    String? productCategoryL2,
    String? channelCategoryL1,
    String? channelCategoryL2,
    String? syncZhongyouHaoke,
    String? effectiveDate,
    String? expireDate,
    String? supplierCodes,
    String? inventoryQty,
    Object? syncSourceRef = _catalogUnset,
    Object? institutionRef = _catalogUnset,
    Object? channelRef = _catalogUnset,
    String? existingBuilt,
    Object? assetProduct = _catalogUnset,
    List<ProposalSkuSettleRow>? settlements,
  }) => ProposalSkuDetailRow(
    id: id,
    productName: productName ?? this.productName,
    faceValue: faceValue ?? this.faceValue,
    productCategoryL1: productCategoryL1 ?? this.productCategoryL1,
    productCategoryL2: productCategoryL2 ?? this.productCategoryL2,
    channelCategoryL1: channelCategoryL1 ?? this.channelCategoryL1,
    channelCategoryL2: channelCategoryL2 ?? this.channelCategoryL2,
    syncZhongyouHaoke: syncZhongyouHaoke ?? this.syncZhongyouHaoke,
    effectiveDate: effectiveDate ?? this.effectiveDate,
    expireDate: expireDate ?? this.expireDate,
    supplierCodes: supplierCodes ?? this.supplierCodes,
    inventoryQty: inventoryQty ?? this.inventoryQty,
    syncSourceRef: identical(syncSourceRef, _catalogUnset)
        ? this.syncSourceRef
        : syncSourceRef as CatalogRef?,
    institutionRef: identical(institutionRef, _catalogUnset)
        ? this.institutionRef
        : institutionRef as CatalogRef?,
    channelRef: identical(channelRef, _catalogUnset)
        ? this.channelRef
        : channelRef as CatalogRef?,
    existingBuilt: existingBuilt ?? this.existingBuilt,
    assetProduct: identical(assetProduct, _catalogUnset)
        ? this.assetProduct
        : assetProduct as ChannelProductHit?,
    settlements: settlements ?? this.settlements,
  );

  ProposalSkuDetailRow applyAssetProduct(
    ChannelProductHit? hit, {
    List<ProposalSkuSettleRow>? settlements,
  }) {
    return copyWith(
      assetProduct: hit,
      productName: hit?.productName ?? '',
      channelRef: hit?.channelRef,
      settlements: settlements ??
          (hit == null
              ? [ProposalSkuSettleRow(id: proposalIntakeNewSkuSettleId())]
              : [
                  for (final item in this.settlements)
                    item.copyWith(
                      terms: item.terms.copyWith(channelRef: hit.channelRef),
                    ),
                ]),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'productName': productName,
    'faceValue': faceValue,
    'productCategoryL1': productCategoryL1,
    'productCategoryL2': productCategoryL2,
    'channelCategoryL1': channelCategoryL1,
    'channelCategoryL2': channelCategoryL2,
    'syncZhongyouHaoke': syncZhongyouHaoke,
    'effectiveDate': effectiveDate,
    'expireDate': expireDate,
    'supplierCodes': supplierCodes,
    'inventoryQty': inventoryQty,
    'syncSource': syncSourceCode,
    'syncSourceRef': catalogRefToJson(syncSourceRef),
    'institution': institutionName,
    'institutionCode': institutionCode,
    'institutionRef': catalogRefToJson(institutionRef),
    'channel': channelName,
    'channelCode': channelCode,
    'channelRef': catalogRefToJson(channelRef),
    'existingBuilt': existingBuilt,
    'assetProduct': assetProduct?.toJson(),
    'settlements': [
      for (final item in settlements)
        item
            .copyWith(terms: item.terms.copyWith(channelRef: channelRef))
            .toJson(),
    ],
  };

  factory ProposalSkuDetailRow.fromJson(Object? raw) {
    if (raw is! Map) return const ProposalSkuDetailRow(id: '');
    var syncRef = catalogRefOrNull(raw['syncSourceRef']);
    if (syncRef == null) {
      final code = '${raw['syncSource'] ?? ''}'.trim();
      if (code.isNotEmpty) syncRef = CatalogRef(code: code, name: code);
    }
    var institution = catalogRefOrNull(raw['institutionRef']);
    if (institution == null) {
      final name = '${raw['institution'] ?? raw['institutionName'] ?? ''}'
          .trim();
      final code = '${raw['institutionCode'] ?? ''}'.trim();
      if (name.isNotEmpty || code.isNotEmpty) {
        institution = CatalogRef(
          code: code.isEmpty ? name : code,
          name: name.isEmpty ? code : name,
        );
      }
    }
    var asset = channelProductHitOrNull(raw['assetProduct']);
    var productName = '${raw['productName'] ?? ''}'.trim();
    if (productName.isEmpty) productName = asset?.productName ?? '';
    var channelRef = proposalIntakeChannelRefFromJson(raw);
    channelRef ??= asset?.channelRef;
    return ProposalSkuDetailRow(
      id: '${raw['id'] ?? ''}'.trim(),
      productName: productName,
      faceValue: '${raw['faceValue'] ?? raw['skuFaceValue'] ?? ''}'.trim(),
      productCategoryL1: '${raw['productCategoryL1'] ?? ''}'.trim(),
      productCategoryL2: '${raw['productCategoryL2'] ?? ''}'.trim(),
      channelCategoryL1: '${raw['channelCategoryL1'] ?? ''}'.trim(),
      channelCategoryL2: '${raw['channelCategoryL2'] ?? ''}'.trim(),
      syncZhongyouHaoke: '${raw['syncZhongyouHaoke'] ?? ''}'.trim(),
      effectiveDate:
          '${raw['effectiveDate'] ?? raw['productEffectiveDate'] ?? ''}'.trim(),
      expireDate: '${raw['expireDate'] ?? raw['productExpireDate'] ?? ''}'
          .trim(),
      supplierCodes: '${raw['supplierCodes'] ?? ''}'.trim(),
      inventoryQty: '${raw['inventoryQty'] ?? ''}'.trim(),
      syncSourceRef: syncRef,
      institutionRef: institution,
      channelRef: channelRef,
      existingBuilt: '${raw['existingBuilt'] ?? ''}'.trim(),
      assetProduct: asset,
      settlements: [
        for (final item in raw['settlements'] is List
            ? raw['settlements'] as List
            : const [])
          if (item is Map) ProposalSkuSettleRow.fromJson(item),
      ].where((item) => item.id.isNotEmpty).toList(),
    );
  }
}

ProposalSkuDetailRow? proposalIntakeLegacySkuDetail(Map<String, dynamic> form) {
  String read(String key) => '${form[key] ?? ''}'.trim();
  final row = ProposalSkuDetailRow(
    id: 'sku-legacy',
    productName: read('productName'),
    faceValue: read('skuFaceValue'),
    productCategoryL1: read('productCategoryL1'),
    productCategoryL2: read('productCategoryL2'),
    channelCategoryL1: read('channelCategoryL1'),
    channelCategoryL2: read('channelCategoryL2'),
    syncZhongyouHaoke: read('syncZhongyouHaoke'),
    effectiveDate: read('productEffectiveDate'),
    expireDate: read('productExpireDate'),
    supplierCodes: read('supplierCodes'),
    inventoryQty: read('inventoryQty'),
  );
  return row.isBlank ? null : row;
}

List<ProposalSkuDetailRow> proposalIntakeSkuDetails(Map<String, dynamic> form) {
  final raw = form['skuDetails'];
  if (raw is List) {
    final rows = [
      for (final item in raw)
        if (item is Map) ProposalSkuDetailRow.fromJson(item),
    ].where((row) => row.id.isNotEmpty).toList();
    if (rows.isNotEmpty) return rows;
  }
  final legacy = proposalIntakeLegacySkuDetail(form);
  return legacy == null ? const [] : [legacy];
}

String proposalIntakeNewSkuId() =>
    'sku-${DateTime.now().microsecondsSinceEpoch}';

String proposalIntakeNewCouponPackId() =>
    'pack-${DateTime.now().microsecondsSinceEpoch}';

class ProposalCouponPackRow {
  const ProposalCouponPackRow({
    required this.id,
    this.name = '',
    this.skuIds = const [],
    this.syncSourceRef,
    this.institutionRef,
    this.channelRef,
    this.existingBuilt = '',
    this.assetProduct,
    this.settlements = const [],
  });

  final String id;
  final String name;
  final List<String> skuIds;
  final CatalogRef? syncSourceRef;
  final CatalogRef? institutionRef;
  final CatalogRef? channelRef;
  final String existingBuilt;
  final ChannelProductHit? assetProduct;
  final List<ProposalSkuSettleRow> settlements;

  String get syncSourceCode => (syncSourceRef?.code ?? '').trim();
  String get institutionCode => (institutionRef?.code ?? '').trim();
  String get institutionName => (institutionRef?.name ?? '').trim();
  String get channelCode => (channelRef?.code ?? '').trim();
  String get channelName => (channelRef?.name ?? '').trim();
  bool get isExistingBuilt => existingBuilt.trim() == '是';

  ProposalCouponPackRow copyWith({
    String? name,
    List<String>? skuIds,
    Object? syncSourceRef = _catalogUnset,
    Object? institutionRef = _catalogUnset,
    Object? channelRef = _catalogUnset,
    String? existingBuilt,
    Object? assetProduct = _catalogUnset,
    List<ProposalSkuSettleRow>? settlements,
  }) => ProposalCouponPackRow(
    id: id,
    name: name ?? this.name,
    skuIds: skuIds ?? this.skuIds,
    syncSourceRef: identical(syncSourceRef, _catalogUnset)
        ? this.syncSourceRef
        : syncSourceRef as CatalogRef?,
    institutionRef: identical(institutionRef, _catalogUnset)
        ? this.institutionRef
        : institutionRef as CatalogRef?,
    channelRef: identical(channelRef, _catalogUnset)
        ? this.channelRef
        : channelRef as CatalogRef?,
    existingBuilt: existingBuilt ?? this.existingBuilt,
    assetProduct: identical(assetProduct, _catalogUnset)
        ? this.assetProduct
        : assetProduct as ChannelProductHit?,
    settlements: settlements ?? this.settlements,
  );

  ProposalCouponPackRow applyAssetProduct(
    ChannelProductHit? hit, {
    List<ProposalSkuSettleRow>? settlements,
  }) {
    return copyWith(
      assetProduct: hit,
      name: hit?.productName ?? '',
      channelRef: hit?.channelRef,
      settlements: settlements ??
          (hit == null
              ? [ProposalSkuSettleRow(id: proposalIntakeNewSkuSettleId())]
              : [
                  for (final item in this.settlements)
                    item.copyWith(
                      terms: item.terms.copyWith(channelRef: hit.channelRef),
                    ),
                ]),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'skuIds': skuIds,
    'syncSource': syncSourceCode,
    'syncSourceRef': catalogRefToJson(syncSourceRef),
    'institution': institutionName,
    'institutionCode': institutionCode,
    'institutionRef': catalogRefToJson(institutionRef),
    'channel': channelName,
    'channelCode': channelCode,
    'channelRef': catalogRefToJson(channelRef),
    'existingBuilt': existingBuilt,
    'assetProduct': assetProduct?.toJson(),
    'settlements': [
      for (final item in settlements)
        item
            .copyWith(terms: item.terms.copyWith(channelRef: channelRef))
            .toJson(),
    ],
  };

  factory ProposalCouponPackRow.fromJson(Object? raw) {
    if (raw is! Map) return const ProposalCouponPackRow(id: '');
    final skuRaw = raw['skuIds'];
    var syncRef = catalogRefOrNull(raw['syncSourceRef']);
    if (syncRef == null) {
      final code = '${raw['syncSource'] ?? ''}'.trim();
      if (code.isNotEmpty) syncRef = CatalogRef(code: code, name: code);
    }
    var institution = catalogRefOrNull(raw['institutionRef']);
    if (institution == null) {
      final name = '${raw['institution'] ?? raw['institutionName'] ?? ''}'
          .trim();
      final code = '${raw['institutionCode'] ?? ''}'.trim();
      if (name.isNotEmpty || code.isNotEmpty) {
        institution = CatalogRef(
          code: code.isEmpty ? name : code,
          name: name.isEmpty ? code : name,
        );
      }
    }
    var asset = channelProductHitOrNull(raw['assetProduct']);
    var name = '${raw['name'] ?? raw['packName'] ?? ''}'.trim();
    if (name.isEmpty) name = asset?.productName ?? '';
    var channelRef = proposalIntakeChannelRefFromJson(raw);
    channelRef ??= asset?.channelRef;
    return ProposalCouponPackRow(
      id: '${raw['id'] ?? ''}'.trim(),
      name: name,
      skuIds: [
        for (final item in skuRaw is List ? skuRaw : const [])
          '${item ?? ''}'.trim(),
      ].where((id) => id.isNotEmpty).toList(),
      syncSourceRef: syncRef,
      institutionRef: institution,
      channelRef: channelRef,
      existingBuilt: '${raw['existingBuilt'] ?? ''}'.trim(),
      assetProduct: asset,
      settlements: [
        for (final item in raw['settlements'] is List
            ? raw['settlements'] as List
            : const [])
          if (item is Map) ProposalSkuSettleRow.fromJson(item),
      ].where((item) => item.id.isNotEmpty).toList(),
    );
  }
}

List<ProposalCouponPackRow> proposalIntakeCouponPacks(
  Map<String, dynamic> form,
) {
  final raw = form['couponPacks'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) ProposalCouponPackRow.fromJson(item),
  ].where((item) => item.id.isNotEmpty).toList();
}

String proposalIntakeNewFinanceModuleId() =>
    'fm-${DateTime.now().microsecondsSinceEpoch}';

/// 条款相同（且已填过收入条款）则返回可关联的模块。
ProposalFinanceModule? proposalIntakeMatchingFinanceModule(
  List<ProposalFinanceModule> modules,
  ProposalFinanceModule candidate, {
  String skipId = '',
}) {
  if (!candidate.hasIdentity) return null;
  for (final item in modules) {
    if (item.id.isEmpty || item.id == skipId || item.id == candidate.id) {
      continue;
    }
    if (item.fingerprint == candidate.fingerprint) return item;
  }
  return null;
}

({List<ProposalLaunchRow> rows, List<ProposalFinanceModule> modules})
proposalIntakeLinkFinanceModule({
  required List<ProposalLaunchRow> rows,
  required List<ProposalFinanceModule> modules,
  required String launchRowId,
  String? associateModuleId,
}) {
  final nextRows = [for (final row in rows) row];
  final nextModules = [for (final item in modules) item];
  final index = nextRows.indexWhere((row) => row.id == launchRowId);
  if (index < 0) {
    return (rows: nextRows, modules: nextModules);
  }
  var moduleId = (associateModuleId ?? '').trim();
  if (moduleId.isEmpty) {
    final created = ProposalFinanceModule(
      id: proposalIntakeNewFinanceModuleId(),
      title: '财务模块${nextModules.length + 1}',
    );
    nextModules.add(created);
    moduleId = created.id;
  } else if (!nextModules.any((item) => item.id == moduleId)) {
    return (rows: nextRows, modules: nextModules);
  }
  nextRows[index] = nextRows[index].copyWith(financeModuleId: moduleId);
  return (rows: nextRows, modules: nextModules);
}

List<String> proposalIntakeLaunchFinanceIssues(Map<String, dynamic> form) {
  final issues = <String>[];
  for (final module in proposalIntakeFinanceModules(form)) {
    final title = module.title.isEmpty ? module.id : module.title;
    if (!module.periodComplete) {
      issues.add(
        module.usesProjectPeriod
            ? '财务模块「$title」非自然月请选择项目周期'
            : '财务模块「$title」请选择是否自然月',
      );
    }
    if (!module.revenueComplete) {
      issues.add('财务模块「$title」收入条款未填完');
    }
    if (!module.costsComplete) {
      issues.add('财务模块「$title」成本项条款未填完');
    }
  }
  return issues;
}

List<String> proposalIntakeLaunchModuleReviewKeys(Map<String, dynamic> form) {
  return [
    for (final item in proposalIntakeFinanceModules(form))
      'launchModule:${item.id}',
  ];
}

const kPurchaseProposalTypes = ['新增', '变更', '延续'];

const kPurchaseCapabilityInputForms = [
  'API接口',
  'H5',
  'SDK',
  '小程序',
  'APP',
  'MCP',
];

const kPurchaseDevelopmentTypes = ['运营配置', '标准接口对接', '涉及改造', '新增产品'];

class ProposalSupplyProductRow {
  const ProposalSupplyProductRow({
    required this.id,
    this.supplierCode = '',
    this.supplierRef,
    this.syncSourceRef,
    this.thresholdAmount = '',
    this.isYuantongCoupon = '',
    this.isStandaloneRebate = '',
    this.isLowDiscountCoupon = '',
    this.rebateMode = '',
    this.effectiveDate = '',
    this.expireDate = '',
    this.oilCategory = '',
    this.oilCategoryRef,
    this.existingBuilt = '',
    this.assetProduct,
    this.settlements = const [],
  });

  final String id;
  final String supplierCode;
  final CatalogRef? supplierRef;
  final CatalogRef? syncSourceRef;
  final String thresholdAmount;
  final String isYuantongCoupon;
  final String isStandaloneRebate;
  final String isLowDiscountCoupon;
  final String rebateMode;
  final String effectiveDate;
  final String expireDate;
  final String oilCategory;
  final CatalogRef? oilCategoryRef;
  final String existingBuilt;
  final ChannelProductHit? assetProduct;
  final List<ProposalSkuSettleRow> settlements;

  String get syncSourceCode => (syncSourceRef?.code ?? '').trim();

  bool get isExistingBuilt => existingBuilt.trim() == '是';

  String get supplierLabel {
    final name = (supplierRef?.name ?? '').trim();
    if (name.isNotEmpty) return name;
    return supplierCode.trim();
  }

  ProposalSupplyProductRow copyWith({
    String? supplierCode,
    Object? supplierRef = _catalogUnset,
    Object? syncSourceRef = _catalogUnset,
    String? thresholdAmount,
    String? isYuantongCoupon,
    String? isStandaloneRebate,
    String? isLowDiscountCoupon,
    String? rebateMode,
    String? effectiveDate,
    String? expireDate,
    String? oilCategory,
    Object? oilCategoryRef = _catalogUnset,
    String? existingBuilt,
    Object? assetProduct = _catalogUnset,
    List<ProposalSkuSettleRow>? settlements,
  }) => ProposalSupplyProductRow(
    id: id,
    supplierCode: supplierCode ?? this.supplierCode,
    supplierRef: identical(supplierRef, _catalogUnset)
        ? this.supplierRef
        : supplierRef as CatalogRef?,
    syncSourceRef: identical(syncSourceRef, _catalogUnset)
        ? this.syncSourceRef
        : syncSourceRef as CatalogRef?,
    thresholdAmount: thresholdAmount ?? this.thresholdAmount,
    isYuantongCoupon: isYuantongCoupon ?? this.isYuantongCoupon,
    isStandaloneRebate: isStandaloneRebate ?? this.isStandaloneRebate,
    isLowDiscountCoupon: isLowDiscountCoupon ?? this.isLowDiscountCoupon,
    rebateMode: rebateMode ?? this.rebateMode,
    effectiveDate: effectiveDate ?? this.effectiveDate,
    expireDate: expireDate ?? this.expireDate,
    oilCategory: oilCategory ?? this.oilCategory,
    oilCategoryRef: identical(oilCategoryRef, _catalogUnset)
        ? this.oilCategoryRef
        : oilCategoryRef as CatalogRef?,
    existingBuilt: existingBuilt ?? this.existingBuilt,
    assetProduct: identical(assetProduct, _catalogUnset)
        ? this.assetProduct
        : assetProduct as ChannelProductHit?,
    settlements: settlements ?? this.settlements,
  );

  ProposalSupplyProductRow applyAssetProduct(
    ChannelProductHit? hit, {
    List<ProposalSkuSettleRow>? settlements,
  }) {
    return copyWith(
      assetProduct: hit,
      supplierRef: hit?.supplierRef,
      supplierCode: (hit?.supplierCode.trim().isNotEmpty == true)
          ? hit!.supplierCode.trim()
          : (hit?.supplierRef?.code ?? ''),
      settlements: settlements ??
          (hit == null
              ? proposalIntakeDefaultSupplySettlements()
              : this.settlements),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'supplierCode': supplierCode,
    'supplierRef': catalogRefToJson(supplierRef),
    'syncSource': syncSourceCode,
    'syncSourceRef': catalogRefToJson(syncSourceRef),
    'thresholdAmount': thresholdAmount,
    'isYuantongCoupon': isYuantongCoupon,
    'isStandaloneRebate': isStandaloneRebate,
    'isLowDiscountCoupon': isLowDiscountCoupon,
    'rebateMode': rebateMode,
    'effectiveDate': effectiveDate,
    'expireDate': expireDate,
    'oilCategory': oilCategory,
    'oilCategoryRef': catalogRefToJson(oilCategoryRef),
    'existingBuilt': existingBuilt,
    'assetProduct': assetProduct?.toJson(),
    'settlements': [for (final item in settlements) item.toJson()],
  };

  factory ProposalSupplyProductRow.fromJson(Object? raw) {
    if (raw is! Map) return const ProposalSupplyProductRow(id: '');
    var syncRef = catalogRefOrNull(raw['syncSourceRef']);
    if (syncRef == null) {
      final code = '${raw['syncSource'] ?? ''}'.trim();
      if (code.isNotEmpty) syncRef = CatalogRef(code: code, name: code);
    }
    var supplier = catalogRefOrNull(raw['supplierRef']);
    final asset = channelProductHitOrNull(raw['assetProduct']);
    supplier ??= asset?.supplierRef;
    var supplierCode =
        '${raw['supplierCode'] ?? raw['productId'] ?? ''}'.trim();
    if (supplierCode.isEmpty) {
      supplierCode = (supplier?.code ?? asset?.supplierCode ?? '').trim();
    }
    if (supplier == null && supplierCode.isNotEmpty) {
      supplier = CatalogRef(code: supplierCode, name: supplierCode);
    }
    return ProposalSupplyProductRow(
      id: '${raw['id'] ?? ''}'.trim(),
      supplierCode: supplierCode,
      supplierRef: supplier,
      syncSourceRef: syncRef,
      thresholdAmount: '${raw['thresholdAmount'] ?? ''}'.trim(),
      isYuantongCoupon: '${raw['isYuantongCoupon'] ?? ''}'.trim(),
      isStandaloneRebate: '${raw['isStandaloneRebate'] ?? ''}'.trim(),
      isLowDiscountCoupon: '${raw['isLowDiscountCoupon'] ?? ''}'.trim(),
      rebateMode: '${raw['rebateMode'] ?? ''}'.trim(),
      effectiveDate: '${raw['effectiveDate'] ?? ''}'.trim(),
      expireDate: '${raw['expireDate'] ?? ''}'.trim(),
      oilCategory: '${raw['oilCategory'] ?? ''}'.trim(),
      oilCategoryRef: catalogRefOrNull(raw['oilCategoryRef']),
      existingBuilt: '${raw['existingBuilt'] ?? ''}'.trim(),
      assetProduct: asset,
      settlements: [
        for (final item in raw['settlements'] is List
            ? raw['settlements'] as List
            : const [])
          if (item is Map) ProposalSkuSettleRow.fromJson(item),
      ].where((item) => item.id.isNotEmpty).toList(),
    );
  }
}

String proposalIntakeNewSupplyProductId() =>
    'supply-${DateTime.now().microsecondsSinceEpoch}';

List<ProposalSkuSettleRow> proposalIntakeDefaultSupplySettlements() => [
  ProposalSkuSettleRow(id: proposalIntakeNewSkuSettleId()),
];

ProposalSupplyProductRow proposalIntakeNewSupplyProduct({
  bool existing = false,
}) =>
    ProposalSupplyProductRow(
      id: proposalIntakeNewSupplyProductId(),
      existingBuilt: existing ? '是' : '否',
      settlements: proposalIntakeDefaultSupplySettlements(),
    );

bool proposalIntakeIsExistingSupplyProduct(Map<String, dynamic> form) {
  return proposalIntakeExistingSupplyOverride(form) ??
      proposalIntakeSupplyProducts(form).any((item) => item.isExistingBuilt);
}

bool? proposalIntakeExistingSupplyOverride(Map<String, dynamic> form) {
  final raw = form['isExistingSupplyProduct'];
  if (raw is bool) return raw;
  final text = '$raw'.trim().toLowerCase();
  if (text == 'true' || text == '1' || text == '是' || text == 'yes') {
    return true;
  }
  if (text == 'false' || text == '0' || text == '否' || text == 'no') {
    return false;
  }
  return null;
}

bool proposalIntakeSupplyStarted(ProposalSupplyProductRow product) {
  return product.supplierCode.trim().isNotEmpty ||
      (product.supplierRef != null && product.supplierRef!.isNotEmpty) ||
      (product.assetProduct != null && product.assetProduct!.isNotEmpty) ||
      product.thresholdAmount.trim().isNotEmpty ||
      product.isYuantongCoupon.trim().isNotEmpty ||
      product.isStandaloneRebate.trim().isNotEmpty ||
      product.isLowDiscountCoupon.trim().isNotEmpty ||
      product.rebateMode.trim().isNotEmpty ||
      product.oilCategory.trim().isNotEmpty ||
      (product.oilCategoryRef != null && product.oilCategoryRef!.isNotEmpty) ||
      product.effectiveDate.trim().isNotEmpty ||
      product.expireDate.trim().isNotEmpty;
}

List<ProposalSupplyProductRow> proposalIntakeSupplyProducts(
  Map<String, dynamic> form,
) {
  final raw = form['supplyProducts'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) ProposalSupplyProductRow.fromJson(item),
  ].where((row) => row.id.isNotEmpty).toList();
}

List<ProposalSkuSettleRow> proposalIntakeSupplySettlements(
  ProposalSupplyProductRow row,
) => proposalIntakeSettlementsOf(id: row.id, settlements: row.settlements);

bool proposalIntakeFormHasText(Map<String, dynamic> form, String key) =>
    '${form[key] ?? ''}'.trim().isNotEmpty;

bool proposalIntakeFormHasList(Map<String, dynamic> form, String key) {
  final raw = form[key];
  if (raw is List) {
    return raw.any((item) => '$item'.trim().isNotEmpty);
  }
  return '${raw ?? ''}'.trim().isNotEmpty;
}

bool proposalIntakeFormHasRef(
  Map<String, dynamic> form,
  String refKey,
  String textKey,
) {
  final ref = catalogRefOrNull(form[refKey]);
  if (ref != null && ref.isNotEmpty) return true;
  return proposalIntakeFormHasText(form, textKey);
}

const kProposalSalesFinanceFillFields = <(String, String)>[
  ('salesScale', '销售规模目标（万元）'),
  ('revenue', '收入（万元）'),
  ('invoiceAmount', '发票（万元）'),
  ('profit', '利润（万元）'),
  ('margin', '毛利率（%）'),
  ('turnoverCash', '预计周转资金（万元）'),
  ('turnoverTimes', '月周转次数'),
  ('supplySettleMode', '供给侧结算模式'),
  ('supplySettleCycle', '供给侧结算周期'),
  ('supplyPayer', '供给侧付款主体'),
  ('supplyPayAccount', '供给侧付款账户'),
  ('channelSettleMode', '渠道侧结算模式'),
  ('channelSettleCycle', '渠道侧结算周期'),
  ('channelPayee', '渠道侧收款主体'),
  ('channelReceiveAccount', '渠道侧收款账户'),
  ('generalBusinessAccount', '普通业务账'),
  ('prepaidAccount', '预收账户'),
  ('profitAccrualAccount', '利润计提账户'),
  ('financeRemark', '财务备注'),
  ('rollback', '是否回滚'),
];

List<String> proposalIntakeContractFillIssues(
  Map<String, dynamic> form, {
  required String prefix,
  required String label,
}) {
  final issues = <String>[];
  void need(String key, String field) {
    if (!proposalIntakeFormHasText(form, key)) issues.add('请填写$field');
  }

  final mode = '${form['${prefix}Mode'] ?? ''}'.trim();
  if (mode.isEmpty) {
    issues.add('请选择$label合同状态');
  } else if (mode == '未签署合同') {
    if (!proposalIntakeFormHasText(form, '${prefix}FileName') &&
        !proposalIntakeFormHasText(form, '${prefix}ObjectKey')) {
      issues.add('请上传未签署的$label合同文件');
    }
  } else if (!proposalIntakeFormHasText(form, '${prefix}No')) {
    issues.add('请填写$label合同编号');
  }
  need('${prefix}Name', '$label合同名称');
  need('${prefix}SignDate', '$label合同签署时间');
  need('${prefix}OurParty', '$label合同我方签约主体');
  need('${prefix}Counterparty', '$label合同对方签约主体');
  need('${prefix}ValidPeriod', '$label合同有效期');
  need('${prefix}CoreTerms', '$label合同核心条款');
  return issues;
}

List<String> proposalIntakeSalesMarketIssues(Map<String, dynamic> form) {
  final issues = <String>[];
  void need(String key, String label) {
    if (!proposalIntakeFormHasText(form, key)) issues.add('请填写$label');
  }

  void needList(String key, String label) {
    if (!proposalIntakeFormHasList(form, key)) issues.add('请选择$label');
  }

  void needRef(String refKey, String textKey, String label) {
    if (!proposalIntakeFormHasRef(form, refKey, textKey)) {
      issues.add('请选择$label');
    }
  }

  needRef('sectorRef', 'sector', '业务板块');
  need('proposalName', '产品提案名称');
  need('proposalType', '提案类型');
  needRef('productRef', 'product', '产品（标签一）');
  needRef('projectRef', 'projectName', '项目名称（标签一二级）');
  needList('supplies', '供给（标签二）');
  needList('channels', '渠道（标签三）');
  need('supplierPolicy', '供货商政策');
  need('channelPolicy', '渠道政策');
  need('executionPlan', '提案执行计划');
  need('riskPoints', '合作风险点');
  needList('profitModes', '盈利模式');
  need('profitFormula', '盈利计算说明');
  if (proposalIntakeHasExistingPurchaseProposal(form)) {
    if (proposalIntakeLinkedPurchaseProposalId(form) <= 0) {
      issues.add('请搜索并选择已审核通过的采购提案');
    } else {
      issues.addAll(
        proposalIntakeContractFillIssues(form, prefix: 'purchase', label: '采购'),
      );
    }
  } else {
    issues.addAll(
      proposalIntakeContractFillIssues(form, prefix: 'purchase', label: '采购'),
    );
  }
  issues.addAll(
    proposalIntakeContractFillIssues(form, prefix: 'sales', label: '销售'),
  );
  return issues;
}

List<String> proposalIntakeSalesFinanceFillIssues(Map<String, dynamic> form) {
  final issues = <String>[];
  for (final field in kProposalSalesFinanceFillFields) {
    if (!proposalIntakeFormHasText(form, field.$1)) {
      issues.add('请填写${field.$2}');
    }
  }
  return issues;
}

List<String> proposalIntakeTechFillIssues(
  Map<String, dynamic> form, {
  required bool purchase,
}) {
  final issues = <String>[];
  void need(String key, String label) {
    if (!proposalIntakeFormHasText(form, key)) issues.add('请填写$label');
  }

  void needList(String key, String label) {
    if (!proposalIntakeFormHasList(form, key)) issues.add('请选择$label');
  }

  need('technologyPlatform', 'τ-标签一');
  needList('technologyCapabilities', 'τ-标签二');
  needList('outputForms', purchase ? '能力输入形式' : '能力输出形式');
  needList('developmentTypes', '研发类型');
  need('hasRdCost', '是否涉及研发费用');
  if ('${form['hasRdCost'] ?? ''}'.trim() == '是') {
    final amount = num.tryParse('${form['rdAmount'] ?? ''}'.trim()) ?? 0;
    if (amount <= 0) issues.add('已选择涉及研发费用，金额必须大于 0');
  }
  need('deliveryDate', '交付时间');
  return issues;
}

bool proposalIntakePurchaseSettleComplete(ProposalFinanceSettleTerms terms) {
  final billType =
      (terms.billTypeRef != null && terms.billTypeRef!.isNotEmpty) ||
      terms.billType.trim().isNotEmpty;
  final settleMode =
      (terms.settleModeRef != null && terms.settleModeRef!.isNotEmpty) ||
      terms.settleMode.trim().isNotEmpty;
  return billType &&
      settleMode &&
      terms.invoiceType.trim().isNotEmpty &&
      terms.effectiveTime.trim().isNotEmpty &&
      terms.expireTime.trim().isNotEmpty &&
      terms.isSkuComplete;
}

List<String> proposalIntakePurchaseSupplyIssues(Map<String, dynamic> form) {
  final issues = <String>[];
  final products = proposalIntakeSupplyProducts(form);
  final existing =
      proposalIntakeExistingSupplyOverride(form) == true ||
      products.any((item) => item.isExistingBuilt);
  if (existing && products.isEmpty) {
    issues.add('已勾选已有供给产品，请至少添加一条并搜索选择已建供给产品');
    return issues;
  }
  for (var i = 0; i < products.length; i++) {
    final product = products[i];
    final label = '供给产品 ${i + 1}';
    final rowExisting = existing || product.isExistingBuilt;
    if (!rowExisting && !proposalIntakeSupplyStarted(product)) {
      continue;
    }
    if (product.syncSourceCode.isEmpty) {
      issues.add('$label 请选择业务平台');
    }
    if (rowExisting) {
      if (product.assetProduct == null || product.assetProduct!.isEmpty) {
        issues.add('$label 请搜索并选择已建供给产品');
      }
    } else {
      final hasSupplier =
          product.supplierCode.trim().isNotEmpty ||
          (product.supplierRef != null && product.supplierRef!.isNotEmpty);
      if (!hasSupplier) {
        issues.add('$label 请选择供应商');
      }
      if (product.thresholdAmount.trim().isEmpty) {
        issues.add('$label 请填写门槛金额');
      }
      if (product.isYuantongCoupon.trim().isEmpty) {
        issues.add('$label 请选择是否元通券');
      }
      if (product.isStandaloneRebate.trim().isEmpty) {
        issues.add('$label 请选择是否单独返利制券');
      }
      if (product.isLowDiscountCoupon.trim().isEmpty) {
        issues.add('$label 请选择是否低折扣券');
      }
      if (product.rebateMode.trim().isEmpty) {
        issues.add('$label 请选择返利模式');
      }
      if (product.oilCategory.trim().isEmpty &&
          (product.oilCategoryRef == null || product.oilCategoryRef!.isEmpty)) {
        issues.add('$label 请选择油品分类');
      }
      if (product.effectiveDate.trim().isEmpty) {
        issues.add('$label 请选择产品生效日期');
      }
      if (product.expireDate.trim().isEmpty) {
        issues.add('$label 请选择产品失效日期');
      }
    }
    final settlements = proposalIntakeSupplySettlements(product);
    if (settlements.isEmpty) {
      issues.add('$label 请填写结算一');
      continue;
    }
    for (var j = 0; j < settlements.length; j++) {
      final terms = settlements[j].terms;
      if (j > 0 && terms.isBlank) continue;
      if (!proposalIntakePurchaseSettleComplete(terms)) {
        issues.add(
          '$label ${proposalIntakeSettleLabel(j)}未填完账单类型、结算方式、金额、计算公式、发票类型、税率和生效失效时间',
        );
      }
    }
  }
  return issues;
}

List<String> proposalIntakePurchaseMarketIssues(Map<String, dynamic> form) {
  final issues = <String>[];
  void need(String key, String label) {
    if (!proposalIntakeFormHasText(form, key)) issues.add('请填写$label');
  }

  void needList(String key, String label) {
    if (!proposalIntakeFormHasList(form, key)) issues.add('请选择$label');
  }

  need('proposalType', '提案类型');
  needList('supplies', '供给（标签二）');
  need('supplyBrand', '供给侧品牌');
  need('bizContact', '采购对接人（业务）');
  need('financeContact', '采购对接人（财务）');
  needList('invoiceTypes', '发票种类');
  need('supplierPolicy', '供给政策');
  need('salesPolicy', '销售政策');
  need('executionPlan', '提案执行计划');
  need('riskPoints', '合作风险点');
  need('financeRemark', '财务备注');
  final mode = '${form['purchaseMode'] ?? ''}'.trim();
  if (mode.isEmpty) {
    issues.add('请选择采购合同状态');
  } else if (mode == '未签署合同') {
    if (!proposalIntakeFormHasText(form, 'purchaseFileName') &&
        !proposalIntakeFormHasText(form, 'purchaseObjectKey')) {
      issues.add('请上传未签署的采购合同文件');
    }
  } else if (!proposalIntakeFormHasText(form, 'purchaseNo')) {
    issues.add('请填写采购合同编号');
  }
  need('purchaseName', '采购合同名称');
  need('purchaseSignDate', '采购合同签署时间');
  need('purchaseOurParty', '我方签约主体');
  need('purchaseCounterparty', '对方签约主体');
  need('purchaseValidPeriod', '采购合同有效期');
  need('purchaseCoreTerms', '采购合同核心条款');
  issues.addAll(proposalIntakePurchaseSupplyIssues(form));
  return issues;
}

List<String> proposalIntakePurchaseTechIssues(Map<String, dynamic> form) =>
    proposalIntakeTechFillIssues(form, purchase: true);

String? proposalIntakePurchaseHunIssue(Map<String, dynamic> form) {
  if (proposalIntakeFormHasText(form, 'hunId')) return null;
  return '请填写 HUN ID';
}
