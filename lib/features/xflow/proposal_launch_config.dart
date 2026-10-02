import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'xflow_category_switcher.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';

enum ProposalLaunchIconTone { accent, green, blue, amber }

class ProposalLaunchItem {
  const ProposalLaunchItem({
    required this.label,
    required this.icon,
    this.tone = ProposalLaunchIconTone.accent,
    this.badge,
    this.templateKey,
    this.screenId,
    this.enabled = true,
    this.isPlaceholder = false,
  });

  final String label;
  final IconData icon;
  final ProposalLaunchIconTone tone;
  final String? badge;
  final String? templateKey;
  final String? screenId;
  final bool enabled;
  final bool isPlaceholder;

  factory ProposalLaunchItem.fromTemplate(XflowTemplateCard template) {
    return ProposalLaunchItem(
      label: template.title.trim().isEmpty ? '提案' : template.title.trim(),
      icon: template.category == 'adm'
          ? Icons.account_balance_outlined
          : Icons.business_center_outlined,
      tone: template.category == 'adm'
          ? ProposalLaunchIconTone.amber
          : ProposalLaunchIconTone.accent,
      badge: template.tagLabel.trim().isEmpty ? null : template.tagLabel.trim(),
      templateKey: template.templateKey,
      enabled: template.enabled,
    );
  }

  static const placeholder = ProposalLaunchItem(
    label: '',
    icon: Icons.widgets_outlined,
    enabled: false,
    isPlaceholder: true,
  );
}

List<ProposalLaunchItem> buildQuickLaunchItems({
  required List<XflowTemplateCard> bizTemplates,
  required List<XflowTemplateCard> admTemplates,
  int maxItems = 4,
  String defaultSalesTemplateKey = XflowService.salesTemplateKey,
}) {
  final enabled = <ProposalLaunchItem>[
    ...bizTemplates
        .where((t) => t.enabled)
        .map(ProposalLaunchItem.fromTemplate),
    ...admTemplates
        .where((t) => t.enabled)
        .map(ProposalLaunchItem.fromTemplate),
  ];
  if (enabled.isEmpty) {
    enabled.addAll([
      ProposalLaunchItem(
        label: '销售提案',
        icon: Icons.business_center_outlined,
        badge: '新建',
        templateKey: defaultSalesTemplateKey,
      ),
      const ProposalLaunchItem(
        label: '合同用印',
        icon: Icons.handshake_outlined,
        tone: ProposalLaunchIconTone.amber,
        badge: '合同',
        templateKey: 'contract-seal',
      ),
    ]);
  }

  final out = enabled.take(maxItems).toList(growable: true);
  while (out.length < maxItems) {
    out.add(ProposalLaunchItem.placeholder);
  }
  return out;
}

LinearGradient proposalLaunchGradient(ProposalLaunchIconTone tone) {
  switch (tone) {
    case ProposalLaunchIconTone.green:
      return const LinearGradient(
        colors: [Color(0xFF3DB089), Color(0xFF1F7E5E)],
      );
    case ProposalLaunchIconTone.blue:
      return const LinearGradient(
        colors: [Color(0xFF5089D9), Color(0xFF2D5DA8)],
      );
    case ProposalLaunchIconTone.amber:
      return const LinearGradient(
        colors: [Color(0xFFD08F40), Color(0xFF9D5F1A)],
      );
    case ProposalLaunchIconTone.accent:
      return const LinearGradient(
        colors: [Color(0xFF7E64BD), Color(0xFF4A3580)],
      );
  }
}

