import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

class WorkProfileFilterBar extends StatelessWidget {
  const WorkProfileFilterBar({
    super.key,
    required this.selected,
    required this.items,
    required this.onChanged,
  });

  final String selected;
  final List<(String, String)> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in items) ...[
            _FilterPill(
              id: item.$1,
              label: item.$2,
              selected: selected == item.$1,
              onTap: () => onChanged(item.$1),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class WorkProfileSelectField extends StatelessWidget {
  const WorkProfileSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon = Icons.apartment_rounded,
  });

  final String label;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final selected = options.where((item) => item.$1 == value);
    final display = selected.isEmpty ? '请选择' : selected.first.$2;
    return PopupMenuButton<String>(
      tooltip: label,
      offset: const Offset(0, 8),
      color: Colors.white,
      elevation: 8,
      shadowColor: const Color(0x33543675),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<String>(
            value: option.$1,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.$2,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: option.$1 == value
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: option.$1 == value
                          ? const Color(0xFF6B46A8)
                          : const Color(0xFF342740),
                    ),
                  ),
                ),
                if (option.$1 == value)
                  const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Color(0xFF7651B8),
                  ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6DCF0)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFF4ECFA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: const Color(0xFF7651B8)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF817589),
                    ),
                  ),
                  Text(
                    display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF342740),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF9A7FB8),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkProfileGhostButton extends StatelessWidget {
  const WorkProfileGhostButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF6F0FC),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE6DCF0)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF7651B8)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5A3D86),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFF6F0FC) : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        key: Key('work-profile-filter-$id'),
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? const Color(0xFFD2BBE8)
                  : const Color(0xFFE6DCF0),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected
                  ? const Color(0xFF6B46A8)
                  : const Color(0xFF5D536B),
            ),
          ),
        ),
      ),
    );
  }
}
