import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import '../tasks/native_task_home_pane.dart';
import 'travel_import_service.dart';

const _themePurple = Color(0xFF7B5CD8);
const _pageSize = 20;

class NativeTravelImportPage extends StatefulWidget {
  const NativeTravelImportPage({
    super.key,
    required this.session,
    this.onChromeChanged,
  });

  final AuthSession session;
  final ValueChanged<TaskShellChrome>? onChromeChanged;

  @override
  State<NativeTravelImportPage> createState() => _NativeTravelImportPageState();
}

class _NativeTravelImportPageState extends State<NativeTravelImportPage> {
  late final TravelImportService _service;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _keywordCtrl = TextEditingController();
  Timer? _keywordDebounce;

  String _kind = 'flight';
  String _match = '';
  int _page = 0;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _uploading = false;
  bool _fileDragging = false;
  String? _error;
  List<TravelOrderRow> _items = const [];
  TravelImportPreview? _preview;
  final Map<String, TravelNameAssignment> _assignments = {};

  bool get _supportsDesktopDrop {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  static const _kinds = [
    ('flight', '机票'),
    ('hotel', '酒店'),
    ('train', '火车'),
    ('ground', '用车'),
  ];

  bool get _hasFilters =>
      _keywordCtrl.text.trim().isNotEmpty ||
      _match == 'unmatched' ||
      _match == 'ambiguous';

  @override
  void initState() {
    super.initState();
    _service = TravelImportService(session: widget.session);
    _scrollController.addListener(_onScroll);
    _keywordCtrl.addListener(_onKeywordChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishChrome();
    });
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _keywordDebounce?.cancel();
    _scrollController.dispose();
    _keywordCtrl.dispose();
    widget.onChromeChanged?.call(const TaskShellChrome());
    super.dispose();
  }

