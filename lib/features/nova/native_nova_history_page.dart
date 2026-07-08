import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'native_nova_service.dart';
import 'nova_history_utils.dart';
import 'nova_widgets.dart';

class NativeNovaHistoryPage extends StatefulWidget {
  const NativeNovaHistoryPage({
    super.key,
    required this.session,
    required this.onBack,
    required this.onOpenConversation,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final void Function(int conversationId, int messageId, String title, String preview) onOpenConversation;

  @override
  State<NativeNovaHistoryPage> createState() => _NativeNovaHistoryPageState();
}

class _NativeNovaHistoryPageState extends State<NativeNovaHistoryPage> {
  late final NativeNovaService _service;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _searchOpen = false;
  String? _error;
  String _oldestAt = '';
  List<NovaHistoryTurn> _all = const <NovaHistoryTurn>[];
  List<NovaHistoryTurn> _visible = const <NovaHistoryTurn>[];

  @override
  void initState() {
    super.initState();
    _service = NativeNovaService(session: widget.session);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (append) {
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _oldestAt = '';
      });
    }
    try {
      final page = await _service.fetchHistoryTurns(size: 20, before: append ? _oldestAt : '');
      if (!mounted) return;
      setState(() {
        if (append) {
          _all = [..._all, ...page.items];
        } else {
          _all = page.items;
        }
        _hasMore = page.hasMore;
        if (page.items.isNotEmpty) {
          final last = page.items.last.lastMessageAt;
          if (last != null) _oldestAt = last.toIso8601String();
        }
        _applyFilter(_searchController.text);
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = NativeNovaService.friendlyError(e);
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _applyFilter(String q) {
    final keyword = q.trim().toLowerCase();
    if (keyword.isEmpty) {
      _visible = _all;
      return;
    }
    _visible = _all.where((t) {
      return t.title.toLowerCase().contains(keyword) || t.preview.toLowerCase().contains(keyword);
    }).toList(growable: false);
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchController.clear();
        _applyFilter('');
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _applyFilter(''));
  }

  List<Widget> _buildRows() {
    final widgets = <Widget>[];
    DateTime? prevDay;
    for (var i = 0; i < _visible.length; i++) {
      final t = _visible[i];
      final at = t.lastMessageAt;
      final dayLabel = historyDayDividerLabel(at, prevDay);
      if (dayLabel != null) {
        widgets.add(NovaHistoryDayLabel(label: dayLabel));
        prevDay = at;
      } else if (prevDay == null && at != null) {
        prevDay = at;
      }
      widgets.add(
        NovaHistoryCard(
          title: t.title.isEmpty ? '新对话' : t.title,
          preview: t.preview.isEmpty ? '（暂无消息预览）' : t.preview,
          timeLabel: formatNovaHistoryTime(at),
          onTap: () => widget.onOpenConversation(t.conversationId, t.messageId, t.title, t.preview),
        ),
      );
    }
    if (_hasMore) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: _loadingMore
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(
                    onPressed: () => _load(append: true),
                    child: const Text('加载更多历史'),
                  ),
          ),
        ),
      );
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NovaC11Header(
              onBack: widget.onBack,
              onToggleSearch: _toggleSearch,
              searchOpen: _searchOpen,
            ),
            if (_searchOpen)
              NovaC11SearchBar(
                controller: _searchController,
                onChanged: (v) => setState(() => _applyFilter(v)),
                onClear: _clearSearch,
              ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: DunesColors.text3)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => _load(), child: const Text('重试')),
          ],
        ),
      );
    }
    if (_visible.isEmpty) {
      return const Center(child: Text('暂无历史对话', style: TextStyle(color: DunesColors.text3)));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: _buildRows(),
    );
  }
}
