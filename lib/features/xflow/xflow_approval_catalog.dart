import 'package:flutter/material.dart';

import 'xflow_models.dart';

/// 审批发起页的二级目录。一级分类仍以后端 category（biz / adm）为准，
/// 二级目录只负责把同一一级分类里的模板整理成可浏览的业务场景。
class XflowApprovalGroup {
  const XflowApprovalGroup({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.icon,
    required this.templateKeys,
  });

  final String id;
  final String category;
  final String title;
  final String description;
  final IconData icon;
  final List<String> templateKeys;
}

class XflowPopulatedApprovalGroup {
  const XflowPopulatedApprovalGroup({
    required this.group,
    required this.templates,
  }) : _previewCount = null,
       _previewId = null,
       _previewTitle = null;

  const XflowPopulatedApprovalGroup.preview({
    required String groupId,
    required String title,
    required int count,
  }) : group = const XflowApprovalGroup(
         id: '',
         category: '',
         title: '',
         description: '',
         icon: Icons.folder_outlined,
         templateKeys: <String>[],
       ),
       templates = const <XflowTemplateCard>[],
       _previewCount = count,
       _previewId = groupId,
       _previewTitle = title;

  final XflowApprovalGroup group;
  final List<XflowTemplateCard> templates;
  final int? _previewCount;
  final String? _previewId;
  final String? _previewTitle;

  String get id => _previewId ?? group.id;
  String get title => _previewTitle ?? group.title;
  int get count => _previewCount ?? templates.length;
}

/// 接口 `/xflow/approval-groups` 不可用时的兜底目录，与后端 V304 + V321 一致。
/// 设备租赁、电子券退款、客户赔付已停用，不再列入。
const List<XflowApprovalGroup> _xflowApprovalGroups = [
  XflowApprovalGroup(
    id: 'biz-initiative',
    category: 'biz',
    title: '业务立项',
    description: '销售方案与立项决策',
    icon: Icons.rocket_launch_outlined,
    templateKeys: ['sales-proposal'],
  ),
  XflowApprovalGroup(
    id: 'biz-contract',
    category: 'biz',
    title: '合同与采购',
    description: '合同、采购与核心成本',
    icon: Icons.handshake_outlined,
    templateKeys: [
      'contract-seal',
      'finance-business-procurement',
      'finance-core-business-cost',
    ],
  ),
  XflowApprovalGroup(
    id: 'biz-payment',
    category: 'biz',
    title: '经营付款',
    description: '保证金、预付与经营支出',
    icon: Icons.account_balance_wallet_outlined,
    templateKeys: [
      'finance-deposit',
      'finance-prepayment',
      'finance-contract-payment',
      'finance-promotion-payment',
      'finance-voucher-distribution',
    ],
  ),
  XflowApprovalGroup(
    id: 'biz-customer',
    category: 'biz',
    title: '客户与回款',
    description: '客户服务、开票与回款',
    icon: Icons.groups_outlined,
    templateKeys: [
      'finance-customer-complaint',
      'finance-invoice-request',
      'finance-receipt-request',
    ],
  ),
  XflowApprovalGroup(
    id: 'biz-expense',
    category: 'biz',
    title: '经营费用',
    description: '招待、礼品与业务差旅',
    icon: Icons.receipt_long_outlined,
    templateKeys: [
      'finance-entertainment-expense',
      'finance-gift-request',
      'finance-travel-expense',
    ],
  ),
  // 下一期电子报销拆出业务那张后挂这里；空板块不显示。
  XflowApprovalGroup(
    id: 'biz-reimbursement',
    category: 'biz',
    title: '内部费用与报销',
    description: '业务差旅报销',
    icon: Icons.luggage_outlined,
    templateKeys: ['electronic-reimbursement'],
  ),
  XflowApprovalGroup(
    id: 'biz-license',
    category: 'biz',
    title: '证照与用印',
    description: '业务资质办理',
    icon: Icons.verified_user_outlined,
    templateKeys: ['admin-business-qualification'],
  ),
  XflowApprovalGroup(
    id: 'adm-reimbursement',
    category: 'adm',
    title: '内部费用与报销',
    description: '员工报销、商旅与行政采购',
    icon: Icons.luggage_outlined,
    templateKeys: [
      'electronic-reimbursement',
      'ctrip-travel-approval',
      'finance-admin-procurement',
      'expense',
    ],
  ),
  XflowApprovalGroup(
    id: 'adm-fund',
    category: 'adm',
    title: '资金与税务',
    description: '借款、还贷、税费与开户',
    icon: Icons.account_balance_outlined,
    templateKeys: [
      'loan-request',
      'finance-loan-interest-payment',
      'finance-tax-payment',
      'admin-account-opening',
    ],
  ),
  XflowApprovalGroup(
    id: 'adm-data',
    category: 'adm',
    title: '数据治理',
    description: '财务数据申请与导出',
    icon: Icons.dataset_outlined,
    templateKeys: ['finance-data-request', 'finance-data-export'],
  ),
  XflowApprovalGroup(
    id: 'adm-license',
    category: 'adm',
    title: '证照与用印',
    description: '证照、资质与各类用印',
    icon: Icons.verified_user_outlined,
    templateKeys: [
      'seal-apply',
      'admin-qualification-use',
      'admin-contract-approval-seal',
    ],
  ),
  XflowApprovalGroup(
    id: 'adm-operation',
    category: 'adm',
    title: '行政运营',
    description: '合同借阅与行政后勤事务',
    icon: Icons.apartment_outlined,
    templateKeys: [
      'admin-contract-borrow',
      'admin-business-card',
      'admin-item-requisition',
      'admin-vehicle-use',
      'admin-overseas-rental',
      'admin-company-subsistence',
    ],
  ),
];

