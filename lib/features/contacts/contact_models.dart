import '../conversation/im_user_status.dart';

class NativeContact {
  const NativeContact({
    required this.userId,
    required this.displayName,
    this.phone,
    this.department,
    this.title,
    this.roleLabel,
    this.roleCodes = const <String>[],
    this.enabled = true,
    this.avatarPreset,
    this.avatarObjectKey,
    this.imStatus = '',
    this.imStatusText = '',
    this.imStatusIcon = '',
    this.imStatusColor = '',
  });

  final int userId;
  final String displayName;
  final String? phone;
  final String? department;
  final String? title;
  final String? roleLabel;
  final List<String> roleCodes;
  final bool enabled;
  final String? avatarPreset;
  final String? avatarObjectKey;
  final String imStatus;
  final String imStatusText;
  final String imStatusIcon;
  final String imStatusColor;

  ImUserStatusValue get statusValue => ImUserStatusCatalog.parse(
        status: imStatus,
        text: imStatusText,
        icon: imStatusIcon,
        color: imStatusColor,
      );

  NativeContact copyWith({
    int? userId,
    String? displayName,
    String? phone,
    String? department,
    String? title,
    String? roleLabel,
    List<String>? roleCodes,
    bool? enabled,
    String? avatarPreset,
    String? avatarObjectKey,
    String? imStatus,
    String? imStatusText,
    String? imStatusIcon,
    String? imStatusColor,
  }) {
    return NativeContact(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      phone: phone ?? this.phone,
      department: department ?? this.department,
      title: title ?? this.title,
      roleLabel: roleLabel ?? this.roleLabel,
      roleCodes: roleCodes ?? this.roleCodes,
      enabled: enabled ?? this.enabled,
      avatarPreset: avatarPreset ?? this.avatarPreset,
      avatarObjectKey: avatarObjectKey ?? this.avatarObjectKey,
      imStatus: imStatus ?? this.imStatus,
      imStatusText: imStatusText ?? this.imStatusText,
      imStatusIcon: imStatusIcon ?? this.imStatusIcon,
      imStatusColor: imStatusColor ?? this.imStatusColor,
    );
  }

  String get displayLabel {
    if (!enabled) return '$displayName-停用';
    return displayName;
  }

  String get primaryRole {
    if ((title ?? '').trim().isNotEmpty) return title!.trim();
    if (roleCodes.isNotEmpty) return roleCodes.first;
    if ((roleLabel ?? '').trim().isNotEmpty) return roleLabel!.trim();
    return '';
  }
}

class NativeDepartment {
  const NativeDepartment({
    required this.id,
    required this.name,
    this.subtitle,
    required this.userCount,
    this.expanded = true,
    this.users = const <NativeContact>[],
    this.children = const <NativeDepartment>[],
  });

  final int id;
  final String name;
  final String? subtitle;
  final int userCount;
  final bool expanded;
  final List<NativeContact> users;
  final List<NativeDepartment> children;
}

class ContactOrgData {
  const ContactOrgData({
    required this.total,
    required this.departments,
    required this.searchItems,
  });

  final int total;
  final List<NativeDepartment> departments;
  final List<NativeContact> searchItems;
}
