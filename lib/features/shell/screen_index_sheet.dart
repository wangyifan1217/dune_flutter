import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/navigation/generated/screen_registry.dart';
import '../../core/theme/dunes_theme.dart';

/// 原生实现的「全部 76 屏」索引，与 HTML overlay / rail 对应。
class ScreenIndexSheet extends StatelessWidget {
  const ScreenIndexSheet({
    super.key,
    required this.onSelect,
  });

  final ValueChanged<String> onSelect;

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onSelect,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DunesColors.bgApp,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ScreenIndexSheet(onSelect: onSelect),
    );
  }

  static const _groups = <_Group>[
    _Group('主 Tab', DunesRegion.lh, ['C1', 'QJ', 'LH', 'B2', 'W1', 'W2', 'W3']),
    _Group('通讯模块', DunesRegion.lh, [
      'C4', 'C2', 'C5', 'C6', 'C7', 'C8', 'C9', 'C3', 'Z2',
      'C10', 'C11', 'C12', 'C13', 'MM', 'MM0', 'MM-L',
    ]),
    _Group('知识库', DunesRegion.biz, ['K1', 'K3', 'K2']),
    _Group('审批 / 发起', DunesRegion.biz, [
      'B1', 'B3', 'P0', 'B4', 'B4D', 'B5', 'B6', 'B7', 'B8', 'B9',
      'B10', 'B11', 'B12', 'B13', 'B14', 'R1', 'P1', 'R2', 'PY1', 'PY2',
    ]),
    _Group('非业务审批', DunesRegion.adm, [
      'A1', 'E1', 'E2', 'E3', 'E4', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8',
      'A8A', 'A8F', 'E5', 'E6', 'E7', 'E8', 'M1', 'M2', 'M3', 'M4',
      'PH1', 'PH2', 'PH3', 'PH4', 'PH5',
    ]),
    _Group('其他页面', DunesRegion.bridge, ['Z1', 'Z3', 'Z4']),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (_, scroll) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '全部页面',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: DunesColors.text,
                              ),
                        ),
                        Text(
                          '${kDunesScreens.length} SCREENS · 与 HTML 索引一致',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: DunesColors.borderSoft),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
                children: [
                  for (final g in _groups) ...[
                    _GroupHeader(title: g.title, region: g.region),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in g.ids)
                          if (dunesScreenById(id) != null)
                            _ScreenChip(
                              info: dunesScreenById(id)!,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onSelect(id);
                                Navigator.pop(context);
                              },
                            ),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Group {
  const _Group(this.title, this.region, this.ids);
  final String title;
  final DunesRegion region;
  final List<String> ids;
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.region});
  final String title;
  final DunesRegion region;

  Color get _tagColor => switch (region) {
        DunesRegion.adm => DunesColors.amber,
        DunesRegion.biz => DunesColors.blue,
        DunesRegion.bridge => DunesColors.coral,
        _ => DunesColors.accent,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _tagColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _tagColor,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenChip extends StatelessWidget {
  const _ScreenChip({required this.info, required this.onTap});
  final DunesScreenInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DunesColors.bgSoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: (MediaQuery.sizeOf(context).width - 48) / 2,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DunesColors.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.id,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: DunesColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                info.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: DunesColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
