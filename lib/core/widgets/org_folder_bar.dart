import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/desktop_features.dart';
import '../theme/dunes_theme.dart';

class OrgFolderItem {
  const OrgFolderItem({
    required this.id,
    required this.name,
    this.itemCount = 0,
  });

  final int id;
  final String name;
  final int itemCount;

  static int _readCount(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  factory OrgFolderItem.fromJson(Map<String, dynamic> json) {
    return OrgFolderItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
      itemCount: _readCount(json['documentCount'] ?? json['meetingCount']),
    );
  }
}

enum OrgFolderKind { all, uncategorized, folder }

String orgFolderDisplayName(int? folderId, List<OrgFolderItem> folders) {
  if (folderId == null || folderId <= 0) return '未分类';
  for (final folder in folders) {
    if (folder.id == folderId) return folder.name;
  }
  return '已分类';
}

class OrgFolderBadge extends StatelessWidget {
  const OrgFolderBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final uncategorized = label == '未分类';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: uncategorized
            ? const Color(0xFFF0EEE8)
            : DunesColors.brandPurpleSoft,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            uncategorized ? Icons.inbox_outlined : Icons.folder_outlined,
            size: 11,
            color: uncategorized ? DunesColors.text3 : DunesColors.brandPurple,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: uncategorized
                  ? DunesColors.text3
                  : DunesColors.brandPurple,
            ),
          ),
        ],
      ),
    );
  }
}

class OrgFolderFilter {
  const OrgFolderFilter._(this.kind, this.folderId);

  const OrgFolderFilter.all() : this._(OrgFolderKind.all, null);

  const OrgFolderFilter.uncategorized()
    : this._(OrgFolderKind.uncategorized, null);

  const OrgFolderFilter.folder(int id) : this._(OrgFolderKind.folder, id);

  final OrgFolderKind kind;
  final int? folderId;

  String get cacheKey => switch (kind) {
    OrgFolderKind.all => 'all',
    OrgFolderKind.uncategorized => 'uncategorized',
    OrgFolderKind.folder => 'folder-${folderId ?? 0}',
  };

  /// 不传 folderId 时保持现有「全部」列表。
  String? get queryValue => switch (kind) {
    OrgFolderKind.all => null,
    OrgFolderKind.uncategorized => 'uncategorized',
    OrgFolderKind.folder => folderId == null ? null : '$folderId',
  };

  int? get uploadFolderId =>
      kind == OrgFolderKind.folder ? folderId : null;

  bool get isAll => kind == OrgFolderKind.all;
}

Future<String?> showOrgFolderNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => _OrgFolderNameDialog(title: title, initial: initial),
  );
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

class _OrgFolderNameDialog extends StatefulWidget {
  const _OrgFolderNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_OrgFolderNameDialog> createState() => _OrgFolderNameDialogState();
}

class _OrgFolderNameDialogState extends State<_OrgFolderNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 64,
        decoration: const InputDecoration(hintText: '文件夹名称'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}

Future<OrgFolderItem?> showOrgFolderPickDialog(
  BuildContext context, {
  required List<OrgFolderItem> folders,
  bool allowUncategorized = true,
}) {
  return showModalBottomSheet<OrgFolderItem>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '移入文件夹',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            if (allowUncategorized)
              ListTile(
                leading: const Icon(Icons.inbox_outlined),
                title: const Text('未分类'),
                onTap: () => Navigator.pop(
                  ctx,
                  const OrgFolderItem(id: 0, name: '未分类'),
                ),
              ),
            for (final folder in folders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.name),
                subtitle: folder.itemCount > 0
                    ? Text('${folder.itemCount} 项')
                    : null,
                onTap: () => Navigator.pop(ctx, folder),
              ),
            if (folders.isEmpty && !allowUncategorized)
              const ListTile(title: Text('还没有文件夹，请先新建')),
          ],
        ),
      );
    },
  );
}

class OrgFolderBar extends StatelessWidget {
  const OrgFolderBar({
    super.key,
    required this.folders,
    required this.selected,
    required this.onSelected,
    required this.onCreate,
    this.onRename,
    this.onDelete,
  });

