import 'dart:async';
import 'dart:io' show Platform;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/chat_file_type_icon.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import '../tasks/native_task_home_pane.dart';
import 'drive_download.dart';
import 'drive_file_open.dart';
import 'drive_im_push.dart';
import 'drive_kb.dart';
import 'drive_subpages.dart';
import 'drive_upload_coordinator.dart';
import 'native_drive_models.dart';
import 'native_drive_service.dart';

const _driveBlue = Color(0xFF3B82F6);

/// 企业微盘：企微「微盘空间」列表式（搜索 + 我的/共享空间列表，无统计）。
class NativeDrivePage extends StatefulWidget {
  const NativeDrivePage({
    super.key,
    required this.session,
    this.onBack,
    this.embedded = false,
    this.onChromeChanged,
    this.initialItemId,
  });

  final AuthSession session;
  final VoidCallback? onBack;
  final bool embedded;
  final ValueChanged<TaskShellChrome>? onChromeChanged;
  final int? initialItemId;

  @override
  State<NativeDrivePage> createState() => _NativeDrivePageState();
}

class _NativeDrivePageState extends State<NativeDrivePage> {
  late final NativeDriveService _service = NativeDriveService(
    session: widget.session,
  );
  late final ConversationService _avatarService = ConversationService(
    session: widget.session,
  );
  final _search = TextEditingController();
  Timer? _searchDebounce;
  List<DriveSpace> _spaces = const [];
  List<DriveItem> _items = const [];
  DriveSpace? _space;
  final List<DriveItem> _folders = <DriveItem>[];
  bool _loading = true;
  bool _busy = false;
  bool _dragging = false;
  String? _error;
  final Set<String> _toastedErrorJobIds = <String>{};
  int? _pendingInitialItemId;
  bool _openingInitialItem = false;

  /// false=空间首页；true=已进入某个空间浏览文件。
  bool _inSpace = false;

  int? get _parentId => _folders.isEmpty ? null : _folders.last.id;

  bool get _isPersonalSpace => (_space?.kind ?? '').toLowerCase() == 'personal';

  bool get _canManageMembers => _space?.canManage == true && !_isPersonalSpace;

  bool get _supportsDesktopDrop {
    if (kIsWeb) return true;
    return !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  }

  @override
  void initState() {
    super.initState();
    _pendingInitialItemId = widget.initialItemId;
    _search.addListener(_onSearchChanged);
    DriveUploadCoordinator.instance.addListener(_onUploadChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _publishChrome());
    _load();
  }