/// 销售提案改从「我的」进入，审批发起页不再展示。
const Set<String> _hiddenApprovalTemplateKeys = {'sales-proposal'};

bool xflowApprovalTemplateVisible(String templateKey) =>
    !_hiddenApprovalTemplateKeys.contains(templateKey);

List<XflowTemplateCard> xflowVisibleApprovalTemplates(
  List<XflowTemplateCard> templates,
) => templates
    .where((template) => xflowApprovalTemplateVisible(template.templateKey))
    .toList(growable: false);

const XflowApprovalGroup _otherApprovalGroup = XflowApprovalGroup(
  id: 'other',
  category: '',
  title: '其他',
  description: '尚未归入固定目录的审批',
  icon: Icons.more_horiz_rounded,
  templateKeys: <String>[],
);

List<String> get xflowApprovalCatalogKeys => _xflowApprovalGroups
    .expand((group) => group.templateKeys)
    .toList(growable: false);

List<XflowApprovalGroup> xflowApprovalGroupsForCategory(
  String category, {
  List<XflowApprovalGroup>? catalog,
}) => (catalog ?? _xflowApprovalGroups)
    .where((group) => group.category == category)
    .toList(growable: false);

XflowApprovalGroup xflowApprovalGroupForTemplate(
  String templateKey, {
  List<XflowApprovalGroup>? catalog,
  String? category,
}) {
  final preferred = category?.trim().toLowerCase() ?? '';
  for (final group in catalog ?? _xflowApprovalGroups) {
    if (!group.templateKeys.contains(templateKey)) continue;
    if (preferred.isEmpty || group.category == preferred) return group;
  }
  return _otherApprovalGroup;
}

List<XflowTemplateCard> xflowSearchApprovalTemplates(
  List<XflowTemplateCard> templates,
  String query, {
  List<XflowApprovalGroup>? catalog,
}) {
  final normalized = query.trim().toLowerCase();
  final visible = xflowVisibleApprovalTemplates(templates);
  if (normalized.isEmpty) return visible;
  return visible
      .where((template) {
        final groups = (catalog ?? _xflowApprovalGroups).where(
          (group) => group.templateKeys.contains(template.templateKey),
        );
        final groupText = groups
            .map((group) => '${group.title} ${group.description}')
            .join(' ');
        final text =
            '${template.title} ${template.subtitle} ${template.tagLabel} '
                    '${template.templateKey} $groupText'
                .toLowerCase();
        return text.contains(normalized);
      })
      .toList(growable: false);
}

List<XflowPopulatedApprovalGroup> xflowPopulatedApprovalGroups(
  List<XflowTemplateCard> templates, {
  required String category,
  List<XflowApprovalGroup>? catalog,
}) {
  final groups = <XflowPopulatedApprovalGroup>[];
  final knownKeys = <String>{};
  final visible = xflowVisibleApprovalTemplates(templates);

  for (final group in xflowApprovalGroupsForCategory(category, catalog: catalog)) {
    final order = <String, int>{
      for (var i = 0; i < group.templateKeys.length; i++)
        group.templateKeys[i]: i,
    };
    final rows = visible
        .where((template) => group.templateKeys.contains(template.templateKey))
        .toList();
    rows.sort(
      (a, b) => (order[a.templateKey] ?? 1 << 20).compareTo(
        order[b.templateKey] ?? 1 << 20,
      ),
    );
    if (rows.isEmpty) continue;
    knownKeys.addAll(rows.map((template) => template.templateKey));
    groups.add(XflowPopulatedApprovalGroup(group: group, templates: rows));
  }

  final otherTemplates = visible
      .where((template) => !knownKeys.contains(template.templateKey))
      .toList(growable: false);
  if (otherTemplates.isNotEmpty) {
    groups.add(
      XflowPopulatedApprovalGroup(
        group: XflowApprovalGroup(
          id: '$category-other',
          category: category,
          title: _otherApprovalGroup.title,
          description: _otherApprovalGroup.description,
          icon: _otherApprovalGroup.icon,
          templateKeys: const <String>[],
        ),
        templates: otherTemplates,
      ),
    );
  }
  return groups;
}

IconData xflowApprovalIcon(String name) {
  switch (name.trim().toLowerCase()) {
    case 'rocket':
      return Icons.rocket_launch_outlined;
    case 'handshake':
      return Icons.handshake_outlined;
    case 'wallet':
      return Icons.account_balance_wallet_outlined;
    case 'groups':
      return Icons.groups_outlined;
    case 'receipt':
      return Icons.receipt_long_outlined;
    case 'luggage':
      return Icons.luggage_outlined;
    case 'bank':
      return Icons.account_balance_outlined;
    case 'dataset':
      return Icons.dataset_outlined;
    case 'verified':
      return Icons.verified_user_outlined;
    case 'apartment':
      return Icons.apartment_outlined;
    default:
      return Icons.folder_outlined;
  }
}

XflowApprovalGroup? xflowApprovalGroupFromMap(Map<String, dynamic> json) {
  final id = (json['groupKey'] ?? '').toString().trim();
  final title = (json['title'] ?? '').toString().trim();
  final category = (json['category'] ?? '').toString().trim().toLowerCase();
  if (id.isEmpty || title.isEmpty) return null;
  if (category != 'biz' && category != 'adm') return null;
  final keys = <String>[];
  final raw = json['templateKeys'];
  if (raw is List) {
    for (final item in raw) {
      final key = item.toString().trim();
      if (key.isNotEmpty) keys.add(key);
    }
  }
  return XflowApprovalGroup(
    id: id,
    category: category,
    title: title,
    description: (json['description'] ?? '').toString(),
    icon: xflowApprovalIcon((json['icon'] ?? '').toString()),
    templateKeys: keys,
  );
}
