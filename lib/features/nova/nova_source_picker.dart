import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/org_folder_bar.dart';
import '../kb/native_kb_models.dart';
import '../kb/native_kb_service.dart';
import '../meeting/native_meeting_models.dart';
import '../meeting/native_meeting_service.dart';
import 'nova_source_scope.dart';

Future<NovaAnalysisSource?> showNovaKbSourcePicker(
  BuildContext context, {
  required NativeKbService kbService,
  NativeMeetingService? meetingService,
  VoidCallback? onOpenLibrary,
}) {
  return _showNovaSourceSheet<NovaAnalysisSource>(
    context,
    title: '选择知识库范围',
    child: _NovaKbSourcePicker(
      kbService: kbService,
      meetingService: meetingService,
      onOpenLibrary: onOpenLibrary,
    ),
  );
}

Future<NovaAnalysisSource?> showNovaMeetingSourcePicker(
  BuildContext context, {
  required NativeMeetingService meetingService,
  VoidCallback? onOpenLibrary,
}) {
  return _showNovaSourceSheet<NovaAnalysisSource>(
    context,
    title: '选择会议纪要',
    child: _NovaMeetingSourcePicker(
      meetingService: meetingService,
      onOpenLibrary: onOpenLibrary,
    ),
  );
}

class NovaSourceChipTray extends StatelessWidget {
  const NovaSourceChipTray({
    super.key,
    required this.sources,
    required this.onRemove,
  });

  final List<NovaAnalysisSource> sources;
  final ValueChanged<NovaAnalysisSource> onRemove;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: const Color(0xFFF7F8FC),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final source in sources)
              _NovaSourceChip(
                source: source,
                onRemove: () => onRemove(source),
              ),
          ],
        ),
      ),
    );
  }
}

class _NovaSourceChip extends StatelessWidget {
  const _NovaSourceChip({
    required this.source,
    required this.onRemove,
  });

  final NovaAnalysisSource source;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final meeting = source.isMeeting;
    return Material(
      color: meeting ? const Color(0xFFEEF4FF) : const Color(0xFFF4F0FB),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: meeting ? const Color(0xFFD4E2F7) : const Color(0xFFE3D8F5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              meeting
                  ? (source.isFolder
                        ? Icons.folder_outlined
                        : Icons.groups_2_rounded)
                  : (source.isFolder
                        ? Icons.folder_outlined
                        : Icons.menu_book_outlined),
              size: 16,
              color: meeting ? const Color(0xFF3B6BB5) : const Color(0xFF6B3FE2),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.62,
              ),
              child: Text(
                source.chipLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
            ),
            InkWell(
              customBorder: const CircleBorder(),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: DunesColors.text3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NovaConversationScopeCard extends StatelessWidget {
  const NovaConversationScopeCard({
    super.key,
    required this.sources,
    this.margin = const EdgeInsets.fromLTRB(14, 4, 14, 12),
  });

  final List<NovaAnalysisSource> sources;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本对话围绕这些材料',
            style: DunesTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '后续提问只会检索这些内容',
            style: DunesTypography.sans(
              fontSize: 11,
              color: DunesColors.text3,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < sources.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _NovaConversationScopeRow(source: sources[i]),
          ],
        ],
      ),
    );
  }
}

class _NovaConversationScopeRow extends StatelessWidget {
  const _NovaConversationScopeRow({required this.source});

  final NovaAnalysisSource source;

  @override
  Widget build(BuildContext context) {
    final preview = novaSourcePreviewLine(source);
    final meeting = source.isMeeting;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: meeting ? DunesColors.blueSoft : DunesColors.brandPurpleSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            meeting
                ? (source.isFolder
                      ? Icons.folder_outlined
                      : Icons.groups_2_rounded)
                : (source.isFolder
                      ? Icons.folder_outlined
                      : Icons.menu_book_outlined),
            size: 16,
            color: meeting ? DunesColors.blue : DunesColors.brandPurple,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                source.chipLabel,
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    color: DunesColors.text2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

Future<T?> _showNovaSourceSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: DunesColors.borderSoft,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: DunesTypography.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      );
    },
  );
}