  @override
  void didUpdateWidget(covariant NativeDrivePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialItemId != oldWidget.initialItemId &&
        (widget.initialItemId ?? 0) > 0) {
      _pendingInitialItemId = widget.initialItemId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openPendingItem());
      });
    }
  }

  @override
  void dispose() {
    DriveUploadCoordinator.instance.removeListener(_onUploadChanged);
    _searchDebounce?.cancel();
    _search.dispose();
    _service.close();
    _avatarService.close();
    super.dispose();
  }

  final Set<String> _refreshedJobIds = <String>{};

  void _onUploadChanged() {
    if (!mounted) return;
    setState(() {});
    final space = _space;
    if (!_inSpace || space == null) return;
    final jobs = DriveUploadCoordinator.instance.jobsFor(
      spaceId: space.id,
      parentId: _parentId,
    );
    var needRefresh = false;
    for (final job in jobs) {
      if (job.done && job.error == null && !_refreshedJobIds.contains(job.id)) {
        _refreshedJobIds.add(job.id);
        needRefresh = true;
      }
      if (job.error != null && !_toastedErrorJobIds.contains(job.id)) {
        _toastedErrorJobIds.add(job.id);
        showDunesCenterToast(
          context,
          friendlyErrorText(job.error, fallback: '上传失败'),
          kind: DunesToastKind.error,
        );
      }
    }
    if (needRefresh) unawaited(_load());
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() {});
    });
  }

  void _publishChrome() {
    if (!widget.embedded) return;
    VoidCallback? onBack;
    if (_folders.isNotEmpty) {
      onBack = () => unawaited(_popFolder());
    } else if (_inSpace) {
      onBack = () => unawaited(_leaveSpace());
    }
    widget.onChromeChanged?.call(
      TaskShellChrome(onBack: onBack, trailing: _buildChromeTrailing()),
    );
  }

  Widget _buildChromeTrailing() {
    if (!_inSpace) {
      return IconButton(
        tooltip: '创建共享空间',
        onPressed: _createSpace,
        icon: const Icon(Icons.add_rounded, size: 24),
        color: DunesColors.text2,
      );
    }
    final canEdit = _space?.canEdit == true;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_canManageMembers)
          IconButton(
            tooltip: '成员',
            onPressed: _showMembers,
            icon: const Icon(Icons.group_outlined, size: 22),
            color: DunesColors.text2,
          ),
        if (_canManageMembers)
          IconButton(
            tooltip: '通知设置',
            onPressed: _showNotificationSettings,
            icon: const Icon(Icons.settings_outlined, size: 21),
            color: DunesColors.text2,
          ),
        if (canEdit)
          // 相对加号左移，避免贴右缘时文字被裁切。
          MenuAnchor(
            alignmentOffset: const Offset(-72, 4),
            style: MenuStyle(
              alignment: AlignmentDirectional.bottomEnd,
              backgroundColor: const WidgetStatePropertyAll(Colors.white),
              elevation: const WidgetStatePropertyAll(8),
              shadowColor: WidgetStatePropertyAll(
                Colors.black.withValues(alpha: 0.12),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 6),
              ),
            ),
            builder: (context, controller, _) {
              return IconButton(
                tooltip: '新建',
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(Icons.add_rounded, size: 24),
                color: DunesColors.text2,
              );
            },
            menuChildren: [
              MenuItemButton(
                onPressed: _upload,
                leadingIcon: const Icon(
                  Icons.upload_file_outlined,
                  size: 18,
                  color: _driveBlue,
                ),
                child: const Text('上传文件'),
              ),
              MenuItemButton(
                onPressed: _createFolder,
                leadingIcon: const Icon(
                  Icons.create_new_folder_outlined,
                  size: 18,
                  color: _driveBlue,
                ),
                child: const Text('新建文件夹'),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _load({bool keepSpace = true}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final spaces = await _service.fetchSpaces();
      if (!_inSpace) {
        if (!mounted) return;
        setState(() {
          _spaces = spaces;
          _loading = false;
        });
        _publishChrome();
        if ((_pendingInitialItemId ?? 0) > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_openPendingItem());
          });
        }
        return;
      }

      DriveSpace? selected;
      if (keepSpace && _space != null) {
        for (final space in spaces) {
          if (space.id == _space!.id) selected = space;
        }
      }
      selected ??= spaces.isEmpty ? null : spaces.first;
      final items = selected == null
          ? const <DriveItem>[]
          : await _service.fetchItems(
              spaceId: selected.id,
              parentId: _parentId,
              query: _search.text,
            );
      if (!mounted) return;
      setState(() {
        _spaces = spaces;
        _space = selected;
        _items = items;
        _loading = false;
      });
      _publishChrome();
      if ((_pendingInitialItemId ?? 0) > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_openPendingItem());
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
      _publishChrome();
    }
  }

  Future<void> _selectSpace(DriveSpace space) async {
    _search.clear();
    setState(() {
      _space = space;
      _folders.clear();
      _inSpace = true;
    });
    _publishChrome();
    await _load();
  }

  Future<void> _openPendingItem() async {
    final itemId = _pendingInitialItemId ?? 0;
    if (itemId <= 0 || _openingInitialItem) return;
    _openingInitialItem = true;
    try {
      final location = await _service.fetchItemLocation(itemId);
      DriveSpace? targetSpace;
      for (final space in _spaces) {
        if (space.id == location.spaceId) {
          targetSpace = space;
          break;
        }
      }
      if (targetSpace == null) {
        final latestSpaces = await _service.fetchSpaces();
        for (final space in latestSpaces) {
          if (space.id == location.spaceId) {
            targetSpace = space;
            break;
          }
        }
      }
      if (targetSpace == null) throw Exception('你已无法访问该共享空间');
      _pendingInitialItemId = null;
      if (!mounted) return;
      setState(() {
        _space = targetSpace;
        _folders
          ..clear()
          ..addAll(location.folders);
        _inSpace = true;
        _search.clear();
      });
      _publishChrome();
      await _load();
      if (!mounted) return;
      await _openFile(location.item);
    } catch (e) {
      _pendingInitialItemId = null;
      _showError(friendlyErrorText(e, fallback: '无法定位该文件'));
    } finally {
      _openingInitialItem = false;
    }
  }

  Future<void> _leaveSpace() async {
    _search.clear();
    setState(() {
      _inSpace = false;
      _space = null;
      _folders.clear();
      _items = const [];
    });
    _publishChrome();
    await _load();
  }

  Future<void> _openFolder(DriveItem item) async {
    if (!item.isFolder || _space == null) return;
    _search.clear();
    setState(() => _folders.add(item));
    _publishChrome();
    await _load();
  }

  Future<void> _popFolder() async {
    if (_folders.isEmpty) return;
    _search.clear();
    setState(() => _folders.removeLast());
    _publishChrome();
    await _load();
  }

  Future<void> _goUp() async {
    if (_folders.isNotEmpty) {
      await _popFolder();
      return;
    }
    if (_inSpace) {
      await _leaveSpace();
      return;
    }
    widget.onBack?.call();
  }

  Future<void> _createFolder() async {
    final name = await pushDrivePage<String>(
      context,
      const DriveTextFormPage(title: '新建文件夹', hint: '文件夹名称'),
    );
    if (name == null || name.trim().isEmpty || _space == null) return;
    await _runBusy(() async {
      await _service.createFolder(
        spaceId: _space!.id,
        parentId: _parentId,
        name: name.trim(),
      );
      await _load();
    });
  }

  Future<void> _upload() async {
    if (_space == null || _space!.canEdit != true) return;
    List<XFile> files;
    try {
      files = await openFiles();
    } catch (_) {
      files = const <XFile>[];
    }
    if (files.isEmpty) return;
    await _enqueueUploads(files);
  }

  Future<void> _enqueueUploads(List<XFile> files) async {
    final space = _space;
    if (space == null || space.canEdit != true || files.isEmpty) return;
    await DriveUploadCoordinator.instance.enqueueMany(
      session: widget.session,
      spaceId: space.id,
      parentId: _parentId,
      files: files,
    );
  }

  Future<void> _onDesktopDrop(DropDoneDetails detail) async {
    if (_space?.canEdit != true) return;
    final files = <XFile>[];
    for (final item in detail.files) {
      if (item is DropItemDirectory) continue;
      final path = item.path;
      if (path.isEmpty) continue;
      files.add(XFile(path, name: item.name));
    }
    if (files.isEmpty) {
      _showError('请拖入文件（暂不支持文件夹）');
      return;
    }
    await _enqueueUploads(files);
  }

  Future<void> _createSpace() async {
    final result = await showDriveSheet<DriveCreateSpaceResult>(
      context,
      DriveCreateSpacePanel(session: widget.session),
    );
    if (result == null || result.name.trim().isEmpty) return;
    await _runBusy(() async {
      final created = await _service.createSpace(
        result.name.trim(),
        description: result.description.trim(),
        members: result.memberIds
            .map((id) => <String, dynamic>{'userId': id, 'role': 'VIEWER'})
            .toList(growable: false),
      );
      final spaces = await _service.fetchSpaces();
      if (!mounted) return;
      setState(() {
        _spaces = spaces;
        _space = spaces.firstWhere(
          (space) => space.id == created.id,
          orElse: () => created,
        );
        _folders.clear();
        _inSpace = true;
      });
      await _load();
    });
  }

  Future<void> _showMembers() async {
    final space = _space;
    if (space == null || !space.canManage) return;
    // 我的空间仅本人可见，不可添加成员。
    if (space.kind.toLowerCase() == 'personal') return;
    await showDriveSheet<bool>(
      context,
      DriveMembersPage(
        session: widget.session,
        service: _service,
        space: space,
      ),
    );
    if (_inSpace) await _load();
  }

  Future<void> _showNotificationSettings() async {
    final space = _space;
    if (space == null || !space.canManage || _isPersonalSpace) return;
    final changed = await pushDrivePage<bool>(
      context,
      DriveSpaceNotificationSettingsPage(service: _service, space: space),
    );
    if (changed == true && mounted) {
      final spaces = await _service.fetchSpaces();
      DriveSpace? refreshed;
      for (final entry in spaces) {
        if (entry.id == space.id) {
          refreshed = entry;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _spaces = spaces;
        if (refreshed != null) _space = refreshed;
      });
      _publishChrome();
    }
  }

  Future<void> _showTrash() async {
    await pushDrivePage<void>(context, DriveTrashPage(service: _service));
    if (_inSpace) await _load();
  }

  Future<void> _showItemMenu(DriveItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.78,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(0, 6, 0, 12 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.canEdit)
                    ListTile(
                      leading: const Icon(
                        Icons.drive_file_rename_outline,
                        color: _driveBlue,
                      ),
                      title: const Text('重命名'),
                      onTap: () => Navigator.pop(context, 'rename'),
                    ),
                  if (item.canEdit)
                    ListTile(
                      leading: const Icon(
                        Icons.delete_outline,
                        color: _driveBlue,
                      ),
                      title: const Text('移入回收站'),
                      onTap: () => Navigator.pop(context, 'trash'),
                    ),
                  if (!item.isFolder && item.canEdit)
                    ListTile(
                      leading: const Icon(Icons.history, color: _driveBlue),
                      title: const Text('版本历史'),
                      onTap: () => Navigator.pop(context, 'versions'),
                    ),
                  if (!item.isFolder && item.canEdit)
                    ListTile(
                      leading: const Icon(
                        Icons.upload_file_outlined,
                        color: _driveBlue,
                      ),
                      title: const Text('上传新版本'),
                      onTap: () => Navigator.pop(context, 'upload-version'),
                    ),
                  if (item.canEdit)
                    ListTile(
                      leading: const Icon(
                        Icons.drive_file_move_outline,
                        color: _driveBlue,
                      ),
                      title: const Text('移动 / 复制'),
                      onTap: () => Navigator.pop(context, 'move'),
                    ),
                  // 文件：选会话以 IM 文件消息发送。
                  if (!item.isFolder)
                    ListTile(
                      leading: const Icon(
                        Icons.chat_outlined,
                        color: _driveBlue,
                      ),
                      title: const Text('发送到聊天'),
                      subtitle: const Text('选择会话，以文件消息推送'),
                      onTap: () => Navigator.pop(context, 'push-im'),
                    ),
                  // 知识库放在下载前，避免底部被裁切时看不到。
                  if (!item.isFolder && driveItemSupportsKbUpload(item))
                    ListTile(
                      leading: Icon(
                        item.kbSavedCurrent
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_upload_outlined,
                        color: _driveBlue,
                      ),
                      title: Text(
                        item.kbSavedCurrent
                            ? '再次存入知识库'
                            : (item.kbSaved ? '更新到知识库' : '存入知识库'),
                      ),
                      subtitle: item.kbSavedCurrent
                          ? const Text('已标记为存入你的知识库')
                          : null,
                      onTap: () => Navigator.pop(context, 'save-kb'),
                    ),
                  if (!item.isFolder)
                    ListTile(
                      leading: Icon(
                        item.downloadedCurrent
                            ? Icons.download_done_rounded
                            : Icons.download_outlined,
                        color: _driveBlue,
                      ),
                      title: Text(
                        item.downloadedCurrent
                            ? '重新下载到本地'
                            : (item.downloaded ? '下载新版本到本地' : '下载到本地'),
                      ),
                      subtitle: item.downloadedCurrent
                          ? const Text('已标记为下载到本地')
                          : (item.downloaded ? const Text('本地有旧版本') : null),
                      onTap: () => Navigator.pop(context, 'download'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      final name = await pushDrivePage<String>(
        context,
        DriveTextFormPage(title: '重命名', initial: item.name),
      );
      if (name == null || name.trim().isEmpty) return;
      await _runBusy(() async {
        await _service.rename(item.id, name.trim());
        await _load();
      });
    } else if (action == 'trash') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(item.isFolder ? '删除文件夹' : '移入回收站'),
          content: Text(
            item.isFolder
                ? '确定将文件夹「${item.name}」及其内容移入回收站吗？'
                : '确定将「${item.name}」移入回收站吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('移入回收站'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await _runBusy(() async {
        await _service.trash(item.id);
        await _load();
      });
    } else if (action == 'versions') {
      await _showVersions(item);
    } else if (action == 'upload-version') {
      final file = await openFile();
      if (file != null) {
        await _runBusy(() async {
          await _service.uploadVersion(itemId: item.id, file: file);
          await _load();
        });
      }
    } else if (action == 'move') {
      await _showMoveCopy(item);
    } else if (action == 'push-im') {
      await pushDriveItemToIm(
        context: context,
        session: widget.session,
        service: _service,
        item: item,
      );
    } else if (action == 'download') {
      final ok = await downloadDriveItemToLocal(
        context: context,
        service: _service,
        item: item,
      );
      if (ok && mounted) await _load();
    } else if (action == 'save-kb') {
      final ok = await saveDriveItemToKb(
        context: context,
        session: widget.session,
        service: _service,
        item: item,
      );
      if (ok && mounted) await _load();
    }
  }

  Future<void> _showVersions(DriveItem item) async {
    try {
      final versions = await _service.fetchVersions(item.id);
      if (!mounted) return;
      await pushDrivePage<void>(
        context,
        DriveVersionsPage(
          versions: versions,
          onRestore: (version) async {
            await _runBusy(() async {
              await _service.restoreVersion(item.id, version.id);
              await _load();
            });
          },
        ),
      );
    } catch (error) {
      _showError('$error');
    }
  }

  Future<void> _showMoveCopy(DriveItem item) async {
    if (_spaces.isEmpty) return;
    DriveSpace sourceSpace = _space ?? _spaces.first;
    for (final space in _spaces) {
      if (space.id == item.spaceId) {
        sourceSpace = space;
        break;
      }
    }
    final result = await pushDrivePage<DriveMoveCopyResult>(
      context,
      DriveMoveCopyPage(
        service: _service,
        spaces: _spaces,
        item: item,
        sourceSpace: sourceSpace,
      ),
    );
    if (result == null) return;
    await _runBusy(() async {
      if (result.mode == 'copy') {
        await _service.copy(
          id: item.id,
          spaceId: result.space.id,
          parentId: result.parentId,
        );
      } else {
        await _service.move(
          id: item.id,
          spaceId: result.space.id,
          parentId: result.parentId,
        );
      }
      await _load();
    });
  }

  Future<void> _confirmDeleteSpaceMenu(DriveSpace space) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
              ),
              title: const Text('删除共享空间'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'delete') await _deleteSharedSpace(space);
  }

  Future<void> _deleteSharedSpace(DriveSpace space) async {
    if (!space.canManage || space.kind.toLowerCase() != 'shared') return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除共享空间'),
        content: Text('确定删除「${space.name}」吗？空间内文件将进入回收站。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _runBusy(() async {
      await _service.deleteSpace(space.id);
      if (_space?.id == space.id) {
        setState(() {
          _inSpace = false;
          _space = null;
          _folders.clear();
          _items = const [];
        });
      }
      await _load(keepSpace: false);
    });
  }

  Future<void> _openFile(DriveItem item) async {
    if (!mounted) return;
    await openDriveFile(
      context: context,
      service: _service,
      item: item,
      session: widget.session,
    );
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _showError('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showDunesCenterToast(
      context,
      friendlyErrorText(message, fallback: message),
      kind: DunesToastKind.error,
    );
  }

  String _ownerInitial(DriveSpace space) {
    final name = space.ownerDisplayName.trim();
    if (name.isEmpty) return '?';
    return String.fromCharCode(name.runes.first);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  List<DriveSpace> get _visibleSpaces {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _spaces;
    return _spaces
        .where((s) => s.name.toLowerCase().contains(q))
        .toList(growable: false);
  }

  List<DriveItem> get _visibleItems {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items
        .where((item) => item.name.toLowerCase().contains(q))
        .toList(growable: false);
  }

  String get _headerTitle {
    if (!_inSpace) return '企业微盘';
    if (_folders.isNotEmpty) return _folders.last.name;
    return _space?.name ?? '企业微盘';
  }

  @override
  Widget build(BuildContext context) {
    final uploadJobs = _inSpace && _space != null
        ? DriveUploadCoordinator.instance.jobsFor(
            spaceId: _space!.id,
            parentId: _parentId,
          )
        : const <DriveUploadJob>[];
    Widget scrollBody = RefreshIndicator(
      onRefresh: _load,
      color: _driveBlue,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_inSpace && _folders.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  '${_space?.name ?? ''} / ${_folders.map((e) => e.name).join(' / ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DunesColors.text3,
                  ),
                ),
              ),
            ),
          if (uploadJobs.isNotEmpty)
            _DriveUploadProgressSliver(jobs: uploadJobs),
          ..._buildBodySlivers(),
        ],
      ),
    );

    if (_inSpace && _space?.canEdit == true && _supportsDesktopDrop) {
      scrollBody = DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (detail) {
          setState(() => _dragging = false);
          unawaited(_onDesktopDrop(detail));
        },
        child: Stack(
          children: [
            scrollBody,
            if (_dragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _driveBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _driveBlue, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '松开以上传文件',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _driveBlue,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final body = ColoredBox(
      color: Colors.white,
      child: Stack(
        children: [
          scrollBody,
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.06),
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: _driveBlue,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchBar(),
        Expanded(child: body),
      ],
    );

    if (widget.embedded) return ColoredBox(color: Colors.white, child: content);

    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _goUp,
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    color: DunesColors.text2,
                  ),
                  Expanded(
                    child: Text(
                      _headerTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                  ),
                  _buildChromeTrailing(),
                ],
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) {
          if (_inSpace) unawaited(_load());
        },
        decoration: InputDecoration(
          hintText: '搜索',
          hintStyle: const TextStyle(color: DunesColors.text3, fontSize: 15),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          prefixIcon: const Icon(
            Icons.search,
            size: 20,
            color: DunesColors.text3,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBodySlivers() {
    if (_loading) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: _driveBlue)),
        ),
      ];
    }
    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 36,
                ),
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                TextButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          ),
        ),
      ];
    }

    if (!_inSpace) return _buildSpaceHomeSlivers();
    return _buildFileListSlivers();
  }

  List<Widget> _buildSpaceHomeSlivers() {
    final q = _search.text.trim().toLowerCase();
    final personal = _visibleSpaces
        .where((s) => s.kind.toLowerCase() == 'personal')
        .toList();
    final shared = _visibleSpaces.where((s) {
      final k = s.kind.toLowerCase();
      return k != 'personal' && k != 'default';
    }).toList();

    if (_spaces.isEmpty && q.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_outlined,
                  size: 48,
                  color: _driveBlue.withValues(alpha: 0.45),
                ),
                const SizedBox(height: 12),
                const Text(
                  '暂无微盘空间',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '创建一个共享空间开始使用',
                  style: TextStyle(fontSize: 13, color: DunesColors.text3),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _createSpace,
                  icon: const Icon(Icons.add),
                  label: const Text('创建共享空间'),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    if (q.isNotEmpty && personal.isEmpty && shared.isEmpty) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              '没有符合条件的空间',
              style: TextStyle(fontSize: 14, color: DunesColors.text3),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            if (personal.isNotEmpty || q.isEmpty) ...[
              const _DriveSectionLabel('我的'),
              if (personal.isEmpty)
                const _DriveEmptyHint('暂无个人空间')
              else
                for (final space in personal)
                  _DriveSpaceRow(
                    title: space.name.isEmpty ? '我的空间' : space.name,
                    subtitle: '仅我本人可见，不可添加成员',
                    icon: Icons.cloud_rounded,
                    onTap: () => unawaited(_selectSpace(space)),
                  ),
              if (q.isEmpty)
                _DriveSpaceRow(
                  title: '回收站',
                  subtitle: '保留 7 天',
                  icon: Icons.delete_outline_rounded,
                  onTap: () => unawaited(_showTrash()),
                ),
            ],
            if (shared.isNotEmpty || q.isEmpty) ...[
              const _DriveSectionLabel('共享'),
              if (shared.isEmpty && q.isNotEmpty)
                const _DriveEmptyHint('没有匹配的共享空间')
              else ...[
                for (final space in shared)
                  _DriveSpaceRow(
                    title: space.name,
                    subtitle: space.description.isNotEmpty
                        ? space.description
                        : (space.canManage
                              ? '管理者'
                              : (space.canEdit ? '可编辑' : '仅查看')),
                    icon: Icons.inventory_2_outlined,
                    onTap: () => unawaited(_selectSpace(space)),
                    onLongPress:
                        space.canManage && space.kind.toLowerCase() == 'shared'
                        ? () => unawaited(_deleteSharedSpace(space))
                        : null,
                    onMore:
                        space.canManage && space.kind.toLowerCase() == 'shared'
                        ? () => unawaited(_confirmDeleteSpaceMenu(space))
                        : null,
                    ownerName: space.ownerDisplayName.isEmpty
                        ? null
                        : space.ownerDisplayName,
                    ownerAvatar: space.ownerUserId > 0
                        ? ImUserAvatar(
                            initial: _ownerInitial(space),
                            seed: space.ownerUserId,
                            size: 28,
                            avatarPreset: space.ownerAvatarPreset.isEmpty
                                ? null
                                : space.ownerAvatarPreset,
                            avatarObjectKey: space.ownerAvatarObjectKey.isEmpty
                                ? null
                                : space.ownerAvatarObjectKey,
                            avatarService: _avatarService,
                          )
                        : null,
                  ),
                if (q.isEmpty)
                  _DriveSpaceRow(
                    title: '创建共享空间',
                    subtitle: '与同事协作共享文件',
                    icon: Icons.add_box_outlined,
                    iconColor: DunesColors.text3,
                    onTap: _createSpace,
                  ),
              ],
            ],
          ]),
        ),
      ),
    ];
  }

  List<Widget> _buildFileListSlivers() {
    final items = _visibleItems;
    final searching = _search.text.trim().isNotEmpty;

    if (items.isEmpty) {
      final emptyHint = searching
          ? '没有符合条件的结果'
          : (_space?.canEdit == true && _supportsDesktopDrop
                ? '此处还没有文件或文件夹\n可将文件拖拽到此上传'
                : '此处还没有文件或文件夹');
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              emptyHint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: DunesColors.text3),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.only(bottom: 24),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, i) {
            final item = items[i];
            final statusLabel = item.isFolder
                ? ''
                : [
                    if (item.downloadedCurrent)
                      '已下载'
                    else if (item.downloaded)
                      '有新版本未下载',
                    if (item.kbSavedCurrent)
                      '已入库'
                    else if (item.kbSaved)
                      '知识库有旧版',
                  ].map((e) => ' · $e').join();
            return _DriveFileRow(
              title: item.name,
              subtitle: item.isFolder
                  ? '文件夹'
                  : '${_formatBytes(item.sizeBytes)} · v${item.version}$statusLabel',
              typeIcon: item.isFolder
                  ? null
                  : ChatFileTypeIcon(
                      fileName: item.name,
                      kindHint: _driveKindHint(item.mimeType),
                      size: 36,
                    ),
              icon: item.isFolder ? Icons.folder_rounded : null,
              iconColor: item.isFolder ? _driveBlue : DunesColors.text2,
              kbSaved: item.kbSavedCurrent,
              downloaded: item.downloadedCurrent,
              // PC：文件双击打开（对齐 IM）；APP：单击打开。文件夹始终单击进入。
              onTap: item.isFolder
                  ? () => unawaited(_openFolder(item))
                  : (isDesktopCommOnly
                        ? null
                        : () => unawaited(_openFile(item))),
              onDoubleTap: !item.isFolder && isDesktopCommOnly
                  ? () => unawaited(_openFile(item))
                  : null,
              // 查看者也可打开菜单（发送到聊天 / 存入知识库 / 下载等）。
              onMore: () => _showItemMenu(item),
            );
          }, childCount: items.length),
        ),
      ),
    ];
  }

  String _driveKindHint(String mime) {
    if (mime.startsWith('image/')) return 'IMAGE';
    if (mime.startsWith('video/')) return 'VIDEO';
    if (mime.startsWith('audio/')) return 'AUDIO';
    return '';
  }
}