  void _publishChrome() {
    widget.onChromeChanged?.call(
      TaskShellChrome(
        trailing: IconButton(
          tooltip: _uploading ? '处理中…' : '上传携程 Excel',
          onPressed: _uploading ? null : _pickAndPreview,
          icon: const Icon(Icons.upload_file_outlined),
        ),
      ),
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        !_hasMore) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 220) {
      unawaited(_loadMore());
    }
  }

  void _onKeywordChanged() {
    setState(() {});
    _keywordDebounce?.cancel();
    _keywordDebounce = Timer(const Duration(milliseconds: 320), _reloadFromTop);
  }

  void _reloadFromTop() {
    if (!mounted) return;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    unawaited(_load(reset: true));
  }

  void _selectKind(String kind) {
    if (_kind == kind) return;
    _keywordDebounce?.cancel();
    setState(() => _kind = kind);
    _reloadFromTop();
  }

  void _toggleUnmatched(bool selected) {
    _keywordDebounce?.cancel();
    setState(() => _match = selected ? 'unmatched' : '');
    _reloadFromTop();
  }

  void _clearFilters() {
    _keywordDebounce?.cancel();
    _keywordCtrl.removeListener(_onKeywordChanged);
    _keywordCtrl.clear();
    _keywordCtrl.addListener(_onKeywordChanged);
    setState(() => _match = '');
    _reloadFromTop();
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        if (_items.isEmpty) _loading = true;
        _error = null;
      });
    }
    try {
      final result = await _service.list(
        kind: _kind,
        match: _match,
        q: _keywordCtrl.text,
        page: 0,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _page = 0;
        _total = result.total;
        _hasMore =
            result.items.length >= _pageSize &&
            result.items.length < result.total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final result = await _service.list(
        kind: _kind,
        match: _match,
        q: _keywordCtrl.text,
        page: nextPage,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...result.items];
        _page = nextPage;
        _total = result.total;
        _hasMore =
            result.items.length >= _pageSize &&
            _items.length < result.total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _pickAndPreview() async {
    if (_uploading) return;
    final group = XTypeGroup(label: 'Excel', extensions: const ['xlsx']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    await _previewFile(
      bytes: await file.readAsBytes(),
      fileName: file.name.isEmpty ? 'ctrip.xlsx' : file.name,
    );
  }

  Future<void> _onFilesDropped(DropDoneDetails detail) async {
    if (_uploading || !_dropLive) return;
    setState(() => _fileDragging = false);
    final files = <XFile>[];
    for (final item in detail.files) {
      if (item is DropItemDirectory) continue;
      files.add(XFile(item.path, name: item.name));
    }
    if (files.isEmpty) {
      showDunesToast(context, '请拖入文件（不支持文件夹）', kind: DunesToastKind.error);
      return;
    }
    final xlsx = files
        .where((f) => f.name.toLowerCase().endsWith('.xlsx'))
        .toList();
    if (xlsx.isEmpty) {
      showDunesToast(context, '请拖入携程 .xlsx 文件', kind: DunesToastKind.error);
      return;
    }
    if (xlsx.length > 1) {
      showDunesToast(context, '一次只能导入一个文件，已取第一个');
    }
    final file = xlsx.first;
    await _previewFile(
      bytes: await file.readAsBytes(),
      fileName: file.name.isEmpty ? 'ctrip.xlsx' : file.name,
    );
  }

  Future<void> _previewFile({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (_uploading) return;
    setState(() => _uploading = true);
    _publishChrome();
    try {
      final preview = await _service.preview(bytes: bytes, fileName: fileName);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _assignments.clear();
        _uploading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '解析 Excel 失败'),
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) _publishChrome();
    }
  }

  Future<void> _commit() async {
    final preview = _preview;
    if (preview == null || preview.previewToken.isEmpty) return;
    final leftover = [
      ...preview.unmatchedNames,
      ...preview.ambiguousNames,
    ].where((n) => !_assignments.containsKey(n)).length;
    if (leftover > 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('仍有姓名未指定'),
          content: Text('还有 $leftover 个出行人未关联组织用户，导入后不会进入差旅地图。确定继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('返回指定'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _themePurple),
              child: const Text('仍导入'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    setState(() => _uploading = true);
    _publishChrome();
    try {
      final result = await _service.commit(
        preview.previewToken,
        assignments: _assignments.values.toList(),
      );
      if (!mounted) return;
      setState(() {
        _preview = null;
        _assignments.clear();
        _uploading = false;
      });
      showDunesToast(
        context,
        leftover > 0
            ? '已导入，未关联 ${result.unmatched} · 重名 ${result.ambiguous}'
            : '导入完成',
      );
      _reloadFromTop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = '$e';
      });
    } finally {
      if (mounted) _publishChrome();
    }
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _pickPerson(String travelerName) async {
    final person = await showTravelUserPicker(
      context,
      service: _service,
      travelerName: travelerName,
    );
    if (person == null || !mounted) return;
    setState(() {
      _assignments[travelerName] = TravelNameAssignment(
        travelerName: travelerName,
        userId: person.userId,
        displayName: person.displayName,
        dept: person.dept,
        saveAlias: false,
      );
    });
  }

  Future<bool> _askSaveAlias(String from, String to) async {
    if (from == to) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('记住别名？'),
        content: Text('将「$from」记为「$to」的别名，以后导入自动匹配。仅在确认后写入。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('仅本次'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _themePurple),
            child: const Text('记住'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _assignExisting(TravelOrderRow row) async {
    if (!row.unmatched && !row.ambiguous) return;
    final person = await showTravelUserPicker(
      context,
      service: _service,
      travelerName: row.travelerName,
    );
    if (person == null || !mounted) return;
    final saveAlias = await _askSaveAlias(row.travelerName, person.displayName);
    if (!mounted) return;
    try {
      final n = await _service.assign(
        TravelNameAssignment(
          travelerName: row.travelerName,
          userId: person.userId,
          displayName: person.displayName,
          saveAlias: saveAlias,
        ),
      );
      if (!mounted) return;
      showDunesToast(
        context,
        saveAlias
            ? '已指定 ${person.displayName}，并记住别名，更新 $n 条'
            : '已指定 ${person.displayName}，更新 $n 条',
      );
      _reloadFromTop();
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '指定失败'),
        kind: DunesToastKind.error,
      );
    }
  }

  bool get _dropLive => TickerMode.valuesOf(context).enabled;

  Widget _wrapDrop(Widget child) {
    if (!_supportsDesktopDrop) return child;
    return DropTarget(
      // 工作台 keep-alive 切走后页面仍挂在树上；desktop_drop 是窗口级监听，
      // 不看 Offstage/IgnorePointer。未加 enable 时，在 IM 里拖文件也会
      // 误报「请拖入携程 .xlsx 文件」。
      enable: _dropLive && !_uploading,
      onDragEntered: (_) {
        if (!_dropLive) return;
        setState(() => _fileDragging = true);
      },
      onDragExited: (_) {
        if (_fileDragging) setState(() => _fileDragging = false);
      },
      onDragDone: (d) {
        if (!_dropLive) return;
        unawaited(_onFilesDropped(d));
      },
      child: child,
    );
  }

  Widget _buildDropZone() {
    final hint = _uploading
        ? '处理中…'
        : (_supportsDesktopDrop || isDesktopCommOnly
            ? '点击选择，或拖拽携程 Excel 到此处'
            : '点击选择携程 Excel');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: _fileDragging
            ? _themePurple.withValues(alpha: 0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _uploading ? null : _pickAndPreview,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _fileDragging
                    ? _themePurple.withValues(alpha: 0.45)
                    : const Color(0xFFE8EAED),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.upload_file_outlined,
                  color: _fileDragging ? _themePurple : DunesColors.text3,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hint,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _fileDragging ? _themePurple : DunesColors.text2,
                        ),
                      ),
                      const Text(
                        '仅 .xlsx · 机票 / 酒店 / 火车 / 用车',
                        style: TextStyle(fontSize: 11, color: DunesColors.text3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _wrapDrop(
      GestureDetector(
      onTap: _dismissKeyboard,
      behavior: HitTestBehavior.translucent,
      child: ColoredBox(
        color: const Color(0xFFF5F6F8),
        child: Stack(
          children: [
            Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _keywordCtrl,
                      onTapOutside: (_) => _dismissKeyboard(),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: '搜索出行人、组织用户或订单号',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _keywordCtrl.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: _keywordCtrl.clear,
                                icon: const Icon(Icons.close, size: 18),
                              ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE8EAED)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE8EAED)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _uploading ? null : _pickAndPreview,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: Text(_uploading ? '处理中…' : '上传'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _themePurple,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < _kinds.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      _FilterChip(
                        label: _kinds[i].$2,
                        active: _kind == _kinds[i].$1,
                        onTap: () => _selectKind(_kinds[i].$1),
                      ),
                    ],
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: '仅未关联',
                      active: _match == 'unmatched',
                      emphasize: true,
                      onTap: () => _toggleUnmatched(_match != 'unmatched'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: '仅重名',
                      active: _match == 'ambiguous',
                      emphasize: true,
                      onTap: () {
                        _keywordDebounce?.cancel();
                        setState(() =>
                            _match = _match == 'ambiguous' ? '' : 'ambiguous');
                        _reloadFromTop();
                      },
                    ),
                  ],
                ),
              ),
            ),
            _buildDropZone(),
            if (_preview != null)
              _PreviewBanner(
                preview: _preview!,
                assignments: _assignments,
                onAssign: (name) => unawaited(_pickPerson(name)),
                onToggleAlias: (name, save) {
                  final cur = _assignments[name];
                  if (cur == null) return;
                  setState(() {
                    _assignments[name] = TravelNameAssignment(
                      travelerName: cur.travelerName,
                      userId: cur.userId,
                      displayName: cur.displayName,
                      dept: cur.dept,
                      saveAlias: save,
                    );
                  });
                },
                onCommit: _commit,
                onDismiss: () => setState(() {
                  _preview = null;
                  _assignments.clear();
                }),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Text(
                    '$_total 条',
                    style: const TextStyle(fontSize: 12, color: DunesColors.text3),
                  ),
                  if (_hasFilters) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _clearFilters,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        foregroundColor: _themePurple,
                      ),
                      child: const Text('清除筛选'),
                    ),
                  ],
                ],
              ),
            ),
            if (_error != null && _items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFB42318), fontSize: 12),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(reset: true),
                child: _buildListBody(),
              ),
            ),
          ],
        ),
            if (_fileDragging)
              const Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Color(0x337B5CD8),
                    child: Center(
                      child: Text(
                        '松开以上传携程 Excel',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _themePurple,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildListBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: DunesColors.text2),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: () => unawaited(_load(reset: true)),
              style: FilledButton.styleFrom(backgroundColor: _themePurple),
              child: const Text('重试'),
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              _hasFilters ? '没有符合筛选条件的订单' : '暂无导入数据，点击上传或拖入携程 Excel',
              style: const TextStyle(color: DunesColors.text3, fontSize: 14),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _OrderTile(
          row: _items[index],
          onAssign: (_items[index].unmatched || _items[index].ambiguous)
              ? () => unawaited(_assignExisting(_items[index]))
              : null,
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.emphasize = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final color = emphasize && active ? const Color(0xFFB42318) : _themePurple;
    return Material(
      color: active ? color : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? color : const Color(0xFFE8EAED),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : DunesColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner({
    required this.preview,
    required this.assignments,
    required this.onAssign,
    required this.onToggleAlias,
    required this.onCommit,
    required this.onDismiss,
  });
  final TravelImportPreview preview;
  final Map<String, TravelNameAssignment> assignments;
  final ValueChanged<String> onAssign;
  final void Function(String name, bool saveAlias) onToggleAlias;
  final VoidCallback onCommit;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final pending = <(String, String)>[];
    final seen = <String>{};
    for (final n in preview.unmatchedNames) {
      if (seen.add(n)) pending.add((n, 'unmatched'));
    }
    for (final n in preview.ambiguousNames) {
      if (seen.add(n)) pending.add((n, 'ambiguous'));
    }
    final assignedCount = pending.where((e) => assignments.containsKey(e.$1)).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${preview.fileName} · ${preview.total} 行 · 匹配 ${preview.matched} · 未关联 ${preview.unmatched} · 重名 ${preview.ambiguous} · 分摊 ${preview.shared}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '需手工指定 $assignedCount / ${pending.length}',
              style: const TextStyle(fontSize: 12, color: DunesColors.text2),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: pending.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final name = pending[i].$1;
                  final kind = pending[i].$2;
                  final a = assignments[name];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                a == null
                                    ? (kind == 'ambiguous' ? '重名未指定' : '未关联组织用户')
                                    : '${a.displayName}${a.dept.isEmpty ? '' : ' · ${a.dept}'}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: a == null
                                      ? (kind == 'ambiguous'
                                          ? const Color(0xFFB54708)
                                          : const Color(0xFFB42318))
                                      : DunesColors.text2,
                                ),
                              ),
                              if (a != null && a.displayName != name)
                                Row(
                                  children: [
                                    SizedBox(
                                      height: 24,
                                      child: Checkbox(
                                        value: a.saveAlias,
                                        visualDensity: VisualDensity.compact,
                                        onChanged: (v) =>
                                            onToggleAlias(name, v ?? true),
                                      ),
                                    ),
                                    Text(
                                      '记住别名（${a.displayName}）',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: DunesColors.text3,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => onAssign(name),
                          child: Text(a == null ? '指定' : '改指定'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(onPressed: onDismiss, child: const Text('取消')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onCommit,
                style: FilledButton.styleFrom(backgroundColor: _themePurple),
                child: const Text('确认导入'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.row, this.onAssign});
  final TravelOrderRow row;
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onAssign,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE8EAED)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.travelerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.text,
                      ),
                    ),
                  ),
                  Text(
                    row.amountLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _themePurple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${row.origin} → ${row.destination}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: DunesColors.text2),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (row.unmatched)
                    const _Tag(text: '未关联组织用户', color: Color(0xFFB42318)),
                  if (row.ambiguous)
                    const _Tag(text: '重名未指定', color: Color(0xFFB54708)),
                  if (onAssign != null)
                    const _Tag(text: '点此指定', color: _themePurple),
                  if (row.shared)
                    const _Tag(text: '分摊', color: _themePurple),
                  if (row.userDisplayName.isNotEmpty)
                    _Tag(text: row.userDisplayName, color: DunesColors.text2),
                  if (row.startAt.isNotEmpty)
                    _Tag(text: row.startAt, color: DunesColors.text3),
                  if (row.orderId.isNotEmpty)
                    _Tag(text: row.orderId, color: DunesColors.text3),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

Future<TravelOrgPerson?> showTravelUserPicker(
  BuildContext context, {
  required TravelImportService service,
  required String travelerName,
}) {
  return showDialog<TravelOrgPerson>(
    context: context,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: SizedBox(
          width: size.width > 520 ? 440 : size.width,
          height: (size.height * 0.72).clamp(360.0, 560.0),
          child: _TravelUserPickerBody(
            service: service,
            travelerName: travelerName,
          ),
        ),
      );
    },
  );
}

