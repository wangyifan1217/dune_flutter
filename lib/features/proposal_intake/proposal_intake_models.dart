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

String proposalIntakeUntitledTitle(String kind) =>
    proposalIntakeIsPurchase(kind) ? '未命名采购业务提案' : '未命名销售业务提案';

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
              for (final item in products) '$item'.trim(),
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
  const ProposalIntakeListResult({
    required this.items,
    required this.total,
    this.stats = const ProposalIntakeLibraryStats(),
  });

  final List<ProposalIntakeRow> items;
  final int total;
  final ProposalIntakeLibraryStats stats;

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
      stats: ProposalIntakeLibraryStats.fromJson(json['stats']),
    );
  }
}

const kProposalIntakePeriodFilters = <(String, String)>[
  ('', '库内提案'),
  ('day', '本日提案'),
  ('week', '本周提案'),
  ('month', '本月提案'),
];

class ProposalIntakeLibraryStats {
  const ProposalIntakeLibraryStats({
    this.total = 0,
    this.day = 0,
    this.week = 0,
    this.month = 0,
    this.sectors = const [],
  });

  final int total;
  final int day;
  final int week;
  final int month;
  final List<ProposalIntakeSectorStat> sectors;

  factory ProposalIntakeLibraryStats.fromJson(Object? raw) {
    if (raw is! Map) return const ProposalIntakeLibraryStats();
    final sectorsRaw = raw['sectors'];
    return ProposalIntakeLibraryStats(
      total: (raw['total'] as num?)?.toInt() ?? 0,
      day: (raw['day'] as num?)?.toInt() ?? 0,
      week: (raw['week'] as num?)?.toInt() ?? 0,
      month: (raw['month'] as num?)?.toInt() ?? 0,
      sectors: [
        if (sectorsRaw is List)
          for (final item in sectorsRaw)
            if (item is Map)
              ProposalIntakeSectorStat(
                name: '${item['name'] ?? ''}'.trim(),
                count: (item['count'] as num?)?.toInt() ?? 0,
              ),
      ],
    );
  }
}

class ProposalIntakeSectorStat {
  const ProposalIntakeSectorStat({required this.name, required this.count});

  final String name;
  final int count;
}

/// 板块计数：配置里的板块按顺序都展示（没有则 0），额外名称和「未填写」跟在后面。
List<(String, int)> proposalIntakeSectorCountRows({
  required List<String> catalog,
  required List<ProposalIntakeSectorStat> counts,
}) {
  final byName = <String, int>{
    for (final item in counts)
      if (item.name.trim().isNotEmpty) item.name.trim(): item.count,
  };
  final seen = <String>{};
  final out = <(String, int)>[];
  for (final raw in catalog) {
    final name = raw.trim();
    if (name.isEmpty || !seen.add(name)) continue;
    out.add((name, byName[name] ?? 0));
  }
  final extras = byName.keys.where((name) => !seen.contains(name)).toList()
    ..sort();
  for (final name in extras) {
    if (name == '未填写') continue;
    out.add((name, byName[name] ?? 0));
  }
  final blank = byName['未填写'] ?? 0;
  if (blank > 0) out.add(('未填写', blank));
  return out;
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
const kProposalTaxCostItems = ['增值税及附加（能源）', '增值税及附加（运营商+公共出行）', '印花税', '所得税'];

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
    for (final name in names) proposalCostAmountId(name, catalog),
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
    final raw = form[settleTermsKey];
    if (raw is Map) {
      next[settleTermsKey] = {
        for (final entry in raw.entries)
          if (keep.contains('${entry.key}'.trim())) '${entry.key}': entry.value,
      };
    }
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
    final rows = proposalCostSettleTermsList(
      {id: entry.value},
      name: id,
      id: id,
    );
    out[id] = rows.isEmpty
        ? ProposalFinanceSettleTerms.fromJson(entry.value)
        : rows.first;
  }
  return out;
}

ProposalFinanceSettleTerms proposalCostSettleTermsOf({
  required Map<String, ProposalFinanceSettleTerms> terms,
  required String name,
  required String id,
}) => terms[id] ?? terms[name] ?? const ProposalFinanceSettleTerms();

List<ProposalFinanceSettleTerms> proposalCostSettleTermsList(
  Object? raw, {
  required String name,
  required String id,
}) {
  if (raw is! Map) return const [];
  Object? value = raw[id];
  value ??= raw[name];
  if (value == null) return const [];
  if (value is List) {
    return [
      for (final item in value)
        if (item is Map) ProposalFinanceSettleTerms.fromJson(item),
    ];
  }
  if (value is Map) {
    final nested = value['settlements'];
    if (nested is List) {
      return [
        for (final item in nested)
          if (item is Map) ProposalFinanceSettleTerms.fromJson(item),
      ];
    }
    return [ProposalFinanceSettleTerms.fromJson(value)];
  }
  return const [];
}

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
  final issues = <String>[];
  for (final name in names) {
    final id = proposalCostAmountId(name, catalog);
    final rows = proposalCostSettleTermsList(
      form[termsKey],
      name: name,
      id: id,
    );
    if (rows.isEmpty || rows.any((row) => !row.isProjectCostComplete)) {
      issues.add('$label「$name」请填写结算比例或单价');
    }
  }
  return issues;
}

List<String> proposalIntakeCostItemSettleIssues(
  Map<String, dynamic> form, {
  List<ProposalCostItemOption> catalog = const [],
  List<ProposalCostItemOption> businessCatalog = const [],
}) => proposalIntakeNamedCostSettleIssues(
  form,
  namesKey: 'businessCostItems',
  termsKey: 'businessCostItemSettleTerms',
  label: '业务成本',
  catalog: businessCatalog,
);

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
    final name = '${map['label'] ?? map['name'] ?? map['value'] ?? ''}'.trim();
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
      'salesInvoiceType',
      'salesInvoiceFlow',
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
    _putField(
      patch,
      'salesInvoiceType',
      pick(['salesInvoiceType', 'invoiceType', 'invoiceTypes']),
    );
    _putField(
      patch,
      'salesInvoiceFlow',
      pick(['salesInvoiceFlow', 'invoiceFlow']),
    );
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

/// 返回列表时是否自动保存。已完成 / 待最终确认只读，不能再 PATCH 草稿。
bool proposalIntakeShouldAutoSaveOnBack(ProposalIntakeRow row) {
  if (!proposalIntakeHasMeaningfulContent(row)) return false;
  if (row.status == 'pending_president') return false;
  if (row.status == 'done' && !row.techRevisionOpen) return false;
  return true;
}

/// 自动保存成功后是否提示「已保存草稿」。
bool proposalIntakeShowDraftSavedToast(ProposalIntakeRow row) {
  return row.status == 'draft' ||
      row.status == 'filling' ||
      row.status.trim().isEmpty;
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

bool proposalIntakeOwnerFilled(Map<String, dynamic> form, String prefix) {
  return proposalIntakeOwnerDisplayName(form, prefix).isNotEmpty ||
      (int.tryParse('${form['${prefix}UserId'] ?? ''}'.trim()) ?? 0) > 0;
}

String proposalIntakeOwnerDisplayName(
  Map<String, dynamic> form,
  String prefix, {
  List<ProposalPerson> people = const [],
}) {
  final fromForm = '${form[prefix] ?? ''}'.trim();
  if (fromForm.isNotEmpty) return fromForm;
  final id = int.tryParse('${form['${prefix}UserId'] ?? ''}'.trim()) ?? 0;
  if (id <= 0) return '';
  for (final person in people) {
    if (person.userId == id && person.name.trim().isNotEmpty) {
      return person.name.trim();
    }
  }
  return '';
}

String proposalIntakeActionLabel(
  String action, {
  ProposalIntakeRow? row,
  List<ProposalPerson> people = const [],
}) {
  final form = row?.form ?? const <String, dynamic>{};
  String withOwner(String base, String prefix, {String fallback = ''}) {
    if (!proposalIntakeOwnerFilled(form, prefix)) {
      return fallback.isEmpty ? base : fallback;
    }
    final suffix = prefix.endsWith('1')
        ? '负责人一'
        : prefix.endsWith('2')
        ? '负责人二'
        : '';
    final titled = suffix.isEmpty ? base : '$base$suffix';
    final name = proposalIntakeOwnerDisplayName(form, prefix, people: people);
    if (name.isEmpty) return titled;
    return '$titled $name';
  }

  String withReviewer(String prefix, {required String fallback}) {
    final name = proposalIntakeOwnerDisplayName(form, prefix, people: people);
    if (name.isEmpty) return fallback;
    return '待$name复核';
  }

  String withName(String base, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == '未指定') return base;
    return '$base $trimmed';
  }

  return switch (action) {
    'fill' => withName('待填写', row?.initiatorDisplayName(people) ?? ''),
    'fill_tech' => withOwner('待填写科技', 'technologyOwner'),
    'fill_finance_interface' => withOwner('待填写财务技术接口', 'financeOwner2'),
    'start_review' => '待重新提交复核',
    'review_market' => withReviewer('marketOwner1', fallback: '待复核市场部'),
    'review_tech' => withReviewer('marketOwner2', fallback: '待复核科技'),
    'review_finance' => withReviewer('financeOwner2', fallback: '待复核财务'),
    'review_finance_interface' => withReviewer(
      'marketOwner2',
      fallback: '待复核财务技术接口',
    ),
    'review_finance_module' => withReviewer(
      'financeOwner1',
      fallback: '待整板块复核财务',
    ),
    'review_contract' => withReviewer('financeOwner2', fallback: '待审核合同'),
    'submit_president' => '待通知最终人',
    'president_confirm' => withName(
      '待最终确认',
      proposalIntakeOwnerDisplayName(form, 'president', people: people),
    ),
    'start_tech_revision' => '待发起科技变更',
    'revise' => '最终人已驳回请从头填写',
    'revise_module' => '板块已驳回请修改',
    _ => '',
  };
}

bool proposalIntakeFinanceLineItemsReviewed(ProposalIntakeRow row) {
  final keys = <String>[
    'salesScale',
    'revenue',
    'couponProcurementCost',
    'profit',
    'margin',
    'turnoverCash',
    'turnoverTimes',
    'supplySettleMode',
    'supplySettleCycle',
    'supplyPayer',
    'supplyPayAccount',
    'channelSettleMode',
    'channelSettleCycle',
    'channelPayee',
    'channelReceiveAccount',
    'generalBusinessAccount',
    'prepaidAccount',
    'financeRemark',
    'costItems',
    'operatingCost',
    'taxCost',
    'rollback',
    'proposalSubtitle',
    ...proposalIntakeLaunchModuleReviewKeys(row.form),
    ...proposalIntakeSkuSettleReviewKeys(row.form),
  ];
  if (keys.isEmpty) return false;
  final raw = row.review['financeItems'];
  final items = raw is Map ? raw : const {};
  for (final key in keys) {
    if (items[key] != true) return false;
  }
  return true;
}

/// 列表上给所有人看的待复核对象：有姓名则「待某某复核」，否则保留短状态。
List<String> proposalIntakePendingReviewLabels(
  ProposalIntakeRow row, {
  List<ProposalPerson> people = const [],
}) {
  final stage = row.resolvedStage;
  if (stage != 'reviewing' && stage != 'tech_reviewing') return const [];
  final review = row.review;
  bool done(String key) => review[key] == true;
  String label(String action) =>
      proposalIntakeActionLabel(action, row: row, people: people);
  final labels = <String>[];
  if (!done('marketCompleted')) {
    labels.add(label('review_market'));
  }
  if (!done('technologyCompleted')) {
    labels.add(label('review_tech'));
  }
  if (stage == 'reviewing' &&
      !proposalIntakeIsPurchase(row.kind) &&
      !done('financeCompleted')) {
    if (!proposalIntakeFinanceLineItemsReviewed(row)) {
      labels.add(label('review_finance'));
    } else {
      labels.add(label('review_finance_module'));
    }
  }
  return [
    for (final item in labels)
      if (item.isNotEmpty) item,
  ];
}

String proposalIntakeListActionText(
  ProposalIntakeRow row, {
  List<ProposalPerson> people = const [],
}) {
  final pending = proposalIntakePendingReviewLabels(row, people: people);
  final mine = proposalIntakeActionLabel(
    row.myAction,
    row: row,
    people: people,
  );
  final labels = <String>[
    ...pending,
    if (mine.isNotEmpty && !pending.contains(mine)) mine,
  ];
  return labels.join('  ·  ');
}

const kProposalTechnologyReviewFields = <String>[
  'technologyPlatform',
  'technologyCapabilities',
  'outputForms',
  'developmentTypes',
  'hasRdCost',
  'rdAmount',
  'deliveryDate',
  'financeInterfaces',
];

