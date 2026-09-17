import 'package:characters/characters.dart';
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

class ImUserStatusValue {
  const ImUserStatusValue({
    this.key = ImUserStatusCatalog.online,
    this.text = '',
    this.icon = '',
    this.color = '',
  });

  static const online = ImUserStatusValue();

  final String key;
  final String text;
  final String icon;
  final String color;

  bool get showsBadge => ImUserStatusCatalog.showsBadge(key);

  ImUserStatusDef get def => ImUserStatusCatalog.resolve(this);

  @override
  bool operator ==(Object other) =>
      other is ImUserStatusValue &&
      other.key == key &&
      other.text == text &&
      other.icon == icon &&
      other.color == color;

  @override
  int get hashCode => Object.hash(key, text, icon, color);
}

abstract final class ImUserStatusCatalog {
  static const String online = 'online';
  static const String busy = 'busy';
  static const String dnd = 'dnd';
  static const String meeting = 'meeting';
  static const String trip = 'trip';
  static const String rest = 'rest';
  static const String leave = 'leave';
  static const String custom = 'custom';
  static const int textMaxChars = 8;

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

  static const List<String> customIcons = <String>[
    'clock',
    'ban',
    'video',
    'plane',
    'moon',
    'palm',
    'coffee',
    'book',
    'home',
    'car',
    'heart',
    'star',
    'fire',
    'music',
    'phone',
    'laptop',
    'gift',
    'meal',
    'gym',
    'game',
  ];

  static const Map<String, IconData> iconData = <String, IconData>{
    'minus': Icons.remove_circle_outline,
    'clock': Icons.access_time_rounded,
    'ban': Icons.do_not_disturb_on_outlined,
    'video': Icons.videocam_outlined,
    'plane': Icons.flight_outlined,
    'moon': Icons.nightlight_round,
    'palm': Icons.beach_access_outlined,
    'coffee': Icons.coffee_outlined,
    'book': Icons.menu_book_outlined,
    'home': Icons.home_outlined,
    'car': Icons.directions_car_outlined,
    'heart': Icons.favorite_border_rounded,
    'star': Icons.star_outline_rounded,
    'fire': Icons.local_fire_department_outlined,
    'music': Icons.music_note_outlined,
    'phone': Icons.phone_outlined,
    'laptop': Icons.laptop_outlined,
    'gift': Icons.card_giftcard_outlined,
    'meal': Icons.restaurant_outlined,
    'gym': Icons.fitness_center_outlined,
    'game': Icons.sports_esports_outlined,
  };

  static const List<String> customColors = <String>[
    '#e67e22',
    '#e25555',
    '#3b82f6',
    '#0d9488',
    '#7b5cd8',
    '#ca8a04',
    '#07a957',
    '#ec4899',
    '#6b7280',
    '#111827',
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

  static const ImUserStatusDef customDef = ImUserStatusDef(
    key: custom,
    label: '自定义',
    icon: Icons.edit_outlined,
    color: DunesColors.brandPurple,
  );

  static String normalize(String? raw) {
    final key = (raw ?? '').trim().toLowerCase();
    if (key.isEmpty || key == online) return online;
    if (key == custom) return custom;
    return _byKey.containsKey(key) ? key : online;
  }

  static String clampText(String? raw) {
    final s = (raw ?? '').replaceAll('\n', '').trim();
    if (s.characters.length <= textMaxChars) return s;
    return s.characters.take(textMaxChars).toString();
  }

  static String normalizeIcon(String? raw) {
    final key = (raw ?? '').trim().toLowerCase();
    if (key.isEmpty) return '';
    return iconData.containsKey(key) ? key : '';
  }

  static String normalizeColor(String? raw) {
    var s = (raw ?? '').trim().toLowerCase();
    if (s.isEmpty) return '';
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 3) {
      s = '${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
    }
    if (s.length != 6) return '';
    if (!RegExp(r'^[0-9a-f]{6}$').hasMatch(s)) return '';
    return '#$s';
  }

  static Color? colorOf(String? raw) {
    final hex = normalizeColor(raw);
    if (hex.isEmpty) return null;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  static ImUserStatusValue parse({
    String? status,
    String? text,
    String? icon,
    String? color,
  }) {
    final key = normalize(status);
    if (key == online) return ImUserStatusValue.online;
    final nextText = clampText(text);
    final nextIcon = normalizeIcon(icon);
    final nextColor = normalizeColor(color);
    if (key == custom && (nextText.isEmpty || nextIcon.isEmpty)) {
      return ImUserStatusValue.online;
    }
    return ImUserStatusValue(
      key: key,
      text: nextText,
      icon: nextIcon,
      color: nextColor,
    );
  }

  static ImUserStatusDef of(String? raw) {
    final key = normalize(raw);
    if (key == online) return unset;
    if (key == custom) return customDef;
    return _byKey[key] ?? unset;
  }

  static ImUserStatusDef resolve(ImUserStatusValue value) {
    final preset = of(value.key);
    if (!value.showsBadge) return preset;
    final icon = iconData[normalizeIcon(value.icon)] ?? preset.icon;
    final label = clampText(value.text);
    final color = colorOf(value.color) ?? preset.color;
    return ImUserStatusDef(
      key: preset.key,
      label: label.isNotEmpty ? label : preset.label,
      icon: icon,
      color: color,
    );
  }

  static bool showsBadge(String? raw) {
    final key = normalize(raw);
    return key != online;
  }
}

class ImStatusBadge extends StatelessWidget {
  const ImStatusBadge({
    super.key,
    required this.status,
    this.text = '',
    this.iconKey = '',
    this.color = '',
    this.compact = true,
  });

  final String status;
  final String text;
  final String iconKey;
  final String color;
  final bool compact;

  factory ImStatusBadge.fromValue(
    ImUserStatusValue value, {
    Key? key,
    bool compact = true,
  }) {
    return ImStatusBadge(
      key: key,
      status: value.key,
      text: value.text,
      iconKey: value.icon,
      color: value.color,
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = ImUserStatusCatalog.parse(
      status: status,
      text: text,
      icon: iconKey,
      color: color,
    );
    if (!value.showsBadge) {
      return const SizedBox.shrink();
    }
    final def = value.def;
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
