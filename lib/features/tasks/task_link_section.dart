import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../kb/native_kb_doc_page.dart';
import '../kb/native_kb_models.dart';
import '../kb/native_kb_service.dart';
import '../meeting/native_meeting_detail_page.dart';
import '../shell/dunes_toast.dart';
import 'task_api.dart';
import 'task_link_api.dart';
import 'task_link_models.dart';
import 'task_models.dart';

const _purple = Color(0xFF7B5CD8);

/// 主任务详情的「关联会议与知识库」区块。
/// 手机与桌面共用；全部交互鼠标可用，不依赖滑动手势。
class TaskLinkSection extends StatefulWidget {
  const TaskLinkSection({
    super.key,
    required this.session,
    required this.task,
    required this.canEdit,
    this.onTaskChanged,
  });

  final AuthSession session;
  final TaskItem task;
  final bool canEdit;

  /// 补充描述后通知父级刷新任务详情。
  final VoidCallback? onTaskChanged;

  @override
  State<TaskLinkSection> createState() => _TaskLinkSectionState();
}

class _TaskLinkSectionState extends State<TaskLinkSection> {
  late final TaskLinkApi _api = TaskLinkApi(widget.session);
  List<TaskLink> _links = const [];
  TaskBindRun? _run;
  bool _loaded = false;
  bool _busy = false;
  Set<int> _knownIds = {};
  Set<int> _newIds = {};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  @override
  void didUpdateWidget(covariant TaskLinkSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _knownIds = {};
      _newIds = {};
      _load(initial: true);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final result = await _api.fetchLinks(widget.task.id);
      if (!mounted) return;
      final ids = result.links.map((l) => l.id).toSet();
      setState(() {
        if (!initial && _knownIds.isNotEmpty) {
          _newIds = ids.difference(_knownIds);
        }
        _knownIds = ids;
        _links = result.links;
        _run = result.bindRun;
        _loaded = true;
      });
      _managePolling();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  void _managePolling() {
    final running = _run?.isRunningFresh == true;
    if (running && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
    } else if (!running && _poll != null) {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// 本地先置为匹配中，立即出现「AI 匹配中…」再等后端。
  void _markRunningLocally() {
    setState(() {
      _run = TaskBindRun(status: 'running', updatedAt: DateTime.now());
    });
    _managePolling();
  }

  Future<void> _rematch() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _api.rematch(widget.task.id);
      if (!mounted) return;
      showDunesCenterToast(context, '已开始 AI 匹配');
      _markRunningLocally();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteLink(TaskLink link) async {
    if (_busy) return;
    // 中间确认弹框（替代底部撤销 Snackbar，桌面端体验一致且不会残留）
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('解除关联'),
        content: Text(
          '确定解除与「${link.title}」的关联吗？\n仅解除关联，${link.kind == 'kb' ? '知识库文档' : '会议纪要'}本身不受影响。',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE35D6A),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.deleteLink(widget.task.id, link.id);
      if (!mounted) return;
      setState(() {
        _links = _links.where((l) => l.id != link.id).toList(growable: false);
      });
      showDunesCenterToast(context, '已解除关联');
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPicker() async {
    final picked = await _showLinkPicker();
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.addLink(widget.task.id, picked);
      if (!mounted) return;
      showDunesCenterToast(context, '已添加关联');
      await _load();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, dynamic>?> _showLinkPicker() {
    final picker = _TaskLinkPicker(api: _api, taskId: widget.task.id);
    if (isDesktopCommOnly) {
      return showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
            child: picker,
          ),
        ),
      );
    }
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) =>
          SizedBox(height: MediaQuery.sizeOf(ctx).height * 0.72, child: picker),
    );
  }

