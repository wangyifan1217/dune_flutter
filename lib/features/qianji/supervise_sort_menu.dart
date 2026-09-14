import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

const _themePurple = Color(0xFF7B5CD8);
const _cardBorder = Color(0xFFE8EAED);

class SuperviseSortOption {
  const SuperviseSortOption({required this.id, required this.label});

  final String id;
  final String label;
}

const kSessionSuperviseSortOptions = <SuperviseSortOption>[
  SuperviseSortOption(id: 'turns_desc', label: '消息多→少'),
  SuperviseSortOption(id: 'turns_asc', label: '消息少→多'),
  SuperviseSortOption(id: 'sessions_desc', label: '会话多→少'),
  SuperviseSortOption(id: 'name_asc', label: '按姓名'),
];

const kKbSuperviseSortOptions = <SuperviseSortOption>[
  SuperviseSortOption(id: 'docs_desc', label: '文档多→少'),
  SuperviseSortOption(id: 'docs_asc', label: '文档少→多'),
  SuperviseSortOption(id: 'uploaded_desc', label: '上传多→少'),
  SuperviseSortOption(id: 'minutes_desc', label: '纪要多→少'),
  SuperviseSortOption(id: 'name_asc', label: '按姓名'),
];

String superviseSortLabel(List<SuperviseSortOption> options, String id) {
  for (final o in options) {
    if (o.id == id) return o.label;
  }
  return options.isEmpty ? '排序' : options.first.label;
}

class SuperviseSortMenu extends StatelessWidget {
  const SuperviseSortMenu({
    super.key,
    required this.selectedId,
    required this.options,
    required this.onSelected,
  });

  final String selectedId;
  final List<SuperviseSortOption> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        highlightColor: DunesColors.brandPurpleSoft,
        hoverColor: DunesColors.brandPurpleSoft,
        splashColor: DunesColors.brandPurpleSoft.withValues(alpha: 0.5),
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: _themePurple,
          onPrimary: Colors.white,
          secondary: _themePurple,
          surface: Colors.white,
          onSurface: DunesColors.text,
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shadowColor: const Color(0x28000000),
          elevation: 8,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: DunesColors.text,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _cardBorder),
          ),
        ),
      ),
      child: PopupMenuButton<String>(
        tooltip: '排序',
        offset: const Offset(0, 8),
        padding: EdgeInsets.zero,
        onSelected: onSelected,
        itemBuilder: (ctx) => [
          for (final o in options)
            PopupMenuItem(
              value: o.id,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    child: o.id == selectedId
                        ? const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: _themePurple,
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    o.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: o.id == selectedId
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: o.id == selectedId
                          ? _themePurple
                          : DunesColors.text,
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _cardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                superviseSortLabel(options, selectedId),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: DunesColors.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
