import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_service.dart';
import 'contact_models.dart';
import 'contact_service.dart';
import 'contacts_widgets.dart';

/// 可内嵌的通讯录多选面板（不自行 push/pop）。
class ContactMemberPickerPanel extends StatefulWidget {
  const ContactMemberPickerPanel({
    super.key,
    required this.session,
    this.title = '添加成员',
    this.excludeIds = const <int>{},
    this.initialSelected = const <int>{},
    required this.onConfirm,
    this.onCancel,
    this.showHeaderActions = true,
  });

  final AuthSession session;
  final String title;
  final Set<int> excludeIds;
  final Set<int> initialSelected;
  final ValueChanged<List<int>> onConfirm;
  final VoidCallback? onCancel;
  final bool showHeaderActions;

  @override
  State<ContactMemberPickerPanel> createState() =>
      ContactMemberPickerPanelState();
}

class ContactMemberPickerPanelState extends State<ContactMemberPickerPanel> {
  late final ContactService _contacts = ContactService(session: widget.session);
  late final ConversationService _avatarService =
      ConversationService(session: widget.session);
  final _search = TextEditingController();
  final _selected = <int>{};
  final _contactById = <int, NativeContact>{};
  bool _loading = true;
  List<NativeContact> _rows = const <NativeContact>[];
  List<NativeDepartment> _departments = const <NativeDepartment>[];

  Map<int, NativeContact> get contactById => Map<int, NativeContact>.from(_contactById);
  Set<int> get selectedIds => Set<int>.from(_selected);

  bool _isEligible(NativeContact c) {
    if (c.userId <= 0 ||
        c.userId == widget.session.userId ||
        c.enabled == false) {
      return false;
    }
    if (widget.excludeIds.contains(c.userId)) return false;
    return true;
  }

  void _rememberContacts(Iterable<NativeContact> rows) {
    for (final c in rows) {
      if (c.userId > 0) _contactById[c.userId] = c;
    }
  }

  void _rememberDepartments(List<NativeDepartment> deps) {
    for (final d in deps) {
      _rememberContacts(d.users);
      _rememberDepartments(d.children);
    }
  }

  NativeDepartment? _filterDept(NativeDepartment dep) {
    final users = dep.users.where(_isEligible).toList(growable: false);
    final children = dep.children
        .map(_filterDept)
        .whereType<NativeDepartment>()
        .toList(growable: false);
    if (users.isEmpty && children.isEmpty) return null;
    final count =
        users.length + children.fold<int>(0, (n, c) => n + c.userCount);
    return NativeDepartment(
      id: dep.id,
      name: dep.name,
      subtitle: dep.subtitle,
      userCount: count,
      expanded: true,
      users: users,
      children: children,
    );
  }

