import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/config/dunes_defaults.dart';
import '../../core/layout/chat_layout.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/user_avatar_widget.dart';
import '../contacts/contact_member_picker_page.dart';
import '../contacts/contact_models.dart';
import '../contacts/contact_service.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import '../chat/dunes_pdf_view.dart';
import 'drive_download.dart';
import 'drive_kb.dart';
import 'native_drive_models.dart';
import 'native_drive_service.dart';

const _driveBlue = Color(0xFF3B82F6);
const _driveSheetBg = Color(0xFFF5F6F8);

/// PC 居中弹层 / 手机全页推入，统一入口。
Future<T?> showDriveSheet<T>(BuildContext context, Widget page) {
  final wide = isWideChatLayout(context) || isDesktopCommOnly;
  if (wide) {
    return showDialog<T>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: SizedBox(
          width: 480,
          height: (MediaQuery.sizeOf(ctx).height * 0.82).clamp(480.0, 720.0),
          child: Material(
            color: _driveSheetBg,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: page,
          ),
        ),
      ),
    );
  }
  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (_) => Material(color: _driveSheetBg, child: page),
    ),
  );
}

/// 兼容旧调用名。
Future<T?> pushDrivePage<T>(BuildContext context, Widget page) =>
    showDriveSheet<T>(context, page);

class DriveCreateSpaceResult {
  const DriveCreateSpaceResult({
    required this.name,
    required this.memberIds,
    this.description = '',
  });

  final String name;
  final String description;
  final List<int> memberIds;
}

/// 创建共享空间：名称 + 成员同一页完成（对齐企微列表风）。
class DriveCreateSpacePanel extends StatefulWidget {
  const DriveCreateSpacePanel({
    super.key,
    required this.session,
  });

  final AuthSession session;

  @override
  State<DriveCreateSpacePanel> createState() => _DriveCreateSpacePanelState();
}