class _TravelUserPickerBody extends StatefulWidget {
  const _TravelUserPickerBody({
    required this.service,
    required this.travelerName,
  });

  final TravelImportService service;
  final String travelerName;

  @override
  State<_TravelUserPickerBody> createState() => _TravelUserPickerBodyState();
}

class _TravelUserPickerBodyState extends State<_TravelUserPickerBody> {
  late final TextEditingController _q;
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<TravelOrgPerson> _items = const [];

  @override
  void initState() {
    super.initState();
    _q = TextEditingController(text: widget.travelerName);
    _q.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.travelerName.trim().isNotEmpty) unawaited(_search());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.removeListener(_onChanged);
    _q.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_search());
    });
  }

  Future<void> _search() async {
    final needle = _q.text.trim();
    if (needle.isEmpty) {
      setState(() {
        _items = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.service.searchPeople(needle);
      if (!mounted) return;
      if (_q.text.trim() != needle) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorText(e, fallback: '搜索失败');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '指定「${widget.travelerName}」',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            '搜索组织用户。别名不会自动写入，需在指定后确认。',
            style: TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _q,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => unawaited(_search()),
            decoration: InputDecoration(
              hintText: '输入姓名、工号或手机号',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _q.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _q.clear,
                      icon: const Icon(Icons.close, size: 18),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildResults()),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_q.text.trim().isEmpty) {
      return const Center(
        child: Text(
          '输入关键词后搜索',
          style: TextStyle(color: DunesColors.text3),
        ),
      );
    }
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Color(0xFFB42318))),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          '没有匹配的组织用户',
          style: TextStyle(color: DunesColors.text3),
        ),
      );
    }
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final p = _items[i];
        final meta = [
          if (p.dept.isNotEmpty) p.dept,
          if (p.title.isNotEmpty) p.title,
        ].join(' · ');
        return ListTile(
          dense: true,
          title: Text(
            p.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: meta.isEmpty ? null : Text(meta),
          onTap: () => Navigator.pop(context, p),
        );
      },
    );
  }
}
