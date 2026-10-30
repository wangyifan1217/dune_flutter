import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_main_tab_bar.dart';
import '../shell/dunes_toast.dart';
import '../chat/file_download.dart' as file_dl;
import 'qianji_chat_service.dart';

const qianjiAllScopes = '全部板块';

const _purple = Color(0xFF6C5CE7);
const _purpleLight = Color(0xFF7B6CF0);
const _purpleDeep = Color(0xFF5A4BD6);
const _ink = Color(0xFF1F2329);
const _muted = Color(0xFF8A919F);
const _faint = Color(0xFFB0B6C0);
const _line = Color(0xFFECEEF2);
const _soft = Color(0xFFF7F8FA);
const _softLine = Color(0xFFECEEF2);
const _tint = Color(0xFFF7F8FA);
const _page = Color(0xFFFFFFFF);
const _glow = Color(0xFFFFFFFF);
const _selectedBg = Color(0xFFF3F0FF);
const _hoverBg = Color(0xFFEEF0F3);
const _disabled = Color(0xFFC9CDD4);
const _aiBorder = Color(0xFFE5E6EB);
const _errorRed = Color(0xFFF53F3F);

const qianjiScopeIcons = <String, IconData>{
  qianjiAllScopes: Icons.auto_awesome_rounded,
  '资金流向': Icons.account_balance_rounded,
  '月结': Icons.receipt_long_rounded,
  '资金借调': Icons.account_balance_wallet_rounded,
  '差旅管理': Icons.flight_takeoff_rounded,
  '工作情况': Icons.groups_outlined,
  '员工画像': Icons.person_search_rounded,
  '使用热力': Icons.grid_view_rounded,
  '会议纪要': Icons.fact_check_outlined,
  'IM会话': Icons.forum_outlined,
  '知识库': Icons.folder_shared_outlined,
  '任务': Icons.task_alt_outlined,
  '日报': Icons.edit_calendar_outlined,
  '群响应': Icons.mark_chat_unread_outlined,
  '提案时效': Icons.timer_outlined,
  '研发账号': Icons.manage_accounts_outlined,
};

class QianjiChatScope {
  const QianjiChatScope(this.label, this.onOpen);

  final String label;

  /// 原页面入口；为 null 时该板块不可选。
  final VoidCallback? onOpen;
}

class QianjiChatScopeGroup {
  const QianjiChatScopeGroup(
    this.title,
    this.scopes, {
    this.initiallyExpanded = false,
  });

  final String title;
  final List<QianjiChatScope> scopes;
  final bool initiallyExpanded;
}