class _DriveUploadProgressSliver extends StatelessWidget {
  const _DriveUploadProgressSliver({required this.jobs});

  final List<DriveUploadJob> jobs;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          children: [
            for (final job in jobs)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          job.error != null
                              ? Icons.error_outline
                              : (job.done
                                    ? Icons.check_circle_outline
                                    : Icons.upload_file_outlined),
                          size: 18,
                          color: job.error != null
                              ? Colors.redAccent
                              : _driveBlue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            job.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          job.error != null
                              ? '失败'
                              : (job.done
                                    ? '完成'
                                    : '${(job.progress * 100).clamp(0, 100).toStringAsFixed(0)}%'),
                          style: TextStyle(
                            fontSize: 12,
                            color: job.error != null
                                ? Colors.redAccent
                                : DunesColors.text3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: job.error != null
                            ? 1
                            : job.progress.clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: const Color(0xFFE5E7EB),
                        color: job.error != null
                            ? Colors.redAccent
                            : _driveBlue,
                      ),
                    ),
                    if (job.error != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        job.error!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DriveSectionLabel extends StatelessWidget {
  const _DriveSectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: DunesColors.text3,
        ),
      ),
    );
  }
}

class _DriveEmptyHint extends StatelessWidget {
  const _DriveEmptyHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: DunesColors.text3),
      ),
    );
  }
}

