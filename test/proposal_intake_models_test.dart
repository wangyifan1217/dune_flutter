import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:dunes_app/features/xflow/approval_chat_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('finance cost rules fall back when missing', () {
    final options = ProposalIntakeOptions.fromJson({});
    expect(options.operatingCostRules, contains('2%'));
    expect(options.businessCostRules, contains('员工提成'));
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
    expect(proposalIntakeActionLabel('revise'), '最终人已驳回请从头填写');
    expect(proposalIntakeActionLabel('revise_module'), '板块已驳回请修改');
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
    ]);
    expect(
      missingProposalReviewAssignees({
        'technologyOwnerUserId': '3',
        'marketOwner2UserId': '2',
        'marketOwner1UserId': '4',
        'financeOwner1UserId': '6',
        'financeOwner2UserId': '5',
      }),
      isEmpty,
    );
    expect(
      missingProposalReviewAssignees({
        'technologyOwnerUserId': '3',
      }, includeTech: false),
      ['市场部负责人二', '市场部负责人一', '财务部负责人一', '财务部负责人二'],
    );
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
  });
}