class _Example {
  const _Example({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
    this.scope,
    this.selectEnd = 0,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final String? scope;

  /// 大于 0 时只填入输入框并选中前 N 个字符，方便直接改成真实姓名或部门。
  final int selectEnd;
}

const _examples = <_Example>[
  _Example(
    icon: Icons.person_search_rounded,
    color: Color(0xFF6B5CE8),
    title: '按人查询',
    text: '张三的知识库有多少文档',
    selectEnd: 2,
  ),
  _Example(
    icon: Icons.apartment_rounded,
    color: Color(0xFF4884E8),
    title: '按部门查询',
    text: '技术部的知识库有多少文档',
    selectEnd: 3,
  ),
  _Example(
    icon: Icons.account_balance_rounded,
    color: Color(0xFF2E7D32),
    title: '资金看板',
    text: '资金流向概览',
    scope: '资金流向',
  ),
  _Example(
    icon: Icons.receipt_long_rounded,
    color: Color(0xFF7B5CD8),
    title: '月结账单',
    text: '月结应收逾期多少？',
    scope: '月结',
  ),
  _Example(
    icon: Icons.task_alt_outlined,
    color: Color(0xFF2F8F7E),
    title: '我的任务',
    text: '我的进行中任务有多少？',
    scope: '任务',
  ),
  _Example(
    icon: Icons.grid_view_rounded,
    color: Color(0xFFD67E33),
    title: '使用热力',
    text: '本月使用热力概览',
    scope: '使用热力',
  ),
];

List<String> qianjiScopeSuggestions(String scope) => switch (scope) {
  '资金流向' => const ['资金流向概览', '资金流向流水列表'],
  '月结' => const ['月结概览', '应收账单列表', '应付账单列表', '应收逾期多少？', '应付逾期多少？'],
  '资金借调' => const ['资金借调有多少条记录？', '资金借调未结清列表', '资金借调逾期多少？'],
  '任务' => const ['我的任务有多少？', '我的进行中任务列表', '我的已完成任务有多少？'],
  '知识库' => const ['知识库有多少文档？', '知识库人员列表'],
  'IM会话' => const ['IM会话有多少？', 'IM会话人员列表'],
  '会议纪要' => const ['会议纪要有多少？', '会议纪要列表'],
  '使用热力' => const ['使用热力概览', '使用热力有多少人？'],
  '研发账号' => const ['研发账号有多少？'],
  '提案时效' => const ['提案时效有多少提案？', '提案时效列表'],
  '差旅管理' || '工作情况' || '员工画像' => ['$scope有多少人？'],
  '日报' || '群响应' => ['$scope有多少？'],
  _ => const [],
};

/// 新版饕：独立对话查询页。会话与小饕历史不共用，结果按当前权限实时重查。
class QianjiChatPanel extends StatefulWidget {
  const QianjiChatPanel({
    super.key,
    required this.scopeGroups,
    required this.onSwitchLegacy,
    this.session,
    this.chatService,
  });

  final List<QianjiChatScopeGroup> scopeGroups;
  final VoidCallback onSwitchLegacy;
  final AuthSession? session;
  final QianjiChatService? chatService;

  @override
  State<QianjiChatPanel> createState() => _QianjiChatPanelState();
}

class _QianjiChatPanelState extends State<QianjiChatPanel>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scroll = ScrollController();
  late final AnimationController _sidebarAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 200),
  );
  late final _sidebarCurve = CurvedAnimation(
    parent: _sidebarAnim,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  bool _sidebarOpen = false;
  bool _composerFocused = false;
  int _view = 0;
  Object? _freshReplyId;
  bool _sidebarInitialized = false;
  bool _wide = false;
  String _scope = qianjiAllScopes;

  List<dynamic> _history = [];
  bool _historyHasMore = false;
  bool _historyLoading = false;
  bool _historyExpanded = false;
  List<dynamic> _turns = [];
  int? _chatId;
  bool _busy = false;
  final Set<int> _exportingTurnIds = <int>{};
  bool _hasOlder = false;
  String? _error;
  String? _pendingQuestion;
  String? _failedQuestion;
  int _generation = 0;
  bool? _visible;
  bool _sessionRestored = false;
  final Map<String, bool> _groupExpanded = {};
  final _sidebarScroll = ScrollController();

  QianjiChatService? get _service =>
      widget.chatService ??
      (widget.session == null ? null : QianjiChatService(widget.session!));

  Map<String, VoidCallback?> get _scopeActions => {
    for (final group in widget.scopeGroups)
      for (final scope in group.scopes) scope.label: scope.onOpen,
  };

  bool _scopeEnabled(String scope) =>
      scope == qianjiAllScopes || _scopeActions[scope] != null;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_composerFocused != _focusNode.hasFocus) {
        setState(() => _composerFocused = _focusNode.hasFocus);
      }
    });
    _controller.addListener(_onDraftChanged);
    unawaited(_restoreSessionThenLoad());
  }

  String get _prefsPrefix {
    final uid = widget.session?.userId ?? 'anon';
    final base = widget.session?.apiBase ?? '';
    return 'qianji_chat_${uid}_$base';
  }

  void _onDraftChanged() {
    // Debounce-ish: persist draft without setState.
    unawaited(_persistSession());
  }

  Future<void> _restoreSessionThenLoad() async {
    await _restoreSession();
    if (!mounted) return;
    unawaited(_loadHistory());
    final id = _chatId;
    if (id != null) unawaited(_openChat(id));
  }

  Future<void> _restoreSession() async {
    if (_sessionRestored) return;
    _sessionRestored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefix = _prefsPrefix;
      final chatId = prefs.getInt('${prefix}_chatId');
      final scope = prefs.getString('${prefix}_scope');
      final draft = prefs.getString('${prefix}_draft') ?? '';
      final sidebarOpen = prefs.getBool('${prefix}_sidebarOpen') ?? false;
      final historyExpanded =
          prefs.getBool('${prefix}_historyExpanded') ?? false;
      final groups =
          prefs.getStringList('${prefix}_groups') ?? const <String>[];
      if (!mounted) return;
      setState(() {
        if (chatId != null) _chatId = chatId;
        if (scope != null && scope.isNotEmpty) _scope = scope;
        if (draft.isNotEmpty) {
          _controller.value = TextEditingValue(
            text: draft,
            selection: TextSelection.collapsed(offset: draft.length),
          );
        }
        _historyExpanded = historyExpanded;
        for (final title in groups) {
          _groupExpanded[title] = true;
        }
        if (sidebarOpen) {
          _sidebarOpen = true;
          _sidebarAnim.value = 1;
          _sidebarInitialized = true;
        }
      });
    } catch (_) {
      // ignore restore failures
    }
  }

  Future<void> _persistSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefix = _prefsPrefix;
      final id = _chatId;
      if (id == null) {
        await prefs.remove('${prefix}_chatId');
      } else {
        await prefs.setInt('${prefix}_chatId', id);
      }
      await prefs.setString('${prefix}_scope', _scope);
      await prefs.setString('${prefix}_draft', _controller.text);
      await prefs.setBool('${prefix}_sidebarOpen', _sidebarOpen);
      await prefs.setBool('${prefix}_historyExpanded', _historyExpanded);
      await prefs.setStringList('${prefix}_groups', [
        for (final e in _groupExpanded.entries)
          if (e.value) e.key,
      ]);
    } catch (_) {
      // ignore persist failures
    }
  }

  void _setSidebar(bool open) {
    _sidebarOpen = open;
    if (open) {
      unawaited(_sidebarAnim.forward());
    } else {
      unawaited(_sidebarAnim.reverse());
    }
    unawaited(_persistSession());
  }

  void _toggleSidebar() => setState(() => _setSidebar(!_sidebarOpen));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Host keep-alive hides hub with TickerMode(false). Keep in-memory
    // chatId / turns / sidebar / scope / draft so leave+return restores.
    final visible = TickerMode.valuesOf(context).enabled;
    if (_visible == visible) return;
    final wasVisible = _visible;
    _visible = visible;
    if (visible && wasVisible == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _visible != true) return;
        unawaited(_loadHistory());
        final id = _chatId;
        if (id != null && _turns.isEmpty) unawaited(_openChat(id));
      });
    }
  }

  @override
  void didUpdateWidget(covariant QianjiChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatService == widget.chatService &&
        oldWidget.session == widget.session) {
      return;
    }
    final sameAccount =
        oldWidget.chatService == widget.chatService &&
        oldWidget.session?.userId == widget.session?.userId &&
        oldWidget.session?.apiBase == widget.session?.apiBase;
    final previousId = sameAccount ? _chatId : null;
    _generation++;
    _history = [];
    _historyHasMore = false;
    _historyLoading = false;
    _turns = [];
    _chatId = previousId;
    _hasOlder = false;
    _busy = false;
    _error = null;
    _pendingQuestion = null;
    _failedQuestion = null;
    if (!sameAccount) _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _visible != true) return;
      unawaited(_loadHistory());
      if (previousId != null) unawaited(_openChat(previousId));
    });
  }

  @override
  void dispose() {
    _sidebarAnim.dispose();
    _sidebarScroll.dispose();
    _controller.dispose();
    _focusNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.positions.last;
      unawaited(
        position.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  Future<void> _loadHistory({bool more = false}) async {
    final service = _service;
    final generation = _generation;
    if (service == null || _historyLoading) return;
    setState(() => _historyLoading = true);
    try {
      final history = await service.conversations(
        offset: more ? _history.length : 0,
      );
      if (mounted && generation == _generation) {
        setState(() {
          if (more) {
            final existing = _history.map((item) => item['id']).toSet();
            _history = [
              ..._history,
              ...history.where((item) => !existing.contains(item['id'])),
            ];
          } else {
            _history = history;
          }
          _historyHasMore = history.length == 30;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '无法读取对话历史，请稍后重试');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _historyLoading = false);
      }
    }
  }

  Future<void> _openChat(int id) async {
    final service = _service;
    final generation = _generation;
    if (service == null || _busy) return;
    if (_chatId == id && _turns.isNotEmpty && _error == null) {
      if (!_wide) setState(() => _setSidebar(false));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _failedQuestion = null;
      if (!_wide) _setSidebar(false);
      _chatId = null;
      _turns = [];
      _freshReplyId = null;
      _view++;
    });
    try {
      final turns = await service.turns(id);
      if (mounted && generation == _generation) {
        setState(() {
          _chatId = id;
          _turns = turns;
          _hasOlder = turns.length == 10;
        });
        unawaited(_persistSession());
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '无法读取此对话，请检查权限或稍后重试');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _loadOlder() async {
    final service = _service;
    final id = _chatId;
    final generation = _generation;
    if (service == null || id == null || _turns.isEmpty || _busy) return;
    final before = (_turns.first['id'] as num).toInt();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final older = await service.turns(id, before: before);
      if (mounted && generation == _generation && _chatId == id) {
        setState(() {
          _turns = [...older, ..._turns];
          _hasOlder = older.length == 10;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '无法读取更早的对话，请稍后重试');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _send([String? preset]) async {
    final service = _service;
    final generation = _generation;
    final scope = _scope;
    final question = (preset ?? _controller.text).trim();
    if (service == null || question.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _failedQuestion = null;
      _pendingQuestion = question;
      _controller.clear();
    });
    Map? autoExportTurn;
    _scrollToBottom();
    try {
      final id = _chatId ?? await service.create();
      if (!mounted || generation != _generation) return;
      if (_chatId == null) {
        setState(() => _chatId = id);
        unawaited(_persistSession());
      }
      final turn = await service.send(id, scope, question);
      final lowerQuestion = question.toLowerCase();
      if (turn['data'] != null &&
          (lowerQuestion.contains('excel') ||
              lowerQuestion.contains('导出') ||
              lowerQuestion.contains('下载') ||
              lowerQuestion.contains('生成表格') ||
              lowerQuestion.contains('生成工作簿')) &&
          '${turn['reply'] ?? ''}'.contains('可导出 Excel')) {
        autoExportTurn = turn;
      }
      if (mounted && generation == _generation) {
        setState(() {
          _turns = [..._turns, turn];
          _pendingQuestion = null;
          _freshReplyId = turn['id'];
        });
        _scrollToBottom();
      }
      await _loadHistory();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _pendingQuestion = null;
          _failedQuestion = question;
        });
        _scrollToBottom();
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
    if (autoExportTurn != null && mounted && generation == _generation) {
      await _exportTurn(autoExportTurn);
    }
  }

  void _newChat() {
    if (_busy) return;
    setState(() {
      _chatId = null;
      _turns = [];
      _hasOlder = false;
      _error = null;
      _failedQuestion = null;
      _freshReplyId = null;
      _scope = qianjiAllScopes;
      _view++;
      if (!_wide) _setSidebar(false);
      _controller.clear();
    });
    unawaited(_persistSession());
  }

  Future<void> _deleteChat(int id) async {
    final service = _service;
    if (service == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteChatDialog(),
    );
    if (confirmed != true || !mounted) return;
    final generation = _generation;
    try {
      await service.delete(id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _history = [
          for (final item in _history)
            if (item is! Map || item['id'] != id) item,
        ];
        if (_chatId == id) {
          _chatId = null;
          _turns = [];
          _hasOlder = false;
          _failedQuestion = null;
        }
      });
      showDunesToast(context, '已删除对话');
    } catch (_) {
      if (mounted) showDunesToast(context, '删除失败，请稍后重试');
    }
  }

  Future<void> _deleteAllChats() async {
    final service = _service;
    if (service == null || _busy || _history.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAllChatsDialog(),
    );
    if (confirmed != true || !mounted) return;
    final generation = _generation;
    setState(() => _historyLoading = true);
    try {
      var guard = 0;
      while (guard < 40) {
        guard += 1;
        final batch = await service.conversations(offset: 0);
        if (batch.isEmpty) break;
        for (final raw in batch) {
          if (raw is! Map) continue;
          final id = (raw['id'] as num?)?.toInt();
          if (id != null) await service.delete(id);
        }
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _history = [];
        _historyHasMore = false;
        _chatId = null;
        _turns = [];
        _hasOlder = false;
        _failedQuestion = null;
        _historyLoading = false;
      });
      showDunesToast(context, '已清空');
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _historyLoading = false);
      showDunesToast(context, '清空失败，请稍后重试');
      unawaited(_loadHistory());
    }
  }

  void _useExample(_Example example) {
    if (example.selectEnd > 0) {
      _controller.value = TextEditingValue(
        text: example.text,
        selection: TextSelection(
          baseOffset: 0,
          extentOffset: example.selectEnd,
        ),
      );
      _focusNode.requestFocus();
      return;
    }
    unawaited(_send(example.text));
  }

  void _editFailed() {
    final question = _failedQuestion;
    if (question == null) return;
    setState(() => _failedQuestion = null);
    _controller.value = TextEditingValue(
      text: question,
      selection: TextSelection.collapsed(offset: question.length),
    );
    _focusNode.requestFocus();
  }

  void _copy(String text) {
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    showDunesToast(context, '已复制');
  }

  void _selectScope(String scope) {
    setState(() {
      _scope = scope;
      if (!_wide) _setSidebar(false);
    });
    unawaited(_persistSession());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        _wide = wide;
        if (!_sidebarInitialized) {
          // 左右分栏时也不默认展开侧栏，避免一进页面就被「限定查询范围」占掉主区。
          _sidebarOpen = false;
          _sidebarAnim.value = 0;
          _sidebarInitialized = true;
        }
        final sidebar = _buildSidebar();
        final main = Column(
          children: [
            _buildHeader(),
            Expanded(child: _centered(_buildBody())),
            _centered(_buildComposerArea()),
          ],
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.35, 1],
              colors: [
                _c(_glow, surface: true),
                _c(_page, surface: true),
                _c(_page, surface: true),
              ],
            ),
          ),
          child: AnimatedBuilder(
            animation: _sidebarCurve,
            child: main,
            builder: (context, main) {
              final t = _sidebarCurve.value;
              return Stack(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (wide && t > 0)
                        ClipRect(
                          child: Align(
                            alignment: Alignment.centerRight,
                            widthFactor: t,
                            child: Container(
                              width: 272,
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                    color: _c(_line, border: true),
                                  ),
                                ),
                              ),
                              child: sidebar,
                            ),
                          ),
                        ),
                      Expanded(child: main!),
                    ],
                  ),
                  if (!wide && t > 0) ...[
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => setState(() => _setSidebar(false)),
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.32 * t),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: -296 * (1 - t),
                      width: 296,
                      child: Material(
                        elevation: 16 * t,
                        shadowColor: const Color(0x66331E54),
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(22),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: sidebar,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  Color _c(Color light, {bool surface = false, bool border = false}) =>
      DunesColors.resolve(
        context,
        light,
        role: surface
            ? DunesColorRole.surface
            : border
            ? DunesColorRole.border
            : DunesColorRole.foreground,
      );

  Widget _centered(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: child,
    ),
  );

  Widget _buildHeader() {
    final hasChat = _turns.isNotEmpty || _chatId != null;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 2),
        child: Row(
          children: [
            IconButton(
              tooltip: _sidebarOpen ? '收起板块' : '展开板块',
              visualDensity: VisualDensity.compact,
              onPressed: _toggleSidebar,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => RotationTransition(
                  turns: Tween(begin: 0.85, end: 1.0).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  _sidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded,
                  key: ValueKey(_sidebarOpen),
                  size: 21,
                  color: _c(_ink),
                ),
              ),
            ),
            const SizedBox(width: 4),
            const QianjiTaoMark(size: 26),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '智能业务查询',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: _c(_ink),
                    ),
                  ),
                  Text(
                    '按当前权限实时取数',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: _c(_muted)),
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: hasChat
                  ? IconButton(
                      key: const ValueKey('new-chat'),
                      tooltip: '新对话',
                      visualDensity: VisualDensity.compact,
                      onPressed: _busy ? null : _newChat,
                      icon: Icon(
                        Icons.add_comment_outlined,
                        size: 20,
                        color: _c(_ink),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 4),
            QianjiPillButton(
              icon: Icons.dashboard_outlined,
              label: '模块入口',
              onTap: widget.onSwitchLegacy,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final noContent =
        _turns.isEmpty && _pendingQuestion == null && _failedQuestion == null;
    final Widget child;
    if (noContent && !_busy) {
      child = KeyedSubtree(
        key: ValueKey('welcome-$_view'),
        child: _buildWelcome(),
      );
    } else if (noContent) {
      child = const _ChatSkeleton(key: ValueKey('loading'));
    } else {
      child = KeyedSubtree(
        key: ValueKey('chat-$_view'),
        child: _buildConversation(),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }

  Widget _buildConversation() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bubbleMax = ((constraints.maxWidth - 32) * 0.8).clamp(
          180.0,
          620.0,
        );
        final olderOffset = _hasOlder ? 1 : 0;
        final tail = (_pendingQuestion != null || _failedQuestion != null)
            ? 1
            : 0;
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          itemCount: olderOffset + _turns.length + tail,
          itemBuilder: (context, index) {
            if (_hasOlder && index == 0) {
              return Center(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: _c(_purple),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: _busy ? null : _loadOlder,
                  icon: _busy
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: _c(_purple),
                          ),
                        )
                      : const Icon(Icons.expand_less_rounded, size: 16),
                  label: Text(_busy ? '加载中…' : '查看更早的对话'),
                ),
              );
            }
            final i = index - olderOffset;
            final gap = EdgeInsets.only(top: i == 0 ? 4 : 20);
            if (i < _turns.length) {
              final turn = _turns[i] as Map;
              final scope = '${turn['scope'] ?? ''}';
              final reply = '${turn['reply'] ?? ''}';
              final turnData = turn['data'];
              final exportable = _hasExportRows(turnData);
              final turnId = (turn['id'] as num?)?.toInt();
              final isLast = i == _turns.length - 1 && tail == 0;
              final fresh =
                  _freshReplyId != null && turn['id'] == _freshReplyId;
              return Padding(
                padding: gap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Appear(
                      key: ValueKey('q-${turn['id']}'),
                      skip: fresh,
                      child: _QuestionBubble(
                        text: '${turn['question']}',
                        maxWidth: bubbleMax,
                        onCopy: () => _copy('${turn['question']}'),
                        onResend: _busy
                            ? null
                            : () => unawaited(_send('${turn['question']}')),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Appear(
                      key: ValueKey('r-${turn['id']}'),
                      child: _ReplyCard(
                        scope: scope,
                        reply: reply,
                        reveal: fresh,
                        maxWidth: bubbleMax + 40,
                        onCopy: () => _copy(reply),
                        onOpenPage: _scopeActions[scope],
                        data: turnData,
                        onExport:
                            exportable &&
                                !_busy &&
                                turnId != null &&
                                !_exportingTurnIds.contains(turnId)
                            ? () => unawaited(_exportTurn(turn))
                            : null,
                        followUps: isLast && !_busy
                            ? _followUpsFor(turn)
                            : const [],
                        onFollowUp: (q) => unawaited(_send(q)),
                        onRevealed: _scrollToBottom,
                      ),
                    ),
                  ],
                ),
              );
            }
            final failed = _failedQuestion;
            return Padding(
              padding: gap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Appear(
                    key: const ValueKey('q-pending'),
                    child: _QuestionBubble(
                      text: failed ?? _pendingQuestion!,
                      maxWidth: bubbleMax,
                      failed: failed != null,
                      onCopy: () => _copy(failed ?? _pendingQuestion!),
                      onResend: _busy
                          ? null
                          : () => unawaited(_send(failed ?? _pendingQuestion!)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topLeft,
                      children: [...previous, ?current],
                    ),
                    child: failed != null
                        ? _FailedHint(
                            key: const ValueKey('failed'),
                            onRetry: () => unawaited(_send(failed)),
                            onEdit: _editFailed,
                          )
                        : const _ThinkingCard(key: ValueKey('thinking')),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<String> _followUpsFor(Map turn) {
    final fromServer = turn['suggestions'];
    // 板块默认问题是 const 列表，不能直接 insert。先复制成可改的。
    final list = <String>[
      if (fromServer is List)
        ...fromServer.map((e) => '$e').where((e) => e.trim().isNotEmpty)
      else
        ...qianjiScopeSuggestions('${turn['scope']}'),
    ];
    final asked = '${turn['question']}'.trim();
    if (_hasExportRows(turn['data']) &&
        !list.any((q) => q.contains('Excel') || q.contains('excel'))) {
      list.insert(0, '生成 Excel');
    }
    return list.where((q) => q != asked).take(4).toList();
  }

  bool _hasExportRows(dynamic value) {
    if (value is List) {
      return value.any((item) => item is Map && item.isNotEmpty);
    }
    if (value is Map) {
      for (final entry in value.entries) {
        if (const {
              'rows',
              'content',
              'items',
              'details',
              'legs',
              'modules',
              'owners',
            }.contains('${entry.key}') &&
            _hasExportRows(entry.value)) {
          return true;
        }
      }
      for (final item in value.values) {
        if (item is Map && _hasExportRows(item)) return true;
      }
      return value.entries.any((entry) {
        if (const {
          'scope',
          'month',
          'person',
          'department',
          'note',
        }.contains('${entry.key}')) {
          return false;
        }
        return entry.value != null &&
            entry.value is! Map &&
            entry.value is! List;
      });
    }
    return false;
  }

  Future<void> _exportTurn(Map turn) async {
    final service = _service;
    final chatId = _chatId;
    final turnId = (turn['id'] as num?)?.toInt();
    if (service == null ||
        chatId == null ||
        turnId == null ||
        _busy ||
        _exportingTurnIds.contains(turnId)) {
      return;
    }
    setState(() => _exportingTurnIds.add(turnId));
    try {
      final bytes = await service.exportTurn(chatId, turnId);
      final fileName = '饕查询_${turn['scope'] ?? '结果'}_$turnId.xlsx';
      if (isDesktopCommOnly) {
        final location = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'Excel 工作簿', extensions: ['xlsx']),
          ],
        );
        if (location == null) return;
        await XFile.fromData(
          bytes,
          name: fileName,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ).saveTo(location.path);
        if (mounted) showDunesToast(context, 'Excel 已保存');
      } else {
        final path = await file_dl.saveBytesAsFile(bytes, fileName);
        if (mounted) {
          showDunesToast(
            context,
            path == null || path.isEmpty ? 'Excel 已开始下载' : 'Excel 已保存：$path',
          );
        }
      }
    } catch (error) {
      if (mounted) {
        showDunesToast(
          context,
          error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingTurnIds.remove(turnId));
    }
  }

  Widget _buildWelcome() {
    final name = widget.session?.displayName?.trim() ?? '';
    final scoped = _scope != qianjiAllScopes;
    final suggestions = qianjiScopeSuggestions(_scope);
    final examples = _examples
        .where((e) => e.scope == null || _scopeEnabled(e.scope!))
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 3 : 2;
        const gap = 10.0;
        final cardWidth =
            ((constraints.maxWidth - 32 - gap * (columns - 1)) / columns)
                .floorToDouble();
        final Widget section = scoped && suggestions.isNotEmpty
            ? Column(
                key: ValueKey('scope-$_scope'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionLabel(text: '常用问题'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < suggestions.length; i++)
                        _Appear(
                          delay: i * 40,
                          child: QianjiSuggestionChip(
                            label: suggestions[i],
                            onTap: () => unawaited(_send(suggestions[i])),
                          ),
                        ),
                    ],
                  ),
                ],
              )
            : Column(
                key: const ValueKey('examples'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionLabel(text: '试试这样问'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < examples.length; i++)
                        _Appear(
                          delay: 80 + i * 45,
                          child: SizedBox(
                            width: cardWidth,
                            child: _ExampleCard(
                              example: examples[i],
                              onTap: () => _useExample(examples[i]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          children: [
            const _Appear(
              child: Center(child: QianjiTaoMark(size: 46, glow: true)),
            ),
            const SizedBox(height: 14),
            _Appear(
              delay: 40,
              child: Text(
                name.isEmpty ? '你好，想查点什么？' : '$name，你好',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: _c(_ink),
                ),
              ),
            ),
            const SizedBox(height: 5),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                scoped
                    ? '已限定在「$_scope」范围，直接提问即可'
                    : '直接说出想查的内容，会自动识别板块、人员、部门和月份',
                key: ValueKey(scoped ? _scope : ''),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, height: 1.5, color: _c(_muted)),
              ),
            ),
            const SizedBox(height: 22),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, ?current],
              ),
              child: section,
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined, size: 12, color: _c(_faint)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '只读查询 · 结果按你当前的数据权限实时计算',
                    style: TextStyle(fontSize: 10.5, color: _c(_faint)),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildComposerArea() {
    final navOverlay = dunesAppBottomNavOverlayExtent(context);
    final bottom = navOverlay > 0
        ? navOverlay + 8
        : MediaQuery.paddingOf(context).bottom + 12;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 4, 14, bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: _error == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ErrorBanner(message: _error!),
                  ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final scoped = _scope != qianjiAllScopes;
    final focused = _composerFocused;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: _c(Colors.white, surface: true),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: focused
              ? _c(_purple, border: true).withValues(alpha: 0.45)
              : _c(_line, border: true),
        ),
        boxShadow: [
          BoxShadow(
            color: focused
                ? _purple.withValues(alpha: 0.10)
                : const Color(0x141F2329),
            blurRadius: focused ? 20 : 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 2, 0),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): () =>
                    unawaited(_send()),
                const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
                    unawaited(_send()),
              },
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: !_busy,
                maxLength: 1000,
                maxLines: 5,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => unawaited(_send()),
                cursorColor: _c(_purple),
                style: TextStyle(fontSize: 13.5, height: 1.45, color: _c(_ink)),
                decoration: InputDecoration(
                  hintText: scoped ? '在「$_scope」中查询…' : '问点什么，例如：张三的知识库有多少文档',
                  hintStyle: TextStyle(fontSize: 13, color: _c(_faint)),
                  counterText: '',
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _ScopeChip(
                scope: _scope,
                onTap: _openScopePicker,
                onClear: scoped
                    ? () => setState(() => _scope = qianjiAllScopes)
                    : null,
              ),
              const Spacer(),
              if (isDesktopCommOnly)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    'Enter 发送',
                    style: TextStyle(fontSize: 10.5, color: _c(_faint)),
                  ),
                ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  return _SendButton(
                    busy: _busy,
                    active: hasText,
                    onTap: _busy ? null : () => unawaited(_send()),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openScopePicker() async {
    final picked = await showQianjiScopePicker(
      context: context,
      groups: widget.scopeGroups,
      selected: _scope,
    );
    if (picked != null && mounted) _selectScope(picked);
  }

  String _historyTitle(Map item) {
    final title = '${item['title'] ?? ''}'.trim();
    return title.isEmpty ? '对话 ${item['id']}' : title;
  }

  static int? _daysAgo(DateTime? time) {
    if (time == null) return null;
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(time.year, time.month, time.day)).inDays;
  }

  static String _historyBucket(DateTime? time) {
    final days = _daysAgo(time);
    if (days == null) return '更早';
    if (days <= 0) return '今天';
    if (days == 1) return '昨天';
    if (days < 7) return '近 7 天';
    return '更早';
  }

  static String _historyTime(DateTime? time) {
    if (time == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    final days = _daysAgo(time)!;
    if (days <= 1) return '${two(time.hour)}:${two(time.minute)}';
    if (time.year == DateTime.now().year) return '${time.month}月${time.day}日';
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }

  List<Widget> _buildHistoryList() {
    final widgets = <Widget>[];
    String? bucket;
    for (final raw in _history) {
      if (raw is! Map) continue;
      final id = (raw['id'] as num).toInt();
      final time = DateTime.tryParse('${raw['updatedAt']}')?.toLocal();
      final current = _historyBucket(time);
      if (current != bucket) {
        bucket = current;
        widgets.add(
          Padding(
            padding: EdgeInsets.fromLTRB(0, widgets.isEmpty ? 0 : 8, 0, 4),
            child: Text(
              current,
              style: TextStyle(
                fontSize: 11,
                height: 20 / 11,
                color: _c(_muted),
              ),
            ),
          ),
        );
      }
      widgets.add(
        _HistoryTile(
          title: _historyTitle(raw),
          time: _historyTime(time),
          selected: _chatId == id,
          onTap: () => _openChat(id),
          onDelete: _busy ? null : () => unawaited(_deleteChat(id)),
        ),
      );
    }
    return widgets;
  }

  IconData _groupIcon(String title) => switch (title) {
    '业务看板' => Icons.monitor_heart_outlined,
    '工作概览' => Icons.groups_outlined,
    '业务查阅' => Icons.manage_search_rounded,
    _ => Icons.folder_open_outlined,
  };

  Widget _buildSidebar() {
    final muted = _c(_muted);
    final sectionColor = muted;
    Widget scopeTile(
      String label,
      VoidCallback? action, {
      double indent = 0,
      double height = 36,
    }) => _SideTile(
      label: label,
      icon: qianjiScopeIcons[label] ?? Icons.circle_outlined,
      selected: _scope == label,
      onTap: action == null ? null : () => _selectScope(label),
      indent: indent,
      height: height,
    );
    return Material(
      color: _c(_soft, surface: true),
      child: SafeArea(
        right: false,
        child: ListView(
          controller: _sidebarScroll,
          padding: EdgeInsets.fromLTRB(
            12,
            12,
            12,
            dunesAppBottomNavContentPadding(context, fallback: 16),
          ),
          children: [
            SizedBox(
              height: 40,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const QianjiTaoMark(size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '业务查询',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.0,
                        fontWeight: FontWeight.w600,
                        color: _c(_ink),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      tooltip: '收起板块',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 24,
                        height: 24,
                      ),
                      icon: Icon(Icons.close_rounded, size: 18, color: muted),
                      onPressed: () => setState(() => _setSidebar(false)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _NewChatButton(enabled: !_busy, onTap: _newChat),
            const SizedBox(height: 16),
            SizedBox(
              height: 36,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() => _historyExpanded = !_historyExpanded);
                        unawaited(_persistSession());
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '历史对话',
                            style: TextStyle(
                              fontSize: 11,
                              height: 16 / 11,
                              fontWeight: FontWeight.w500,
                              color: sectionColor,
                            ),
                          ),
                          if (_history.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              '${_history.length}${_historyHasMore ? '+' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                height: 20 / 11,
                                color: muted,
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (_history.isEmpty)
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Icon(
                                _historyExpanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 18,
                                color: muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_history.isNotEmpty) ...[
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: muted,
                        textStyle: const TextStyle(fontSize: 12, height: 1),
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _busy || _historyLoading
                          ? null
                          : () => unawaited(_deleteAllChats()),
                      child: const Text('清空'),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        setState(() => _historyExpanded = !_historyExpanded);
                        unawaited(_persistSession());
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: Icon(
                          _historyExpanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 18,
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_historyExpanded) ...[
              const SizedBox(height: 4),
              if (_history.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
                  child: Text(
                    _historyLoading ? '加载中…' : '暂无对话',
                    style: TextStyle(
                      fontSize: 12,
                      height: 20 / 12,
                      color: muted,
                    ),
                  ),
                )
              else ...[
                ..._buildHistoryList(),
                if (_historyHasMore)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: _c(_purple),
                        textStyle: const TextStyle(fontSize: 12),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _historyLoading
                          ? null
                          : () => _loadHistory(more: true),
                      child: const Text('查看更多对话'),
                    ),
                  ),
              ],
            ],
            const SizedBox(height: 12),
            Divider(height: 1, thickness: 1, color: _c(_line, border: true)),
            const SizedBox(height: 12),
            Text(
              '限定查询范围',
              style: TextStyle(
                fontSize: 11,
                height: 16 / 11,
                fontWeight: FontWeight.w500,
                color: sectionColor,
              ),
            ),
            const SizedBox(height: 6),
            scopeTile(qianjiAllScopes, () {}),
            for (final group in widget.scopeGroups)
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  controlAffinity: ListTileControlAffinity.trailing,
                  leading: SizedBox(
                    width: 20,
                    height: 20,
                    child: Center(
                      child: Icon(
                        _groupIcon(group.title),
                        size: 16,
                        color: muted,
                      ),
                    ),
                  ),
                  title: Text(
                    group.title,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.0,
                      fontWeight: FontWeight.w400,
                      color: _c(_ink),
                    ),
                  ),
                  initiallyExpanded: _groupExpanded[group.title] ?? false,
                  onExpansionChanged: (open) {
                    _groupExpanded[group.title] = open;
                    unawaited(_persistSession());
                  },
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  minTileHeight: 36,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                  childrenPadding: EdgeInsets.zero,
                  expandedAlignment: Alignment.centerLeft,
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  iconColor: muted,
                  collapsedIconColor: muted,
                  children: [
                    for (final scope in group.scopes)
                      scopeTile(
                        scope.label,
                        scope.onOpen,
                        indent: 28,
                        height: 32,
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

/// 查询范围选择：APP 底部卡片，PC 居中卡片。
Future<String?> showQianjiScopePicker({
  required BuildContext context,
  required List<QianjiChatScopeGroup> groups,
  required String selected,
}) {
  Widget panel(BuildContext ctx, {required bool sheet}) {
    Color c(Color light, {bool surface = false}) => DunesColors.resolve(
      ctx,
      light,
      role: surface ? DunesColorRole.surface : DunesColorRole.foreground,
    );
    Widget option(String label, bool enabled) => _ScopeOption(
      label: label,
      selected: selected == label,
      onTap: enabled ? () => Navigator.of(ctx).pop(label) : null,
    );
    return Material(
      color: c(Colors.white, surface: true),
      borderRadius: sheet
          ? const BorderRadius.vertical(top: Radius.circular(22))
          : BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(18, sheet ? 12 : 18, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sheet)
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: c(const Color(0xFFE8E0F0), surface: true),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              Text(
                '选择查询范围',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: c(_ink),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '默认智能识别；问题里写明板块、人员或部门时会自动匹配',
                style: TextStyle(fontSize: 11.5, color: c(_muted)),
              ),
              const SizedBox(height: 14),
              option(qianjiAllScopes, true),
              for (final group in groups)
                if (group.scopes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    group.title,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: c(_muted),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final scope in group.scopes)
                        option(scope.label, scope.onOpen != null),
                    ],
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }

  if (isDesktopCommOnly) {
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      pageBuilder: (ctx, _, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: panel(ctx, sheet: false),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(top: false, child: panel(ctx, sheet: true)),
  );
}

/// 饕品牌标识：与金刚区一致的紫色微渐变底座。
class QianjiTaoMark extends StatelessWidget {
  const QianjiTaoMark({super.key, this.size = 32, this.glow = false});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final end = DunesColors.resolve(context, _purpleDeep);
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DunesColors.resolve(context, _purpleLight), end],
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: [
          BoxShadow(
            color: end.withValues(alpha: glow ? 0.32 : 0.22),
            blurRadius: glow ? 22 : 7,
            offset: Offset(0, glow ? 8 : 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.auto_awesome_rounded,
        size: size * 0.5,
        color: Colors.white,
      ),
    );
    if (!glow) return mark;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: DunesColors.resolve(
          context,
          _purple,
          role: DunesColorRole.surface,
        ).withValues(alpha: 0.08),
      ),
      child: mark,
    );
  }
}

class QianjiPillButton extends StatelessWidget {
  const QianjiPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = DunesColors.resolve(context, _purple);
    return Material(
      color: DunesColors.resolve(
        context,
        _purple,
        role: DunesColorRole.surface,
      ).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QianjiSuggestionChip extends StatelessWidget {
  const QianjiSuggestionChip({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = DunesColors.resolve(context, _purple);
    return _Pressable(
      child: Material(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        shape: StadiumBorder(
          side: BorderSide(
            color: DunesColors.resolve(
              context,
              _softLine,
              role: DunesColorRole.border,
            ),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.north_east_rounded, size: 12, color: accent),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: accent,
                    ),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, this.horizontal = 0});

  final String text;
  final double horizontal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: DunesColors.resolve(context, const Color(0xFF646A73)),
        ),
      ),
    );
  }
}

class _ExampleCard extends StatelessWidget {
  const _ExampleCard({required this.example, required this.onTap});

  final _Example example;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = DunesColors.resolve(context, example.color);
    return _Pressable(
      child: Material(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 11, 11, 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: DunesColors.resolve(
                  context,
                  _line,
                  role: DunesColorRole.border,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF331E54).withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: DunesColors.resolve(
                          context,
                          example.color,
                          role: DunesColorRole.surface,
                        ).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Icon(example.icon, size: 14, color: color),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        example.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: DunesColors.resolve(context, _ink),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '「${example.text}」',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: DunesColors.resolve(context, _muted),
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

class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble({
    required this.text,
    required this.maxWidth,
    required this.onCopy,
    this.onResend,
    this.failed = false,
  });

  final String text;
  final double maxWidth;
  final VoidCallback onCopy;
  final VoidCallback? onResend;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final radius = const BorderRadius.only(
      topLeft: Radius.circular(18),
      topRight: Radius.circular(6),
      bottomLeft: Radius.circular(18),
      bottomRight: Radius.circular(18),
    );
    final muted = DunesColors.resolve(context, _muted);
    final faint = DunesColors.resolve(context, _faint);

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: DunesColors.resolve(
                  context,
                  _purple,
                  role: DunesColorRole.surface,
                ),
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: _purple.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              foregroundDecoration: failed
                  ? BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.35),
                      borderRadius: radius,
                    )
                  : null,
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _UserBubbleAction(label: '复制', color: muted, onTap: onCopy),
                const SizedBox(width: 12),
                _UserBubbleAction(
                  label: '重发',
                  color: onResend == null ? faint : muted,
                  onTap: onResend,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UserBubbleAction extends StatelessWidget {
  const _UserBubbleAction({
    required this.label,
    required this.color,
    this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, height: 1.2, color: color),
        ),
      ),
    );
  }
}

final _metricPattern = RegExp(
  r'\d[\d,]*(?:\.\d+)?\s*(?:万元|元|份文档|份|个会话|个账号|个提案|个|条|人|笔|次|小时|%)',
);

class _ReplyCard extends StatefulWidget {
  const _ReplyCard({
    required this.scope,
    required this.reply,
    required this.maxWidth,
    required this.onCopy,
    required this.onOpenPage,
    required this.data,
    required this.onExport,
    required this.followUps,
    required this.onFollowUp,
    this.reveal = false,
    this.onRevealed,
  });

  final String scope;
  final String reply;
  final double maxWidth;
  final VoidCallback onCopy;
  final VoidCallback? onOpenPage;
  final dynamic data;
  final VoidCallback? onExport;
  final List<String> followUps;
  final ValueChanged<String> onFollowUp;

  /// 新回复逐字展开；历史回复直接完整显示。
  final bool reveal;
  final VoidCallback? onRevealed;

  @override
  State<_ReplyCard> createState() => _ReplyCardState();
}

class _ReplyCardState extends State<_ReplyCard>
    with SingleTickerProviderStateMixin {
  late String _headline;
  late List<String> _bullets;
  AnimationController? _anim;
  double _headShare = 1;

  @override
  void initState() {
    super.initState();
    _parse();
    if (widget.reveal) {
      final headMs = (_headline.length * 16).clamp(260, 900);
      final bulletMs = (_bullets.length * 70).clamp(0, 1200);
      final totalMs = headMs + bulletMs + 220;
      _headShare = headMs / totalMs;
      _anim = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: totalMs),
      );
      unawaited(
        _anim!.forward().whenComplete(() {
          if (mounted) widget.onRevealed?.call();
        }),
      );
    }
  }

  @override
  void didUpdateWidget(covariant _ReplyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reply != widget.reply) _parse();
  }

  void _parse() {
    final lines = widget.reply.split('\n');
    _headline = lines
        .where((line) => !line.trimLeft().startsWith('•'))
        .join('\n')
        .trim();
    _bullets = [
      for (final line in lines)
        if (line.trimLeft().startsWith('•'))
          line.trimLeft().substring(1).trim(),
    ];
  }

  List<Map<String, dynamic>> _dataRows() {
    final found = <Map<String, dynamic>>[];
    void visit(dynamic value) {
      if (value is List) {
        for (final item in value) {
          if (item is Map && item.isNotEmpty) {
            found.add(Map<String, dynamic>.from(item));
            if (found.length >= 8) return;
          }
        }
      } else if (value is Map) {
        for (final entry in value.entries) {
          if (const {
            'rows',
            'content',
            'items',
            'details',
            'legs',
            'modules',
            'owners',
          }.contains('${entry.key}')) {
            visit(entry.value);
            if (found.isNotEmpty) return;
          }
        }
        if (found.isEmpty) {
          for (final item in value.values) {
            if (item is Map || item is List) visit(item);
            if (found.isNotEmpty) return;
          }
        }
      }
    }

    visit(widget.data);
    return found;
  }

  @override
  void dispose() {
    _anim?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = _anim;
    if (anim == null) return _buildCard(context, 1);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) => _buildCard(context, anim.value),
    );
  }

  Widget _buildCard(BuildContext context, double t) {
    Color c(Color light, {bool surface = false, bool border = false}) =>
        DunesColors.resolve(
          context,
          light,
          role: surface
              ? DunesColorRole.surface
              : border
              ? DunesColorRole.border
              : DunesColorRole.foreground,
        );
    final scope = widget.scope;
    final headline = _headline;
    final bullets = _bullets;
    final rows = _dataRows();
    final headProgress = _headShare <= 0
        ? 1.0
        : (t / _headShare).clamp(0.0, 1.0);
    final visibleChars = (headline.length * headProgress).ceil();
    final rest = 1 - _headShare;
    double bulletProgress(int i) {
      if (t >= 1) return 1;
      final step = rest / (bullets.length + 2);
      return ((t - _headShare - i * step) / (step * 2)).clamp(0.0, 1.0);
    }

    final tailProgress = t >= 1 ? 1.0 : ((t - 0.82) / 0.18).clamp(0.0, 1.0);
    final showScope = scope.isNotEmpty && scope != qianjiAllScopes;
    final baseStyle = TextStyle(fontSize: 13.5, height: 1.6, color: c(_ink));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            decoration: BoxDecoration(
              color: c(Colors.white, surface: true),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(color: c(_aiBorder, border: true)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1F2329).withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const QianjiTaoMark(size: 20),
                    if (showScope) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: c(_hoverBg, surface: true),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              qianjiScopeIcons[scope] ?? Icons.apps_rounded,
                              size: 11,
                              color: c(_muted),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              scope,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: c(_ink),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (headline.isNotEmpty)
                  Text.rich(
                    _highlight(headline, baseStyle, c(_purple), visibleChars),
                  ),
                if (bullets.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: c(_tint, surface: true),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < bullets.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: 12,
                              endIndent: 12,
                              color: c(_line, border: true),
                            ),
                          Opacity(
                            opacity: bulletProgress(i),
                            child: Transform.translate(
                              offset: Offset(0, 6 * (1 - bulletProgress(i))),
                              child: _BulletRow(text: bullets[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (rows.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _QueryRowsPreview(
                    rows: rows,
                    color: c(_ink),
                    muted: c(_muted),
                  ),
                ],
                const SizedBox(height: 6),
                Opacity(
                  opacity: tailProgress,
                  child: Row(
                    children: [
                      _MiniAction(
                        icon: Icons.copy_rounded,
                        label: '复制',
                        onTap: widget.onCopy,
                      ),
                      if (widget.onExport != null)
                        _MiniAction(
                          icon: Icons.table_view_rounded,
                          label: '生成 Excel',
                          onTap: widget.onExport!,
                        ),
                      if (widget.onOpenPage != null)
                        _MiniAction(
                          icon: Icons.open_in_new_rounded,
                          label: '打开原页面',
                          onTap: widget.onOpenPage!,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: widget.followUps.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: IgnorePointer(
                    ignoring: tailProgress < 1,
                    child: Opacity(
                      opacity: tailProgress,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < widget.followUps.length; i++)
                            _Appear(
                              delay: i * 50,
                              child: QianjiSuggestionChip(
                                label: widget.followUps[i],
                                onTap: () =>
                                    widget.onFollowUp(widget.followUps[i]),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// 未展开的字符用透明色占位，保证逐字展开时卡片高度不跳动。
  static TextSpan _highlight(
    String text,
    TextStyle base,
    Color accent,
    int visible,
  ) {
    final spans = <TextSpan>[];
    void add(String part, int offset, {required bool metric}) {
      final style = metric
          ? TextStyle(color: accent, fontWeight: FontWeight.w700)
          : null;
      final shown = (visible - offset).clamp(0, part.length);
      if (shown > 0) {
        spans.add(TextSpan(text: part.substring(0, shown), style: style));
      }
      if (shown < part.length) {
        spans.add(
          TextSpan(
            text: part.substring(shown),
            style: (style ?? const TextStyle()).copyWith(
              color: Colors.transparent,
            ),
          ),
        );
      }
    }

    var start = 0;
    for (final match in _metricPattern.allMatches(text)) {
      if (match.start > start) {
        add(text.substring(start, match.start), start, metric: false);
      }
      add(match.group(0)!, match.start, metric: true);
      start = match.end;
    }
    if (start < text.length) {
      add(text.substring(start), start, metric: false);
    }
    return TextSpan(style: base, children: spans);
  }
}

class _QueryRowsPreview extends StatelessWidget {
  const _QueryRowsPreview({
    required this.rows,
    required this.color,
    required this.muted,
  });

  final List<Map<String, dynamic>> rows;
  final Color color;
  final Color muted;

  String _label(String key) => switch (key) {
    'displayName' || 'personName' => '姓名',
    'departmentName' => '部门',
    'username' => '账号',
    'title' => '标题',
    'createdAt' || 'meetingDate' => '时间',
    'summary' || 'replySummary' => '摘要',
    'status' || 'statusLabel' => '状态',
    _ => key,
  };

  String _value(dynamic value) {
    if (value == null) return '—';
    if (value is Map || value is List) return jsonEncode(value);
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final keys = <String>[];
    for (final row in rows) {
      for (final key in row.keys) {
        if (keys.length >= 5) break;
        if (!keys.contains(key)) keys.add(key);
      }
    }
    final columns = keys.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.dataset_outlined, size: 14, color: muted),
            const SizedBox(width: 5),
            Text(
              '查询明细 · ${rows.length} 条预览',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 32,
            dataRowMinHeight: 34,
            dataRowMaxHeight: 56,
            horizontalMargin: 10,
            columnSpacing: 18,
            columns: [
              for (final key in columns)
                DataColumn(
                  label: Text(
                    _label(key),
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: [
                    for (final key in columns)
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            _value(row[key]),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: color),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final parts = text.split(' · ');
    final title = parts.first;
    final metric = parts.length >= 3 ? parts.last : '';
    final detail = parts.length >= 3
        ? parts.sublist(1, parts.length - 1).join(' · ')
        : parts.skip(1).join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: DunesColors.resolve(context, _ink),
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: DunesColors.resolve(context, _muted),
                    ),
                  ),
              ],
            ),
          ),
          if (metric.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(
              metric,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DunesColors.resolve(context, _purple),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = DunesColors.resolve(context, _muted);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}

class _ThinkingCard extends StatefulWidget {
  const _ThinkingCard({super.key});

  @override
  State<_ThinkingCard> createState() => _ThinkingCardState();
}

class _ThinkingCardState extends State<_ThinkingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = DunesColors.resolve(context, _purple);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        decoration: BoxDecoration(
          color: DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.surface,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(
            color: DunesColors.resolve(
              context,
              _line,
              role: DunesColorRole.border,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const QianjiTaoMark(size: 20),
            const SizedBox(width: 10),
            for (var i = 0; i < 3; i++)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = (_controller.value + i * 0.18) % 1.0;
                  final bounce = (t < 0.5 ? t : 1 - t) * 2;
                  return Transform.translate(
                    offset: Offset(0, -3 * Curves.easeOut.transform(bounce)),
                    child: Container(
                      width: 6,
                      height: 6,
                      margin: EdgeInsets.only(right: i < 2 ? 4 : 8),
                      decoration: BoxDecoration(
                        color: dot.withValues(alpha: 0.35 + bounce * 0.65),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              ),
            Text(
              '正在识别问题并查询…',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: DunesColors.resolve(context, _muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedHint extends StatelessWidget {
  const _FailedHint({super.key, required this.onRetry, required this.onEdit});

  final VoidCallback onRetry;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final coral = DunesColors.resolve(context, _errorRed);
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Icon(Icons.error_outline_rounded, size: 14, color: coral),
          Text(
            '未能确认查询结果，请求可能已保存',
            style: TextStyle(fontSize: 12, color: coral),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: DunesColors.resolve(context, _purple),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onRetry,
            child: const Text('重试'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: DunesColors.resolve(context, _muted),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onEdit,
            child: const Text('编辑'),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final coral = DunesColors.resolve(context, _errorRed);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: coral.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: coral),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, height: 1.4, color: coral),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.scope, required this.onTap, this.onClear});

  final String scope;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final all = scope == qianjiAllScopes;
    final fg = DunesColors.resolve(context, all ? _ink : _purple);
    final bg = DunesColors.resolve(
      context,
      all ? _hoverBg : _selectedBg,
      role: DunesColorRole.surface,
    );
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: EdgeInsets.fromLTRB(9, 5, onClear == null ? 7 : 4, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                qianjiScopeIcons[scope] ?? Icons.apps_rounded,
                size: 13,
                color: fg,
              ),
              const SizedBox(width: 4),
              Text(
                all ? '范围 · 智能识别' : '范围 · $scope',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              if (onClear == null)
                Icon(Icons.expand_more_rounded, size: 16, color: fg)
              else
                InkResponse(
                  onTap: onClear,
                  radius: 14,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded, size: 14, color: fg),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.busy,
    required this.active,
    required this.onTap,
  });

  final bool busy;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '发送',
      child: AnimatedScale(
        scale: active || busy ? 1 : 0.92,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active && !busy
                    ? DunesColors.resolve(
                        context,
                        _purple,
                        role: DunesColorRole.surface,
                      )
                    : DunesColors.resolve(
                        context,
                        _disabled,
                        role: DunesColorRole.surface,
                      ),
              ),
              alignment: Alignment.center,
              child: busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      Icons.arrow_upward_rounded,
                      size: 18,
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.85),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewChatButton extends StatelessWidget {
  const _NewChatButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = DunesColors.resolve(context, _purple);
    final fill = DunesColors.resolve(
      context,
      _selectedBg,
      role: DunesColorRole.surface,
    );
    return SizedBox(
      height: 40,
      width: double.infinity,
      child: Material(
        color: enabled ? fill : fill.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: accent.withValues(alpha: enabled ? 1 : 0.4)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(
                    Icons.add_comment_outlined,
                    size: 18,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '新建对话',
                  style: TextStyle(
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w500,
                    color: accent,
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

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final accent = DunesColors.resolve(context, _purple);
    final fg = selected
        ? accent
        : enabled
        ? DunesColors.resolve(context, _ink)
        : DunesColors.resolve(context, _faint);
    return Material(
      color: selected
          ? DunesColors.resolve(
              context,
              _selectedBg,
              role: DunesColorRole.surface,
            )
          : DunesColors.resolve(
              context,
              _hoverBg,
              role: DunesColorRole.surface,
            ),
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? Colors.transparent
              : DunesColors.resolve(
                  context,
                  _line,
                  role: DunesColorRole.border,
                ),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                qianjiScopeIcons[label] ?? Icons.apps_rounded,
                size: 14,
                color: selected ? accent : DunesColors.resolve(context, _muted),
              ),
              const SizedBox(width: 5),
              Text(
                label == qianjiAllScopes ? '智能识别（全部板块）' : label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 侧栏单行：默认高 36；选中浅底 + 2px 左条，圆角 6。
class _SideTile extends StatelessWidget {
  const _SideTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.indent = 0,
    this.height = 36,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  final double indent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final accent = DunesColors.resolve(context, _purple);
    final muted = DunesColors.resolve(context, _muted);
    final labelColor = selected
        ? accent
        : DunesColors.resolve(
            context,
            enabled ? _ink : _muted.withValues(alpha: 0.6),
          );
    final bg = selected
        ? DunesColors.resolve(
            context,
            _selectedBg,
            role: DunesColorRole.surface,
          )
        : Colors.transparent;
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: DunesColors.resolve(
            context,
            _hoverBg,
            role: DunesColorRole.surface,
          ),
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border(
                left: BorderSide(
                  color: selected ? accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Icon(
                      icon,
                      size: 16,
                      color: selected
                          ? accent
                          : muted.withValues(alpha: enabled ? 1 : 0.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.0,
                        fontWeight: FontWeight.w400,
                        color: labelColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatefulWidget {
  const _HistoryTile({
    required this.title,
    required this.time,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final String title;
  final String time;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = DunesColors.resolve(context, _purple);
    final muted = DunesColors.resolve(context, _muted);
    final faint = DunesColors.resolve(context, _faint);
    final selected = widget.selected;
    final showDelete =
        widget.onDelete != null && (!isDesktopCommOnly || _hover || selected);
    final showTime =
        widget.time.isNotEmpty && (!isDesktopCommOnly || !showDelete);
    final bg = selected
        ? DunesColors.resolve(
            context,
            _selectedBg,
            role: DunesColorRole.surface,
          )
        : _hover
        ? DunesColors.resolve(context, _hoverBg, role: DunesColorRole.surface)
        : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: isDesktopCommOnly ? null : widget.onDelete,
            borderRadius: BorderRadius.circular(8),
            child: Ink(
              height: 44,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    color: selected ? accent : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 9, right: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 20,
                        color: selected ? accent : muted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.0,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: selected
                              ? accent
                              : DunesColors.resolve(context, _ink),
                        ),
                      ),
                    ),
                    if (showTime) ...[
                      const SizedBox(width: 6),
                      Text(
                        widget.time,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.0,
                          color: faint,
                        ),
                      ),
                    ],
                    if (showDelete)
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Tooltip(
                          message: '删除对话',
                          child: InkResponse(
                            onTap: widget.onDelete,
                            radius: 16,
                            child: Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: _hover ? muted : faint,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteAllChatsDialog extends StatelessWidget {
  const _DeleteAllChatsDialog();

  @override
  Widget build(BuildContext context) {
    final coral = DunesColors.resolve(context, _errorRed);
    return Dialog(
      backgroundColor: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: coral.withValues(alpha: 0.1),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.delete_sweep_outlined,
                  size: 20,
                  color: coral,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '删除全部历史对话？',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolve(context, _ink),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '不可恢复，确认后将清空全部历史对话。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: DunesColors.resolve(context, _muted),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DunesColors.resolve(context, _ink),
                        side: BorderSide(
                          color: DunesColors.resolve(
                            context,
                            _line,
                            role: DunesColorRole.border,
                          ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: coral,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('确认清空'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteChatDialog extends StatelessWidget {
  const _DeleteChatDialog();

  @override
  Widget build(BuildContext context) {
    final coral = DunesColors.resolve(context, DunesColors.coral);
    return Dialog(
      backgroundColor: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: DunesColors.resolve(
                    context,
                    DunesColors.coralSoft,
                    role: DunesColorRole.surface,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: coral,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '删除这个对话？',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolve(context, _ink),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '删除后无法恢复，对话中的提问记录会一并清除。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: DunesColors.resolve(context, _muted),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DunesColors.resolve(context, _ink),
                        side: BorderSide(
                          color: DunesColors.resolve(
                            context,
                            _line,
                            role: DunesColorRole.border,
                          ),
                        ),
                        minimumSize: const Size.fromHeight(38),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: coral,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(38),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('删除'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 入场动画：淡入并轻微上移，`delay` 用于同组元素依次出现。
class _Appear extends StatefulWidget {
  const _Appear({
    super.key,
    required this.child,
    this.delay = 0,
    this.skip = false,
  });

  final Widget child;
  final int delay;
  final bool skip;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  static const _base = 320;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _base + widget.delay),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      widget.delay / (_base + widget.delay),
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void initState() {
    super.initState();
    if (widget.skip) {
      _controller.value = 1;
    } else {
      unawaited(_controller.forward());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - _curve.value)),
          child: child,
        ),
      ),
    );
  }
}

/// 按下时轻微缩小，松开回弹。
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child});

  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: Duration(milliseconds: _pressed ? 90 : 180),
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// 打开历史对话时的骨架屏，避免空白闪烁。
class _ChatSkeleton extends StatefulWidget {
  const _ChatSkeleton({super.key});

  @override
  State<_ChatSkeleton> createState() => _ChatSkeletonState();
}

class _ChatSkeletonState extends State<_ChatSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = DunesColors.resolve(
      context,
      _soft,
      role: DunesColorRole.surface,
    );
    final card = DunesColors.resolve(
      context,
      Colors.white,
      role: DunesColorRole.surface,
    );
    final line = DunesColors.resolve(
      context,
      _line,
      role: DunesColorRole.border,
    );
    Widget bar(double width, {double height = 10}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(99),
      ),
    );
    Widget group(double questionWidth, List<double> lines) => Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: questionWidth,
              height: 34,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lines.length; i++) ...[
                    if (i > 0) const SizedBox(height: 9),
                    bar(lines[i]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return FadeTransition(
      opacity: Tween(begin: 0.55, end: 1.0).animate(_controller),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          group(150, [90, 240, 200]),
          group(190, [70, 220, 160, 230]),
        ],
      ),
    );
  }
}