IconData xflowTemplateIcon(XflowTemplateCard template) {
  switch (template.icon.trim().toLowerCase()) {
    case 'seal':
      return Icons.approval_outlined;
    case 'contract':
      return Icons.handshake_outlined;
    case 'receipt-yuan':
      return Icons.payments_outlined;
    case 'customer-service':
      return Icons.support_agent_outlined;
    case 'plane':
      return Icons.flight_takeoff_rounded;
    case 'bank':
      return Icons.account_balance_outlined;
    case 'id-card':
      return Icons.badge_outlined;
    case 'book':
      return Icons.menu_book_outlined;
    case 'gift':
      return Icons.redeem_outlined;
    case 'home':
      return Icons.home_work_outlined;
    case 'car':
      return Icons.directions_car_outlined;
    case 'building':
      return Icons.corporate_fare_outlined;
    case 'certificate':
      return Icons.workspace_premium_outlined;
  }
  final key = template.templateKey.toLowerCase();
  if (key.contains('invoice') || key.contains('receipt')) {
    return Icons.receipt_long_outlined;
  }
  if (key.contains('data')) return Icons.dataset_outlined;
  if (key.contains('travel')) return Icons.luggage_outlined;
  if (key.contains('procurement')) return Icons.shopping_bag_outlined;
  return template.category == 'adm'
      ? Icons.apartment_outlined
      : Icons.business_center_outlined;
}

class ProposalQuickLaunchCell extends StatelessWidget {
  const ProposalQuickLaunchCell({
    super.key,
    required this.item,
    required this.onTap,
  });

  final ProposalLaunchItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (item.isPlaceholder) {
      return _placeholderCell();
    }

    final badge = item.badge?.trim();
    final tappable = item.enabled && onTap != null;

