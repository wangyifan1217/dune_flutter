import 'package:dunes_app/features/xflow/approval_list_cache.dart';
import 'package:dunes_app/features/xflow/approval_list_digest.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('labeled form shows both parties, matter and amount', () {
    final lines = buildApprovalListHighlights(
      title: '陆青 · 推广费付款申请单',
      fields: [
        _field('ourSide', '我方主体'),
        _field('theirSide', '对方主体'),
        _field('reason', '申请事由'),
        _field('payAmount', '付款金额'),
        _field('files', '附件', type: 'upload'),
        _field('phone', '对方联系人'),
      ],
      form: {
        'ourSide': '上海卓悦优泰',
        'theirSide': {'name': '杭州推客网络科技有限公司'},
        'reason': '渠道投放-信息流推广费，对应8月结算',
        'payAmount': 12800,
        'files': [
          {'fileName': '合同.pdf', 'objectKey': 'a/b'},
        ],
        'phone': '王敏',
      },
    );

    expect(lines.map((line) => '${line.label}|${line.value}'), [
      '双方主体|上海卓悦优泰 · 杭州推客网络科技有限公司',
      '事由|渠道投放-信息流推广费，对应8月结算',
      '金额|¥12,800',
    ]);
  });

  test('common keys still identify a payment without field labels', () {
    final lines = buildApprovalListHighlights(
      form: {
        'ourEntityName': '上海和联盟信息技术有限公司',
        'promoterName': '杭州推客',
        'expensePurpose': '信息流补量，对应3月结算',
        'paymentAmount': '36000',
        'payeeAccount': '招商银行 5719',
      },
    );

    expect(lines.map((line) => line.label), ['双方主体', '事项', '金额']);
    expect(lines[0].value, '上海和联盟信息技术有限公司 · 杭州推客');
    expect(lines[1].value, '信息流补量，对应3月结算');
    expect(lines[2].value, '¥36,000');
  });

  test('a single party keeps its own label and title is not repeated', () {
    final lines = buildApprovalListHighlights(
      title: '推广费付款申请单',
      form: {
        'payeeName': '苏州灵辰财税咨询有限公司',
        'expensePurpose': '推广费付款申请单',
      },
    );

    expect(lines, hasLength(1));
    expect(lines.single.label, '对方主体');
    expect(lines.single.value, '苏州灵辰财税咨询有限公司');
  });

  test('returning to the list keeps the template filter and search text', () {
    const userId = 42;
    ApprovalListCache.instance.put(
      userId: userId,
      listType: 'b1',
      rows: [
        XflowProposalItem(
          id: 1,
          businessType: 'FINANCE_PROMOTION_PAYMENT',
          code: 'PP-881',
          title: '陆青 · 推广费付款申请单',
          status: 'PENDING',
          createdByName: '陆青',
          createdAt: DateTime(2026, 10, 18),
        ),
      ],
      statusFilter: 'ALL',
      searchQuery: '推客',
      templateFilter: 'finance-promotion-payment',
    );

    final snap = ApprovalListCache.instance.peek(
      userId: userId,
      listType: 'b1',
    );
    expect(snap?.searchQuery, '推客');
    expect(snap?.templateFilter, 'finance-promotion-payment');
    ApprovalListCache.instance.invalidate(userId: userId, listType: 'b1');
  });
}

XflowField _field(String key, String label, {String type = 'text'}) {
  return XflowField(
    key: key,
    type: type,
    label: label,
    placeholder: '',
    required: false,
    readonly: false,
    options: const [],
    children: const [],
    raw: const {},
  );
}