const kProposalTechnologyReviewLabels = <String, String>{
  'technologyPlatform': 'τ-标签一',
  'technologyCapabilities': 'τ-标签二',
  'outputForms': '能力输出/输入形式',
  'developmentTypes': '研发类型',
  'hasRdCost': '是否涉及研发费用',
  'rdAmount': '研发费用金额',
  'deliveryDate': '交付时间',
  'financeInterfaces': '财务技术接口',
};

List<String> proposalIntakeTechnologyReviewGaps(
  Map<String, dynamic> review, {
  Map<String, dynamic>? form,
}) {
  final raw = review['technologyItems'];
  final items = raw is Map ? raw : const {};
  final keys = form == null
      ? kProposalTechnologyReviewFields
      : proposalIntakeTechnologyReviewItemKeys(form);
  String labelOf(String key) {
    if (key.startsWith(kProposalChildTechReviewPrefix)) {
      final field = key.substring(kProposalChildTechReviewPrefix.length);
      return '子产品${kProposalTechnologyReviewLabels[field] ?? field}';
    }
    return kProposalTechnologyReviewLabels[key] ?? key;
  }

  return [
    for (final key in keys)
      if (items[key] != true) labelOf(key),
  ];
}

enum ProposalIntakeNavSection { toc, market, tech, finance, flow }

ProposalIntakeNavSection? proposalIntakeNavSectionForAction(String action) {
  return switch (action) {
    'fill' ||
    'revise' ||
    'revise_module' ||
    'start_review' ||
    'review_market' => ProposalIntakeNavSection.market,
    'fill_tech' ||
    'fill_finance_interface' ||
    'review_tech' ||
    'review_finance_interface' ||
    'start_tech_revision' => ProposalIntakeNavSection.tech,
    'review_finance' ||
    'review_finance_module' ||
    'review_contract' => ProposalIntakeNavSection.finance,
    _ => null,
  };
}

String proposalIntakeNavSectionLabel(ProposalIntakeNavSection section) {
  return switch (section) {
    ProposalIntakeNavSection.toc => '目录',
    ProposalIntakeNavSection.market => '市场部',
    ProposalIntakeNavSection.tech => '科技部',
    ProposalIntakeNavSection.finance => '财务部',
    ProposalIntakeNavSection.flow => '四流',
  };
}

bool proposalIntakeActionIsModuleReview(String action) {
  return action == 'review_market' || action == 'review_finance_module';
}

bool proposalIntakeAwaitingModuleConfirm(
  String action,
  Map<String, dynamic> review, {
  Map<String, dynamic>? form,
}) {
  return action == 'review_tech' &&
      review['technologyCompleted'] != true &&
      proposalIntakeTechnologyReviewGaps(review, form: form).isEmpty;
}

String proposalIntakeTaskBannerTitle(
  String action, {
  bool awaitingModuleConfirm = false,
}) {
  if (awaitingModuleConfirm && action == 'review_tech') {
    return '逐条已完成，请确认科技部板块';
  }
  return switch (action) {
    'review_market' => '待你整板块复核市场部',
    'review_finance_module' => '待你整板块复核财务部',
    'review_tech' => '待你逐条复核科技部',
    'review_finance' => '待你逐条复核财务部',
    'review_finance_interface' => '待你逐条复核财务技术接口',
    'review_contract' => '待你复核合同',
    'president_confirm' => '待你最终确认',
    _ => '',
  };
}

String proposalIntakeTaskBannerBody(
  String action, {
  bool awaitingModuleConfirm = false,
}) {
  if (awaitingModuleConfirm && action == 'review_tech') {
    return '字段旁的「已复核」还不算过。请到科技部最底部点「确认本板块通过」。点保存不会结束复核。';
  }
  if (proposalIntakeActionIsModuleReview(action)) {
    return '看完内容后，到本板块最底部点「整个板块复核通过」。也可直接整板块驳回。';
  }
  return switch (action) {
    'review_tech' => '到各字段旁点复核，财务技术接口也算科技一条。底部确认前会检查遗漏。也可直接整板块驳回。',
    'review_finance' => '到各费用字段旁点复核。也可直接整板块驳回。',
    'review_finance_interface' => '到财务技术接口处点复核。',
    'review_contract' => '到合同处点复核。也可直接整板块驳回。',
    'president_confirm' => '审批进度和其他人看到的一样。看完各板块后，到页面底部点「确认通过」或「驳回」。',
    _ => '',
  };
}

String proposalIntakeNavJumpLabel(
  String action, {
  bool awaitingModuleConfirm = false,
}) {
  if (awaitingModuleConfirm ||
      proposalIntakeActionIsModuleReview(action) ||
      action == 'president_confirm') {
    return '去底部确认';
  }
  final section = proposalIntakeNavSectionForAction(action);
  if (section == null) return '';
  final name = proposalIntakeNavSectionLabel(section);
  if (action.startsWith('review') || action == 'review_contract') {
    return '去$name复核';
  }
  if (action == 'fill' ||
      action == 'fill_tech' ||
      action == 'fill_finance_interface' ||
      action == 'revise' ||
      action == 'revise_module') {
    return '去$name填写';
  }
  if (action == 'start_tech_revision') return '去$name变更';
  if (action == 'start_review') return '去$name';
  return '去$name';
}

enum ProposalIntakeProgressState { pending, current, done, rejected }

class ProposalIntakeProgressStep {
  const ProposalIntakeProgressStep({
    required this.id,
    required this.title,
    required this.state,
    this.role = '',
    this.name = '',
    this.action = '',
    this.statusText = '',
    this.time = '',
  });

  final String id;
  final String title;
  final String role;
  final String name;
  final String action;
  final String statusText;
  final String time;
  final ProposalIntakeProgressState state;
}

int proposalIntakeStageRank(String stage) {
  return switch (stage) {
    'filling' || 'draft' => 0,
    'awaiting_tech' || 'tech_revising' => 1,
    'awaiting_start_review' => 2,
    'reviewing' || 'tech_reviewing' => 3,
    'awaiting_submit' => 4,
    'pending_president' => 5,
    'done' => 6,
    _ => 0,
  };
}

String formatProposalIntakeProgressTime(String raw) {
  final parsed = parseProposalIntakeInstant(raw);
  if (parsed == null) return '';
  final local = parsed.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.month)}.${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String proposalIntakeProgressHeadline(List<ProposalIntakeProgressStep> steps) {
  final current = [
    for (final step in steps)
      if (step.state == ProposalIntakeProgressState.current) step,
  ];
  if (current.isEmpty) {
    if (steps.any(
      (item) =>
          item.id == 'end' && item.state == ProposalIntakeProgressState.done,
    )) {
      return '已完成';
    }
    return '';
  }
  return current
      .map((step) {
        if (step.role.isNotEmpty && step.name.isNotEmpty) {
          return '${step.role} · ${step.name}';
        }
        if (step.name.isNotEmpty) return step.name;
        return step.title;
      })
      .join('、');
}

List<ProposalIntakeProgressStep> proposalIntakeProgressSteps({
  required ProposalIntakeRow row,
  List<ProposalPerson> people = const [],
  ProposalIntakeOptions? options,
}) {
  final stage = row.resolvedStage;
  final rank = proposalIntakeStageRank(stage);
  final purchase = proposalIntakeIsPurchase(row.kind);
  final review = row.review;
  bool flag(String key) => review[key] == true;
  final presidentRejected = flag('presidentRejected');
  final reviewRejected = flag('reviewRejected') && !presidentRejected;
  final rejectSection = '${review['reviewRejectSection'] ?? ''}'.trim();
  final anyReviewDone = [
    'marketCompleted',
    'technologyCompleted',
    'financeInterfaceCompleted',
    'financeCompleted',
    'purchaseContractCompleted',
    'salesContractCompleted',
  ].any(flag);
  final inTechFill = stage == 'awaiting_tech' || stage == 'tech_revising';
  final inStartReview = stage == 'awaiting_start_review';
  final inReview = stage == 'reviewing' || stage == 'tech_reviewing';
  final inTechReview = stage == 'tech_reviewing';
  final inNotify = stage == 'awaiting_submit';
  final inPresident = stage == 'pending_president';
  final finished = stage == 'done';
  final leftFilling = rank == 0;
  final crossedTech = rank >= 1 || reviewRejected || anyReviewDone;
  final initiator = row.initiatorDisplayName(people);
  final initiatorName = initiator == '未指定' ? '' : initiator;
  final createdAt = formatProposalIntakeProgressTime(row.createdAt);
  final handoffAt = formatProposalIntakeProgressTime(
    '${review['lastHandoffAt'] ?? ''}',
  );
  final reviewedAt = formatProposalIntakeProgressTime(
    '${review['lastReviewedAt'] ?? ''}',
  );
  final decidedAt = formatProposalIntakeProgressTime(
    '${review['presidentDecidedAt'] ?? ''}',
  );

  String ownerName(String prefix) {
    return proposalIntakeOwnerDisplayName(row.form, prefix, people: people);
  }

  String presidentName() {
    final fromForm = ownerName('president');
    final configured = options?.presidentDisplayNames(people).trim() ?? '';
    if (fromForm.isNotEmpty) {
      if (configured.isNotEmpty && !fromForm.contains(configured)) {
        return '$fromForm、$configured';
      }
      return fromForm;
    }
    return configured;
  }

  String statusOf(ProposalIntakeProgressState state, {String done = '已通过'}) {
    return switch (state) {
      ProposalIntakeProgressState.pending => '待处理',
      ProposalIntakeProgressState.current => '进行中',
      ProposalIntakeProgressState.done => done,
      ProposalIntakeProgressState.rejected => '已驳回',
    };
  }

  String timeOf(
    ProposalIntakeProgressState state, {
    String done = '',
    String current = '',
  }) {
    if (state == ProposalIntakeProgressState.pending) return '';
    if (state == ProposalIntakeProgressState.current) {
      return current.isNotEmpty ? current : '当前';
    }
    if (done.isNotEmpty) return done;
    if (current.isNotEmpty) return current;
    return '';
  }

  ProposalIntakeProgressStep person({
    required String id,
    required String role,
    required String name,
    required String action,
    required ProposalIntakeProgressState state,
    String doneStatus = '已通过',
    String time = '',
    String currentTime = '',
    String? title,
    String? statusText,
  }) {
    final resolvedName = name.trim();
    return ProposalIntakeProgressStep(
      id: id,
      title: title ?? role,
      role: role,
      name: resolvedName,
      action: action,
      statusText: statusText ?? statusOf(state, done: doneStatus),
      time: timeOf(state, done: time, current: currentTime),
      state: state,
    );
  }

  ProposalIntakeProgressState fillState({required bool current}) {
    if (current) return ProposalIntakeProgressState.current;
    if (crossedTech) return ProposalIntakeProgressState.done;
    return ProposalIntakeProgressState.pending;
  }

  ProposalIntakeProgressState startReviewState() {
    if (inStartReview) return ProposalIntakeProgressState.current;
    if (inTechFill) return ProposalIntakeProgressState.pending;
    if (presidentRejected && leftFilling) {
      return ProposalIntakeProgressState.pending;
    }
    if (rank >= 3 || reviewRejected || finished || inNotify || inPresident) {
      return ProposalIntakeProgressState.done;
    }
    return ProposalIntakeProgressState.pending;
  }

  ProposalIntakeProgressState reviewerState(
    String flagKey, {
    bool techRound = false,
    bool rejected = false,
    bool completed = false,
  }) {
    if (rejected || (reviewRejected && rejectSection == flagKey)) {
      return ProposalIntakeProgressState.rejected;
    }
    if (completed || flag(flagKey)) return ProposalIntakeProgressState.done;
    if (inReview) {
      if (inTechReview && !techRound) {
        return flag(flagKey)
            ? ProposalIntakeProgressState.done
            : ProposalIntakeProgressState.pending;
      }
      return ProposalIntakeProgressState.current;
    }
    if (rank >= 4) return ProposalIntakeProgressState.done;
    return ProposalIntakeProgressState.pending;
  }

  ProposalIntakeProgressState notifyState() {
    if (inNotify) return ProposalIntakeProgressState.current;
    if (inPresident || finished) return ProposalIntakeProgressState.done;
    return ProposalIntakeProgressState.pending;
  }

  ProposalIntakeProgressState presidentState() {
    if (presidentRejected) return ProposalIntakeProgressState.rejected;
    if (inPresident) return ProposalIntakeProgressState.current;
    if (finished) return ProposalIntakeProgressState.done;
    return ProposalIntakeProgressState.pending;
  }

  final initiateState = finished || !leftFilling
      ? ProposalIntakeProgressState.done
      : ProposalIntakeProgressState.current;
  final contractsDone = purchase
      ? flag('purchaseContractCompleted')
      : flag('purchaseContractCompleted') && flag('salesContractCompleted');
  final finance2Done = purchase
      ? contractsDone
      : flag('financeCompleted') ||
            (contractsDone && proposalIntakeFinanceLineItemsReviewed(row));
  final contractRejected =
      rejectSection == 'purchaseContractCompleted' ||
      rejectSection == 'salesContractCompleted' ||
      rejectSection.startsWith('contractItem');

  return [
    person(
      id: 'initiate',
      role: '提交人',
      name: initiatorName,
      action: leftFilling ? '填写' : '发起',
      title: initiatorName.isEmpty ? '提交人 发起' : '$initiatorName 发起',
      state: initiateState,
      doneStatus: '已发起',
      statusText: initiateState == ProposalIntakeProgressState.current
          ? '填写中'
          : null,
      time: createdAt,
      currentTime: createdAt,
    ),
    person(
      id: 'fill_tech',
      role: '科技部负责人',
      name: ownerName('technologyOwner'),
      action: '填写科技',
      state: fillState(current: inTechFill),
      time: handoffAt,
      currentTime: handoffAt,
    ),
    person(
      id: 'fill_finance_interface',
      role: '财务部负责人二',
      name: ownerName('financeOwner2'),
      action: '填写财务技术接口',
      state: fillState(current: inTechFill),
      time: handoffAt,
      currentTime: handoffAt,
    ),
    person(
      id: 'start_review',
      role: '提交人',
      name: initiatorName,
      action: '提交复核',
      state: startReviewState(),
      time: handoffAt,
      currentTime: handoffAt,
    ),
    person(
      id: 'review_market',
      role: '市场部负责人一',
      name: ownerName('marketOwner1'),
      action: '整板块复核市场',
      state: reviewerState('marketCompleted', techRound: true),
      time: reviewedAt,
    ),
    person(
      id: 'review_tech',
      role: '市场部负责人二',
      name: ownerName('marketOwner2'),
      action: '逐条复核科技（含财务技术接口）',
      state: reviewerState('technologyCompleted', techRound: true),
      time: reviewedAt,
    ),
    person(
      id: 'review_contract',
      role: '财务部负责人二',
      name: ownerName('financeOwner2'),
      action: purchase ? '复核采购合同' : '复核合同与财务',
      state: reviewerState(
        'purchaseContractCompleted',
        rejected: contractRejected,
        completed: finance2Done,
      ),
      time: reviewedAt,
    ),
    if (!purchase)
      person(
        id: 'review_finance_module',
        role: '财务部负责人一',
        name: ownerName('financeOwner1'),
        action: '整板块复核财务',
        state: reviewerState('financeCompleted'),
        time: reviewedAt,
      ),
    person(
      id: 'notify_president',
      role: '提交人',
      name: initiatorName,
      action: '通知最终人',
      state: notifyState(),
      time: handoffAt,
      currentTime: handoffAt,
    ),
    person(
      id: 'president',
      role: '最终确认人',
      name: presidentName(),
      action: '最终确认',
      state: presidentState(),
      time: decidedAt,
      currentTime: decidedAt,
    ),
    ProposalIntakeProgressStep(
      id: 'end',
      title: '审批结束',
      role: '',
      name: '',
      action: finished ? '提案已完成' : '各环节通过后结束',
      statusText: finished ? '已完成' : '待处理',
      time: finished ? decidedAt : '',
      state: finished
          ? ProposalIntakeProgressState.done
          : ProposalIntakeProgressState.pending,
    ),
  ];
}

class ProposalIntakeNotifyRecipient {
  const ProposalIntakeNotifyRecipient({
    required this.userId,
    required this.role,
    this.name = '',
    this.task = '',
  });

  final int userId;
  final String role;
  final String name;
  final String task;

  String get line {
    final who = name.isNotEmpty ? '$role $name' : role;
    if (task.trim().isEmpty) return who;
    return '$who · $task';
  }

  factory ProposalIntakeNotifyRecipient.fromJson(Map json) {
    return ProposalIntakeNotifyRecipient(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      role: '${json['role'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      task: '${json['task'] ?? ''}'.trim(),
    );
  }
}

class ProposalIntakeWriteResult {
  const ProposalIntakeWriteResult({
    required this.row,
    this.notified = const [],
  });

  final ProposalIntakeRow row;
  final List<ProposalIntakeNotifyRecipient> notified;

  factory ProposalIntakeWriteResult.fromJson(Map<String, dynamic> json) {
    final raw = json['notified'];
    return ProposalIntakeWriteResult(
      row: ProposalIntakeRow.fromJson(json),
      notified: [
        if (raw is List)
          for (final item in raw)
            if (item is Map) ProposalIntakeNotifyRecipient.fromJson(item),
      ].where((item) => item.userId > 0).toList(growable: false),
    );
  }
}

String proposalIntakeNotifiedToast(List<ProposalIntakeNotifyRecipient> items) {
  if (items.isEmpty) return '';
  return '已通知：${items.map((item) {
    if (item.name.isNotEmpty) return '${item.name}（${item.role}）';
    return item.role;
  }).join('、')}';
}

