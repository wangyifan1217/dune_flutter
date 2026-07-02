import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'xflow_models.dart';

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
          ? Icons.apartment_outlined
          : Icons.assignment_outlined,
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
}) {
  final enabled = <ProposalLaunchItem>[
    ...bizTemplates.where((t) => t.enabled).map(ProposalLaunchItem.fromTemplate),
    ...admTemplates.where((t) => t.enabled).map(ProposalLaunchItem.fromTemplate),
  ];
  if (enabled.isEmpty) {
    enabled.add(
      const ProposalLaunchItem(
        label: '销售提案',
        icon: Icons.assignment_outlined,
        badge: '新建',
        templateKey: 'sales-proposal',
      ),
    );
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
      color: DunesColors.bgApp,
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
              color: tappable ? DunesColors.borderSoft : const Color(0xFFEFEFEF),
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
                    child: Icon(item.icon, color: Colors.white, size: 16),
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
                      color: DunesColors.text,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
              if (badge != null && badge.isNotEmpty)
                Positioned(
                  top: 0,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: DunesColors.accentSoft,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      badge,
                      style: DunesTypography.sans(
                        fontSize: 7.5,
                        color: DunesColors.accentDeep,
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

class ProposalTemplateListTile extends StatelessWidget {
  const ProposalTemplateListTile({
    super.key,
    required this.template,
    required this.isAdm,
    required this.onTap,
  });

  final XflowTemplateCard template;
  final bool isAdm;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = isAdm ? const Color(0xFF9D5F1A) : DunesColors.accentDeep;
    final soft = isAdm ? const Color(0xFFFFF4E5) : DunesColors.accentSoft;
    final tappable = template.enabled && onTap != null;
    final subtitle = template.subtitle.trim();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: tappable ? onTap : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DunesColors.borderSoft),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isAdm ? Icons.apartment_outlined : Icons.assignment_outlined,
                  color: accent,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DunesTypography.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 11,
                          color: DunesColors.text3,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (tappable)
                const Padding(
                  padding: EdgeInsets.only(left: 4, top: 6),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: DunesColors.text3,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