  List<NativeContact> _allSelectable() {
    final out = <NativeContact>[];
    void walk(NativeDepartment dep) {
      out.addAll(dep.users.where(_isEligible));
      for (final child in dep.children) {
        walk(child);
      }
    }

    for (final dep in _departments) {
      walk(dep);
    }
    for (final c in _rows) {
      if (_isEligible(c) && !out.any((e) => e.userId == c.userId)) {
        out.add(c);
      }
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelected.where((id) => id > 0));
    _search.addListener(() => _load(_search.text.trim()));
    _load('');
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    setState(() => _loading = true);
    try {
      final org = await _contacts.fetchOrgContacts(keyword: q);
      if (!mounted) return;
      _rememberContacts(org.searchItems);
      _rememberDepartments(org.departments);
      if (q.isNotEmpty) {
        setState(() {
          _rows = org.searchItems.where(_isEligible).toList(growable: false);
          _departments = const <NativeDepartment>[];
          _loading = false;
        });
      } else {
        setState(() {
          _departments = org.departments
              .map(_filterDept)
              .whereType<NativeDepartment>()
              .toList(growable: false);
          _rows = const <NativeContact>[];
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rows = const <NativeContact>[];
        _departments = const <NativeDepartment>[];
        _loading = false;
      });
    }
  }

  void _toggle(NativeContact c) {
    setState(() {
      if (_selected.contains(c.userId)) {
        _selected.remove(c.userId);
      } else {
        _selected.add(c.userId);
      }
    });
  }

  void selectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll(_allSelectable().map((c) => c.userId));
    });
  }

  void clearAll() => setState(() => _selected.clear());

  void confirm() => widget.onConfirm(_selected.toList());

  String _initialName(String? name) {
    final t = (name ?? '').trim();
    if (t.isEmpty) return '?';
    return String.fromCharCode(t.runes.first);
  }

  Widget _buildListBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final searching = _search.text.trim().isNotEmpty;
    if (searching) {
      if (_rows.isEmpty) {
        return const Center(
          child: Text('无匹配联系人', style: TextStyle(color: DunesColors.text3)),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _rows.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      indent: 66,
                      color: Color(0xFFF0F1F3),
                    ),
                  ContactRowTile(
                    contact: _rows[i],
                    currentUserId: widget.session.userId,
                    onOpenProfile: () {},
                    onMessage: () {},
                    avatarService: _avatarService,
                    pickMode: true,
                    selected: _selected.contains(_rows[i].userId),
                    onToggleSelect: () => _toggle(_rows[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }
    if (_departments.isEmpty) {
      return const Center(
        child: Text('暂无可添加的同事', style: TextStyle(color: DunesColors.text3)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        for (final dep in _departments)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F1F3),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: DeptBlockTile(
              department: dep,
              currentUserId: widget.session.userId,
              onOpenContact: (_) {},
              onMessageContact: (_) {},
              avatarService: _avatarService,
              pickMode: true,
              selectedUserIds: _selected,
              onToggleContact: _toggle,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIds = _selected.toList()..sort();
    return Column(
      children: [
        if (widget.showHeaderActions)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Row(
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text(
                    '取消',
                    style: TextStyle(fontSize: 16, color: DunesColors.text2),
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: selectAll,
                  child: const Text('全选', style: TextStyle(fontSize: 14)),
                ),
                TextButton(
                  onPressed: () => widget.onConfirm(_selected.toList()),
                  child: Text(
                    _selected.isEmpty ? '完成' : '完成（${_selected.length}）',
                    style: const TextStyle(
                      fontSize: 16,
                      color: _driveAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (selectedIds.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            color: Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final id in selectedIds)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () => setState(() => _selected.remove(id)),
                        child: Column(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ImUserAvatar(
                                  initial: _initialName(
                                    _contactById[id]?.displayName,
                                  ),
                                  seed: id,
                                  size: 40,
                                  avatarPreset: _contactById[id]?.avatarPreset,
                                  avatarObjectKey:
                                      _contactById[id]?.avatarObjectKey,
                                  avatarService: _avatarService,
                                ),
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF9CA3AF),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 48,
                              child: Text(
                                _contactById[id]?.displayName ?? '$id',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: DunesColors.text3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: '搜索姓名 / 部门',
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFEDEEF1),
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(child: _buildListBody()),
      ],
    );
  }
}

const _driveAccent = Color(0xFF3B82F6);

/// 全页包装（兼容旧调用）。
class ContactMemberPickerPage extends StatelessWidget {
  const ContactMemberPickerPage({
    super.key,
    required this.session,
    this.title = '选择成员',
    this.excludeIds = const <int>{},
    this.initialSelected = const <int>{},
  });

  final AuthSession session;
  final String title;
  final Set<int> excludeIds;
  final Set<int> initialSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: DunesColors.text,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: ContactMemberPickerPanel(
        session: session,
        excludeIds: excludeIds,
        initialSelected: initialSelected,
        onCancel: () => Navigator.pop(context),
        onConfirm: (ids) => Navigator.pop(context, ids),
      ),
    );
  }
}