ProposalIntakeNotifyRecipient? proposalIntakeNotifyOwner({
  required Map<String, dynamic> form,
  required List<ProposalPerson> people,
  required String prefix,
  required String role,
  required String task,
  int fallbackUserId = 0,
}) {
  var id = int.tryParse('${form['${prefix}UserId'] ?? ''}'.trim()) ?? 0;
  if (id <= 0) id = fallbackUserId;
  if (id <= 0) return null;
  return ProposalIntakeNotifyRecipient(
    userId: id,
    role: role,
    name: proposalIntakeOwnerDisplayName(form, prefix, people: people),
    task: task,
  );
}

List<ProposalIntakeNotifyRecipient> proposalIntakeNotifyRecipients({
  required String action,
  required ProposalIntakeRow row,
  List<ProposalPerson> people = const [],
  ProposalIntakeOptions? options,
  List<String>? onlyFlags,
}) {
  final form = row.form;
  ProposalIntakeNotifyRecipient? owner(
    String prefix,
    String role,
    String task, {
    int fallback = 0,
  }) {
    return proposalIntakeNotifyOwner(
      form: form,
      people: people,
      prefix: prefix,
      role: role,
      task: task,
      fallbackUserId: fallback,
    );
  }

  List<ProposalIntakeNotifyRecipient> reviewers({List<String>? flags}) {
    final want = flags;
    bool has(String key) => want == null || want.contains(key);
    final purchase = proposalIntakeIsPurchase(row.kind);
    final out = <ProposalIntakeNotifyRecipient>[];
    void add(ProposalIntakeNotifyRecipient? item) {
      if (item == null) return;
      out.add(item);
    }

    if (has('marketCompleted')) {
      add(owner('marketOwner1', '市场部负责人一', '请复核市场部板块'));
    }
    if (has('technologyCompleted') || has('financeInterfaceCompleted')) {
      add(
        owner(
          'marketOwner2',
          '市场部负责人二',
          '请复核科技部内容（含财务技术接口）',
          fallback: row.createdBy,
        ),
      );
    }
    if (want == null && !purchase) {
      add(owner('financeOwner2', '财务部负责人二', '请复核财务内容'));
    }
    if (has('financeCompleted') && !purchase) {
      add(owner('financeOwner1', '财务部负责人一', '请复核财务整板块'));
    }
    final wantPurchase = has('purchaseContractCompleted');
    final wantSales = !purchase && has('salesContractCompleted');
    if (wantPurchase || wantSales) {
      var task = '请审核合同';
      if (wantPurchase && !wantSales) task = '请审核采购合同';
      if (wantSales && !wantPurchase) task = '请审核销售合同';
      add(owner('financeOwner2', '财务部负责人二', task));
    }
    return _dedupeNotifyRecipients(out);
  }

  switch (action) {
    case 'notify_tech':
      return _dedupeNotifyRecipients(
        [
          owner('technologyOwner', '科技部负责人', '请填写科技部内容'),
          owner('financeOwner2', '财务部负责人二', '请填写财务技术接口'),
        ].whereType<ProposalIntakeNotifyRecipient>().toList(),
      );
    case 'notify_market2':
    case 'confirm_tech':
    case 'start_review':
      if (onlyFlags != null) return reviewers(flags: onlyFlags);
      final resume = row.review['reviewRejected'] == true;
      final section = '${row.review['reviewRejectSection'] ?? ''}'.trim();
      if (resume && section.isNotEmpty) {
        return reviewers(flags: [section]);
      }
      return reviewers();
    case 'confirm_tech_revision':
      return _dedupeNotifyRecipients(
        [owner('marketOwner2', '市场部负责人二', '请复核本轮科技变更', fallback: row.createdBy)]
            .whereType<ProposalIntakeNotifyRecipient>()
            .toList(),
      );
    case 'start_tech_revision':
      return _dedupeNotifyRecipients(
        [
          owner('financeOwner2', '财务部负责人二', '本轮科技变更可填写财务技术接口'),
        ].whereType<ProposalIntakeNotifyRecipient>().toList(),
      );
    case 'submit_president':
      final ids = options?.presidentUserIds ?? const <int>[];
      if (ids.isNotEmpty) {
        return [
          for (final id in ids)
            if (id > 0)
              ProposalIntakeNotifyRecipient(
                userId: id,
                role: '最终确认人',
                name: _presidentName(id, options, people),
                task: '请查看提案并给出意见',
              ),
        ];
      }
      return _dedupeNotifyRecipients(
        [
          owner('president', '最终确认人', '请查看提案并给出意见'),
        ].whereType<ProposalIntakeNotifyRecipient>().toList(),
      );
    case 'remind':
      return proposalIntakeRemindRecipients(
        row: row,
        people: people,
        options: options,
      );
    default:
      return const [];
  }
}

String _presidentName(
  int id,
  ProposalIntakeOptions? options,
  List<ProposalPerson> people,
) {
  for (final person in options?.presidents ?? const <ProposalPerson>[]) {
    if (person.userId == id && person.name.trim().isNotEmpty) {
      return person.name.trim();
    }
  }
  for (final person in people) {
    if (person.userId == id && person.name.trim().isNotEmpty) {
      return person.name.trim();
    }
  }
  return '';
}

List<ProposalIntakeNotifyRecipient> proposalIntakeRemindRecipients({
  required ProposalIntakeRow row,
  List<ProposalPerson> people = const [],
  ProposalIntakeOptions? options,
}) {
  final stage = row.resolvedStage;
  switch (stage) {
    case 'filling':
    case 'draft':
      final name = row.initiatorDisplayName(people);
      return [
        if (row.createdBy > 0)
          ProposalIntakeNotifyRecipient(
            userId: row.createdBy,
            role: '提交人',
            name: name == '未指定' ? '' : name,
            task: '请填写',
          ),
      ];
    case 'awaiting_tech':
    case 'tech_revising':
      return proposalIntakeNotifyRecipients(
        action: 'notify_tech',
        row: row,
        people: people,
        options: options,
      );
    case 'awaiting_start_review':
      final name = row.initiatorDisplayName(people);
      return [
        if (row.createdBy > 0)
          ProposalIntakeNotifyRecipient(
            userId: row.createdBy,
            role: '提交人',
            name: name == '未指定' ? '' : name,
            task: '请重新提交复核',
          ),
      ];
    case 'reviewing':
    case 'tech_reviewing':
      bool done(String key) => row.review[key] == true;
      final purchase = proposalIntakeIsPurchase(row.kind);
      final flags = <String>[
        if (!done('marketCompleted')) 'marketCompleted',
        if (!done('technologyCompleted')) 'technologyCompleted',
        if (!purchase && !done('financeCompleted')) 'financeCompleted',
        if (!done('purchaseContractCompleted')) 'purchaseContractCompleted',
        if (!purchase && !done('salesContractCompleted'))
          'salesContractCompleted',
      ];
      final list = proposalIntakeNotifyRecipients(
        action: 'notify_market2',
        row: row,
        people: people,
        options: options,
        onlyFlags: flags,
      );
      if (!purchase &&
          !done('financeCompleted') &&
          !proposalIntakeFinanceLineItemsReviewed(row)) {
        final fin2 = proposalIntakeNotifyOwner(
          form: row.form,
          people: people,
          prefix: 'financeOwner2',
          role: '财务部负责人二',
          task: '请复核财务内容',
        );
        if (fin2 != null) {
          return _dedupeNotifyRecipients([...list, fin2]);
        }
      }
      return list;
    case 'awaiting_submit':
      final name = row.initiatorDisplayName(people);
      return [
        if (row.createdBy > 0)
          ProposalIntakeNotifyRecipient(
            userId: row.createdBy,
            role: '提交人',
            name: name == '未指定' ? '' : name,
            task: '请通知最终人',
          ),
      ];
    case 'pending_president':
      return proposalIntakeNotifyRecipients(
        action: 'submit_president',
        row: row,
        people: people,
        options: options,
      );
    default:
      return const [];
  }
}

List<ProposalIntakeNotifyRecipient> _dedupeNotifyRecipients(
  List<ProposalIntakeNotifyRecipient> items,
) {
  final seen = <int>{};
  final out = <ProposalIntakeNotifyRecipient>[];
  for (final item in items) {
    if (item.userId <= 0 || !seen.add(item.userId)) continue;
    out.add(item);
  }
  return out;
}