class _DriveSpaceRow extends StatelessWidget {
  const _DriveSpaceRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.onMore,
    this.ownerName,
    this.ownerAvatar,
    this.iconColor = _driveBlue,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;
  final String? ownerName;
  final Widget? ownerAvatar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: DunesColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
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
              if (ownerAvatar != null ||
                  (ownerName != null && ownerName!.isNotEmpty)) ...[
                const SizedBox(width: 8),
                if (ownerAvatar != null) ownerAvatar!,
                if (ownerName != null && ownerName!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 72),
                    child: Text(
                      ownerName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: DunesColors.text2,
                      ),
                    ),
                  ),
                ],
              ],
              if (onMore != null)
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: '更多',
                    onPressed: onMore,
                    icon: const Icon(Icons.more_horiz_rounded, size: 20),
                    color: DunesColors.text3,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriveFileRow extends StatelessWidget {
  const _DriveFileRow({
    required this.title,
    required this.subtitle,
    this.icon,
    this.typeIcon,
    this.onTap,
    this.onDoubleTap,
    this.onMore,
    this.iconColor = _driveBlue,
    this.kbSaved = false,
    this.downloaded = false,
  });

  final String title;
  final String subtitle;
  final IconData? icon;

  /// 非文件夹时的彩色类型图标；优先于 [icon]。
  final Widget? typeIcon;
  final Color iconColor;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onMore;
  final bool kbSaved;
  final bool downloaded;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: typeIcon ?? Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: DunesColors.text,
                            ),
                          ),
                        ),
                        if (downloaded) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.download_done_rounded,
                            size: 16,
                            color: _driveBlue,
                          ),
                        ],
                        if (kbSaved) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.cloud_done_outlined,
                            size: 16,
                            color: _driveBlue,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
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
                width: 40,
                height: 40,
                child: onMore == null
                    ? null
                    : IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        onPressed: onMore,
                        icon: const Icon(Icons.more_horiz_rounded, size: 22),
                        color: DunesColors.text3,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
