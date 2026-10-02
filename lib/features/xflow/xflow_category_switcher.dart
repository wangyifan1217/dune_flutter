import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'xflow_approval_catalog.dart';

/// 灯塔同款紫色基底：浅紫底 + 墨紫选中，矩形语言，不用胶囊。
abstract final class XflowApprovalPalette {
  static const accent = DunesColors.brandPurple;
  static const accentDeep = DunesColors.brandPurpleDeep;
  static const soft = DunesColors.brandPurpleSoft;
  static const line = Color(0xFFE6DFF5);
  static const page = Color(0xFFF8F6FD);
}

class XflowApprovalCategorySwitcher extends StatelessWidget {
  const XflowApprovalCategorySwitcher({
    super.key,
    required this.selectedCategory,
    required this.businessCount,
    required this.administrationCount,
    required this.onChanged,
  });

  final String selectedCategory;
  final int businessCount;
  final int administrationCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isAdm = selectedCategory == 'adm';
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          XflowApprovalPalette.soft,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            XflowApprovalPalette.line,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _XflowCategoryTab(
              category: 'biz',
              title: '业务审批',
              count: businessCount,
              selected: !isAdm,
              onTap: () => onChanged('biz'),
            ),
          ),
          Expanded(
            child: _XflowCategoryTab(
              category: 'adm',
              title: '非业务审批',
              count: administrationCount,
              selected: isAdm,
              onTap: () => onChanged('adm'),
            ),
          ),
        ],
      ),
    );
  }
}

class _XflowCategoryTab extends StatelessWidget {
  const _XflowCategoryTab({
    required this.category,
    required this.title,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String category;
  final String title;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$title，$count项',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('xflow-category-$category'),
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      DunesColors.resolve(context, XflowApprovalPalette.accent),
                      DunesColors.resolve(
                        context,
                        XflowApprovalPalette.accentDeep,
                      ),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(7),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: XflowApprovalPalette.accent.withValues(alpha: .28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? DunesColors.resolve(context, Colors.white)
                      : DunesColors.resolve(context, DunesColors.text2),
                  context: context,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: DunesTypography.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? DunesColors.resolve(
                          context,
                          Colors.white,
                        ).withValues(alpha: .82)
                      : DunesColors.resolve(context, DunesColors.text3),
                  context: context,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 场景标签栏：紫色下划线 + 底部发丝线，参考灯塔「产品 / 供给方 / 渠道」。
class XflowApprovalGroupRail extends StatelessWidget {
  const XflowApprovalGroupRail({
    super.key,
    required this.groups,
    required this.selectedGroupId,
    required this.isAdm,
    required this.onChanged,
  });

  final List<XflowPopulatedApprovalGroup> groups;
  final String selectedGroupId;
  final bool isAdm;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
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
      child: Wrap(
        spacing: 2,
        children: [
          for (final item in groups)
            _XflowGroupTab(
              item: item,
              selected: item.id == selectedGroupId,
              onTap: () => onChanged(item.id),
            ),
        ],
      ),
    );
  }
}

class _XflowGroupTab extends StatelessWidget {
  const _XflowGroupTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final XflowPopulatedApprovalGroup item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${item.title}，${item.count}项',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('xflow-group-${item.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 9, 8, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      style: DunesTypography.sans(
                        fontSize: 12.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected
                            ? DunesColors.resolve(
                                context,
                                XflowApprovalPalette.accentDeep,
                              )
                            : DunesColors.resolve(context, DunesColors.text2),
                        context: context,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${item.count}',
                      style: DunesTypography.mono(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? DunesColors.resolve(
                                context,
                                XflowApprovalPalette.accent,
                              )
                            : DunesColors.resolve(context, DunesColors.text3),
                        context: context,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 2,
                  width: selected ? 26 : 0,
                  color: DunesColors.resolve(
                    context,
                    XflowApprovalPalette.accent,
                  ),
                ),
                const SizedBox(height: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