bool proposalIntakeReviewsComplete(ProposalIntakeRow row) {
  bool done(String key) => row.review[key] == true;
  if (!done('marketCompleted') ||
      !done('technologyCompleted') ||
      !done('purchaseContractCompleted')) {
    return false;
  }
  if (proposalIntakeIsPurchase(row.kind)) return true;
  return done('financeCompleted') && done('salesContractCompleted');
}

bool proposalIntakeTechRevisionReviewsComplete(ProposalIntakeRow row) {
  return row.review['technologyCompleted'] == true &&
      row.review['marketCompleted'] == true;
}

ProposalIntakeNotifyRecipient? proposalIntakeSubmitterNotifyRecipient(
  ProposalIntakeRow row, {
  required String task,
  List<ProposalPerson> people = const [],
}) {
  if (row.createdBy <= 0) return null;
  final name = row.initiatorDisplayName(people);
  return ProposalIntakeNotifyRecipient(
    userId: row.createdBy,
    role: '提交人',
    name: name == '未指定' ? '' : name,
    task: task,
  );
}

/// 板块复核后会通知谁，和后端 notifyProposalIntakeReviewChange 对齐，仅用于确认框预览。
List<ProposalIntakeNotifyRecipient> proposalIntakeAfterReviewNotifyRecipients({
  required ProposalIntakeRow row,
  required String flag,
  required bool approved,
  List<ProposalPerson> people = const [],
}) {
  ProposalIntakeNotifyRecipient? owner(
    String prefix,
    String role,
    String task,
  ) {
    return proposalIntakeNotifyOwner(
      form: row.form,
      people: people,
      prefix: prefix,
      role: role,
      task: task,
    );
  }

  if (!approved) {
    var item = proposalIntakeSubmitterNotifyRecipient(
      row,
      task: '请修改',
      people: people,
    );
    if (flag.contains('financeInterface')) {
      item = owner('financeOwner2', '财务部负责人二', '请修改');
    } else if (row.techRevisionOpen || row.isTechRevising) {
      item = owner('technologyOwner', '科技部负责人', '请修改');
    } else if (flag.startsWith('technology')) {
      item = owner('technologyOwner', '科技部负责人', '请修改');
    }
    return [if (item != null) item];
  }

  final after = row.copyWith(review: {...row.review, flag: true});
  if (row.techRevisionOpen || after.isTechReviewing || after.isTechRevising) {
    final out = <ProposalIntakeNotifyRecipient>[];
    if (flag == 'technologyCompleted' &&
        after.review['technologyCompleted'] == true) {
      final item = owner('marketOwner1', '市场部负责人一', '请复核本轮市场内容');
      if (item != null) out.add(item);
    }
    if (proposalIntakeTechRevisionReviewsComplete(after) &&
        !proposalIntakeTechRevisionReviewsComplete(row)) {
      final item = owner('technologyOwner', '科技部负责人', '本轮科技变更已完成');
      if (item != null) out.add(item);
    }
    return _dedupeNotifyRecipients(out);
  }

  if (proposalIntakeReviewsComplete(after) &&
      !proposalIntakeReviewsComplete(row)) {
    final item = proposalIntakeSubmitterNotifyRecipient(
      row,
      task: '请通知最终人',
      people: people,
    );
    return [if (item != null) item];
  }
  return const [];
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

DateTime? parseProposalIntakeInstant(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

DateTime? proposalIntakeOpenedAt(ProposalIntakeRow row) {
  final created = parseProposalIntakeInstant(row.createdAt);
  if (created != null) return created.toLocal();
  final match = RegExp(r'(\d{8})').firstMatch(row.code);
  if (match == null) return null;
  final raw = match.group(1)!;
  final y = int.tryParse(raw.substring(0, 4));
  final m = int.tryParse(raw.substring(4, 6));
  final d = int.tryParse(raw.substring(6, 8));
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// 打开日到今天，含当天，方便老板一眼看老化。
int proposalIntakeDaysOpen(ProposalIntakeRow row, {DateTime? now}) {
  final opened = proposalIntakeOpenedAt(row);
  if (opened == null) return 0;
  final n = now ?? DateTime.now();
  final start = DateTime(opened.year, opened.month, opened.day);
  final end = DateTime(n.year, n.month, n.day);
  final days = end.difference(start).inDays + 1;
  return days < 1 ? 1 : days;
}

String proposalIntakeDaysOpenLabel(ProposalIntakeRow row, {DateTime? now}) {
  final days = proposalIntakeDaysOpen(row, now: now);
  if (days <= 0) return '';
  if (days == 1) return '今天打开';
  return '已开 $days 天';
}

DateTime? proposalIntakeListDay(ProposalIntakeRow row) {
  final updated = parseProposalIntakeInstant(row.updatedAt);
  if (updated != null) {
    final local = updated.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
  final opened = proposalIntakeOpenedAt(row);
  if (opened == null) return null;
  return DateTime(opened.year, opened.month, opened.day);
}

String proposalIntakeDateSectionLabel(DateTime day, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final date = DateTime(day.year, day.month, day.day);
  final diff = today.difference(date).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  return '${date.month}月${date.day}日';
}

class ProposalIntakeDateGroup {
  const ProposalIntakeDateGroup({required this.label, required this.rows});

  final String label;
  final List<ProposalIntakeRow> rows;
}

/// 按最后更新日分组，组内保持传入顺序。
List<ProposalIntakeDateGroup> groupProposalIntakeRowsByDate(
  List<ProposalIntakeRow> rows, {
  DateTime? now,
}) {
  final buckets = <DateTime, List<ProposalIntakeRow>>{};
  final undated = <ProposalIntakeRow>[];
  for (final row in rows) {
    final day = proposalIntakeListDay(row);
    if (day == null) {
      undated.add(row);
      continue;
    }
    buckets.putIfAbsent(day, () => []).add(row);
  }
  final days = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in days)
      ProposalIntakeDateGroup(
        label: proposalIntakeDateSectionLabel(day, now: now),
        rows: buckets[day]!,
      ),
    if (undated.isNotEmpty) ProposalIntakeDateGroup(label: '更早', rows: undated),
  ];
}

/// 列表筛「未填写业务板块」时传给后端的哨兵值。
const kProposalIntakeSectorBlankFilter = '__blank';

String proposalIntakeSectorName(ProposalIntakeRow row) {
  final text = '${row.form['sector'] ?? ''}'.trim();
  if (text.isNotEmpty) return text;
  return (proposalIntakeFormRef(row.form, 'sectorRef')?.name ?? '').trim();
}

List<(String, String)> proposalIntakeSectorFilters(List<String> sectors) {
  final seen = <String>{};
  return [
    ('', '全部板块'),
    for (final raw in sectors)
      if (raw.trim().isNotEmpty && seen.add(raw.trim()))
        (raw.trim(), raw.trim()),
    (kProposalIntakeSectorBlankFilter, '未填写'),
  ];
}

bool proposalIntakeMatchesSectorFilter(ProposalIntakeRow row, String filter) {
  final want = filter.trim();
  if (want.isEmpty) return true;
  final name = proposalIntakeSectorName(row);
  if (want == kProposalIntakeSectorBlankFilter) return name.isEmpty;
  return name == want;
}

class ProposalIntakeFillProgress {
  const ProposalIntakeFillProgress({required this.filled, required this.total});

  final int filled;
  final int total;

  int get missing {
    final left = total - filled;
    if (left < 0) return 0;
    if (left > total) return total;
    return left;
  }

  int get filledPercent {
    if (total <= 0) return 0;
    final pct = ((filled / total) * 100).round();
    if (pct < 0) return 0;
    if (pct > 100) return 100;
    return pct;
  }

  String get label => '已填 $filledPercent%';
}

ProposalIntakeFillProgress proposalIntakeFillProgress(ProposalIntakeRow row) {
  final tally = _ProposalFillTally();
  final form = row.form;
  if (proposalIntakeIsPurchase(row.kind)) {
    _tallyPurchaseFill(tally, form);
  } else {
    _tallySalesFill(tally, form);
  }
  return ProposalIntakeFillProgress(filled: tally.filled, total: tally.total);
}

class _ProposalFillTally {
  int filled = 0;
  int total = 0;

  void slot(bool ok) {
    total++;
    if (ok) filled++;
  }

  void text(Map<String, dynamic> form, String key) =>
      slot(proposalIntakeFormHasText(form, key));

  void list(Map<String, dynamic> form, String key) =>
      slot(proposalIntakeFormHasList(form, key));

  void ref(Map<String, dynamic> form, String refKey, String textKey) =>
      slot(proposalIntakeFormHasRef(form, refKey, textKey));
}

void _tallyContractFill(
  _ProposalFillTally tally,
  Map<String, dynamic> form,
  String prefix,
) {
  final mode = '${form['${prefix}Mode'] ?? ''}'.trim();
  tally.slot(mode.isNotEmpty);
  if (mode == '未签署合同') {
    tally.slot(
      proposalIntakeFormHasText(form, '${prefix}FileName') ||
          proposalIntakeFormHasText(form, '${prefix}ObjectKey'),
    );
  } else if (mode.isNotEmpty) {
    tally.slot(proposalIntakeFormHasText(form, '${prefix}No'));
  }
  tally.text(form, '${prefix}Name');
  tally.text(form, '${prefix}SignDate');
  tally.text(form, '${prefix}OurParty');
  tally.text(form, '${prefix}Counterparty');
  tally.text(form, '${prefix}ValidPeriod');
  tally.text(form, '${prefix}CoreTerms');
}

void _tallyTechFill(_ProposalFillTally tally, Map<String, dynamic> form) {
  tally.text(form, 'technologyPlatform');
  tally.list(form, 'technologyCapabilities');
  tally.list(form, 'outputForms');
  tally.list(form, 'developmentTypes');
  tally.text(form, 'hasRdCost');
  if ('${form['hasRdCost'] ?? ''}'.trim() == '是') {
    final amount = num.tryParse('${form['rdAmount'] ?? ''}'.trim()) ?? 0;
    tally.slot(amount > 0);
  }
  tally.text(form, 'deliveryDate');
}

void _tallySalesFill(_ProposalFillTally tally, Map<String, dynamic> form) {
  tally.ref(form, 'sectorRef', 'sector');
  tally.text(form, 'proposalName');
  tally.text(form, 'proposalType');
  tally.ref(form, 'productRef', 'product');
  tally.ref(form, 'projectRef', 'projectName');
  tally.list(form, 'supplies');
  tally.text(form, 'supplierPolicy');
  tally.text(form, 'channelPolicy');
  tally.text(form, 'executionPlan');
  tally.text(form, 'riskPoints');
  tally.list(form, 'profitModes');
  tally.text(form, 'profitFormula');
  if (proposalIntakeHasExistingPurchaseProposal(form)) {
    final linked = proposalIntakeLinkedPurchaseProposalId(form) > 0;
    tally.slot(linked);
    if (linked) _tallyContractFill(tally, form, 'purchase');
  } else {
    _tallyContractFill(tally, form, 'purchase');
  }
  _tallyContractFill(tally, form, 'sales');
  _tallyTechFill(tally, form);
  if (proposalIntakeHasChildProducts(form)) {
    _tallyTechFill(tally, proposalIntakeChildTechnology(form));
  }
  final derivedFinance = proposalIntakeHasProductSalesScale(form);
  final derivedProcurement =
      proposalIntakeHasSupplySettleRatio(form) &&
      (derivedFinance || proposalIntakeFormHasText(form, 'salesScale'));
  tally.slot(derivedFinance);
  for (final field in kProposalSalesFinanceFillFields) {
    if (_kDerivedFinanceMetricKeys.contains(field.$1)) continue;
    if (field.$1 == 'couponProcurementCost' && derivedProcurement) {
      tally.slot(true);
      continue;
    }
    tally.text(form, field.$1);
  }
  for (final module in proposalIntakeFinanceModules(form)) {
    tally.slot(module.periodComplete);
    tally.slot(module.revenueComplete);
    tally.slot(module.costsComplete);
  }
  _tallySkuFill(tally, form);
}

void _tallySkuFill(_ProposalFillTally tally, Map<String, dynamic> form) {
  _tallySkuGroupFill(
    tally,
    proposalIntakeSkuDetails(form),
    proposalIntakeExistingBuiltOverride(form) == true,
  );
  if (proposalIntakeHasChildProducts(form)) {
    _tallySkuGroupFill(
      tally,
      proposalIntakeChildProducts(form),
      proposalIntakeIsChildExistingBuilt(form),
    );
  }
}

void _tallySkuGroupFill(
  _ProposalFillTally tally,
  List<ProposalSkuDetailRow> channel,
  bool existingBuilt,
) {
  if (existingBuilt) {
    tally.slot(channel.isNotEmpty);
  }
  for (final sku in channel) {
    if (existingBuilt || sku.isExistingBuilt) {
      tally.slot(sku.syncSourceCode.isNotEmpty);
      tally.slot(sku.assetProduct != null && sku.assetProduct!.isNotEmpty);
    }
  }
  for (final sku in channel) {
    if (!existingBuilt &&
        !sku.isExistingBuilt &&
        !proposalIntakeSkuStarted(sku)) {
      continue;
    }
    for (final settle in proposalIntakeSkuSettlements(sku)) {
      tally.slot(settle.terms.isSkuComplete);
    }
  }
}

void _tallyPurchaseFill(_ProposalFillTally tally, Map<String, dynamic> form) {
  tally.text(form, 'proposalType');
  tally.list(form, 'supplies');
  tally.text(form, 'supplyBrand');
  tally.text(form, 'bizContact');
  tally.text(form, 'financeContact');
  tally.list(form, 'invoiceTypes');
  tally.text(form, 'supplierPolicy');
  tally.text(form, 'salesPolicy');
  tally.text(form, 'executionPlan');
  tally.text(form, 'riskPoints');
  tally.text(form, 'financeRemark');
  _tallyContractFill(tally, form, 'purchase');
  _tallyPurchaseSupplyFill(tally, form);
  _tallyTechFill(tally, form);
}

void _tallyPurchaseSupplyFill(
  _ProposalFillTally tally,
  Map<String, dynamic> form,
) {
  final products = proposalIntakeSupplyProducts(form);
  final existing =
      proposalIntakeExistingSupplyOverride(form) == true ||
      products.any((item) => item.isExistingBuilt);
  if (existing && products.isEmpty) {
    tally.slot(false);
    return;
  }
  for (final product in products) {
    final rowExisting = existing || product.isExistingBuilt;
    if (!rowExisting && !proposalIntakeSupplyStarted(product)) continue;
    tally.slot(product.syncSourceCode.isNotEmpty);
    if (rowExisting) {
      tally.slot(
        product.assetProduct != null && product.assetProduct!.isNotEmpty,
      );
    } else {
      tally.slot(
        product.supplierCode.trim().isNotEmpty ||
            (product.supplierRef != null && product.supplierRef!.isNotEmpty),
      );
      tally.slot(product.productCode.trim().isNotEmpty);
      tally.slot(product.thresholdAmount.trim().isNotEmpty);
      tally.slot(product.isYuantongCoupon.trim().isNotEmpty);
      tally.slot(product.isStandaloneRebate.trim().isNotEmpty);
      tally.slot(product.isLowDiscountCoupon.trim().isNotEmpty);
      tally.slot(product.rebateMode.trim().isNotEmpty);
      tally.slot(
        product.oilCategory.trim().isNotEmpty ||
            (product.oilCategoryRef != null &&
                product.oilCategoryRef!.isNotEmpty),
      );
      tally.slot(product.effectiveDate.trim().isNotEmpty);
      tally.slot(product.expireDate.trim().isNotEmpty);
    }
    final settlements = proposalIntakeSupplySettlements(product);
    if (settlements.isEmpty) {
      tally.slot(false);
      continue;
    }
    for (var j = 0; j < settlements.length; j++) {
      final terms = settlements[j].terms;
      if (j > 0 && terms.isBlank) continue;
      tally.slot(proposalIntakePurchaseSettleComplete(terms));
    }
  }
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

/// 业务平台：优先 `syncSourceRef`，兼容对外 JSON 里的 `syncSource` 对象或纯 code。
CatalogRef? proposalIntakeSyncSourceRefFromJson(Map raw) {
  final fromRef = catalogRefOrNull(raw['syncSourceRef']);
  if (fromRef != null && fromRef.isNotEmpty) return fromRef;
  final source = raw['syncSource'];
  final fromSource = catalogRefOrNull(source);
  if (fromSource != null && fromSource.isNotEmpty) return fromSource;
  if (source is String && source.trim().isNotEmpty) {
    return CatalogRef(code: source.trim(), name: source.trim());
  }
  return null;
}

String proposalIntakeExistingBuiltText(Object? raw) {
  if (raw is Map) {
    final labeled = _existingBuiltFlag(raw['existingBuilt']);
    if (labeled.isNotEmpty) return labeled;
    return _existingBuiltFlag(
      raw['isExistingProduct'] ?? raw['isExistingBuilt'],
    );
  }
  return _existingBuiltFlag(raw);
}

String _existingBuiltFlag(Object? value) {
  if (value is bool) return value ? '是' : '否';
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return '';
  final lower = text.toLowerCase();
  if (lower == 'true' || lower == '1' || lower == 'yes' || text == '是') {
    return '是';
  }
  if (lower == 'false' || lower == '0' || lower == 'no' || text == '否') {
    return '否';
  }
  return text;
}

ChannelProductHit? proposalIntakeAssetProductFromJson(
  Map raw, {
  String productName = '',
  CatalogRef? channelRef,
  CatalogRef? syncSourceRef,
}) {
  final direct =
      channelProductHitOrNull(raw['assetProduct']) ??
      channelProductHitOrNull(raw['existingProduct']);
  if (direct != null) return direct;
  final name = productName.trim().isNotEmpty
      ? productName.trim()
      : '${raw['productName'] ?? raw['name'] ?? ''}'.trim();
  final code = '${raw['productCode'] ?? ''}'.trim();
  if (name.isEmpty && code.isEmpty) return null;
  if (proposalIntakeExistingBuiltText(raw) != '是' && code.isEmpty) return null;
  return ChannelProductHit(
    productName: name,
    productCode: code,
    channelId: channelRef?.id,
    channelName: (channelRef?.name ?? '').trim(),
    syncSource: (syncSourceRef?.code ?? '').trim(),
  );
}

/// 产品上的结算渠道：优先自身 [channelRef]，否则从结算明细提升（兼容旧单）。
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
    this.scale = '',
    this.scalePeriod = '',
    this.skuIds = const [],
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

  /// 产品结算上的销售规模，单位万元。
  final String scale;

  /// 规模口径：空或「年」按年，「月」按 ×12 年化。
  final String scalePeriod;

  /// 项目成本/共用规则关联的渠道产品。
  final List<String> skuIds;
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
      scale.isEmpty &&
      scalePeriod.isEmpty &&
      skuIds.isEmpty &&
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

  /// 项目成本：有比例或单价就能算，不要求销售结算那套主体和税率。
  bool get isProjectCostComplete =>
      displayRatio.trim().isNotEmpty || displayUnitPrice.trim().isNotEmpty;

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
    scale,
    scalePeriod,
    skuIds.join(','),
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
    String? scale,
    String? scalePeriod,
    List<String>? skuIds,
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
    scale: scale ?? this.scale,
    scalePeriod: scalePeriod ?? this.scalePeriod,
    skuIds: skuIds ?? this.skuIds,
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
    'scale': scale,
    'scalePeriod': scalePeriod,
    'skuIds': skuIds,
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
      scale: read('scale').isNotEmpty ? read('scale') : read('salesScale'),
      scalePeriod: read('scalePeriod'),
      skuIds: proposalIntakeParseIdList(raw['skuIds']),
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

const kProposalFinanceModuleOwnerMain = 'main';
const kProposalFinanceModuleOwnerChildren = 'children';

/// 销售提案的财务数据必须按产品归属保存，不能把主、子产品写进同一份整单汇总。
///
/// `main` 保存主产品合计，`children` 保存全部子产品合计。老单没有
/// `productFinance` 时，主产品仍从顶层旧字段读取，因而可继续查看和编辑。
const kProposalProductFinanceMain = 'main';
const kProposalProductFinanceChildren = 'children';

const _kProposalProductFinanceFields = <String>[
  'salesScale',
  'revenue',
  'couponProcurementCost',
  'profit',
  'margin',
  'turnoverCash',
  'turnoverTimes',
  'supplySettleMode',
  'supplySettleCycle',
  'supplyPayer',
  'supplyPayAccount',
  'channelSettleMode',
  'channelSettleCycle',
  'channelPayee',
  'channelReceiveAccount',
  'generalBusinessAccount',
  'prepaidAccount',
  'financeRemark',
  'costItems',
  'costItemCodes',
  'costItemAmounts',
  'costItemSettleTerms',
  'projectCost',
  'businessCostItems',
  'businessCostItemCodes',
  'businessCostItemAmounts',
  'businessCostItemSettleTerms',
  'businessCost',
  'operatingCostItems',
  'operatingCostItemCodes',
  'operatingCostItemAmounts',
  'operatingCost',
  'taxCostItems',
  'taxCostItemCodes',
  'taxCostItemAmounts',
  'taxCost',
  'rollback',
  'financeModules',
];

String proposalIntakeProductFinanceOwner(Object? raw) =>
    '$raw'.trim() == kProposalProductFinanceChildren
    ? kProposalProductFinanceChildren
    : kProposalProductFinanceMain;

/// Returns one product group's finance data.
///
/// The main group deliberately falls back to top-level fields for old records;
/// a child group never does, preventing legacy whole-order totals being
/// presented as a child-product total.
Map<String, dynamic> proposalIntakeProductFinance(
  Map<String, dynamic> form, {
  required String owner,
}) {
  final resolvedOwner = proposalIntakeProductFinanceOwner(owner);
  final raw = form['productFinance'];
  if (raw is Map && raw[resolvedOwner] is Map) {
    return Map<String, dynamic>.from(raw[resolvedOwner] as Map);
  }
  if (resolvedOwner == kProposalProductFinanceChildren) {
    return <String, dynamic>{};
  }
  return {
    for (final key in _kProposalProductFinanceFields)
      if (form.containsKey(key)) key: form[key],
  };
}

/// Writes only the chosen product group's financial payload.
///
/// Existing top-level main values are retained for API compatibility and old
/// clients. New child values are exclusively nested in `productFinance`.
Map<String, dynamic> proposalIntakeWriteProductFinance(
  Map<String, dynamic> form, {
  required String owner,
  required Map<String, dynamic> finance,
}) {
  final resolvedOwner = proposalIntakeProductFinanceOwner(owner);
  final groups = form['productFinance'] is Map
      ? Map<String, dynamic>.from(form['productFinance'] as Map)
      : <String, dynamic>{};
  groups[resolvedOwner] = Map<String, dynamic>.from(finance);
  final next = Map<String, dynamic>.from(form)..['productFinance'] = groups;
  if (resolvedOwner == kProposalProductFinanceMain) {
    for (final key in _kProposalProductFinanceFields) {
      if (finance.containsKey(key)) next[key] = finance[key];
    }
  }
  return next;
}

const _kProductFinanceScopeDerivedKeys = {
  'salesScale',
  'revenue',
  'profit',
  'margin',
  'turnoverCash',
  'couponProcurementCost',
};

/// Produces an isolated calculation input for one finance group.  Product
/// settlements are filtered before any derived metric is evaluated, so a
/// child-product amount can never inflate the main-product result.
Map<String, dynamic> proposalIntakeProductFinanceScope(
  Map<String, dynamic> form, {
  required String owner,
}) {
  final resolvedOwner = proposalIntakeProductFinanceOwner(owner);
  final finance = proposalIntakeProductFinance(form, owner: resolvedOwner);
  final skus = resolvedOwner == kProposalProductFinanceMain
      ? proposalIntakeSkuDetails(form)
      : proposalIntakeChildProducts(form);
  final skuIds = {for (final sku in skus) sku.id};
  final next = <String, dynamic>{
    ...form,
    for (final entry in finance.entries)
      if (!_kProductFinanceScopeDerivedKeys.contains(entry.key))
        entry.key: entry.value,
    'skuDetails': [for (final sku in skus) sku.toJson()],
    'childProducts': const <Map<String, dynamic>>[],
    'channelSkus': const <Map<String, dynamic>>[],
    'products': const <Map<String, dynamic>>[],
    'packs': const <Map<String, dynamic>>[],
    'couponPacks': const <Map<String, dynamic>>[],
    'productFinance': const <String, dynamic>{},
    'sharedSettlements': [
      for (final group in proposalIntakeSharedSettlements(form))
        if (group.skuIds.any(skuIds.contains))
          group
              .copyWith(
                skuIds: [
                  for (final id in group.skuIds)
                    if (skuIds.contains(id)) id,
                ],
              )
              .toJson(),
    ],
  };
  for (final key in _kProductFinanceScopeDerivedKeys) {
    if (resolvedOwner == kProposalProductFinanceMain) {
      if (form.containsKey(key)) {
        next[key] = form[key];
      } else if (finance.containsKey(key)) {
        next[key] = finance[key];
      }
    } else if (finance.containsKey(key)) {
      next[key] = finance[key];
    } else {
      next.remove(key);
    }
  }
  if (resolvedOwner == kProposalProductFinanceChildren) {
    for (final key in _kProposalProductFinanceFields) {
      if (!finance.containsKey(key)) next.remove(key);
    }
  }
  return next;
}

class ProposalFinanceModule {
  const ProposalFinanceModule({
    required this.id,
    this.title = '',
    this.owner = kProposalFinanceModuleOwnerMain,
    this.naturalMonth = '',
    this.projectPeriodStart = '',
    this.projectPeriodEnd = '',
    this.revenue = const ProposalFinanceSettleTerms(),
    this.projectCosts = const [],
    this.businessCosts = const [],
  });

  final String id;
  final String title;

  /// 旧版上线模块归属。新界面按产品财务分组展示，旧数据空值当主产品。
  final String owner;

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
    return '${owner.isEmpty ? kProposalFinanceModuleOwnerMain : owner}#${revenue.fingerprint}#${costs.join(';')}#$period';
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

  bool get isChildrenOwner =>
      owner.trim() == kProposalFinanceModuleOwnerChildren;

  ProposalFinanceModule copyWith({
    String? title,
    String? owner,
    String? naturalMonth,
    String? projectPeriodStart,
    String? projectPeriodEnd,
    ProposalFinanceSettleTerms? revenue,
    List<ProposalFinanceCostLine>? projectCosts,
    List<ProposalFinanceCostLine>? businessCosts,
  }) => ProposalFinanceModule(
    id: id,
    title: title ?? this.title,
    owner: owner ?? this.owner,
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
    'owner': owner.isEmpty ? kProposalFinanceModuleOwnerMain : owner,
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
      owner: _financeModuleOwner(raw['owner']),
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

String _financeModuleOwner(Object? raw) {
  final text = '$raw'.trim();
  if (text == kProposalFinanceModuleOwnerChildren) {
    return kProposalFinanceModuleOwnerChildren;
  }
  return kProposalFinanceModuleOwnerMain;
}

List<ProposalFinanceModule> proposalIntakeFinanceModulesOf(
  Map<String, dynamic> form, {
  required String owner,
}) {
  final want = _financeModuleOwner(owner);
  return [
    for (final item in proposalIntakeFinanceModules(form))
      if (_financeModuleOwner(item.owner) == want) item,
  ];
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

String proposalIntakeNewSharedSettleId() =>
    'ss-${DateTime.now().microsecondsSinceEpoch}';

List<String> proposalIntakeParseIdList(Object? raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  final seen = <String>{};
  for (final item in raw) {
    final id = '$item'.trim();
    if (id.isEmpty || seen.contains(id)) continue;
    seen.add(id);
    out.add(id);
  }
  return out;
}

class ProposalSharedSettleRow {
  const ProposalSharedSettleRow({
    required this.id,
    this.skuIds = const [],
    this.terms = const ProposalFinanceSettleTerms(),
  });

  final String id;
  final List<String> skuIds;
  final ProposalFinanceSettleTerms terms;

  bool get isBlank => skuIds.isEmpty && terms.isBlank;

  ProposalSharedSettleRow copyWith({
    List<String>? skuIds,
    ProposalFinanceSettleTerms? terms,
  }) => ProposalSharedSettleRow(
    id: id,
    skuIds: skuIds ?? this.skuIds,
    terms: terms ?? this.terms,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'skuIds': skuIds,
    ...terms.toJson(),
  };

  factory ProposalSharedSettleRow.fromJson(Object? raw) {
    if (raw is! Map) return const ProposalSharedSettleRow(id: '');
    final id = '${raw['id'] ?? ''}'.trim();
    return ProposalSharedSettleRow(
      id: id,
      skuIds: proposalIntakeParseIdList(raw['skuIds']),
      terms: ProposalFinanceSettleTerms.fromJson(raw),
    );
  }
}

List<ProposalSharedSettleRow> proposalIntakeSharedSettlements(
  Map<String, dynamic> form,
) {
  final raw = form['sharedSettlements'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) ProposalSharedSettleRow.fromJson(item),
  ].where((row) => row.id.isNotEmpty).toList();
}

Set<String> proposalIntakeSharedSettleSkuIds(Map<String, dynamic> form) {
  return {
    for (final row in proposalIntakeSharedSettlements(form)) ...row.skuIds,
  };
}

Set<String> proposalIntakeActiveSharedSettleSkuIds(Map<String, dynamic> form) {
  if (!kProposalSharedSettleEnabled) return const {};
  return proposalIntakeSharedSettleSkuIds(form);
}

bool proposalIntakeHasSupplySettleRatio(Map<String, dynamic> form) {
  for (final product in proposalIntakeSupplyProducts(form)) {
    for (final settle in proposalIntakeSupplySettlements(product)) {
      if (settle.terms.displayRatio.trim().isNotEmpty) return true;
    }
  }
  return false;
}

/// 暂时关闭「共用结算」入口，产品各自填结算。旧数据仍可参与测算。
const kProposalSharedSettleEnabled = false;

/// 规模口径暂时只按年填，不开放按月。
const kProposalScalePeriodLockedToYear = true;

/// 规模口径取值：空或「年」按年度值，「月」按 ×12 年化。
const kProposalScalePeriodYear = '年';
const kProposalScalePeriodMonth = '月';
const kProposalScalePeriods = <String>[
  kProposalScalePeriodYear,
  kProposalScalePeriodMonth,
];

/// 年化倍数：按月填写的规模乘 12，其余按年原值。
double proposalScaleAnnualFactor(String period) =>
    period.trim() == kProposalScalePeriodMonth ? 12 : 1;

/// 单条结算条款的年化规模（万元）。
/// 评级、印花税、增值税销项、周转资金一律取年化值，避免按月填写时整体偏 12 倍。
double proposalAnnualizedScale(ProposalFinanceSettleTerms terms) {
  if (terms.scale.trim().isEmpty) return 0;
  return proposalCostAmountValue(terms.scale) *
      proposalScaleAnnualFactor(terms.scalePeriod);
}

double proposalIntakeSkuScaleTotal(ProposalSkuDetailRow sku) {
  var sum = 0.0;
  for (final settle in proposalIntakeSkuSettlements(sku)) {
    if (settle.terms.scale.trim().isEmpty) continue;
    sum += proposalAnnualizedScale(settle.terms);
  }
  return sum;
}

String proposalIntakeSettleLabel(int index, {String kind = '结算'}) {
  const names = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
  if (index >= 0 && index < names.length) return '$kind${names[index]}';
  return '$kind${index + 1}';
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

bool proposalIntakeIsExistingBuilt(Map<String, dynamic> form) {
  return proposalIntakeExistingBuiltOverride(form) ??
      proposalIntakeSkuDetails(form).any((item) => item.isExistingBuilt);
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

List<ProposalFinanceSettleTerms> proposalIntakeProductSalesSettleTerms(
  Map<String, dynamic> form,
) {
  final shared = proposalIntakeSharedSettlements(form);
  final covered = proposalIntakeSharedSettleSkuIds(form);
  final skus = {
    for (final sku in proposalIntakeAllSellableSkus(form)) sku.id: sku,
  };
  return [
    for (final group in shared)
      for (final skuId in group.skuIds)
        if (skus[skuId] != null)
          for (final settle in proposalIntakeSkuSettlements(skus[skuId]!))
            if (settle.terms.scale.trim().isNotEmpty)
              group.terms.copyWith(
                scale: settle.terms.scale,
                scalePeriod: settle.terms.scalePeriod,
              ),
    for (final sku in proposalIntakeAllSellableSkus(form))
      if (!covered.contains(sku.id))
        for (final settle in proposalIntakeSkuSettlements(sku)) settle.terms,
  ];
}

bool proposalIntakeHasProductSalesScale(Map<String, dynamic> form) {
  return proposalIntakeProductSalesSettleTerms(
    form,
  ).any((terms) => terms.scale.trim().isNotEmpty);
}

const _kDerivedFinanceMetricKeys = {
  'salesScale',
  'revenue',
  'profit',
  'margin',
};

List<String> proposalIntakeSkuSettleReviewKeys(Map<String, dynamic> form) {
  return [
    for (final sku in proposalIntakeAllSellableSkus(form))
      for (final settle in proposalIntakeSkuSettlements(sku))
        'skuSettle:${sku.id}:${settle.id}',
    if (kProposalSharedSettleEnabled)
      for (final group in proposalIntakeSharedSettlements(form))
        'sharedSettle:${group.id}:${group.id}',
  ];
}

bool proposalIntakeSkuStarted(ProposalSkuDetailRow sku) {
  return sku.productName.trim().isNotEmpty ||
      (sku.assetProduct != null && sku.assetProduct!.isNotEmpty);
}

List<String> proposalIntakeSkuSettleIssues(
  Map<String, dynamic> form, {
  bool includeSettlements = true,
}) {
  final issues = <String>[];
  issues.addAll(
    _proposalIntakeSkuGroupIssues(
      rows: proposalIntakeSkuDetails(form),
      existingBuilt: proposalIntakeExistingBuiltOverride(form) == true,
      includeSettlements: includeSettlements,
      emptyExistingLabel: '已勾选已建产品，请至少添加一条渠道产品并搜索选择已建产品',
      rowLabel: (i, sku) => sku.productName.isEmpty
          ? '渠道产品第${i + 1}条'
          : '渠道产品「${sku.productName}」',
      covered: proposalIntakeActiveSharedSettleSkuIds(form),
    ),
  );
  final children = proposalIntakeChildProducts(form);
  if (children.isNotEmpty) {
    final mainIds = {for (final sku in proposalIntakeSkuDetails(form)) sku.id};
    for (final child in children) {
      if (child.parentSkuId.isEmpty) {
        issues.add(
          '子产品「${child.productName.isEmpty ? '未命名' : child.productName}」请选择关联主产品',
        );
      } else if (!mainIds.contains(child.parentSkuId)) {
        issues.add(
          '子产品「${child.productName.isEmpty ? '未命名' : child.productName}」关联的主产品不存在',
        );
      }
    }
    issues.addAll(
      _proposalIntakeSkuGroupIssues(
        rows: children,
        existingBuilt: proposalIntakeIsChildExistingBuilt(form),
        includeSettlements: includeSettlements,
        emptyExistingLabel: '已勾选子产品已建产品，请至少添加一条子产品并搜索选择已建产品',
        rowLabel: (i, sku) => sku.productName.isEmpty
            ? '子产品第${i + 1}条'
            : '子产品「${sku.productName}」',
        covered: proposalIntakeActiveSharedSettleSkuIds(form),
      ),
    );
  }
  if (includeSettlements && kProposalSharedSettleEnabled) {
    for (final group in proposalIntakeSharedSettlements(form)) {
      if (group.isBlank) continue;
      if (group.skuIds.isEmpty) {
        issues.add('共用结算请勾选适用的渠道产品');
      }
      if (!group.terms.isSkuComplete) {
        issues.add('共用结算未填完结算方式对应金额、计算公式、税率');
      }
    }
  }
  return issues;
}

List<String> _proposalIntakeSkuGroupIssues({
  required List<ProposalSkuDetailRow> rows,
  required bool existingBuilt,
  required bool includeSettlements,
  required String emptyExistingLabel,
  required String Function(int index, ProposalSkuDetailRow sku) rowLabel,
  required Set<String> covered,
}) {
  final issues = <String>[];
  if (existingBuilt && rows.isEmpty) {
    issues.add(emptyExistingLabel);
  }
  for (var i = 0; i < rows.length; i++) {
    final sku = rows[i];
    final name = rowLabel(i, sku);
    if (existingBuilt || sku.isExistingBuilt) {
      if (sku.syncSourceCode.isEmpty) {
        issues.add('$name请选择业务平台');
      }
      if (sku.assetProduct == null || sku.assetProduct!.isEmpty) {
        issues.add('$name请搜索并选择已建产品');
      }
    }
  }
  if (!includeSettlements) return issues;
  for (var i = 0; i < rows.length; i++) {
    final sku = rows[i];
    if (!existingBuilt &&
        !sku.isExistingBuilt &&
        !proposalIntakeSkuStarted(sku)) {
      continue;
    }
    if (covered.contains(sku.id)) continue;
    final name = rowLabel(i, sku);
    final settlements = proposalIntakeSkuSettlements(sku);
    for (var j = 0; j < settlements.length; j++) {
      if (!settlements[j].terms.isSkuComplete) {
        issues.add('$name${proposalIntakeSettleLabel(j)}未填完结算方式对应金额、计算公式、税率');
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
    this.channelCategoryL1Ref,
    this.channelCategoryL2Ref,
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
    this.parentSkuId = '',
    this.settlements = const [],
  });

  final String id;
  final String productName;
  final String faceValue;
  final String productCategoryL1;
  final String productCategoryL2;
  final String channelCategoryL1;
  final String channelCategoryL2;
  final CatalogRef? channelCategoryL1Ref;
  final CatalogRef? channelCategoryL2Ref;
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

  /// 子产品关联的主产品 id。主产品自身保持为空。
  final String parentSkuId;
  final List<ProposalSkuSettleRow> settlements;

  String get syncSourceCode => (syncSourceRef?.code ?? '').trim();
  String get institutionCode => (institutionRef?.code ?? '').trim();
  String get institutionName => (institutionRef?.name ?? '').trim();
  String get channelCode => (channelRef?.code ?? '').trim();
  String get channelName => (channelRef?.name ?? '').trim();
  CatalogRef? get resolvedChannelCategoryL1 =>
      proposalIntakeResolvedCategoryRef(
        channelCategoryL1Ref,
        channelCategoryL1,
      );
  CatalogRef? get resolvedChannelCategoryL2 =>
      proposalIntakeResolvedCategoryRef(
        channelCategoryL2Ref,
        channelCategoryL2,
      );
  bool get isExistingBuilt => existingBuilt.trim() == '是';

  bool get isBlank =>
      productName.isEmpty &&
      faceValue.isEmpty &&
      productCategoryL1.isEmpty &&
      productCategoryL2.isEmpty &&
      channelCategoryL1.isEmpty &&
      channelCategoryL2.isEmpty &&
      (channelCategoryL1Ref == null || channelCategoryL1Ref!.isEmpty) &&
      (channelCategoryL2Ref == null || channelCategoryL2Ref!.isEmpty) &&
      syncZhongyouHaoke.isEmpty &&
      effectiveDate.isEmpty &&
      expireDate.isEmpty &&
      supplierCodes.isEmpty &&
      inventoryQty.isEmpty &&
      (syncSourceRef == null || syncSourceRef!.isEmpty) &&
      (institutionRef == null || institutionRef!.isEmpty) &&
      (channelRef == null || channelRef!.isEmpty) &&
      existingBuilt.isEmpty &&
      (assetProduct == null || assetProduct!.isEmpty) &&
      parentSkuId.isEmpty;

  ProposalSkuDetailRow copyWith({
    String? productName,
    String? faceValue,
    String? productCategoryL1,
    String? productCategoryL2,
    String? channelCategoryL1,
    String? channelCategoryL2,
    Object? channelCategoryL1Ref = _catalogUnset,
    Object? channelCategoryL2Ref = _catalogUnset,
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
    String? parentSkuId,
    List<ProposalSkuSettleRow>? settlements,
  }) => ProposalSkuDetailRow(
    id: id,
    productName: productName ?? this.productName,
    faceValue: faceValue ?? this.faceValue,
    productCategoryL1: productCategoryL1 ?? this.productCategoryL1,
    productCategoryL2: productCategoryL2 ?? this.productCategoryL2,
    channelCategoryL1: channelCategoryL1 ?? this.channelCategoryL1,
    channelCategoryL2: channelCategoryL2 ?? this.channelCategoryL2,
    channelCategoryL1Ref: identical(channelCategoryL1Ref, _catalogUnset)
        ? this.channelCategoryL1Ref
        : channelCategoryL1Ref as CatalogRef?,
    channelCategoryL2Ref: identical(channelCategoryL2Ref, _catalogUnset)
        ? this.channelCategoryL2Ref
        : channelCategoryL2Ref as CatalogRef?,
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
    parentSkuId: parentSkuId ?? this.parentSkuId,
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
      settlements:
          settlements ??
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
    'channelCategoryL1': proposalIntakeCategoryLabel(
      resolvedChannelCategoryL1,
      channelCategoryL1,
    ),
    'channelCategoryL2': proposalIntakeCategoryLabel(
      resolvedChannelCategoryL2,
      channelCategoryL2,
    ),
    'channelCategoryL1Ref': catalogRefToJson(resolvedChannelCategoryL1),
    'channelCategoryL2Ref': catalogRefToJson(resolvedChannelCategoryL2),
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
    'parentSkuId': parentSkuId,
    'settlements': [
      for (final item in settlements)
        item
            .copyWith(terms: item.terms.copyWith(channelRef: channelRef))
            .toJson(),
    ],
  };

  factory ProposalSkuDetailRow.fromJson(Object? raw) {
    if (raw is! Map) return const ProposalSkuDetailRow(id: '');
    var syncRef = proposalIntakeSyncSourceRefFromJson(raw);
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
    var productName = '${raw['productName'] ?? raw['name'] ?? ''}'.trim();
    var channelRef = proposalIntakeChannelRefFromJson(raw);
    var asset = proposalIntakeAssetProductFromJson(
      raw,
      productName: productName,
      channelRef: channelRef,
      syncSourceRef: syncRef,
    );
    if (productName.isEmpty) productName = asset?.label ?? '';
    channelRef ??= asset?.channelRef;
    final l1Ref = proposalIntakeResolvedCategoryRef(
      catalogRefOrNull(raw['channelCategoryL1Ref']),
      '${raw['channelCategoryL1'] ?? ''}'.trim(),
    );
    final l2Ref = proposalIntakeResolvedCategoryRef(
      catalogRefOrNull(raw['channelCategoryL2Ref']),
      '${raw['channelCategoryL2'] ?? ''}'.trim(),
    );
    return ProposalSkuDetailRow(
      id: '${raw['id'] ?? ''}'.trim(),
      productName: productName,
      faceValue: '${raw['faceValue'] ?? raw['skuFaceValue'] ?? ''}'.trim(),
      productCategoryL1: '${raw['productCategoryL1'] ?? ''}'.trim(),
      productCategoryL2: '${raw['productCategoryL2'] ?? ''}'.trim(),
      channelCategoryL1: (l1Ref?.name ?? '${raw['channelCategoryL1'] ?? ''}')
          .trim(),
      channelCategoryL2: (l2Ref?.name ?? '${raw['channelCategoryL2'] ?? ''}')
          .trim(),
      channelCategoryL1Ref: l1Ref,
      channelCategoryL2Ref: l2Ref,
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
      existingBuilt: proposalIntakeExistingBuiltText(raw),
      assetProduct: asset,
      parentSkuId: '${raw['parentSkuId'] ?? ''}'.trim(),
      settlements: [
        for (final item
            in raw['settlements'] is List
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

List<ProposalSkuDetailRow> _parseSkuDetailRows(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) ProposalSkuDetailRow.fromJson(item),
  ].where((row) => row.id.isNotEmpty).toList();
}

List<T> _preferFilledCatalogRows<T>({
  required List<T> primary,
  required List<T> aliases,
  required String Function(T row) idOf,
  required bool Function(T row) isBlank,
}) {
  if (primary.isEmpty) return aliases;
  if (aliases.isEmpty) return primary;
  if (primary.every(isBlank) && aliases.any((row) => !isBlank(row))) {
    return aliases;
  }
  final aliasById = {for (final row in aliases) idOf(row): row};
  return [
    for (final row in primary)
      if (isBlank(row) && aliasById[idOf(row)] != null)
        aliasById[idOf(row)]!
      else
        row,
  ];
}

bool proposalIntakeSkuHasManualDetails(ProposalSkuDetailRow sku) {
  if (sku.faceValue.trim().isNotEmpty ||
      sku.institutionName.isNotEmpty ||
      sku.channelCategoryL1.trim().isNotEmpty ||
      sku.channelCategoryL2.trim().isNotEmpty ||
      sku.syncZhongyouHaoke.trim().isNotEmpty ||
      sku.effectiveDate.trim().isNotEmpty ||
      sku.expireDate.trim().isNotEmpty ||
      sku.supplierCodes.trim().isNotEmpty ||
      sku.inventoryQty.trim().isNotEmpty) {
    return true;
  }
  final channelName = sku.channelName.trim();
  if (channelName.isEmpty) return false;
  final hit = sku.assetProduct;
  if (hit != null && hit.isNotEmpty && channelName == hit.channelName.trim()) {
    return false;
  }
  return true;
}

List<ProposalSkuDetailRow> proposalIntakeSkuDetails(Map<String, dynamic> form) {
  final primary = _parseSkuDetailRows(form['skuDetails']);
  final aliases = [
    ..._parseSkuDetailRows(form['channelSkus']),
    ..._parseSkuDetailRows(form['products']),
  ];
  final merged = _preferFilledCatalogRows(
    primary: primary,
    aliases: aliases,
    idOf: (row) => row.id,
    isBlank: (row) => row.isBlank,
  );
  if (merged.isNotEmpty) return merged;
  final legacy = proposalIntakeLegacySkuDetail(form);
  return legacy == null ? const [] : [legacy];
}

/// 子产品：显式关联后才有。旧单多条渠道产品仍走 [proposalIntakeSkuDetails]，不会自动升成子产品。
List<ProposalSkuDetailRow> proposalIntakeChildProducts(
  Map<String, dynamic> form,
) => _parseSkuDetailRows(form['childProducts']);

bool proposalIntakeHasChildProducts(Map<String, dynamic> form) =>
    proposalIntakeChildProducts(form).isNotEmpty;

/// 主产品渠道产品 + 子产品，用于规模加总和结算复核。
List<ProposalSkuDetailRow> proposalIntakeAllSellableSkus(
  Map<String, dynamic> form,
) => [...proposalIntakeSkuDetails(form), ...proposalIntakeChildProducts(form)];

bool proposalIntakeIsChildExistingBuilt(Map<String, dynamic> form) {
  final raw = form['childIsExistingBuilt'];
  if (raw is bool) return raw;
  final text = '$raw'.trim().toLowerCase();
  if (text == 'true' || text == '1' || text == '是' || text == 'yes') {
    return true;
  }
  if (text == 'false' || text == '0' || text == '否' || text == 'no') {
    return false;
  }
  return proposalIntakeChildProducts(form).any((item) => item.isExistingBuilt);
}

class ProposalBenefitProduct {
  const ProposalBenefitProduct({
    required this.id,
    this.name = '',
    this.skuQuantities = const {},
  });

  final String id;
  final String name;
  final Map<String, int> skuQuantities;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'skuQuantities': skuQuantities,
  };

  factory ProposalBenefitProduct.fromJson(Object? raw) {
    if (raw is! Map) {
      return const ProposalBenefitProduct(id: 'benefit-main');
    }
    final id = '${raw['id'] ?? ''}'.trim();
    final quantities = <String, int>{};
    final rawQuantities = raw['skuQuantities'];
    if (rawQuantities is Map) {
      for (final entry in rawQuantities.entries) {
        final id = '${entry.key}'.trim();
        final quantity = int.tryParse('${entry.value}'.trim()) ?? 0;
        if (id.isNotEmpty && quantity > 0) quantities[id] = quantity;
      }
    }
    return ProposalBenefitProduct(
      id: id.isEmpty ? 'benefit-main' : id,
      name: '${raw['name'] ?? ''}'.trim(),
      skuQuantities: quantities,
    );
  }
}

ProposalBenefitProduct proposalIntakeBenefitProduct(Map<String, dynamic> form) {
  final stored = ProposalBenefitProduct.fromJson(form['benefitProduct']);
  if (stored.name.isNotEmpty) return stored;
  final title = '${form['proposalName'] ?? ''}'.trim();
  if (title.isEmpty) return stored;
  return ProposalBenefitProduct(
    id: stored.id,
    name: title,
    skuQuantities: stored.skuQuantities,
  );
}

int proposalIntakeChildProductQuantity(
  Map<String, dynamic> form,
  String childId,
) {
  final quantity = proposalIntakeBenefitProduct(form).skuQuantities[childId];
  return quantity == null || quantity < 1 ? 1 : quantity;
}

Map<String, dynamic> proposalIntakeChildTechnology(Map<String, dynamic> form) {
  final raw = form['childTechnology'];
  if (raw is! Map) return <String, dynamic>{};
  return Map<String, dynamic>.from(
    raw.map((key, value) => MapEntry('$key', value)),
  );
}

const kProposalChildTechReviewPrefix = 'children:';

List<String> proposalIntakeTechnologyReviewItemKeys(Map<String, dynamic> form) {
  final keys = [...kProposalTechnologyReviewFields];
  if (!proposalIntakeHasChildProducts(form)) return keys;
  return [
    ...keys,
    for (final key in kProposalTechnologyReviewFields)
      '$kProposalChildTechReviewPrefix$key',
  ];
}

String proposalIntakeNewSkuId() =>
    'sku-${DateTime.now().microsecondsSinceEpoch}';

String proposalIntakeNewChildSkuId() =>
    'child-${DateTime.now().microsecondsSinceEpoch}';

CatalogRef? proposalIntakeResolvedCategoryRef(CatalogRef? ref, String name) {
  if (ref != null && ref.isNotEmpty) return ref;
  final fromName = CatalogRef.fromName(name);
  return fromName.isEmpty ? null : fromName;
}

String proposalIntakeCategoryLabel(CatalogRef? ref, String fallback) {
  final name = (ref?.name ?? '').trim();
  if (name.isNotEmpty) return name;
  final code = (ref?.code ?? '').trim();
  if (code.isNotEmpty) return code;
  return fallback.trim();
}

bool proposalIntakeChannelCategoryChildOf(CatalogRef child, CatalogRef parent) {
  if (child.isEmpty || parent.isEmpty) return false;
  final pid = child.parentId;
  if (pid != null && pid != 0 && parent.id != null && parent.id == pid) {
    return true;
  }
  bool same(String a, String b) => a.trim().isNotEmpty && a.trim() == b.trim();
  if (same(child.parentCode, parent.code) ||
      same(child.parentCode, parent.name)) {
    return true;
  }
  if (same(child.parentName, parent.name) ||
      same(child.parentName, parent.code)) {
    return true;
  }
  return false;
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
    final prefix = module.isChildrenOwner ? '子产品' : '';
    if (!module.periodComplete) {
      issues.add(
        module.usesProjectPeriod
            ? '$prefix财务模块「$title」非自然月请选择项目周期'
            : '$prefix财务模块「$title」请选择是否自然月',
      );
    }
    if (!module.revenueComplete) {
      issues.add('$prefix财务模块「$title」收入条款未填完');
    }
    if (!module.costsComplete) {
      issues.add('$prefix财务模块「$title」成本项条款未填完');
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
    this.productCode = '',
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
  final String productCode;
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
    String? productCode,
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
    productCode: productCode ?? this.productCode,
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
      productCode: hit?.productCode ?? '',
      settlements:
          settlements ??
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
    'productCode': productCode,
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
    var syncRef = proposalIntakeSyncSourceRefFromJson(raw);
    var supplier = catalogRefOrNull(raw['supplierRef']);
    final asset = proposalIntakeAssetProductFromJson(
      raw,
      productName: '${raw['productName'] ?? raw['name'] ?? ''}'.trim(),
      syncSourceRef: syncRef,
    );
    supplier ??= asset?.supplierRef;
    var supplierCode = '${raw['supplierCode'] ?? raw['productId'] ?? ''}'
        .trim();
    if (supplierCode.isEmpty) {
      supplierCode = (supplier?.code ?? asset?.supplierCode ?? '').trim();
    }
    if (supplier == null && supplierCode.isNotEmpty) {
      supplier = CatalogRef(code: supplierCode, name: supplierCode);
    }
    var productCode = '${raw['productCode'] ?? ''}'.trim();
    if (productCode.isEmpty) {
      productCode = (asset?.productCode ?? '').trim();
    }
    return ProposalSupplyProductRow(
      id: '${raw['id'] ?? ''}'.trim(),
      supplierCode: supplierCode,
      supplierRef: supplier,
      syncSourceRef: syncRef,
      productCode: productCode,
      thresholdAmount: '${raw['thresholdAmount'] ?? ''}'.trim(),
      isYuantongCoupon: '${raw['isYuantongCoupon'] ?? ''}'.trim(),
      isStandaloneRebate: '${raw['isStandaloneRebate'] ?? ''}'.trim(),
      isLowDiscountCoupon: '${raw['isLowDiscountCoupon'] ?? ''}'.trim(),
      rebateMode: '${raw['rebateMode'] ?? ''}'.trim(),
      effectiveDate: '${raw['effectiveDate'] ?? ''}'.trim(),
      expireDate: '${raw['expireDate'] ?? ''}'.trim(),
      oilCategory: '${raw['oilCategory'] ?? ''}'.trim(),
      oilCategoryRef: catalogRefOrNull(raw['oilCategoryRef']),
      existingBuilt: proposalIntakeExistingBuiltText(raw),
      assetProduct: asset,
      settlements: [
        for (final item
            in raw['settlements'] is List
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
}) => ProposalSupplyProductRow(
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
      product.productCode.trim().isNotEmpty ||
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

List<ProposalSupplyProductRow> _parseSupplyProductRows(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) ProposalSupplyProductRow.fromJson(item),
  ].where((row) => row.id.isNotEmpty).toList();
}

List<ProposalSupplyProductRow> proposalIntakeSupplyProducts(
  Map<String, dynamic> form,
) {
  return _preferFilledCatalogRows(
    primary: _parseSupplyProductRows(form['supplyProducts']),
    aliases: _parseSupplyProductRows(form['products']),
    idOf: (row) => row.id,
    isBlank: (row) =>
        row.supplierCode.trim().isEmpty &&
        (row.supplierRef == null || row.supplierRef!.isEmpty) &&
        (row.assetProduct == null || row.assetProduct!.isEmpty) &&
        row.productCode.trim().isEmpty &&
        (row.syncSourceRef == null || row.syncSourceRef!.isEmpty),
  );
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
  ('salesScale', '销售规模目标（年·万元）'),
  ('revenue', '收入（万元）'),
  ('couponProcurementCost', '电子券采购成本（万元）'),
  ('profit', '利润（万元）'),
  ('margin', '毛利率（%）'),
  ('turnoverTimes', '月周转次数'),
  ('supplySettleMode', '供给侧结算模式'),
  ('supplySettleCycle', '供给侧结算周期'),
  ('supplyPayer', '供给侧付款主体'),
  ('supplyPayAccount', '供给侧付款账户'),
  ('channelSettleMode', '渠道侧结算模式'),
  ('channelSettleCycle', '渠道侧结算周期'),
  ('channelPayee', '渠道侧收款主体'),
  ('channelReceiveAccount', '渠道侧收款账户'),
  ('generalBusinessAccount', '结算账户一'),
  ('prepaidAccount', '结算账户二'),
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
  final derived = proposalIntakeHasProductSalesScale(form);
  final derivedProcurement =
      proposalIntakeHasSupplySettleRatio(form) &&
      (derived || proposalIntakeFormHasText(form, 'salesScale'));
  if (!derived) {
    issues.add('请在产品结算中填写规模（万元）');
  }
  for (final field in kProposalSalesFinanceFillFields) {
    if (_kDerivedFinanceMetricKeys.contains(field.$1)) continue;
    if (field.$1 == 'couponProcurementCost' && derivedProcurement) continue;
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

List<String> proposalIntakeChildTechFillIssues(Map<String, dynamic> form) {
  if (!proposalIntakeHasChildProducts(form)) return const [];
  return [
    for (final issue in proposalIntakeTechFillIssues(
      proposalIntakeChildTechnology(form),
      purchase: false,
    ))
      issue.startsWith('子产品') ? issue : '子产品$issue',
  ];
}

bool proposalIntakePurchaseSettleComplete(ProposalFinanceSettleTerms terms) {
  return proposalIntakePurchaseSettleGaps(terms).isEmpty;
}

/// 采购供给结算还缺哪些项。按比例结算不要求单价；单价结算不要求比例。
List<String> proposalIntakePurchaseSettleGaps(
  ProposalFinanceSettleTerms terms,
) {
  final gaps = <String>[];
  final billType =
      (terms.billTypeRef != null && terms.billTypeRef!.isNotEmpty) ||
      terms.billType.trim().isNotEmpty;
  if (!billType) gaps.add('账单类型');
  final settleMode =
      (terms.settleModeRef != null && terms.settleModeRef!.isNotEmpty) ||
      terms.settleMode.trim().isNotEmpty;
  if (!settleMode) gaps.add('结算方式');
  if (proposalIntakeSettleIsTier(terms)) {
    if (terms.settleRule.trim().isEmpty && terms.displayFormula.isEmpty) {
      gaps.add('阶梯价格');
    }
  } else if (proposalIntakeSettleUsesRatio(terms) &&
      proposalIntakeSettleUsesUnitPrice(terms)) {
    if (terms.displayRatio.isEmpty) gaps.add('结算比例');
    if (terms.displayUnitPrice.isEmpty) gaps.add('结算单价');
  } else if (proposalIntakeSettleUsesUnitPrice(terms)) {
    if (terms.displayUnitPrice.isEmpty && terms.resolvedPrice.isEmpty) {
      gaps.add('结算单价');
    }
  } else if (terms.resolvedPrice.isEmpty) {
    gaps.add(proposalIntakeSettleUsesRatio(terms) ? '结算比例' : '结算金额');
  }
  if (terms.displayFormula.isEmpty) gaps.add('计算公式');
  if (terms.invoiceType.trim().isEmpty) gaps.add('发票类型');
  if (terms.taxRate.trim().isEmpty) gaps.add('税率');
  if (terms.effectiveTime.trim().isEmpty) gaps.add('生效时间');
  if (terms.expireTime.trim().isEmpty) gaps.add('失效时间');
  return gaps;
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
      if (product.productCode.trim().isEmpty) {
        issues.add('$label 请填写产品编码');
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
        final gaps = proposalIntakePurchaseSettleGaps(terms);
        issues.add(
          '$label ${proposalIntakeSettleLabel(j)}未填完：${gaps.join('、')}',
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

Map<String, dynamic> proposalIntakeEnsureChildFinanceModule(
  Map<String, dynamic> form,
) {
  if (!proposalIntakeHasChildProducts(form)) return form;
  final modules = proposalIntakeFinanceModules(form);
  if (modules.any((item) => item.isChildrenOwner)) return form;
  return {
    ...form,
    'financeModules': [
      for (final item in modules) item.toJson(),
      ProposalFinanceModule(
        id: proposalIntakeNewFinanceModuleId(),
        title: '子产品财务模块',
        owner: kProposalFinanceModuleOwnerChildren,
      ).toJson(),
    ],
  };
}

Map<String, dynamic> proposalIntakeSyncChildProductMeta(
  Map<String, dynamic> form,
) {
  final children = proposalIntakeChildProducts(form);
  final hasChildren = children.isNotEmpty;
  final benefit = proposalIntakeBenefitProduct(form);
  var next = Map<String, dynamic>.from(form)
    ..['benefitProduct'] = {
      ...benefit.toJson(),
      'relatedSkuIds': [for (final child in children) child.id],
      'skuQuantities': {
        for (final child in children)
          child.id: proposalIntakeChildProductQuantity(form, child.id),
      },
    }
    ..['isCouponPack'] = hasChildren;
  if (!hasChildren) {
    next['couponPacks'] = <Map<String, dynamic>>[];
    return next;
  }
  next['couponPacks'] = [proposalIntakeMainProductPackJson(next)];
  // 旧版会在这里自动创建「子产品合并财务模块」。现在子产品财务
  // 归属 `productFinance.children`，不再制造一个独立汇总模块。
  return next;
}

Map<String, dynamic> proposalIntakeSkuOutboundJson(ProposalSkuDetailRow sku) {
  return {
    ...sku.toJson(),
    'productCode': sku.assetProduct?.productCode ?? '',
    'isExistingProduct': sku.isExistingBuilt,
  };
}

Map<String, dynamic> proposalIntakeMainProductPackJson(
  Map<String, dynamic> form,
) {
  final benefit = proposalIntakeBenefitProduct(form);
  final children = proposalIntakeChildProducts(form);
  final mainSkus = proposalIntakeSkuDetails(form);
  final lead = mainSkus.isEmpty ? null : mainSkus.first;
  final name = benefit.name.isNotEmpty
      ? benefit.name
      : (lead?.productName ?? '');
  return {
    'id': benefit.id,
    'name': name,
    'skuIds': [for (final child in children) child.id],
    'skuQuantities': {
      for (final child in children)
        child.id: proposalIntakeChildProductQuantity(form, child.id),
    },
    'productCode': lead?.assetProduct?.productCode ?? '',
    'syncSource': lead == null || lead.syncSourceRef == null
        ? null
        : {
            'code': lead.syncSourceCode,
            'name': (lead.syncSourceRef?.name ?? '').trim(),
          },
    'channel': lead?.channelName ?? '',
    'channelCode': lead?.channelCode ?? '',
    'isExistingProduct': proposalIntakeIsExistingBuilt(form),
    'existingBuilt': proposalIntakeIsExistingBuilt(form) ? '是' : '否',
    'settlements': [
      for (final sku in mainSkus)
        for (final settle in proposalIntakeSkuSettlements(sku))
          {'id': settle.id, ...settle.terms.toJson()},
    ],
  };
}

/// 终审对外 JSON：有子产品时主产品进 packs、子产品进 products；无子产品时渠道产品仍进 products。
Map<String, dynamic> proposalIntakeSalesOutboundJson({
  required Map<String, dynamic> form,
  required int id,
  required String code,
  required String title,
}) {
  final hasChildren = proposalIntakeHasChildProducts(form);
  final products = hasChildren
      ? proposalIntakeChildProducts(form)
      : proposalIntakeSkuDetails(form);
  return {
    'kind': 'sales',
    'id': id,
    'code': code,
    'title': title,
    'isCouponPack': hasChildren,
    'isExistingProduct': proposalIntakeIsExistingBuilt(form),
    'products': [
      for (final sku in products) proposalIntakeSkuOutboundJson(sku),
    ],
    'packs': hasChildren
        ? [proposalIntakeMainProductPackJson(form)]
        : <Map<String, dynamic>>[],
  };
}