class _NovaKbSourcePicker extends StatefulWidget {
  const _NovaKbSourcePicker({
    required this.kbService,
    this.meetingService,
    this.onOpenLibrary,
  });

  final NativeKbService kbService;
  final NativeMeetingService? meetingService;
  final VoidCallback? onOpenLibrary;

  @override
  State<_NovaKbSourcePicker> createState() => _NovaKbSourcePickerState();
}

class _NovaKbSourcePickerState extends State<_NovaKbSourcePicker> {
  bool _loading = true;
  String? _error;
  String _keyword = '';
  List<OrgFolderItem> _folders = const [];
  List<NativeKbDocument> _docs = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final folders = await widget.kbService.listFolders();
      final docs = await _loadKbDocuments(widget.kbService);
      final meetingKbIds = await _loadMeetingKbDocumentIds(widget.meetingService);
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _docs = docs
            .where(
              (doc) => novaKbDocumentAllowedInPicker(
                doc,
                meetingKbIds: meetingKbIds,
              ),
            )
            .toList();
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

  List<NativeKbDocument> get _visibleDocs {
    final q = _keyword.trim().toLowerCase();
    if (q.isEmpty) return _docs;
    return _docs.where((doc) {
      return novaKbDocumentDisplayName(doc).toLowerCase().contains(q) ||
          doc.fileName.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  List<OrgFolderItem> get _visibleFolders {
    final q = _keyword.trim().toLowerCase();
    final folders = [
      ..._folders,
      if (_docs.any((doc) => doc.folderId == null || doc.folderId! <= 0))
        const OrgFolderItem(id: -1, name: '未分类'),
    ];
    if (q.isEmpty) return folders;
    return folders
        .where((folder) => folder.name.toLowerCase().contains(q))
        .toList(growable: false);
  }

  void _pickFolder(OrgFolderItem folder) {
    final folderId = folder.id <= 0 ? null : folder.id;
    final docs = _docs.where((doc) {
      if (folderId == null) {
        return doc.folderId == null || doc.folderId! <= 0;
      }
      return doc.folderId == folderId;
    }).toList(growable: false);
    final names = docs.map(novaKbDocumentDisplayName).toList(growable: false);
    HapticFeedback.selectionClick();
    Navigator.pop(
      context,
      NovaAnalysisSource(
        kind: NovaSourceKind.kbFolder,
        id: folder.id <= 0 ? 'uncategorized' : '${folder.id}',
        title: folder.name,
        subtitle: names.isEmpty ? '目录' : '${names.length} 份文档',
        documentNames: names,
        documentIds: novaKbLocalIds(docs),
        ragflowDocIds: novaKbRagflowIds(docs),
      ),
    );
  }

  void _pickDoc(NativeKbDocument doc) {
    HapticFeedback.selectionClick();
    Navigator.pop(
      context,
      NovaAnalysisSource(
        kind: NovaSourceKind.kbFile,
        id: doc.dunesDocumentId.isNotEmpty ? doc.dunesDocumentId : doc.id,
        title: novaKbDocumentDisplayName(doc),
        subtitle: doc.fileName,
        documentNames: <String>[novaKbDocumentDisplayName(doc)],
        documentIds: novaKbLocalIds([doc]),
        ragflowDocIds: novaKbRagflowIds([doc]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _NovaSourcePickerScaffold(
      hint: '搜索知识库目录或文件',
      notice: '从会议详情上传到知识库的纪要请走「会议」入口，这里仍可看到你自己传到知识库的文件。',
      openLabel: '打开完整知识库',
      onOpenLibrary: widget.onOpenLibrary,
      keyword: _keyword,
      onKeyword: (value) => setState(() => _keyword = value),
      loading: _loading,
      error: _error,
      onRetry: _load,
      emptyText: '暂无可分析的知识库目录或文件',
      children: [
        if (_visibleFolders.isNotEmpty) ...[
          const _NovaSourceSectionTitle(text: '目录'),
          for (final folder in _visibleFolders)
            _NovaSourceTile(
              icon: Icons.folder_outlined,
              title: folder.name,
              subtitle: folder.itemCount > 0 ? '${folder.itemCount} 项' : '用此目录分析',
              onTap: () => _pickFolder(folder),
            ),
        ],
        if (_visibleDocs.isNotEmpty) ...[
          const _NovaSourceSectionTitle(text: '文件'),
          for (final doc in _visibleDocs)
            _NovaSourceTile(
              icon: Icons.description_outlined,
              title: novaKbDocumentDisplayName(doc),
              subtitle: doc.statusLabel,
              onTap: () => _pickDoc(doc),
            ),
        ],
      ],
    );
  }
}

class _NovaMeetingSourcePicker extends StatefulWidget {
  const _NovaMeetingSourcePicker({
    required this.meetingService,
    this.onOpenLibrary,
  });

  final NativeMeetingService meetingService;
  final VoidCallback? onOpenLibrary;

  @override
  State<_NovaMeetingSourcePicker> createState() =>
      _NovaMeetingSourcePickerState();
}

class _NovaMeetingSourcePickerState extends State<_NovaMeetingSourcePicker> {
  bool _loading = true;
  String? _error;
  String _keyword = '';
  List<OrgFolderItem> _folders = const [];
  List<NativeMeetingSummary> _meetings = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final folders = await widget.meetingService.listFolders();
      final page = await widget.meetingService.fetchListPage(page: 0, size: 80);
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _meetings = page.items;
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

  List<NativeMeetingSummary> get _visibleMeetings {
    final q = _keyword.trim().toLowerCase();
    if (q.isEmpty) return _meetings;
    return _meetings
        .where((item) => novaMeetingDisplayName(item).toLowerCase().contains(q))
        .toList(growable: false);
  }

  List<OrgFolderItem> get _visibleFolders {
    final q = _keyword.trim().toLowerCase();
    final folders = [
      ..._folders,
      if (_meetings.any((item) => item.folderId == null || item.folderId! <= 0))
        const OrgFolderItem(id: -1, name: '未分类'),
    ];
    if (q.isEmpty) return folders;
    return folders
        .where((folder) => folder.name.toLowerCase().contains(q))
        .toList(growable: false);
  }

  void _pickFolder(OrgFolderItem folder) {
    final folderId = folder.id <= 0 ? null : folder.id;
    final meetings = _meetings.where((item) {
      if (folderId == null) {
        return item.folderId == null || item.folderId! <= 0;
      }
      return item.folderId == folderId;
    }).toList(growable: false);
    final names = meetings.map(novaMeetingDisplayName).toList(growable: false);
    HapticFeedback.selectionClick();
    Navigator.pop(
      context,
      NovaAnalysisSource(
        kind: NovaSourceKind.meetingFolder,
        id: folder.id <= 0 ? 'uncategorized' : '${folder.id}',
        title: folder.name,
        subtitle: names.isEmpty ? '目录' : '${names.length} 份纪要',
        documentNames: names,
        documentIds: novaMeetingKbIds(meetings),
        inlineText: novaMeetingInlineText(meetings),
      ),
    );
  }

  void _pickMeeting(NativeMeetingSummary meeting) {
    HapticFeedback.selectionClick();
    Navigator.pop(
      context,
      NovaAnalysisSource(
        kind: NovaSourceKind.meetingFile,
        id: '${meeting.meetingId}',
        title: novaMeetingDisplayName(meeting),
        subtitle: meeting.displayTime,
        documentNames: <String>[novaMeetingDisplayName(meeting)],
        documentIds: novaMeetingKbIds([meeting]),
        inlineText: novaMeetingInlineText([meeting]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _NovaSourcePickerScaffold(
      hint: '搜索会议目录或纪要',
      notice: '这里只选会议纪要。普通知识库文件请从「知识库」进入。',
      openLabel: '打开会议列表',
      onOpenLibrary: widget.onOpenLibrary,
      keyword: _keyword,
      onKeyword: (value) => setState(() => _keyword = value),
      loading: _loading,
      error: _error,
      onRetry: _load,
      emptyText: '暂无可分析的会议目录或纪要',
      children: [
        if (_visibleFolders.isNotEmpty) ...[
          const _NovaSourceSectionTitle(text: '目录'),
          for (final folder in _visibleFolders)
            _NovaSourceTile(
              icon: Icons.folder_outlined,
              title: folder.name,
              subtitle: folder.itemCount > 0 ? '${folder.itemCount} 项' : '用此目录分析',
              onTap: () => _pickFolder(folder),
            ),
        ],
        if (_visibleMeetings.isNotEmpty) ...[
          const _NovaSourceSectionTitle(text: '会议纪要'),
          for (final meeting in _visibleMeetings)
            _NovaSourceTile(
              icon: Icons.groups_2_rounded,
              title: novaMeetingDisplayName(meeting),
              subtitle: meeting.displayTime,
              onTap: () => _pickMeeting(meeting),
            ),
        ],
      ],
    );
  }
}

class _NovaSourcePickerScaffold extends StatelessWidget {
  const _NovaSourcePickerScaffold({
    required this.hint,
    required this.notice,
    required this.openLabel,
    required this.keyword,
    required this.onKeyword,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.emptyText,
    required this.children,
    this.onOpenLibrary,
  });

  final String hint;
  final String notice;
  final String openLabel;
  final String keyword;
  final ValueChanged<String> onKeyword;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final String emptyText;
  final List<Widget> children;
  final VoidCallback? onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            onChanged: onKeyword,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor: const Color(0xFFF6F7FB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Text(
            notice,
            style: DunesTypography.sans(
              fontSize: 12,
              color: DunesColors.text3,
              height: 1.4,
            ),
          ),
        ),
        Expanded(child: _buildBody()),
        if (onOpenLibrary != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextButton(
              onPressed: () {
                Navigator.pop(context);
                onOpenLibrary!();
              },
              child: Text(openLabel),
            ),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error!,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(color: DunesColors.text2),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (children.isEmpty) {
      return Center(
        child: Text(
          emptyText,
          style: DunesTypography.sans(color: DunesColors.text3),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
      children: children,
    );
  }
}

class _NovaSourceSectionTitle extends StatelessWidget {
  const _NovaSourceSectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      child: Text(
        text,
        style: DunesTypography.sans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: DunesColors.text3,
        ),
      ),
    );
  }
}

class _NovaSourceTile extends StatelessWidget {
  const _NovaSourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F7FB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: const Color(0xFF6B3FE2)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DunesTypography.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFC9CDD4)),
            ],
          ),
        ),
      ),
    );
  }
}

Future<List<NativeKbDocument>> _loadKbDocuments(NativeKbService service) async {
  final all = <NativeKbDocument>[];
  var page = 0;
  while (page < 4) {
    final result = await service.listDocuments(page: page, size: 50);
    all.addAll(result.items);
    if (result.items.length < 50 || all.length >= result.total) break;
    page += 1;
  }
  return all;
}

Future<Set<int>> _loadMeetingKbDocumentIds(NativeMeetingService? service) async {
  if (service == null) return const <int>{};
  try {
    final page = await service.fetchListPage(page: 0, size: 80);
    final ids = <int>{};
    for (final meeting in page.items) {
      final id = meeting.kbDocumentId ?? 0;
      if (id > 0) ids.add(id);
    }
    return ids;
  } catch (_) {
    return const <int>{};
  }
}
