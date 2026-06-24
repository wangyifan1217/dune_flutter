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
