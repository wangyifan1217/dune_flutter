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

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }
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
      rollbackOptions: _strings(finance['rollbackOptions']),
      // 金额口径为元。旧配置若仍是「万元」整数，这里一并换算。
      ratingS: _yuan(_number(rules['ratingS'], 50000000)),
      ratingA: _yuan(_number(rules['ratingA'], 20000000)),
      ratingB: _yuan(_number(rules['ratingB'], 5000000)),
      minimumScale: _yuan(_number(rules['minimumScale'], 5000000)),
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

List<String> _strings(Object? value) => _list(value)
    .map((item) => '$item'.trim())
    .where((item) => item.isNotEmpty)
    .toList(growable: false);

double _number(Object? value, double fallback) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

double _yuan(double value) =>
    value > 0 && value < 10000 ? value * 10000 : value;

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

  final patch = <String, dynamic>{
    '${prefix}ContractId': detail['id'],
  };
  for (final key in proposalIntakeContractFillKeys(prefix)) {
    patch[key] = '';
  }
  _putField(patch, '${prefix}No', pick(['${prefix}No', 'contractNo']));
  _putField(patch, '${prefix}Name', pick(['${prefix}Name', 'contractName']));
  _putField(
    patch,
    '${prefix}SignDate',
    pick(['${prefix}SignDate', 'signDate']),
  );
  _putField(
    patch,
    '${prefix}OurParty',
    pick(['${prefix}OurParty', 'partyA']),
  );
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
    _putField(
      patch,
      'channelReceiveAccount',
      pick(['channelReceiveAccount']),
    );
  }
  return patch;
}

String proposalIntakeActionLabel(String action) {
  return switch (action) {
    'fill_tech' => '待填写科技',
    'start_review' => '待开始复核',
    'review_market' => '待复核市场部',
    'review_tech' => '待复核科技',
    'review_finance' => '待复核财务',
    'review_finance_module' => '待整板块复核财务',
    'review_contract' => '待审核合同',
    'submit_president' => '待最终提交',
    'president_confirm' => '待总裁确认',
    'revise' => '总裁已驳回请修改',
    _ => '',
  };
}

String proposalIntakeStatusLabel(String status) {
  return switch (status) {
    'done' => '已完成',
    'pending_president' => '待总裁确认',
    'reviewing' => '复核中',
    'filling' => '填写中',
    _ => '草稿',
  };
}
