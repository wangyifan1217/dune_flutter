import 'dart:convert';

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
    this.stage = '',
    this.myAction = '',
  });

  final int id;
  final String code;
  final String title;
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
  for (final item in catalog) {
    if (item.name == name && item.code.isNotEmpty) return item.code;
  }
  return name;
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
  final byName = {for (final item in catalog) item.name: item.code};
  final codes = [
    for (final name in names)
      if ((byName[name] ?? '').isNotEmpty) byName[name]!,
  ];
  final keep = <String>{
    ...names,
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
      issues.add('$label「$name」请填写结算单价/比例、结算规则、对方主体、我方主体、税率');
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
    required this.profitModes,
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
  final List<String> profitModes;
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
      profitModes: _strings(market['profitModes']),
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
    'start_review' => '待重新提交复核',
    'review_market' => '待复核市场部',
    'review_tech' => '待复核科技',
    'review_finance' => '待复核财务',
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
      platform: '${json['technologyPlatform'] ?? json['platform'] ?? ''}'.trim(),
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

Map<String, dynamic> proposalIntakeTechnologySnapshot(Map<String, dynamic> form) {
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
    for (final item in (form['technologyRecords'] is List
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

/// 复核相关负责人：没选就不能通知科技 / 提交复核。运营为可选项。
List<String> missingProposalReviewAssignees(
  Map<String, dynamic> form, {
  bool includeTech = true,
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

/// 结算条款：收入或单条成本共用。
class ProposalFinanceSettleTerms {
  const ProposalFinanceSettleTerms({
    this.settlePrice = '',
    this.settleRule = '',
    this.counterparty = '',
    this.ourParty = '',
    this.taxRate = '',
  });

  final String settlePrice;
  final String settleRule;
  final String counterparty;
  final String ourParty;
  final String taxRate;

  bool get isBlank =>
      settlePrice.isEmpty &&
      settleRule.isEmpty &&
      counterparty.isEmpty &&
      ourParty.isEmpty &&
      taxRate.isEmpty;

  bool get isComplete =>
      settlePrice.isNotEmpty &&
      settleRule.isNotEmpty &&
      counterparty.isNotEmpty &&
      ourParty.isNotEmpty &&
      taxRate.isNotEmpty;

  String get fingerprint =>
      [settlePrice, settleRule, counterparty, ourParty, taxRate].join('|');

  ProposalFinanceSettleTerms copyWith({
    String? settlePrice,
    String? settleRule,
    String? counterparty,
    String? ourParty,
    String? taxRate,
  }) => ProposalFinanceSettleTerms(
    settlePrice: settlePrice ?? this.settlePrice,
    settleRule: settleRule ?? this.settleRule,
    counterparty: counterparty ?? this.counterparty,
    ourParty: ourParty ?? this.ourParty,
    taxRate: taxRate ?? this.taxRate,
  );

  Map<String, dynamic> toJson() => {
    'settlePrice': settlePrice,
    'settleRule': settleRule,
    'counterparty': counterparty,
    'ourParty': ourParty,
    'taxRate': taxRate,
  };

  factory ProposalFinanceSettleTerms.fromJson(Object? raw) {
    if (raw is! Map) return const ProposalFinanceSettleTerms();
    String read(String key) => '${raw[key] ?? ''}'.trim();
    return ProposalFinanceSettleTerms(
      settlePrice: read('settlePrice'),
      settleRule: read('settleRule'),
      counterparty: read('counterparty'),
      ourParty: read('ourParty'),
      taxRate: read('taxRate'),
    );
  }
}

class ProposalFinanceCostLine {
  const ProposalFinanceCostLine({
    required this.id,
    this.name = '',
    this.terms = const ProposalFinanceSettleTerms(),
  });

  final String id;
  final String name;
  final ProposalFinanceSettleTerms terms;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    ...terms.toJson(),
  };

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
    this.revenue = const ProposalFinanceSettleTerms(),
    this.projectCosts = const [],
    this.businessCosts = const [],
  });

  final String id;
  final String title;
  final ProposalFinanceSettleTerms revenue;
  final List<ProposalFinanceCostLine> projectCosts;
  final List<ProposalFinanceCostLine> businessCosts;

  String get fingerprint {
    final costs = [
      for (final line in projectCosts) 'P:${line.name}:${line.terms.fingerprint}',
      for (final line in businessCosts) 'B:${line.name}:${line.terms.fingerprint}',
    ]..sort();
    return '${revenue.fingerprint}#${costs.join(';')}';
  }

  bool get hasIdentity => !revenue.isBlank;

  bool get revenueComplete => revenue.isComplete;

  bool get costsComplete {
    for (final line in [...projectCosts, ...businessCosts]) {
      if (line.name.isEmpty || !line.terms.isComplete) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
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
  final rows = proposalIntakeLaunchRows(form);
  final modules = {
    for (final item in proposalIntakeFinanceModules(form)) item.id: item,
  };
  final issues = <String>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final n = i + 1;
    if (row.province.isEmpty || row.faceValue.isEmpty) {
      issues.add('上线第$n行请填写省份和面值');
    }
    if (!row.needFinanceModule) continue;
    if (row.financeModuleId.isEmpty || modules[row.financeModuleId] == null) {
      issues.add('上线第$n行已勾选需要财务模块，请新增或关联财务模块');
      continue;
    }
    final module = modules[row.financeModuleId]!;
    if (!module.revenueComplete) {
      issues.add('财务模块「${module.title.isEmpty ? module.id : module.title}」收入条款未填完');
    }
    if (!module.costsComplete) {
      issues.add('财务模块「${module.title.isEmpty ? module.id : module.title}」成本项条款未填完');
    }
  }
  return issues;
}

List<String> proposalIntakeLaunchModuleReviewKeys(Map<String, dynamic> form) {
  final ids = <String>{};
  for (final row in proposalIntakeLaunchRows(form)) {
    if (row.needFinanceModule && row.financeModuleId.isNotEmpty) {
      ids.add(row.financeModuleId);
    }
  }
  return [for (final id in ids) 'launchModule:$id'];
}