  Future<void> _editDescription() async {
    final ctrl = TextEditingController(text: widget.task.description);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('任务描述'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            maxLines: 5,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '写清楚任务内容与目标，AI 会自动关联相关会议纪要',
              filled: true,
              fillColor: const Color(0xFFF5F6F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _purple),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final text = ctrl.text.trim();
    if (text.isEmpty || text == widget.task.description.trim()) return;
    setState(() => _busy = true);
    try {
      await TaskApi(
        widget.session,
      ).patchTask(widget.task.id, {'description': text});
      if (!mounted) return;
      showDunesCenterToast(context, '已保存，AI 开始匹配相关会议');
      _markRunningLocally();
      widget.onTaskChanged?.call();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openLink(TaskLink link) {
    if (link.isMeeting && (link.meetingId ?? 0) > 0) {
      showNativeMeetingDetail(
        context: context,
        session: widget.session,
        meetingId: link.meetingId!,
      );
      return;
    }
    if ((link.kbDocumentId ?? 0) > 0) {
      _openKbDoc('${link.kbDocumentId}');
    }
  }

  void _openKbDoc(String docId) {
    Widget pageFor(VoidCallback onBack) =>
        NativeKbDocPage(session: widget.session, docId: docId, onBack: onBack);
    if (isDesktopCommOnly) {
      showDialog<void>(
        context: context,
        builder: (ctx) {
          final size = MediaQuery.sizeOf(ctx);
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 40,
              vertical: 28,
            ),
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 720,
                maxHeight: size.height * 0.88,
                minWidth: 480,
                minHeight: 420,
              ),
              child: Material(
                color: DunesColors.bgApp,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: SelectionArea(
                  child: pageFor(() => Navigator.of(ctx).maybePop()),
                ),
              ),
            ),
          );
        },
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          backgroundColor: DunesColors.bgApp,
          body: SafeArea(child: pageFor(() => Navigator.of(ctx).pop())),
        ),
      ),
    );
  }

  String _linkKindLabel(TaskLink link) {
    switch (link.linkKind) {
      case 'auto_sync':
        return 'AI';
      case 'user_create':
        return '创建';
      default:
        return '手动';
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _run?.isRunningFresh == true;
    final failed = _run?.status == 'failed';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '关联会议与知识库',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            if (running)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _purple,
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'AI 匹配中…',
                      style: TextStyle(fontSize: 12, color: _purple),
                    ),
                  ],
                ),
              ),
            if (widget.canEdit &&
                !running &&
                widget.task.description.trim().isNotEmpty)
              IconButton(
                tooltip: '重新匹配',
                visualDensity: VisualDensity.compact,
                onPressed: _busy ? null : _rematch,
                icon: const Icon(
                  Icons.autorenew,
                  size: 19,
                  color: DunesColors.text3,
                ),
              ),
            if (widget.canEdit)
              IconButton(
                tooltip: '添加关联',
                visualDensity: VisualDensity.compact,
                onPressed: _busy ? null : _openPicker,
                icon: const Icon(
                  Icons.add_link,
                  size: 20,
                  color: DunesColors.text3,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (failed && _links.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '自动匹配未完成${widget.canEdit ? '，可点右上角重新匹配' : ''}',
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
          ),
        if (!_loaded)
          const SizedBox(
            height: 44,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _purple,
                ),
              ),
            ),
          )
        else if (_links.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8EAED)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  running
                      ? 'AI 正在分析任务描述，匹配相关会议…'
                      : widget.task.description.trim().isEmpty && widget.canEdit
                      ? '还没有任务描述。写清楚任务内容，AI 会自动关联相关会议。'
                      : '暂无关联。AI 会根据描述匹配相关会议，也可手动添加会议或知识库文档。',
                  style: const TextStyle(
                    fontSize: 13,
                    color: DunesColors.text3,
                    height: 1.5,
                  ),
                ),
                if (widget.task.description.trim().isEmpty &&
                    widget.canEdit &&
                    !running) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _editDescription,
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text('填写描述'),
                  ),
                ],
              ],
            ),
          )
        else
          for (final link in _links) _buildLinkRow(link),
      ],
    );
  }

  Widget _buildLinkRow(TaskLink link) {
    final subtitle = link.matchReason.trim().isNotEmpty
        ? link.matchReason.trim()
        : link.decisionExcerpt.trim();
    final isNew = _newIds.contains(link.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openLink(link),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isNew
                    ? _purple.withValues(alpha: 0.55)
                    : const Color(0xFFE8EAED),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  link.isMeeting
                      ? Icons.event_note_outlined
                      : Icons.menu_book_outlined,
                  size: 20,
                  color: link.isMeeting ? _purple : const Color(0xFF2D8A5E),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              link.title.isEmpty
                                  ? (link.isMeeting ? '会议纪要' : '知识库文档')
                                  : link.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _TagChip(
                            text: _linkKindLabel(link),
                            color: link.isAuto ? _purple : DunesColors.text3,
                          ),
                          if (isNew) ...[
                            const SizedBox(width: 4),
                            const _TagChip(text: '新', color: Color(0xFFE35D6A)),
                          ],
                        ],
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: DunesColors.text3,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.canEdit)
                  IconButton(
                    tooltip: '解除关联',
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : () => _deleteLink(link),
                    icon: const Icon(
                      Icons.link_off,
                      size: 18,
                      color: DunesColors.text3,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// 添加关联选择器：搜索 + 「可能相关」分组 + 会议 / 知识库文档（不含入库纪要）。
class _TaskLinkPicker extends StatefulWidget {
  const _TaskLinkPicker({required this.api, required this.taskId});

  final TaskLinkApi api;
  final int taskId;

  @override
  State<_TaskLinkPicker> createState() => _TaskLinkPickerState();
}

class _TaskLinkPickerState extends State<_TaskLinkPicker> {
  TaskLinkCandidates _candidates = const TaskLinkCandidates();
  bool _loading = true;
  String? _error;
  String _query = '';

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
      final c = await widget.api.fetchCandidates(widget.taskId);
      final docs = await _loadNonMeetingKbDocs(c);
      if (!mounted) return;
      setState(() {
        _candidates = TaskLinkCandidates(meetings: c.meetings, docs: docs);
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

  bool _matches(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  Future<List<TaskLinkCandidateDoc>> _loadNonMeetingKbDocs(
    TaskLinkCandidates candidates,
  ) async {
    final meetingKbIds = {
      for (final m in candidates.meetings)
        if (m.kbDocumentId > 0) m.kbDocumentId,
    };
    final linkedKb = {
      for (final d in candidates.docs)
        if (d.linked && d.kbDocumentId > 0) d.kbDocumentId,
    };
    try {
      final links = await widget.api.fetchLinks(widget.taskId);
      for (final link in links.links) {
        final id = link.kbDocumentId;
        if (id != null && id > 0) linkedKb.add(id);
      }
    } catch (_) {}

    final byId = <int, TaskLinkCandidateDoc>{};
    for (final d in candidates.docs) {
      if (d.kbDocumentId <= 0 ||
          d.meetingId > 0 ||
          meetingKbIds.contains(d.kbDocumentId) ||
          _looksLikeMeetingMinutesTitle(d.title)) {
        continue;
      }
      byId[d.kbDocumentId] = d;
    }

    NativeKbService? kb;
    try {
      kb = NativeKbService(session: widget.api.session);
      final page = await kb.listDocuments(size: 80);
      for (final doc in page.items) {
        if (_looksLikeMeetingMinutesDoc(doc)) continue;
        final id = int.tryParse(doc.dunesDocumentId) ?? 0;
        if (id <= 0 || meetingKbIds.contains(id)) continue;
        byId.putIfAbsent(
          id,
          () => TaskLinkCandidateDoc(
            kbDocumentId: id,
            title: doc.title.trim().isEmpty ? doc.fileName : doc.title.trim(),
            linked: linkedKb.contains(id),
          ),
        );
      }
    } catch (_) {
      // 知识库列表失败时仍展示会议；文档组为空即可。
    } finally {
      kb?.close();
    }

    final docs = byId.values.toList(growable: false);
    return [
      for (final d in docs)
        TaskLinkCandidateDoc(
          kbDocumentId: d.kbDocumentId,
          title: d.title,
          meetingId: d.meetingId,
          score: d.score,
          linked: d.linked || linkedKb.contains(d.kbDocumentId),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final meetings = _candidates.meetings
        .where((m) => _matches('${m.title} ${m.summary}'))
        .toList(growable: false);
    final docs = _candidates.docs
        .where((d) => _matches(d.title))
        .toList(growable: false);
    final related = meetings
        .where((m) => m.score > 0 && !m.linked)
        .take(5)
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '添加关联',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.close,
                  size: 20,
                  color: DunesColors.text3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            autofocus: false,
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              hintText: '搜索会议或文档',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF5F6F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _purple))
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: const TextStyle(fontSize: 13)),
                        TextButton(onPressed: _load, child: const Text('重试')),
                      ],
                    ),
                  )
                : ListView(
                    children: [
                      if (related.isNotEmpty) ...[
                        const _PickerGroupLabel('可能相关'),
                        for (final m in related)
                          _meetingRow(m, highlight: true),
                      ],
                      const _PickerGroupLabel('我主持的会议'),
                      if (meetings.isEmpty) const _PickerEmptyHint('没有可关联的会议'),
                      for (final m in meetings) _meetingRow(m),
                      const _PickerGroupLabel('知识库文档'),
                      if (docs.isEmpty) const _PickerEmptyHint('没有可关联的知识库文档'),
                      for (final doc in docs) _docRow(doc),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _meetingRow(TaskLinkCandidateMeeting m, {bool highlight = false}) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(
        Icons.event_note_outlined,
        size: 20,
        color: highlight ? _purple : DunesColors.text3,
      ),
      title: Text(
        m.title.isEmpty ? '会议 ${m.meetingId}' : m.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: m.meetingDate.isEmpty
          ? null
          : Text(m.meetingDate, style: const TextStyle(fontSize: 12)),
      trailing: m.linked
          ? const Text(
              '已关联',
              style: TextStyle(fontSize: 12, color: DunesColors.text3),
            )
          : null,
      enabled: !m.linked,
      onTap: m.linked
          ? null
          : () => Navigator.of(context).pop(<String, dynamic>{
              'kind': 'meeting',
              'meetingId': m.meetingId,
              'title': m.title,
            }),
    );
  }

  Widget _docRow(TaskLinkCandidateDoc doc) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Icon(
        Icons.menu_book_outlined,
        size: 20,
        color: Color(0xFF2D8A5E),
      ),
      title: Text(
        doc.title.isEmpty ? '文档 ${doc.kbDocumentId}' : doc.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      trailing: doc.linked
          ? const Text(
              '已关联',
              style: TextStyle(fontSize: 12, color: DunesColors.text3),
            )
          : null,
      enabled: !doc.linked,
      onTap: doc.linked
          ? null
          : () => Navigator.of(context).pop(<String, dynamic>{
              'kind': 'kb',
              'kbDocumentId': doc.kbDocumentId,
              'title': doc.title,
            }),
    );
  }
}

bool _looksLikeMeetingMinutesTitle(String title) {
  final name = title.trim().toLowerCase();
  return name.contains('会议纪要') || name.contains('meeting-minutes');
}

bool _looksLikeMeetingMinutesDoc(NativeKbDocument doc) {
  return _looksLikeMeetingMinutesTitle('${doc.title} ${doc.fileName}');
}

class _PickerGroupLabel extends StatelessWidget {
  const _PickerGroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: DunesColors.text3,
        ),
      ),
    );
  }
}

class _PickerEmptyHint extends StatelessWidget {
  const _PickerEmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: DunesColors.text3),
      ),
    );
  }
}