  final List<OrgFolderItem> folders;
  final OrgFolderFilter selected;
  final ValueChanged<OrgFolderFilter> onSelected;
  final VoidCallback onCreate;
  final ValueChanged<OrgFolderItem>? onRename;
  final ValueChanged<OrgFolderItem>? onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(
            label: '全部',
            selected: selected.kind == OrgFolderKind.all,
            icon: Icons.apps_rounded,
            onTap: () => onSelected(const OrgFolderFilter.all()),
          ),
          const SizedBox(width: 6),
          _chip(
            label: '未分类',
            selected: selected.kind == OrgFolderKind.uncategorized,
            icon: Icons.inbox_outlined,
            onTap: () => onSelected(const OrgFolderFilter.uncategorized()),
          ),
          for (final folder in folders) ...[
            const SizedBox(width: 6),
            _OrgUserFolderChip(
              folder: folder,
              selected:
                  selected.kind == OrgFolderKind.folder &&
                  selected.folderId == folder.id,
              onTap: () => onSelected(OrgFolderFilter.folder(folder.id)),
              onRename: onRename,
              onDelete: onDelete,
            ),
          ],
          const SizedBox(width: 6),
          _chip(
            label: '新建',
            selected: false,
            icon: Icons.create_new_folder_outlined,
            onTap: onCreate,
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      visualDensity: VisualDensity.compact,
      selected: selected,
      showCheckmark: false,
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selectedColor: DunesColors.brandPurpleSoft,
      side: BorderSide(
        color: selected ? DunesColors.brandPurple : DunesColors.borderSoft,
      ),
      onSelected: (_) => onTap(),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 2),
    );
  }
}

class _OrgUserFolderChip extends StatelessWidget {
  const _OrgUserFolderChip({
    required this.folder,
    required this.selected,
    required this.onTap,
    this.onRename,
    this.onDelete,
  });

  final OrgFolderItem folder;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<OrgFolderItem>? onRename;
  final ValueChanged<OrgFolderItem>? onDelete;

  Future<void> _openActions(BuildContext context) async {
    final action = await showOrgFolderManageActions(context);
    if (action == 'rename') onRename?.call(folder);
    if (action == 'delete') onDelete?.call(folder);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '点 ··· 或右键可重命名、删除；删除后内容回到未分类',
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        onSecondaryTap: () => unawaited(_openActions(context)),
        onLongPress: () => unawaited(_openActions(context)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilterChip(
              visualDensity: VisualDensity.compact,
              selected: selected,
              showCheckmark: false,
              avatar: const Icon(Icons.folder_outlined, size: 16),
              label: Text(folder.name, style: const TextStyle(fontSize: 12)),
              selectedColor: DunesColors.brandPurpleSoft,
              side: BorderSide(
                color: selected
                    ? DunesColors.brandPurple
                    : DunesColors.borderSoft,
              ),
              onSelected: (_) => onTap(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelPadding: const EdgeInsets.only(right: 2),
              padding: const EdgeInsets.symmetric(horizontal: 2),
            ),
            InkWell(
              key: ValueKey('folder-more-${folder.id}'),
              onTap: () => unawaited(_openActions(context)),
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: DunesColors.text2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> showOrgFolderManageActions(BuildContext context) async {
  if (isDesktopCommOnly) {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box != null && overlay != null) {
      return showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromPoints(
            box.localToGlobal(Offset.zero, ancestor: overlay),
            box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
          ),
          Offset.zero & overlay.size,
        ),
        items: const [
          PopupMenuItem<String>(
            value: 'rename',
            child: Text('重命名'),
          ),
          PopupMenuItem<String>(
            value: 'delete',
            child: Text('删除文件夹（内容回到未分类）'),
          ),
        ],
      );
    }
  }
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('重命名'),
            onTap: () => Navigator.pop(ctx, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('删除文件夹'),
            subtitle: const Text('里面的内容会回到未分类，文件本身不会删除'),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    ),
  );
}

class OrgFolderMultiSelectButton extends StatelessWidget {
  const OrgFolderMultiSelectButton({
    super.key,
    required this.selecting,
    required this.onPressed,
  });

  final bool selecting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (selecting) {
      return TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.close_rounded, size: 18),
        label: const Text('取消多选'),
        style: TextButton.styleFrom(
          foregroundColor: DunesColors.brandPurple,
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.checklist_rounded, size: 18),
      label: const Text('多选'),
      style: OutlinedButton.styleFrom(
        foregroundColor: DunesColors.brandPurple,
        side: const BorderSide(color: DunesColors.brandPurple),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
  }
}

class OrgFolderSelectBar extends StatelessWidget {
  const OrgFolderSelectBar({
    super.key,
    required this.count,
    required this.total,
    required this.onCancel,
    required this.onMove,
    required this.onToggleSelectAll,
  });

  final int count;
  final int total;
  final VoidCallback onCancel;
  final VoidCallback onMove;
  final VoidCallback onToggleSelectAll;

  bool get allSelected => total > 0 && count >= total;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Text(
                allSelected ? '已全选 $count 项' : '已选 $count 项',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: total > 0 ? onToggleSelectAll : null,
                child: Text(allSelected ? '取消全选' : '全选'),
              ),
              const Spacer(),
              TextButton(onPressed: onCancel, child: const Text('取消')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: count > 0 ? onMove : null,
                child: const Text('移入文件夹'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
