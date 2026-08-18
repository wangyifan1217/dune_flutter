import 'package:dunes_app/features/reconciliation/reconciliation_shucai_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconReviewStats counts confirmed rejected and pending', () {
    const report = ShucaiReport(
      columns: [],
      rows: [
        {'rowKey': 'p1', 'provinceName': '天津'},
        {'rowKey': 'p2', 'provinceName': '山西'},
        {'rowKey': 'p3', 'provinceName': '内蒙古'},
        {'rowKey': '__TOTAL__', 'detailName': '合计'},
      ],
      tab: 'tag2',
    );
    final previous = <String, List<ReconRowReviewer>>{
      reconRowDecisionId('tag2', 'p1'): const [
        ReconRowReviewer(
          userName: '张三',
          tab: 'tag2',
          rowKey: 'p1',
          roleLabel: '财务',
          chainStep: 'FINANCE',
          decision: 'CONFIRM',
        ),
      ],
      'p2': const [
        ReconRowReviewer(
          userName: '李四',
          tab: 'tag2',
          rowKey: 'p2',
          roleLabel: '一层',
          chainStep: 'L1',
          decision: 'REJECT',
        ),
      ],
    };

    final stats = reconReviewStats(
      report: report,
      tab: 'tag2',
      previous: previous,
    );
    expect(stats.total, 3);
    expect(stats.confirmed, 1);
    expect(stats.rejected, 1);
    expect(stats.pending, 1);
  });

  test('L2 is a confirmer, Final is view-only', () {
    const l2 = ReconCardStatus(
      cardType: 'CNPC',
      asOfDate: '2026-08-13',
      myRole: 'L2',
      canConfirm: true,
    );
    expect(l2.viewerOnly, isFalse);
    expect(l2.confirmed, isFalse);

    const l2Done = ReconCardStatus(
      cardType: 'CNPC',
      asOfDate: '2026-08-13',
      myRole: 'ENERGY_L2',
      canConfirm: true,
      mine: ReconPerson(userId: 1, userName: '王二'),
    );
    expect(l2Done.viewerOnly, isFalse);
    expect(l2Done.confirmed, isTrue);

    const finalUser = ReconCardStatus(
      cardType: 'CNPC',
      asOfDate: '2026-08-13',
      myRole: 'FINAL',
      canConfirm: false,
    );
    expect(finalUser.viewerOnly, isTrue);
    expect(finalUser.confirmed, isFalse);
  });

  test('shucaiRowDisplayName prefers group detail third', () {
    expect(
      shucaiRowDisplayName({
        'groupName': '产险',
        'detailName': '湖南中石油',
      }),
      '产险 · 湖南中石油',
    );
    expect(
      shucaiRowDisplayName({'provinceName': '广东省'}),
      '广东省',
    );
  });

  test('shucaiMarkdownFromDisplayTable builds GFM', () {
    final md = shucaiMarkdownFromDisplayTable({
      'title': '数财一体-标签二（截止日期 2026-08-17）',
      'columns': ['省份', '期末预付款余额'],
      'rows': [
        ['中油BP', '-31,546,600'],
        ['全国', '0'],
      ],
    });
    expect(md, contains('## 数财一体-标签二（截止日期 2026-08-17）'));
    expect(md, contains('| 省份 | 期末预付款余额 |'));
    expect(md, contains('| 中油BP | -31,546,600 |'));
  });

  test('reviewers are grouped by layer and latest prefers L2', () {
    expect(reconChainStepFromRole('ENERGY_L1'), reconChainL1);
    expect(reconChainStepFromRole('TAG3_FINANCE'), reconChainFinance);
    expect(reconChainStepFromRole('OPERATOR_L2'), reconChainL2);
    expect(reconChainStepFromRole('', roleLabel: '一层'), reconChainL1);

    final previous = <String, List<ReconRowReviewer>>{};
    reconIndexRowReviewer(
      previous,
      const ReconRowReviewer(
        userName: '一层人',
        tab: 'tag2',
        rowKey: 'p1',
        role: 'L1',
        chainStep: 'L1',
        decision: 'CONFIRM',
      ),
    );
    reconIndexRowReviewer(
      previous,
      const ReconRowReviewer(
        userName: '财务人',
        tab: 'tag2',
        rowKey: 'p1',
        role: 'FINANCE',
        chainStep: 'FINANCE',
        decision: 'REJECT',
      ),
    );
    final reviewers = reconReviewersForRow(
      previous: previous,
      tab: 'tag2',
      rowKey: 'p1',
    );
    expect(reviewers.length, 2);
    expect(reconReviewerForLayer(reviewers, reconChainL1)?.userName, '一层人');
    expect(reconLatestReviewer(reviewers)?.userName, '财务人');
    expect(reconLatestReviewer(reviewers)?.rejected, isTrue);
  });

  test('card ack fills empty L2 column and mine merges into own layer', () {
    final withAck = reconReviewersWithCardAcks(
      reviewers: const [
        ReconRowReviewer(
          userName: '一层人',
          chainStep: 'L1',
          decision: 'CONFIRM',
        ),
      ],
      acks: const [
        ReconPerson(userId: 9, userName: '二层人', role: 'L2'),
      ],
    );
    expect(reconReviewerForLayer(withAck, reconChainL2)?.userName, '二层人');
    expect(reconReviewerForLayer(withAck, reconChainL2)?.confirmed, isTrue);

    final merged = reconMergeMineReviewers(
      previous: const {},
      mine: const [
        ReconRowDecision(tab: 'tag2', rowKey: 'p1', decision: 'CONFIRM'),
      ],
      myRole: 'L1',
      userName: '我',
      userId: 3,
    );
    expect(
      reconReviewerForLayer(
        reconReviewersForRow(previous: merged, tab: 'tag2', rowKey: 'p1'),
        reconChainL1,
      )?.userName,
      '我',
    );
  });

  test('reconMergeMineReviewers keeps existing avatar', () {
    final previous = <String, List<ReconRowReviewer>>{};
    reconIndexRowReviewer(
      previous,
      const ReconRowReviewer(
        userName: '王奕凡',
        tab: 'tag2',
        rowKey: 'p1',
        role: 'L1',
        chainStep: 'L1',
        decision: 'CONFIRM',
        userId: 3,
        avatarPreset: 'cat',
        avatarObjectKey: '3/photo.jpg',
      ),
    );
    final merged = reconMergeMineReviewers(
      previous: previous,
      mine: const [
        ReconRowDecision(tab: 'tag2', rowKey: 'p1', decision: 'CONFIRM'),
      ],
      myRole: 'L1',
      userName: '王奕凡',
      userId: 3,
    );
    final mine = reconReviewerForLayer(
      reconReviewersForRow(previous: merged, tab: 'tag2', rowKey: 'p1'),
      reconChainL1,
    );
    expect(mine?.avatarPreset, 'cat');
    expect(mine?.avatarObjectKey, '3/photo.jpg');
  });

  test('overview chip uses current user confirmation', () {
    expect(
      reconOverviewMineChip(teamConfirmed: true).label,
      '已确认',
    );
    expect(
      reconOverviewMineChip(
        status: const ReconCardStatus(
          cardType: 'CNPC',
          asOfDate: '2026-08-17',
          myRole: 'L1',
          canConfirm: true,
          mine: ReconPerson(userId: 3, userName: '王奕凡'),
        ),
      ).label,
      '你已确认',
    );
    expect(
      reconOverviewMineChip(
        status: const ReconCardStatus(
          cardType: 'ENERGY',
          asOfDate: '2026-08-17',
          myRole: 'L1',
          canConfirm: true,
        ),
      ).label,
      '待你确认',
    );
    expect(
      reconOverviewMineChip(
        status: const ReconCardStatus(
          cardType: 'CNPC',
          asOfDate: '2026-08-17',
          myRole: 'FINAL',
          canConfirm: false,
        ),
      ).label,
      '仅查阅',
    );
  });

  test('everyone status lists confirmers by sector and layer', () {
    final sectors = reconEveryonePeopleStatus({
      'CNPC': const ReconCardStatus(
        cardType: 'CNPC',
        asOfDate: '2026-08-17',
        myRole: 'FINAL',
        expected: [
          ReconPerson(userId: 1, userName: '一层甲', role: 'L1'),
          ReconPerson(userId: 2, userName: '财务乙', role: 'TAG2_FINANCE'),
          ReconPerson(userId: 3, userName: '二层丙', role: 'L2'),
        ],
        acks: [
          ReconPerson(
            userId: 1,
            userName: '一层甲',
            role: 'L1',
            confirmedAt: '2026-08-18T10:00:00Z',
          ),
        ],
      ),
    });
    expect(sectors.map((e) => e.sector).toList(), reconSectorTypes);
    final cnpc = sectors.firstWhere((e) => e.sector == 'CNPC');
    expect(cnpc.people.length, 3);
    expect(cnpc.confirmedCount, 1);
    expect(cnpc.people.map((e) => e.step).toList(), ['L1', 'FINANCE', 'L2']);
    expect(cnpc.people.first.confirmed, isTrue);
    expect(cnpc.people.last.confirmed, isFalse);
    expect(sectors.firstWhere((e) => e.sector == 'ENERGY').people, isEmpty);
  });

  test('visible audit steps hide later layers', () {
    expect(reconVisibleAuditSteps('L1'), [reconChainL1]);
    expect(reconVisibleAuditSteps('TAG3_FINANCE'), [
      reconChainL1,
      reconChainFinance,
    ]);
    expect(reconVisibleAuditSteps('L2'), reconAuditChainSteps);
    expect(reconVisibleAuditSteps('FINAL'), reconAuditChainSteps);
    expect(
      reconFilterReviewersForSteps(
        const [
          ReconRowReviewer(userName: '一层', chainStep: 'L1', decision: 'CONFIRM'),
          ReconRowReviewer(
            userName: '财务',
            chainStep: 'FINANCE',
            decision: 'CONFIRM',
          ),
        ],
        reconVisibleAuditSteps('L1'),
      ).map((e) => e.userName),
      ['一层'],
    );
  });

  test('reconMineRowStats counts current user progress', () {
    const report = ShucaiReport(
      columns: [],
      rows: [
        {'rowKey': 'p1', 'provinceName': '天津'},
        {'rowKey': 'p2', 'provinceName': '山西'},
        {'rowKey': 'p3', 'provinceName': '内蒙古'},
      ],
      tab: 'tag2',
    );
    final stats = reconMineRowStats(
      reports: const [report],
      decisions: {
        reconRowDecisionId('tag2', 'p1'): const ReconRowDecision(
          tab: 'tag2',
          rowKey: 'p1',
          decision: 'CONFIRM',
        ),
        'p2': const ReconRowDecision(
          tab: 'tag2',
          rowKey: 'p2',
          decision: 'REJECT',
        ),
      },
    );
    expect(stats.total, 3);
    expect(stats.done, 2);
    expect(stats.rejected, 1);
    expect(stats.pending, 1);
  });
}
