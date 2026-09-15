import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

class ImUserStatusDef {
  const ImUserStatusDef({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String key;
  final String label;
  final IconData icon;
  final Color color;
}

abstract final class ImUserStatusCatalog {
  static const String online = 'online';
  static const String busy = 'busy';
  static const String dnd = 'dnd';
  static const String meeting = 'meeting';
  static const String trip = 'trip';
  static const String rest = 'rest';
  static const String leave = 'leave';

  static const List<ImUserStatusDef> all = <ImUserStatusDef>[
    ImUserStatusDef(
      key: busy,
      label: '忙碌',
      icon: Icons.access_time_rounded,
      color: Color(0xFFE67E22),
    ),
    ImUserStatusDef(
      key: dnd,
      label: '勿扰',
      icon: Icons.do_not_disturb_on_outlined,
      color: Color(0xFFE25555),
    ),
    ImUserStatusDef(
      key: meeting,
      label: '会议中',
      icon: Icons.videocam_outlined,
      color: Color(0xFF3B82F6),
    ),
    ImUserStatusDef(
      key: trip,
      label: '出差中',
      icon: Icons.flight_outlined,
      color: Color(0xFF0D9488),
    ),
    ImUserStatusDef(
      key: rest,
      label: '休息中',
      icon: Icons.nightlight_round,
      color: Color(0xFF7B5CD8),
    ),
    ImUserStatusDef(
      key: leave,
      label: '请假中',
      icon: Icons.beach_access_outlined,
      color: Color(0xFFCA8A04),
    ),
  ];

  static final Map<String, ImUserStatusDef> _byKey = <String, ImUserStatusDef>{
    for (final item in all) item.key: item,
  };

  static const ImUserStatusDef unset = ImUserStatusDef(
    key: online,
    label: '设置状态',
    icon: Icons.sentiment_satisfied_alt_outlined,
    color: Color(0xFF6B7280),
  );

  static String normalize(String? raw) {
    final key = (raw ?? '').trim().toLowerCase();
    if (key.isEmpty || key == online) return online;
    return _byKey.containsKey(key) ? key : online;
  }

  static ImUserStatusDef of(String? raw) {
    final key = normalize(raw);
    if (key == online) return unset;
    return _byKey[key] ?? unset;
  }

  static bool showsBadge(String? raw) {
    final key = normalize(raw);
    return key != online;
  }
}

class ImStatusBadge extends StatelessWidget {
  const ImStatusBadge({super.key, required this.status, this.compact = true});

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!ImUserStatusCatalog.showsBadge(status)) {
      return const SizedBox.shrink();
    }
    final def = ImUserStatusCatalog.of(status);
    final iconSize = compact ? 12.0 : 14.0;
    final fontSize = compact ? 11.0 : 12.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(def.icon, size: iconSize, color: def.color),
        const SizedBox(width: 3),
        Text(
          def.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DunesTypography.sans(
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            color: def.color,
          ),
        ),
      ],
    );
  }
}