class _DriveCreateSpacePanelState extends State<DriveCreateSpacePanel> {
  late final ContactService _contacts = ContactService(session: widget.session);
  late final ConversationService _avatarService =
      ConversationService(session: widget.session);
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _memberIds = <int>{};
  final _contactById = <int, NativeContact>{};
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _warmupContacts();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _warmupContacts() async {
    try {
      final org = await _contacts.fetchOrgContacts();
      if (!mounted) return;
      for (final c in org.searchItems) {
        if (c.userId > 0) _contactById[c.userId] = c;
      }
      void walk(NativeDepartment d) {
        for (final c in d.users) {
          if (c.userId > 0) _contactById[c.userId] = c;
        }
        for (final child in d.children) {
          walk(child);
        }
      }

      for (final d in org.departments) {
        walk(d);
      }
      setState(() {});
    } catch (_) {}
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      DriveCreateSpaceResult(
        name: name,
        description: _description.text.trim(),
        memberIds: _memberIds.toList(growable: false),
      ),
    );
  }

  String _initial(String? name) {
    final t = (name ?? '').trim();
    if (t.isEmpty) return '?';
    return String.fromCharCode(t.runes.first);
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: DunesColors.text3,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _memberRow({
    required int userId,
    required String name,
    required String role,
    String? avatarPreset,
    String? avatarObjectKey,
    VoidCallback? onRemove,
  }) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            ImUserAvatar(
              initial: _initial(name),
              seed: userId,
              size: 36,
              avatarPreset: avatarPreset,
              avatarObjectKey: avatarObjectKey,
              avatarService: _avatarService,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, color: DunesColors.text),
              ),
            ),
            Text(
              role,
              style: const TextStyle(fontSize: 14, color: DunesColors.text3),
            ),
            if (onRemove != null) ...[
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.close, size: 18, color: DunesColors.text3),
                onPressed: onRemove,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ownerName =
        (widget.session.displayName ?? '').trim().isEmpty
            ? '我'
            : widget.session.displayName!.trim();
    final canSubmit = _name.text.trim().isNotEmpty;

    if (_picking) {
      return ColoredBox(
        color: _driveSheetBg,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ContactMemberPickerPanel(
                  session: widget.session,
                  title: '添加成员',
                  excludeIds: {widget.session.userId},
                  initialSelected: _memberIds,
                  onCancel: () => setState(() => _picking = false),
                  onConfirm: (ids) {
                    setState(() {
                      _memberIds
                        ..clear()
                        ..addAll(ids.where((id) => id > 0));
                      _picking = false;
                    });
                    unawaited(_warmupContacts());
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    final memberIds = _memberIds.toList()..sort();
    return ColoredBox(
      color: _driveSheetBg,
      child: SafeArea(
        child: Column(
          children: [
            _DriveSheetHeader(
              title: '创建共享空间',
              onCancel: () => Navigator.pop(context),
              actionLabel: '完成',
              actionEnabled: canSubmit,
              onAction: _submit,
            ),
            Expanded(
              child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _sectionLabel('空间名称'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      controller: _name,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: '请输入空间名称',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: DunesColors.text3),
                      ),
                    ),
                  ),
                ),
                _sectionLabel('空间简介'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      controller: _description,
                      maxLength: 512,
                      maxLines: 3,
                      minLines: 2,
                      decoration: const InputDecoration(
                        hintText: '选填，将展示在空间列表',
                        border: InputBorder.none,
                        counterText: '',
                        hintStyle: TextStyle(color: DunesColors.text3),
                      ),
                    ),
                  ),
                ),
                _sectionLabel('成员及权限'),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    '共享空间可添加同事；「我的空间」仅自己可见、不可加人',
                    style: TextStyle(fontSize: 12, color: DunesColors.text3),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () => setState(() => _picking = true),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10),
                          ),
                          child: const SizedBox(
                            height: 56,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Row(
                                children: [
                                  _AddMemberIcon(),
                                  SizedBox(width: 12),
                                  Text(
                                    '添加成员',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: DunesColors.text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 1, indent: 62),
                        _memberRow(
                          userId: widget.session.userId,
                          name: ownerName,
                          role: '管理者',
                          avatarPreset:
                              _contactById[widget.session.userId]?.avatarPreset,
                          avatarObjectKey: _contactById[widget.session.userId]
                              ?.avatarObjectKey,
                        ),
                        for (final id in memberIds) ...[
                          const Divider(height: 1, indent: 62),
                          _memberRow(
                            userId: id,
                            name: _contactById[id]?.displayName ?? '用户$id',
                            role: '查看者',
                            avatarPreset: _contactById[id]?.avatarPreset,
                            avatarObjectKey:
                                _contactById[id]?.avatarObjectKey,
                            onRemove: () =>
                                setState(() => _memberIds.remove(id)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _AddMemberIcon extends StatelessWidget {
  const _AddMemberIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _driveBlue,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.add, color: Colors.white, size: 22),
    );
  }
}

class _DriveSheetHeader extends StatelessWidget {
  const _DriveSheetHeader({
    required this.title,
    required this.onCancel,
    this.actionLabel,
    this.actionEnabled = true,
    this.onAction,
  });

  final String title;
  final VoidCallback onCancel;
  final String? actionLabel;
  final bool actionEnabled;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Row(
        children: [
          TextButton(
            onPressed: onCancel,
            child: const Text(
              '取消',
              style: TextStyle(fontSize: 16, color: DunesColors.text2),
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: DunesColors.text,
              ),
            ),
          ),
          if (actionLabel == null)
            const SizedBox(width: 64)
          else
            TextButton(
              onPressed: actionEnabled ? onAction : null,
              child: Text(
                actionLabel!,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: actionEnabled ? _driveBlue : DunesColors.text3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 通用文本表单（列表风）。
class DriveTextFormPage extends StatefulWidget {
  const DriveTextFormPage({
    super.key,
    required this.title,
    this.hint,
    this.initial = '',
    this.confirmLabel = '完成',
    this.allowEmpty = false,
    this.sectionLabel,
  });

  final String title;
  final String? hint;
  final String initial;
  final String confirmLabel;
  final bool allowEmpty;
  final String? sectionLabel;

  @override
  State<DriveTextFormPage> createState() => _DriveTextFormPageState();
}

class _DriveTextFormPageState extends State<DriveTextFormPage> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text;
    if (!widget.allowEmpty && text.trim().isEmpty) return;
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        widget.allowEmpty || _controller.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: _driveSheetBg,
      body: SafeArea(
        child: Column(
          children: [
            _DriveSheetHeader(
              title: widget.title,
              onCancel: () => Navigator.pop(context),
              actionLabel: widget.confirmLabel,
              actionEnabled: canSubmit,
              onAction: _submit,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.sectionLabel ?? '内容',
                  style: const TextStyle(
                    fontSize: 13,
                    color: DunesColors.text3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      border: InputBorder.none,
                      hintStyle: const TextStyle(color: DunesColors.text3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DriveTrashPage extends StatefulWidget {
  const DriveTrashPage({super.key, required this.service});

  final NativeDriveService service;

  @override
  State<DriveTrashPage> createState() => _DriveTrashPageState();
}

class _DriveTrashPageState extends State<DriveTrashPage> {
  bool _loading = true;
  String? _error;
  List<DriveItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.service.fetchTrash();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _formatDeletedAt(DateTime? at) {
    if (at == null) return '保留 7 天';
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '删除于 ${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: destructive ? Colors.redAccent : _driveBlue,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _restore(DriveItem item) async {
    final ok = await _confirm(
      title: '恢复文件',
      content: '确定将「${item.name}」恢复到原位置吗？',
      confirmLabel: '恢复',
    );
    if (!ok || !mounted) return;
    try {
      await widget.service.restoreTrash(item.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      showDunesCenterToast(
        context,
        friendlyErrorText(e, fallback: '恢复失败'),
        kind: DunesToastKind.error,
      );
    }
  }

  Future<void> _purge(DriveItem item) async {
    final ok = await _confirm(
      title: '永久删除',
      content: '确定永久删除「${item.name}」吗？删除后不可恢复。',
      confirmLabel: '永久删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await widget.service.purgeTrash(item.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      showDunesCenterToast(
        context,
        friendlyErrorText(e, fallback: '删除失败'),
        kind: DunesToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: DunesColors.text,
        elevation: 0,
        title: const Text(
          '回收站',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _driveBlue))
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  TextButton(onPressed: _load, child: const Text('重试')),
                ],
              ),
            )
          : _items.isEmpty
          ? const Center(
              child: Text('回收站为空', style: TextStyle(color: DunesColors.text3)),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _items.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, indent: 56, endIndent: 16),
              itemBuilder: (context, i) {
                final item = _items[i];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        item.isFolder
                            ? Icons.folder_outlined
                            : Icons.insert_drive_file_outlined,
                        color: _driveBlue,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: DunesColors.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatDeletedAt(item.deletedAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: DunesColors.text3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: item.canManage ? 88 : 44,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              icon: const Icon(Icons.restore, size: 22),
                              tooltip: '恢复',
                              onPressed: () => unawaited(_restore(item)),
                            ),
                            if (item.canManage)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 40,
                                  minHeight: 40,
                                ),
                                icon: const Icon(
                                  Icons.delete_forever_outlined,
                                  size: 22,
                                ),
                                tooltip: '永久删除',
                                onPressed: () => unawaited(_purge(item)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class DriveMembersPage extends StatefulWidget {
  const DriveMembersPage({
    super.key,
    required this.session,
    required this.service,
    required this.space,
  });

  final AuthSession session;
  final NativeDriveService service;
  final DriveSpace space;

  @override
  State<DriveMembersPage> createState() => _DriveMembersPageState();
}

class _DriveMembersPageState extends State<DriveMembersPage> {
  late final ContactService _contacts = ContactService(session: widget.session);
  late final ConversationService _avatarService =
      ConversationService(session: widget.session);
  final _memberIds = <int>{};
  final _contactById = <int, NativeContact>{};
  bool _loading = true;
  bool _saving = false;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final members = await widget.service.fetchMembers(widget.space.id);
      final org = await _contacts.fetchOrgContacts();
      void remember(Iterable<NativeContact> rows) {
        for (final c in rows) {
          if (c.userId > 0) _contactById[c.userId] = c;
        }
      }

      void rememberDeps(List<NativeDepartment> deps) {
        for (final d in deps) {
          remember(d.users);
          rememberDeps(d.children);
        }
      }

      remember(org.searchItems);
      rememberDeps(org.departments);
      _memberIds
        ..clear()
        ..addAll(
          members
              .map((m) => int.tryParse('${m['userId']}') ?? 0)
              .where((id) => id > 0 && id != widget.session.userId),
        );
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.service.replaceMembers(
        widget.space.id,
        _memberIds
            .map((id) => <String, dynamic>{'userId': id, 'role': 'VIEWER'})
            .toList(growable: false),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _initial(String? name) {
    final t = (name ?? '').trim();
    if (t.isEmpty) return '?';
    return String.fromCharCode(t.runes.first);
  }

  @override
  Widget build(BuildContext context) {
    final ownerName = (widget.session.displayName ?? '').trim().isEmpty
        ? '我'
        : widget.session.displayName!.trim();
    final ids = _memberIds.toList()..sort();

    if (_picking) {
      return ColoredBox(
        color: _driveSheetBg,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ContactMemberPickerPanel(
                  session: widget.session,
                  title: '添加成员',
                  excludeIds: {widget.session.userId},
                  initialSelected: _memberIds,
                  onCancel: () => setState(() => _picking = false),
                  onConfirm: (picked) {
                    setState(() {
                      _memberIds
                        ..clear()
                        ..addAll(picked.where((id) => id > 0));
                      _picking = false;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: _driveSheetBg,
      child: SafeArea(
        child: Column(
          children: [
            _DriveSheetHeader(
              title: '成员及权限',
              onCancel: () => Navigator.pop(context),
              actionLabel: _saving ? '保存中' : '完成',
              actionEnabled: !_saving && !_loading,
              onAction: _save,
            ),
            if (_loading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: _driveBlue),
                ),
              )
            else
              Expanded(
                child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text(
                      '成员及权限',
                      style: TextStyle(
                        fontSize: 13,
                        color: DunesColors.text3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          InkWell(
                            onTap: () => setState(() => _picking = true),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  _AddMemberIcon(),
                                  SizedBox(width: 12),
                                  Text(
                                    '添加成员',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: DunesColors.text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 1, indent: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                ImUserAvatar(
                                  initial: _initial(ownerName),
                                  seed: widget.session.userId,
                                  size: 36,
                                  avatarPreset: _contactById[widget.session.userId]
                                      ?.avatarPreset,
                                  avatarObjectKey:
                                      _contactById[widget.session.userId]
                                          ?.avatarObjectKey,
                                  avatarService: _avatarService,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    ownerName,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                                const Text(
                                  '管理者',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: DunesColors.text3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (final id in ids) ...[
                            const Divider(height: 1, indent: 62),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  ImUserAvatar(
                                    initial: _initial(
                                      _contactById[id]?.displayName,
                                    ),
                                    seed: id,
                                    size: 36,
                                    avatarPreset:
                                        _contactById[id]?.avatarPreset,
                                    avatarObjectKey:
                                        _contactById[id]?.avatarObjectKey,
                                    avatarService: _avatarService,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _contactById[id]?.displayName ??
                                          '用户$id',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                  const Text(
                                    '查看者',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: DunesColors.text3,
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.close,
                                      size: 18,
                                      color: DunesColors.text3,
                                    ),
                                    onPressed: () => setState(
                                      () => _memberIds.remove(id),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DriveVersionsPage extends StatelessWidget {
  const DriveVersionsPage({
    super.key,
    required this.versions,
    required this.onRestore,
  });

  final List<DriveVersion> versions;
  final Future<void> Function(DriveVersion version) onRestore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: DunesColors.text,
        elevation: 0,
        title: const Text(
          '版本历史',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: versions.isEmpty
          ? const Center(child: Text('暂无版本'))
          : ListView.builder(
              itemCount: versions.length,
              itemBuilder: (context, i) {
                final version = versions[i];
                return ListTile(
                  leading: CircleAvatar(child: Text('${version.versionNo}')),
                  title: Text(version.fileName),
                  subtitle: Text(
                    '${_formatBytes(version.sizeBytes)} · ${version.createdAt ?? ''}',
                  ),
                  trailing: version.current
                      ? const Chip(label: Text('当前'))
                      : TextButton(
                          onPressed: () async {
                            await onRestore(version);
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: const Text('恢复'),
                        ),
                );
              },
            ),
    );
  }
}

class DriveMoveCopyResult {
  const DriveMoveCopyResult({
    required this.mode,
    required this.space,
    this.parentId,
  });

  final String mode; // move | copy
  final DriveSpace space;
  final int? parentId;
}

/// 移动/复制：统一微盘弹层风格，可选目标空间与文件夹。
/// 移动仅限同一空间；跨空间请用复制。
class DriveMoveCopyPage extends StatefulWidget {
  const DriveMoveCopyPage({
    super.key,
    required this.service,
    required this.spaces,
    required this.item,
    required this.sourceSpace,
  });

  final NativeDriveService service;
  final List<DriveSpace> spaces;
  final DriveItem item;
  final DriveSpace sourceSpace;

  @override
  State<DriveMoveCopyPage> createState() => _DriveMoveCopyPageState();
}

class _DriveMoveCopyPageState extends State<DriveMoveCopyPage> {
  late DriveSpace _target = widget.sourceSpace;
  final List<DriveItem> _folderStack = [];
  List<DriveItem> _folders = const [];
  bool _loading = true;
  String? _error;

  int? get _parentId =>
      _folderStack.isEmpty ? null : _folderStack.last.id;

  bool get _sameSpace => _target.id == widget.sourceSpace.id;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFolders());
  }

  Future<void> _loadFolders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.service.fetchItems(
        spaceId: _target.id,
        parentId: _parentId,
      );
      final folders = items
          .where((e) => e.isFolder && e.id != widget.item.id)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorText(e, fallback: '加载文件夹失败');
      });
    }
  }

  Future<void> _switchSpace(DriveSpace space) async {
    if (space.id == _target.id) return;
    setState(() {
      _target = space;
      _folderStack.clear();
    });
    await _loadFolders();
  }

  Future<void> _enterFolder(DriveItem folder) async {
    setState(() => _folderStack.add(folder));
    await _loadFolders();
  }

  Future<void> _goUp() async {
    if (_folderStack.isEmpty) return;
    setState(() => _folderStack.removeLast());
    await _loadFolders();
  }

  String get _locationLabel {
    if (_folderStack.isEmpty) return '根目录';
    return _folderStack.map((e) => e.name).join(' / ');
  }

  void _finish(String mode) {
    if (mode == 'move' && !_sameSpace) return;
    Navigator.pop(
      context,
      DriveMoveCopyResult(
        mode: mode,
        space: _target,
        parentId: _parentId,
      ),
    );
  }

  List<DriveSpace> get _spaceOptions {
    final writable = widget.spaces.where((s) => s.canEdit).toList();
    return writable.isEmpty ? widget.spaces : writable;
  }

  @override
  Widget build(BuildContext context) {
    final options = _spaceOptions;
    final selected = options.cast<DriveSpace?>().firstWhere(
          (s) => s?.id == _target.id,
          orElse: () => options.isEmpty ? null : options.first,
        );

    return Scaffold(
      backgroundColor: _driveSheetBg,
      body: SafeArea(
        child: Column(
          children: [
            _DriveSheetHeader(
              title: '移动或复制',
              onCancel: () => Navigator.pop(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '将「${widget.item.name}」放到',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: DunesColors.text3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<DriveSpace>(
                      isExpanded: true,
                      value: selected,
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: DunesColors.text3,
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        color: DunesColors.text,
                        fontWeight: FontWeight.w500,
                      ),
                      items: options
                          .map(
                            (space) => DropdownMenuItem(
                              value: space,
                              child: Text(
                                space.id == widget.sourceSpace.id
                                    ? '${space.name}（当前空间）'
                                    : space.name,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: options.isEmpty
                          ? null
                          : (space) {
                              if (space != null) unawaited(_switchSpace(space));
                            },
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  if (_folderStack.isNotEmpty)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () => unawaited(_goUp()),
                      icon: const Icon(
                        Icons.chevron_left_rounded,
                        color: _driveBlue,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      '当前位置：$_locationLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: DunesColors.text2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: _buildFolderBody(),
                ),
              ),
            ),
            if (!_sameSpace)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '跨空间只能复制，不能移动',
                    style: TextStyle(fontSize: 12, color: DunesColors.text3),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _finish('copy'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _driveBlue,
                        side: const BorderSide(color: _driveBlue),
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        '复制到此处',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _sameSpace ? () => _finish('move') : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: _driveBlue,
                        disabledBackgroundColor: _driveBlue.withValues(
                          alpha: 0.35,
                        ),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        '移动到此处',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: _driveBlue),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: DunesColors.text3, fontSize: 14),
          ),
        ),
      );
    }
    if (_folders.isEmpty) {
      return const Center(
        child: Text(
          '此位置暂无子文件夹\n可直接移动/复制到此处',
          textAlign: TextAlign.center,
          style: TextStyle(color: DunesColors.text3, fontSize: 14, height: 1.5),
        ),
      );
    }
    return ListView.separated(
      itemCount: _folders.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, i) {
        final folder = _folders[i];
        return ListTile(
          leading: const Icon(Icons.folder_rounded, color: _driveBlue, size: 28),
          title: Text(
            folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: DunesColors.text,
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: DunesColors.text3,
          ),
          onTap: () => unawaited(_enterFolder(folder)),
        );
      },
    );
  }
}

class DriveFolderPickResult {
  const DriveFolderPickResult({
    required this.space,
    this.parentId,
  });

  final DriveSpace space;
  final int? parentId;
}

/// 选择微盘目标位置（可写空间 + 文件夹），用于 IM 存入微盘等。
class DriveFolderPickerPage extends StatefulWidget {
  const DriveFolderPickerPage({
    super.key,
    required this.service,
    required this.spaces,
    required this.fileName,
    this.initial,
    this.confirmLabel = '存入此处',
  });

  final NativeDriveService service;
  final List<DriveSpace> spaces;
  final String fileName;
  final DriveSpace? initial;
  final String confirmLabel;

  @override
  State<DriveFolderPickerPage> createState() => _DriveFolderPickerPageState();
}

class _DriveFolderPickerPageState extends State<DriveFolderPickerPage> {
  late DriveSpace _target;
  final List<DriveItem> _folderStack = [];
  List<DriveItem> _folders = const [];
  bool _loading = true;
  String? _error;

  int? get _parentId =>
      _folderStack.isEmpty ? null : _folderStack.last.id;

  List<DriveSpace> get _spaceOptions {
    final writable = widget.spaces.where((s) => s.canEdit).toList();
    return writable.isEmpty ? widget.spaces : writable;
  }

  @override
  void initState() {
    super.initState();
    final options = _spaceOptions;
    final preferred = widget.initial;
    if (preferred != null && options.any((s) => s.id == preferred.id)) {
      _target = preferred;
    } else {
      _target = options.firstWhere(
        (s) => s.kind.toLowerCase() == 'personal',
        orElse: () => options.first,
      );
    }
    unawaited(_loadFolders());
  }

  Future<void> _loadFolders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.service.fetchItems(
        spaceId: _target.id,
        parentId: _parentId,
      );
      final folders =
          items.where((e) => e.isFolder).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorText(e, fallback: '加载文件夹失败');
      });
    }
  }

  Future<void> _switchSpace(DriveSpace space) async {
    if (space.id == _target.id) return;
    setState(() {
      _target = space;
      _folderStack.clear();
    });
    await _loadFolders();
  }

  Future<void> _enterFolder(DriveItem folder) async {
    setState(() => _folderStack.add(folder));
    await _loadFolders();
  }

  Future<void> _goUp() async {
    if (_folderStack.isEmpty) return;
    setState(() => _folderStack.removeLast());
    await _loadFolders();
  }

  String get _locationLabel {
    if (_folderStack.isEmpty) return '根目录';
    return _folderStack.map((e) => e.name).join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    final options = _spaceOptions;
    final selected = options.cast<DriveSpace?>().firstWhere(
          (s) => s?.id == _target.id,
          orElse: () => options.isEmpty ? null : options.first,
        );
    final titleName = widget.fileName.trim().isEmpty
        ? '文件'
        : widget.fileName.trim();

    return Scaffold(
      backgroundColor: _driveSheetBg,
      body: SafeArea(
        child: Column(
          children: [
            _DriveSheetHeader(
              title: '存入微盘',
              onCancel: () => Navigator.pop(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '将「$titleName」存到',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: DunesColors.text3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<DriveSpace>(
                      isExpanded: true,
                      value: selected,
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: DunesColors.text3,
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        color: DunesColors.text,
                        fontWeight: FontWeight.w500,
                      ),
                      items: options
                          .map(
                            (space) => DropdownMenuItem(
                              value: space,
                              child: Text(space.name),
                            ),
                          )
                          .toList(),
                      onChanged: options.isEmpty
                          ? null
                          : (space) {
                              if (space != null) {
                                unawaited(_switchSpace(space));
                              }
                            },
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  if (_folderStack.isNotEmpty)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () => unawaited(_goUp()),
                      icon: const Icon(
                        Icons.chevron_left_rounded,
                        color: _driveBlue,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      '当前位置：$_locationLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: DunesColors.text2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: _buildFolderBody(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selected == null
                      ? null
                      : () => Navigator.pop(
                            context,
                            DriveFolderPickResult(
                              space: selected,
                              parentId: _parentId,
                            ),
                          ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _driveBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    widget.confirmLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: _driveBlue),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: DunesColors.text3, fontSize: 14),
          ),
        ),
      );
    }
    if (_folders.isEmpty) {
      return const Center(
        child: Text(
          '此位置暂无子文件夹\n可直接存入此处',
          textAlign: TextAlign.center,
          style: TextStyle(color: DunesColors.text3, fontSize: 14, height: 1.5),
        ),
      );
    }
    return ListView.separated(
      itemCount: _folders.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, i) {
        final folder = _folders[i];
        return ListTile(
          leading: const Icon(Icons.folder_rounded, color: _driveBlue, size: 28),
          title: Text(
            folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: DunesColors.text,
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: DunesColors.text3,
          ),
          onTap: () => unawaited(_enterFolder(folder)),
        );
      },
    );
  }
}

class DriveShareCreateResult {
  const DriveShareCreateResult({
    this.password = '',
    this.expiresDays = 7,
  });

  final String password;
  final int expiresDays;
}

/// 创建分享：可选密码 + 有效天数。
class DriveShareCreatePage extends StatefulWidget {
  const DriveShareCreatePage({super.key});

  @override
  State<DriveShareCreatePage> createState() => _DriveShareCreatePageState();
}

class _DriveShareCreatePageState extends State<DriveShareCreatePage> {
  final _password = TextEditingController();
  int _expiresDays = 7;
  bool _usePassword = false;

  static const _dayOptions = <int>[1, 7, 30, 90];

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(
      context,
      DriveShareCreateResult(
        password: _usePassword ? _password.text.trim() : '',
        expiresDays: _expiresDays,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _driveSheetBg,
      body: SafeArea(
        child: Column(
          children: [
            _DriveSheetHeader(
              title: '创建分享链接',
              onCancel: () => Navigator.pop(context),
              actionLabel: '创建',
              onAction: _submit,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 12, 8, 8),
                    child: Text(
                      '有效期',
                      style: TextStyle(
                        fontSize: 13,
                        color: DunesColors.text3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final d in _dayOptions)
                            ChoiceChip(
                              label: Text('$d 天'),
                              selected: _expiresDays == d,
                              selectedColor: _driveBlue.withValues(alpha: 0.15),
                              labelStyle: TextStyle(
                                color: _expiresDays == d
                                    ? _driveBlue
                                    : DunesColors.text2,
                                fontWeight: FontWeight.w500,
                              ),
                              onSelected: (_) =>
                                  setState(() => _expiresDays = d),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 20, 8, 8),
                    child: Text(
                      '访问密码',
                      style: TextStyle(
                        fontSize: 13,
                        color: DunesColors.text3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                          ),
                          title: const Text('需要密码才能打开'),
                          value: _usePassword,
                          activeThumbColor: _driveBlue,
                          onChanged: (v) => setState(() => _usePassword = v),
                        ),
                        if (_usePassword) ...[
                          const Divider(height: 1, indent: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: TextField(
                              controller: _password,
                              obscureText: true,
                              decoration: const InputDecoration(
                                hintText: '请输入访问密码',
                                border: InputBorder.none,
                                hintStyle: TextStyle(color: DunesColors.text3),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatDriveShareExpiry(DateTime? at) {
  if (at == null) return '';
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

/// 把后端可能返回的本地/旧路径，纠正为网关公开分享地址。
String resolveDriveShareUrl(DriveShareLink link, {String apiBase = ''}) {
  final token = link.token.trim();
  final raw = link.url.trim();
  final base = apiBase.trim().isNotEmpty
      ? apiBase.trim()
      : DunesDefaults.apiBase;
  // apiBase = http://host:6090/api/v1
  final root = base.replaceAll(RegExp(r'/api/v1/?$'), '');
  if (token.isNotEmpty) {
    return '$root/api/v1/public/drive/$token';
  }
  if (raw.contains('/api/v1/public/drive/')) return raw;
  final m = RegExp(r'/share/drive/([^/?#]+)').firstMatch(raw);
  if (m != null) {
    return '$root/api/v1/public/drive/${m.group(1)}';
  }
  return raw;
}

class DriveShareResultPage extends StatelessWidget {
  const DriveShareResultPage({
    super.key,
    required this.link,
    this.apiBase = '',
  });

  final DriveShareLink link;
  final String apiBase;

  @override
  Widget build(BuildContext context) {
    final text = resolveDriveShareUrl(link, apiBase: apiBase);
    final expiry = formatDriveShareExpiry(link.expiresAt);
    return Scaffold(
      backgroundColor: _driveSheetBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: DunesColors.text,
        elevation: 0,
        title: const Text(
          '分享链接',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '链接地址',
              style: TextStyle(
                fontSize: 13,
                color: DunesColors.text3,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: SelectableText(
                  text,
                  style: const TextStyle(
                    fontSize: 15,
                    color: DunesColors.text,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            if (expiry.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '有效期至 $expiry',
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
            ],
            if (link.hasPassword) ...[
              const SizedBox(height: 4),
              const Text(
                '已设置访问密码',
                style: TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
            ],
            const Spacer(),
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                showDunesCenterToast(context, '已复制链接');
              },
              style: FilledButton.styleFrom(
                backgroundColor: _driveBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('复制链接'),
            ),
          ],
        ),
      ),
    );
  }
}

class DriveShareLinksPage extends StatefulWidget {
  const DriveShareLinksPage({
    super.key,
    required this.service,
    required this.item,
    required this.canManage,
  });

  final NativeDriveService service;
  final DriveItem item;
  final bool canManage;

  @override
  State<DriveShareLinksPage> createState() => _DriveShareLinksPageState();
}

class _DriveShareLinksPageState extends State<DriveShareLinksPage> {
  bool _loading = true;
  List<DriveShareLink> _links = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final links = await widget.service.fetchShareLinks(widget.item.id);
      if (!mounted) return;
      setState(() {
        _links = links;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: DunesColors.text,
        elevation: 0,
        title: const Text(
          '分享链接',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _driveBlue))
          : _links.isEmpty
          ? const Center(child: Text('暂无分享链接'))
          : ListView.builder(
              itemCount: _links.length,
              itemBuilder: (context, i) {
                final link = _links[i];
                return ListTile(
                  leading: Icon(
                    link.revoked ? Icons.link_off : Icons.link,
                    color: link.revoked ? DunesColors.text3 : DunesColors.accent,
                  ),
                  title: Text(
                    link.revoked
                        ? '已撤销'
                        : (formatDriveShareExpiry(link.expiresAt).isEmpty
                              ? '有效期未知'
                              : '有效至 ${formatDriveShareExpiry(link.expiresAt)}'),
                  ),
                  subtitle: Text(link.hasPassword ? '已设置密码' : '无需密码'),
                  trailing: link.revoked || !widget.canManage
                      ? null
                      : TextButton(
                          onPressed: () async {
                            await widget.service.revokeShareLink(link.id);
                            await _load();
                          },
                          child: const Text('撤销'),
                        ),
                );
              },
            ),
    );
  }
}

class DrivePreviewPage extends StatelessWidget {
  const DrivePreviewPage({
    super.key,
    required this.item,
    required this.bytes,
    this.session,
    this.service,
  });

  final DriveItem item;
  final Uint8List bytes;
  final AuthSession? session;
  final NativeDriveService? service;

  @override
  Widget build(BuildContext context) {
    Widget body;
    final isPdf = item.mimeType.toLowerCase() == 'application/pdf' ||
        item.name.toLowerCase().endsWith('.pdf');
    if (item.mimeType.startsWith('image/')) {
      body = InteractiveViewer(
        child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
      );
    } else if (isPdf) {
      body = DunesPdfView(bytes: bytes, padding: 6);
    } else {
      body = Center(
        child: Text(
          '文件大小：${_formatBytes(bytes.length)}\n支持在会话中下载或预览。',
          textAlign: TextAlign.center,
          style: const TextStyle(color: DunesColors.text2),
        ),
      );
    }
    final canSaveKb = session != null &&
        service != null &&
        driveItemSupportsKbUpload(item);
    final canDownload = service != null;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: DunesColors.text,
        elevation: 0,
        title: Text(
          item.name,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (canDownload)
            IconButton(
              tooltip: '下载到本地',
              onPressed: () => unawaited(
                downloadDriveItemToLocal(
                  context: context,
                  service: service!,
                  item: item,
                ),
              ),
              icon: const Icon(Icons.download_outlined),
            ),
          if (canSaveKb)
            IconButton(
              tooltip: '存入我的知识库',
              onPressed: () => unawaited(
                saveDriveItemToKb(
                  context: context,
                  session: session!,
                  service: service!,
                  item: item,
                ),
              ),
              icon: const Icon(Icons.cloud_upload_outlined),
            ),
        ],
      ),
      body: body,
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