    return Material(
      color: DunesColors.resolve(
        context,
        DunesColors.bgApp,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: tappable ? onTap : null,
        child: Container(
          height: 74,
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: tappable
                  ? DunesColors.resolve(
                      context,
                      DunesColors.borderSoft,
                      role: DunesColorRole.border,
                    )
                  : DunesColors.resolve(
                      context,
                      const Color(0xFFEFEFEF),
                      role: DunesColorRole.border,
                    ),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: proposalLaunchGradient(item.tone),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x18000000),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      item.icon,
                      color: DunesColors.resolve(context, Colors.white),
                      size: 16,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: DunesTypography.sans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: DunesColors.resolve(context, DunesColors.text),
                      height: 1.15,
                      context: context,
                    ),
                  ),
                ],
              ),
              if (badge != null && badge.isNotEmpty)
                Positioned(
                  top: 0,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: DunesColors.resolve(
                        context,
                        DunesColors.accentSoft,
                        role: DunesColorRole.surface,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      badge,
                      style: DunesTypography.sans(
                        fontSize: 7.5,
                        color: DunesColors.resolve(
                          context,
                          DunesColors.accentDeep,
                        ),
                        context: context,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderCell() {
    return Container(
      height: 74,
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEFEFEF)),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFFECECEC),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.widgets_outlined,
          size: 16,
          color: DunesColors.text3.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class ProposalTemplateGroupPanel extends StatelessWidget {
  const ProposalTemplateGroupPanel({
    super.key,
    required this.title,
    required this.description,
    required this.templates,
    required this.isAdm,
    required this.onOpen,
    this.eyebrow,
    this.groupLabelFor,
  });

  final String title;
  final String description;
  final List<XflowTemplateCard> templates;
  final bool isAdm;
  final ValueChanged<XflowTemplateCard> onOpen;
  final String? eyebrow;
  final String Function(XflowTemplateCard template)? groupLabelFor;

  @override
  Widget build(BuildContext context) {
    final eyebrowText = eyebrow?.trim() ?? '';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            XflowApprovalPalette.line,
            role: DunesColorRole.border,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: XflowApprovalPalette.accentDeep.withValues(alpha: .06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: DunesColors.resolve(
                context,
                XflowApprovalPalette.soft,
                role: DunesColorRole.surface,
              ),
              border: Border(
                bottom: BorderSide(
                  color: DunesColors.resolve(
                    context,
                    XflowApprovalPalette.line,
                    role: DunesColorRole.border,
                  ),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: eyebrowText.isEmpty ? 15 : 26,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          DunesColors.resolve(
                            context,
                            XflowApprovalPalette.accent,
                            role: DunesColorRole.surface,
                          ),
                          DunesColors.resolve(
                            context,
                            XflowApprovalPalette.accentDeep,
                            role: DunesColorRole.surface,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrowText.isNotEmpty) ...[
                          Text(
                            eyebrowText,
                            style: DunesTypography.mono(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: DunesColors.resolve(
                                context,
                                XflowApprovalPalette.accent,
                              ),
                              letterSpacing: 1.1,
                              context: context,
                            ),
                          ),
                          const SizedBox(height: 3),
                        ],
                        Text(
                          title,
                          style: DunesTypography.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: DunesColors.resolve(
                              context,
                              XflowApprovalPalette.accentDeep,
                            ),
                            context: context,
                          ),
                        ),
                        if (description.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DunesTypography.sans(
                              fontSize: 11,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text2,
                              ),
                              context: context,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${templates.length}',
                    style: DunesTypography.mono(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.resolve(
                        context,
                        XflowApprovalPalette.accent,
                      ),
                      context: context,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '项',
                    style: DunesTypography.sans(
                      fontSize: 11,
                      color: DunesColors.resolve(context, DunesColors.text3),
                      context: context,
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (var index = 0; index < templates.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                indent: 49,
                endIndent: 12,
                color: DunesColors.resolve(
                  context,
                  DunesColors.borderSoft,
                  role: DunesColorRole.border,
                ),
              ),
            ProposalTemplateListTile(
              template: templates[index],
              isAdm: isAdm,
              index: index + 1,
              groupLabel: groupLabelFor?.call(templates[index]),
              onTap: templates[index].enabled
                  ? () => onOpen(templates[index])
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class ProposalTemplateListTile extends StatelessWidget {
  const ProposalTemplateListTile({
    super.key,
    required this.template,
    required this.isAdm,
    required this.onTap,
    this.index,
    this.groupLabel,
  });

  final XflowTemplateCard template;
  final bool isAdm;
  final VoidCallback? onTap;
  final int? index;
  final String? groupLabel;

  @override
  Widget build(BuildContext context) {
    final tappable = template.enabled && onTap != null;
    final subtitle = template.subtitle.trim();
    final resolvedGroup = groupLabel?.trim() ?? '';
    final tag = resolvedGroup.isNotEmpty
        ? resolvedGroup
        : template.tagLabel.trim();
    final serial = index == null ? '' : index!.toString().padLeft(2, '0');

    return Material(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      child: InkWell(
        onTap: tappable ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tappable
                      ? DunesColors.resolve(
                          context,
                          XflowApprovalPalette.soft,
                          role: DunesColorRole.surface,
                        )
                      : DunesColors.resolve(
                          context,
                          DunesColors.bgSoft,
                          role: DunesColorRole.surface,
                        ),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: tappable
                        ? DunesColors.resolve(
                            context,
                            XflowApprovalPalette.line,
                            role: DunesColorRole.border,
                          )
                        : DunesColors.resolve(
                            context,
                            DunesColors.borderSoft,
                            role: DunesColorRole.border,
                          ),
                  ),
                ),
                child: Icon(
                  xflowTemplateIcon(template),
                  color: tappable
                      ? DunesColors.resolve(
                          context,
                          XflowApprovalPalette.accentDeep,
                        )
                      : DunesColors.resolve(context, DunesColors.text3),
                  size: 15,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DunesTypography.sans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.resolve(context, DunesColors.text),
                        context: context,
                      ),
                    ),
                    if (subtitle.isNotEmpty ||
                        tag.isNotEmpty ||
                        serial.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (serial.isNotEmpty) ...[
                            Text(
                              serial,
                              style: DunesTypography.mono(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: DunesColors.resolve(
                                  context,
                                  XflowApprovalPalette.accent,
                                ).withValues(alpha: .72),
                                context: context,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 1,
                              height: 9,
                              color: DunesColors.resolve(
                                context,
                                XflowApprovalPalette.line,
                                role: DunesColorRole.surface,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              [
                                if (tag.isNotEmpty) tag,
                                if (subtitle.isNotEmpty) subtitle,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DunesTypography.sans(
                                fontSize: 11,
                                color: DunesColors.resolve(
                                  context,
                                  DunesColors.text3,
                                ),
                                height: 1.3,
                                context: context,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (tappable)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: DunesColors.resolve(
                    context,
                    XflowApprovalPalette.accent,
                  ).withValues(alpha: .55),
                )
              else
                Text(
                  '停用',
                  style: DunesTypography.sans(
                    fontSize: 11,
                    color: DunesColors.resolve(context, DunesColors.text3),
                    context: context,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
