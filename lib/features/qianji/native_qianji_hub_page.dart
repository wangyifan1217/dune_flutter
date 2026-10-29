import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/dunes_choice_panel.dart';
import '../auth/auth_session.dart';
import '../robots/robot_character.dart';
import '../robots/robot_consult_store.dart';
import '../robots/robot_models.dart';
import '../robots/robot_service.dart';
import '../shell/dunes_main_tab_bar.dart';
import 'digital_auto/digital_employee_service.dart';
import 'qianji_chat_service.dart';

/// 新版对话页暂时隐藏。改回 true 后恢复进入新版的入口。
const bool qianjiHubNewLayoutEnabled = false;

/// 饕板块紫调主色系统
const _themePurple = Color(0xFF7B5CD8);
const _deepPurple = Color(0xFF261D38);
const _subText = Color(0xFF888196);
const _cardBorder = Color(0xFFEDE8F5);
const _bgSurface = Color(0xFFF7F6FA);

/// 千机（饕）板块页面：
/// 采用参考支付宝 APP 的高质感卡片布局风格，并保持当前紫色调为主色。
class NativeQianjiHubPage extends StatefulWidget {
  const NativeQianjiHubPage({
    super.key,
    required this.onOpenCursorAccount,
    this.onOpenMeetingSupervise,
    this.onOpenSessionSupervise,
    this.onOpenKbSupervise,
    this.onOpenTaskMonitor,
    this.onOpenDailyReportMonitor,
    this.onOpenGroupReply,
    this.onOpenProposalSla,
    this.onOpenMonthlyOpinion,
    this.onOpenProposalReview,
    this.onOpenEfficiencyAnalysis,
    this.onOpenEfficiencyBossPreview,
    this.onOpenWorkProfileManagement,
    this.onOpenAppUsage,
    this.onOpenFundSecondment,
    this.onOpenCashFlow,
    this.onOpenMonthlyBill,
    this.onOpenTravel,
    this.onOpenRobotHome,
    this.onOpenRobot,
    this.onOpenDigitalEmployee,
    this.session,
    this.chatService,
  });

  final VoidCallback onOpenCursorAccount;
  final VoidCallback? onOpenMeetingSupervise;
  final VoidCallback? onOpenSessionSupervise;
  final VoidCallback? onOpenKbSupervise;
  final VoidCallback? onOpenTaskMonitor;
  final VoidCallback? onOpenDailyReportMonitor;
  final VoidCallback? onOpenGroupReply;
  final VoidCallback? onOpenProposalSla;
  final VoidCallback? onOpenMonthlyOpinion;
  final VoidCallback? onOpenProposalReview;
  final VoidCallback? onOpenEfficiencyAnalysis;
  final VoidCallback? onOpenEfficiencyBossPreview;
  final VoidCallback? onOpenWorkProfileManagement;
  final VoidCallback? onOpenAppUsage;
  final VoidCallback? onOpenFundSecondment;
  final VoidCallback? onOpenCashFlow;
  final VoidCallback? onOpenMonthlyBill;
  final VoidCallback? onOpenTravel;
  final VoidCallback? onOpenRobotHome;

  /// 点击单个机器人名片：由 Host 按 canChat 决定进聊天或提示。
  final ValueChanged<RobotRole>? onOpenRobot;
  final ValueChanged<DigitalEmployeeItem>? onOpenDigitalEmployee;
  final AuthSession? session;
  final QianjiChatService? chatService;

  @override
  State<NativeQianjiHubPage> createState() => _NativeQianjiHubPageState();
}

class _NativeQianjiHubPageState extends State<NativeQianjiHubPage> {
  bool _newLayout = qianjiHubNewLayoutEnabled;
  bool _sidebarOpen = false;
  bool _sidebarInitialized = false;
  bool _wideLayout = false;
  String _queryScope = '全部板块';
  final _queryController = TextEditingController();
  List<dynamic> _chatHistory = [];
  bool _historyHasMore = false;
  bool _historyLoading = false;
  List<dynamic> _chatTurns = [];
  int? _chatId;
  bool _chatBusy = false;
  bool _chatHasOlder = false;
  String? _chatError;
  int _chatGeneration = 0;
  bool? _chatVisible;

  QianjiChatService? get _chatService =>
      widget.chatService ??
      (widget.session == null ? null : QianjiChatService(widget.session!));

  Future<void> _loadChatHistory({bool more = false}) async {
    final service = _chatService;
    final generation = _chatGeneration;
    if (service == null || _historyLoading) return;
    setState(() => _historyLoading = true);
    try {
      final history = await service.conversations(
        offset: more ? _chatHistory.length : 0,
      );
      if (mounted && generation == _chatGeneration) {
        setState(() {
          if (more) {
            final existing = _chatHistory.map((item) => item['id']).toSet();
            _chatHistory = [
              ..._chatHistory,
              ...history.where((item) => !existing.contains(item['id'])),
            ];
          } else {
            _chatHistory = history;
          }
          _historyHasMore = history.length == 30;
          _chatError = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _chatGeneration) {
        setState(() => _chatError = '无法读取饕对话历史，请稍后重试');
      }
    } finally {
      if (mounted && generation == _chatGeneration) {
        setState(() => _historyLoading = false);
      }
    }
  }

  Future<void> _openChat(int id) async {
    final service = _chatService;
    final generation = _chatGeneration;
    if (service == null || _chatBusy) return;
    setState(() {
      _chatBusy = true;
      _chatError = null;
      if (!_wideLayout) _sidebarOpen = false;
      _chatId = null;
      _chatTurns = [];
    });
    try {
      final turns = await service.turns(id);
      if (mounted && generation == _chatGeneration) {
        setState(() {
          _chatId = id;
          _chatTurns = turns;
          _chatHasOlder = turns.length == 10;
        });
      }
    } catch (_) {
      if (mounted && generation == _chatGeneration) {
        setState(() => _chatError = '无法读取此对话，请检查权限或稍后重试');
      }
    } finally {
      if (mounted && generation == _chatGeneration) {
        setState(() => _chatBusy = false);
      }
    }
  }

  Future<void> _loadOlderChat() async {
    final service = _chatService;
    final id = _chatId;
    final generation = _chatGeneration;
    if (service == null || id == null || _chatTurns.isEmpty || _chatBusy) {
      return;
    }
    final before = (_chatTurns.first['id'] as num).toInt();
    setState(() {
      _chatBusy = true;
      _chatError = null;
    });
    try {
      final older = await service.turns(id, before: before);
      if (mounted && generation == _chatGeneration && _chatId == id) {
        setState(() {
          _chatTurns = [...older, ..._chatTurns];
          _chatHasOlder = older.length == 10;
        });
      }
    } catch (_) {
      if (mounted && generation == _chatGeneration) {
        setState(() => _chatError = '无法读取更早的对话，请稍后重试');
      }
    } finally {
      if (mounted && generation == _chatGeneration) {
        setState(() => _chatBusy = false);
      }
    }
  }

  Future<void> _sendChat() async {
    final service = _chatService;
    final generation = _chatGeneration;
    final scope = _queryScope;
    final question = _queryController.text.trim();
    if (service == null || question.isEmpty || _chatBusy) return;
    setState(() {
      _chatBusy = true;
      _chatError = null;
    });
    try {
      final id = _chatId ?? await service.create();
      if (mounted && generation == _chatGeneration && _chatId == null) {
        setState(() => _chatId = id);
      }
      if (!mounted || generation != _chatGeneration) return;
      final turn = await service.send(id, scope, question);
      if (mounted && generation == _chatGeneration) {
        setState(() {
          _chatTurns = [..._chatTurns, turn];
          _queryController.clear();
        });
      }
      await _loadChatHistory();
    } catch (_) {
      if (mounted && generation == _chatGeneration) {
        setState(() => _chatError = '未能确认查询结果。请求可能已保存，请先重新打开该对话确认。');
      }
    } finally {
      if (mounted && generation == _chatGeneration) {
        setState(() => _chatBusy = false);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (_chatVisible == visible) return;
    final wasVisible = _chatVisible;
    _chatVisible = visible;
    if (!visible && wasVisible == true) {
      _chatGeneration++;
      _chatTurns = [];
      _chatBusy = false;
      _historyLoading = false;
    } else if (visible && wasVisible == false) {
      final id = _chatId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _chatVisible != true) return;
        unawaited(_loadChatHistory());
        if (id != null) unawaited(_openChat(id));
      });
    }
  }

  @override
  void didUpdateWidget(covariant NativeQianjiHubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatService != widget.chatService ||
        oldWidget.session != widget.session) {
      final sameAccount =
          oldWidget.chatService == widget.chatService &&
          oldWidget.session?.userId == widget.session?.userId &&
          oldWidget.session?.apiBase == widget.session?.apiBase;
      final previousId = sameAccount ? _chatId : null;
      _chatGeneration++;
      _chatHistory = [];
      _historyHasMore = false;
      _historyLoading = false;
      _chatTurns = [];
      _chatId = previousId;
      _chatHasOlder = false;
      _chatBusy = false;
      _chatError = null;
      if (!sameAccount) _queryController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _chatVisible != true || !_hasAccess) return;
        unawaited(_loadChatHistory());
        if (previousId != null) unawaited(_openChat(previousId));
      });
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  List<RobotRole> _robots = const [];
  bool _loadingRobots = false;
  List<DigitalEmployeeItem> _digitalEmployees = const [];
  bool _loadingDigitalEmployees = false;

  bool get _hasAccess =>
      widget.session == null || widget.session!.effectiveQianjiAccess;

  bool get _canUseRobots =>
      widget.session == null || widget.session!.effectiveRobotAccess;

  bool get _canUseDigitalEmployees =>
      widget.session == null || widget.session!.effectiveDigitalEmployeeAccess;

  static const _fallbackDigitalEmployees = <DigitalEmployeeItem>[
    DigitalEmployeeItem(
      employeeKey: 'meeting-minutes',
      name: '会议纪要',
      subtitle: 'AI 助理 · 会议纪要与行动项',
      iconKey: 'auto_awesome',
      screenId: 'QJMA',
      comingSoon: false,
    ),
    DigitalEmployeeItem(
      employeeKey: 'channel-dock',
      name: '三桶油.渠道对接',
      subtitle: '数字配置 · AI 助理',
      iconKey: 'oil_barrel',
      screenId: 'QJTO',
      comingSoon: false,
    ),
    DigitalEmployeeItem(
      employeeKey: 'am-settlement',
      name: '资管.AI助理',
      subtitle: '结算字典 · AI 助理',
      iconKey: 'account_balance',
      screenId: 'QJAM',
      comingSoon: false,
    ),
    DigitalEmployeeItem(
      employeeKey: 'sanyoutong-farm',
      name: '三桶油.AI助理',
      subtitle: '运营查询 · 产品链路 / 供应商 / 预警 / 导出',
      iconKey: 'oil_barrel',
      screenId: 'QJDE',
      comingSoon: false,
    ),
  ];

  void _showMeetingAssistantComingSoon() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('会议纪要 AI 助理即将上线')));
  }

  @override
  void initState() {
    super.initState();
    final store = RobotConsultStore.instance;
    store.bindSession(widget.session);
    _loadRobots();
    _loadDigitalEmployees();
    unawaited(_loadChatHistory());
    if (widget.session != null && widget.session!.effectiveRobotAccess) {
      store.refreshHub();
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadRobots(), _loadDigitalEmployees()]);
  }

  VoidCallback? _mergedWorkSituationTap() {
    final preview = widget.onOpenEfficiencyBossPreview;
    final analysis = widget.onOpenEfficiencyAnalysis;
    if (preview == null && analysis == null) return null;
    if (preview != null && analysis == null) return preview;
    if (preview == null && analysis != null) return analysis;
    return () => _openHubChoices(
      title: '选择查看入口',
      items: [
        (
          title: '工作情况',
          subtitle: widget.session?.workSituationViewAll == true
              ? '全部部门'
              : '本人及下级',
          icon: Icons.groups_outlined,
          onTap: preview!,
        ),
        (
          title: 'AI效能分析',
          subtitle: '个人与部门',
          icon: Icons.insights_outlined,
          onTap: analysis!,
        ),
      ],
    );
  }

  void _openHubChoices({
    required String title,
    required List<
      ({String title, String subtitle, IconData icon, VoidCallback onTap})
    >
    items,
  }) {
    unawaited(
      showDunesChoicePanel(
        context: context,
        title: title,
        items: [
          for (final item in items)
            DunesChoiceItem(
              title: item.title,
              subtitle: item.subtitle,
              icon: item.icon,
              onTap: item.onTap,
            ),
        ],
      ),
    );
  }

  Future<void> _loadRobots() async {
    final session = widget.session;
    if (session == null || !_canUseRobots) {
      if (mounted) {
        setState(() {
          _robots = const [];
          _loadingRobots = false;
        });
      }
      return;
    }
    RobotConsultStore.instance.bindSession(session);
    setState(() => _loadingRobots = true);
    try {
      final list = await RobotService(session: session).listRobots();
      if (!mounted) return;
      setState(() {
        _robots = list;
        _loadingRobots = false;
      });
      unawaited(RobotConsultStore.instance.refreshHub());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _robots = const [];
        _loadingRobots = false;
      });
    }
  }

  Future<void> _loadDigitalEmployees() async {
    final session = widget.session;
    if (!_canUseDigitalEmployees) {
      if (mounted) {
        setState(() {
          _digitalEmployees = const [];
          _loadingDigitalEmployees = false;
        });
      }
      return;
    }
    if (session == null || !session.digitalEmployeeAccessKnown) {
      if (mounted) {
        setState(() {
          _digitalEmployees = _fallbackDigitalEmployees;
          _loadingDigitalEmployees = false;
        });
      }
      return;
    }
    setState(() => _loadingDigitalEmployees = true);
    try {
      final list = await DigitalEmployeeService(
        session: session,
      ).listEmployees();
      if (!mounted) return;
      setState(() {
        _digitalEmployees = list;
        _loadingDigitalEmployees = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _digitalEmployees = const [];
        _loadingDigitalEmployees = false;
      });
    }
  }

  void _onTapDigitalEmployee(DigitalEmployeeItem item) {
    if (item.comingSoon) {
      _showMeetingAssistantComingSoon();
      return;
    }
    switch (item.screenId) {
      case 'QJTO':
      case 'QJMA':
      case 'QJAM':
      case 'QJDE':
        if (widget.onOpenDigitalEmployee != null) {
          widget.onOpenDigitalEmployee!(item);
        } else {
          _showMeetingAssistantComingSoon();
        }
        break;
      default:
        _showMeetingAssistantComingSoon();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAccess || !qianjiHubNewLayoutEnabled) return _buildLegacy();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        _wideLayout = wide;
        if (!_sidebarInitialized) {
          _sidebarOpen = wide;
          _sidebarInitialized = true;
        }
        final sidebar = _buildSidebar();
        return Stack(
          children: [
            if (_newLayout)
              Row(
                children: [
                  if (wide && _sidebarOpen)
                    SizedBox(width: 250, child: sidebar),
                  Expanded(
                    child: Column(
                      children: [
                        Material(
                          color: Theme.of(context).colorScheme.surface,
                          child: SafeArea(
                            bottom: false,
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: _sidebarOpen ? '收起板块' : '展开板块',
                                  onPressed: () => setState(
                                    () => _sidebarOpen = !_sidebarOpen,
                                  ),
                                  icon: const Icon(Icons.menu),
                                ),
                                const Expanded(
                                  child: Text(
                                    '饕',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _newLayout = false),
                                  child: const Text('切换旧版'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(child: _buildConversation()),
                      ],
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  SafeArea(
                    bottom: false,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _newLayout = true),
                        child: const Text('切换新版'),
                      ),
                    ),
                  ),
                  Expanded(child: _buildLegacy()),
                ],
              ),
            if (_newLayout && !wide && _sidebarOpen) ...[
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _sidebarOpen = false),
                  child: Container(color: Colors.black38),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                width: 280,
                child: Material(elevation: 8, child: sidebar),
              ),
            ],
          ],
        );
      },
    );
  }

  String _historyTime(dynamic value) {
    final parsed = DateTime.tryParse('$value')?.toLocal();
    if (parsed == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} ${two(parsed.hour)}:${two(parsed.minute)}';
  }

  Widget _buildSidebar() {
    Widget item(String label, VoidCallback? action) => ListTile(
      dense: true,
      selected: _queryScope == label,
      title: Text(label),
      enabled: action != null,
      onTap: action == null
          ? null
          : () => setState(() {
              _queryScope = label;
              if (!_wideLayout) _sidebarOpen = false;
            }),
    );
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            ListTile(
              title: const Text(
                '饕 · 业务查询',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: IconButton(
                tooltip: '收起板块',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _sidebarOpen = false),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('新建对话'),
              enabled: !_chatBusy,
              onTap: () => setState(() {
                _chatId = null;
                _chatTurns = [];
                _chatHasOlder = false;
                _chatError = null;
                _queryScope = '全部板块';
                if (!_wideLayout) _sidebarOpen = false;
                _queryController.clear();
              }),
            ),
            ExpansionTile(
              title: const Text('历史对话'),
              leading: const Icon(Icons.history),
              children: [
                if (_chatHistory.isEmpty) const ListTile(title: Text('暂无对话')),
                for (var i = 0; i < _chatHistory.length; i++)
                  ListTile(
                    dense: true,
                    title: Text('对话 ${_chatHistory[i]['id']}'),
                    subtitle: Text(_historyTime(_chatHistory[i]['updatedAt'])),
                    selected: _chatId == _chatHistory[i]['id'],
                    onTap: () =>
                        _openChat((_chatHistory[i]['id'] as num).toInt()),
                  ),
                if (_historyHasMore)
                  TextButton(
                    onPressed: _historyLoading
                        ? null
                        : () => _loadChatHistory(more: true),
                    child: const Text('查看更多对话'),
                  ),
              ],
            ),
            item('全部板块', () {}),
            ExpansionTile(
              title: const Text('业务看板'),
              initiallyExpanded: true,
              children: [
                if (widget.onOpenCashFlow != null)
                  item('资金流向', widget.onOpenCashFlow),
                if (widget.onOpenMonthlyBill != null)
                  item('月结', widget.onOpenMonthlyBill),
                if (widget.onOpenFundSecondment != null)
                  item('资金借调', widget.onOpenFundSecondment),
                item('差旅管理', widget.onOpenTravel),
              ],
            ),
            ExpansionTile(
              title: const Text('工作概览'),
              children: [
                item('工作情况', _mergedWorkSituationTap()),
                item('员工画像', widget.onOpenWorkProfileManagement),
                item('使用热力', widget.onOpenAppUsage),
              ],
            ),
            ExpansionTile(
              title: const Text('业务查阅'),
              children: [
                item('会议纪要', widget.onOpenMeetingSupervise),
                item('IM会话', widget.onOpenSessionSupervise),
                item('知识库', widget.onOpenKbSupervise),
                item('任务', widget.onOpenTaskMonitor),
                item('日报', widget.onOpenDailyReportMonitor),
                item('群响应', widget.onOpenGroupReply),
                if (widget.onOpenProposalSla != null)
                  item('提案时效', widget.onOpenProposalSla),
                item('研发账号', widget.onOpenCursorAccount),
                if (widget.onOpenMonthlyOpinion != null)
                  item('月度舆情', widget.onOpenMonthlyOpinion),
                if (widget.onOpenProposalReview != null)
                  item('提案审核', widget.onOpenProposalReview),
              ],
            ),
          ],
        ),
      ),
    );
  }

  VoidCallback? get _selectedLegacyPage => switch (_queryScope) {
    '资金流向' => widget.onOpenCashFlow,
    '月结' => widget.onOpenMonthlyBill,
    '资金借调' => widget.onOpenFundSecondment,
    '差旅管理' => widget.onOpenTravel,
    '工作情况' => _mergedWorkSituationTap(),
    '员工画像' => widget.onOpenWorkProfileManagement,
    '使用热力' => widget.onOpenAppUsage,
    '会议纪要' => widget.onOpenMeetingSupervise,
    'IM会话' => widget.onOpenSessionSupervise,
    '知识库' => widget.onOpenKbSupervise,
    '任务' => widget.onOpenTaskMonitor,
    '日报' => widget.onOpenDailyReportMonitor,
    '群响应' => widget.onOpenGroupReply,
    '提案时效' => widget.onOpenProposalSla,
    '月度舆情' => widget.onOpenMonthlyOpinion,
    '提案审核' => widget.onOpenProposalReview,
    '研发账号' => widget.onOpenCursorAccount,
    _ => null,
  };

  String get _suggestedQuery => switch (_queryScope) {
    '资金流向' => '资金流向概览',
    '月结' => '月结概览',
    '研发账号' => '研发账号有多少？',
    '任务' => '我的任务有多少？',
    '知识库' => '知识库有多少文档？',
    '提案时效' => '提案时效有多少提案？',
    '资金借调' => '资金借调有多少条记录？',
    '差旅管理' || '工作情况' || '使用热力' || '员工画像' => '$_queryScope有多少人？',
    '日报' || '群响应' || '会议纪要' || 'IM会话' => '$_queryScope有多少？',
    _ => '',
  };

  Widget _buildConversation() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.forum_outlined, color: _themePurple),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '查询范围：$_queryScope',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton(
                onPressed:
                    _selectedLegacyPage ??
                    () => setState(() => _newLayout = false),
                child: Text(_selectedLegacyPage == null ? '前往旧版' : '打开原页面'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _chatTurns.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '选择左侧板块后提问。目前支持部分板块的数量统计与财务概览；其他查询正在接入。',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _chatTurns.length + (_chatHasOlder ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_chatHasOlder && index == 0) {
                      return TextButton(
                        onPressed: _chatBusy ? null : _loadOlderChat,
                        child: const Text('查看更早的对话'),
                      );
                    }
                    final turn =
                        _chatTurns[index - (_chatHasOlder ? 1 : 0)] as Map;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8, top: 8),
                            child: Text(
                              '查询板块：${turn['scope']}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Card(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text('${turn['question']}'),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text('${turn['reply']}'),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
        if (_suggestedQuery.isNotEmpty && !_chatBusy)
          Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final question in [
                    _suggestedQuery,
                    if (_queryScope == '资金借调') ...[
                      '资金借调列表',
                      '资金借调未结清列表',
                      '资金借调已结清列表',
                      '资金借调逾期多少？',
                    ],
                    if (_queryScope == '资金流向') '资金流向流水列表',
                    if (_queryScope == '会议纪要') '会议纪要列表',
                    if (_queryScope == '使用热力') '使用热力概览',
                    if (_queryScope == '知识库' || _queryScope == 'IM会话')
                      '$_queryScope人员列表',
                    if (_queryScope == '月结') ...[
                      '应收账单列表',
                      '应付账单列表',
                      '渠道应收账单列表',
                      '供给应收账单列表',
                      '应收逾期多少？',
                      '应付逾期多少？',
                    ],
                    if (_queryScope == '任务') ...[
                      '我的任务列表',
                      '我的进行中任务列表',
                      '我的进行中任务有多少？',
                      '我的已完成任务有多少？',
                    ],
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(question),
                        onPressed: () {
                          _queryController.text = question;
                          _sendChat();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (_chatTurns.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '历史结果按当前数据与权限重新查询',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        if (_chatError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _chatError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    enabled: !_chatBusy,
                    maxLength: 1000,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(
                      hintText: '输入业务查询问题',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '发送',
                  onPressed: _chatBusy ? null : _sendChat,
                  icon: _chatBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegacy() {
    if (!_hasAccess) {
      return _buildNoAccessView();
    }

    final assetRows = <Widget>[
      if (widget.onOpenCashFlow != null)
        _AlipayAssetRow(
          icon: Icons.account_balance_rounded,
          iconBgColor: DunesColors.resolve(
            context,
            const Color(0xFFE8F5E9),
            role: DunesColorRole.surface,
          ),
          iconColor: DunesColors.resolve(context, const Color(0xFF2E7D32)),
          title: '资金流向',
          subtitle: '公司账户 · 由大到小',
          actionText: '实时看板',
          onTap: widget.onOpenCashFlow!,
        ),
      if (widget.onOpenMonthlyBill != null)
        _AlipayAssetRow(
          icon: Icons.receipt_long_rounded,
          iconBgColor: DunesColors.resolve(
            context,
            const Color(0xFFEDE7F6),
            role: DunesColorRole.surface,
          ),
          iconColor: _themePurple,
          title: '月结',
          subtitle: '应收 · 应付',
          actionText: '账单台账',
          onTap: widget.onOpenMonthlyBill!,
        ),
      if (widget.onOpenFundSecondment != null)
        _AlipayAssetRow(
          icon: Icons.account_balance_wallet_rounded,
          iconBgColor: DunesColors.resolve(
            context,
            const Color(0xFFFFF3E0),
            role: DunesColorRole.surface,
          ),
          iconColor: DunesColors.resolve(context, const Color(0xFFE65100)),
          title: '资金借调',
          subtitle: '已通过借款单',
          actionText: '借还明细',
          onTap: widget.onOpenFundSecondment!,
        ),
      if (widget.onOpenTravel != null)
        _AlipayAssetRow(
          icon: Icons.flight_takeoff_rounded,
          iconBgColor: DunesColors.resolve(
            context,
            const Color(0xFFE0F7FA),
            role: DunesColorRole.surface,
          ),
          iconColor: DunesColors.resolve(context, const Color(0xFF00838F)),
          title: '差旅管理',
          subtitle: '出行成本 · 地图',
          actionText: '行程地图',
          onTap: widget.onOpenTravel!,
        ),
    ];

    final workSituationTap = _mergedWorkSituationTap();
    final summaryItems = <_SuperviseItemData>[
      _SuperviseItemData(
        title: '工作情况',
        subtitle:
            widget.onOpenEfficiencyAnalysis != null &&
                widget.onOpenEfficiencyBossPreview != null
            ? '态势 · 能效'
            : (widget.session?.workSituationViewAll == true ? '全部部门' : '本人及下级'),
        icon: Icons.groups_outlined,
        gradientColors: [
          DunesColors.resolve(context, Color(0xFF8B6BE8)),
          DunesColors.resolve(context, Color(0xFF6743D3)),
        ],
        onTap: workSituationTap,
      ),
      if (widget.onOpenWorkProfileManagement != null)
        _SuperviseItemData(
          title: '员工画像',
          subtitle: '团队概览 · 工作成果',
          icon: Icons.person_search_rounded,
          gradientColors: [
            DunesColors.resolve(context, Color(0xFF9A75D4)),
            DunesColors.resolve(context, Color(0xFF6743A0)),
          ],
          onTap: widget.onOpenWorkProfileManagement,
        ),
      _SuperviseItemData(
        title: '使用热力',
        subtitle: widget.session?.appUsageViewAll == true ? '全部人员' : '本人及下级',
        icon: Icons.grid_view_rounded,
        gradientColors: [
          DunesColors.resolve(context, Color(0xFF6B5CE8)),
          DunesColors.resolve(context, Color(0xFF4A3BC7)),
        ],
        onTap: widget.onOpenAppUsage,
      ),
    ];

    final personalItems = <_SuperviseItemData>[
      _SuperviseItemData(
        title: '会议纪要',
        subtitle: '',
        icon: Icons.fact_check_outlined,
        gradientColors: [
          DunesColors.resolve(context, Color(0xFF9E43C2)),
          DunesColors.resolve(context, Color(0xFF7A25A0)),
        ],
        onTap: widget.onOpenMeetingSupervise,
      ),
      _SuperviseItemData(
        title: 'IM会话',
        subtitle: '',
        icon: Icons.forum_outlined,
        gradientColors: [
          DunesColors.resolve(context, Color(0xFF4884E8)),
          DunesColors.resolve(context, Color(0xFF2E63BE)),
        ],
        onTap: widget.onOpenSessionSupervise,
      ),
      _SuperviseItemData(
        title: '知识库',
        subtitle: '',
        icon: Icons.folder_shared_outlined,
        gradientColors: [
          DunesColors.resolve(context, Color(0xFFD67E33)),
          DunesColors.resolve(context, Color(0xFFB5611B)),
        ],
        onTap: widget.onOpenKbSupervise,
      ),
      _SuperviseItemData(
        title: '任务',
        subtitle: '',
        icon: Icons.task_alt_outlined,
        gradientColors: [
          DunesColors.resolve(context, Color(0xFF2F8F7E)),
          DunesColors.resolve(context, Color(0xFF1F6F62)),
        ],
        onTap: widget.onOpenTaskMonitor,
      ),
      _SuperviseItemData(
        title: '日报',
        subtitle: '',
        icon: Icons.edit_calendar_outlined,
        gradientColors: [
          DunesColors.resolve(context, Color(0xFF3D7A8C)),
          DunesColors.resolve(context, Color(0xFF2A5C6B)),
        ],
        onTap: widget.onOpenDailyReportMonitor,
      ),
      _SuperviseItemData(
        title: '群响应',
        subtitle: '',
        icon: Icons.mark_chat_unread_outlined,
        gradientColors: [
          DunesColors.resolve(context, Color(0xFF5B6FC4)),
          DunesColors.resolve(context, Color(0xFF3E529E)),
        ],
        onTap: widget.onOpenGroupReply,
      ),
      if (widget.onOpenProposalSla != null)
        _SuperviseItemData(
          title: '提案时效',
          subtitle: '',
          icon: Icons.timer_outlined,
          gradientColors: [
            DunesColors.resolve(context, Color(0xFFC45B7A)),
            DunesColors.resolve(context, Color(0xFF9E3E5C)),
          ],
          onTap: widget.onOpenProposalSla,
        ),
      _SuperviseItemData(
        title: '研发账号',
        subtitle: '',
        icon: Icons.manage_accounts_outlined,
        gradientColors: [
          DunesColors.resolve(context, Color(0xFF4A3E66)),
          DunesColors.resolve(context, Color(0xFF322849)),
        ],
        onTap: widget.onOpenCursorAccount,
      ),
    ];
    final lookupSubtitle = widget.onOpenProposalSla == null
        ? '任务 · 日报 · 群响应'
        : '任务 · 日报 · 群响应 · 提案时效';

    return ColoredBox(
      color: DunesColors.resolve(
        context,
        _bgSurface,
        role: DunesColorRole.surface,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  // 顶部微光柔和紫光渐变，保留高质感背景氛围
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 160,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            DunesColors.resolve(
                              context,
                              Color(0xFFEFE9FA),
                              role: DunesColorRole.surface,
                            ),
                            DunesColors.resolve(
                              context,
                              Color(0xFFF7F4FD),
                              role: DunesColorRole.surface,
                            ),
                            DunesColors.resolve(
                              context,
                              _bgSurface,
                              role: DunesColorRole.surface,
                            ),
                          ],
                          stops: [0.0, 0.6, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // 页面主体容器（PC 端响应式铺平，APP 端紧凑单列）
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 768;
                      final horizontalPadding = isWide ? 24.0 : 16.0;

                      return RefreshIndicator(
                        color: _themePurple,
                        onRefresh: _refreshAll,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            16,
                            horizontalPadding,
                            dunesAppBottomNavContentPadding(
                              context,
                              fallback: 40,
                            ),
                          ),
                          children: [
                            // 1. 资金看板（PC 全宽上下结构，宽屏内 2 列铺开）
                            if (assetRows.isNotEmpty) ...[
                              _buildFinanceAssetCard(assetRows, isWide: isWide),
                              SizedBox(height: isWide ? 18 : 14),
                            ],

                            // 2. 督导管理区：组织汇总 / 业务查阅 拆分
                            if (summaryItems.isNotEmpty) ...[
                              _buildSuperviseGridCard(
                                summaryItems,
                                isWide: isWide,
                                title: '组织汇总',
                                subtitle: '部门态势 · 用量与效能',
                              ),
                              SizedBox(height: isWide ? 18 : 14),
                            ],
                            if (personalItems.isNotEmpty) ...[
                              _buildSuperviseGridCard(
                                personalItems,
                                isWide: isWide,
                                title: '业务查阅',
                                subtitle: lookupSubtitle.isEmpty
                                    ? '会议纪要 · IM会话 · 知识库'
                                    : lookupSubtitle,
                              ),
                              SizedBox(height: isWide ? 18 : 14),
                            ],

                            // 3. 数字员工专区（PC 宽屏自适应 3~4 列平铺网格）
                            if (_canUseDigitalEmployees &&
                                (_loadingDigitalEmployees ||
                                    _digitalEmployees.isNotEmpty)) ...[
                              _buildDigitalEmployeesSection(
                                _digitalEmployees,
                                isWide: isWide,
                              ),
                              const SizedBox(height: 18),
                            ],

                            // 4. 智能机器人矩阵（PC 宽屏双列平铺网格）
                            if (_canUseRobots &&
                                (_loadingRobots || _robots.isNotEmpty)) ...[
                              _buildRobotSection(_robots, isWide: isWide),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 1. 资金与财务看板
  Widget _buildFinanceAssetCard(List<Widget> assetRows, {bool isWide = false}) {
    return Container(
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            _cardBorder,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: DunesColors.resolveNullable(
                      context,
                      _themePurple,
                      role: DunesColorRole.surface,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '资金看板',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.resolveNullable(context, _deepPurple),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '账户流向 · 月结 · 差旅',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: DunesColors.resolveNullable(context, _subText),
                    ),
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final useTwoCol = isWide && constraints.maxWidth >= 720;
              if (!useTwoCol) {
                return Column(
                  children: [
                    for (var i = 0; i < assetRows.length; i++) ...[
                      assetRows[i],
                      if (i < assetRows.length - 1)
                        Divider(
                          height: 1,
                          indent: 64,
                          endIndent: 16,
                          color: DunesColors.resolve(
                            context,
                            Color(0xFFF3F0F7),
                            role: DunesColorRole.border,
                          ),
                        ),
                    ],
                  ],
                );
              }

              const columns = 2;
              final itemWidth = (constraints.maxWidth / columns)
                  .floorToDouble();
              return Wrap(
                children: [
                  for (var i = 0; i < assetRows.length; i++)
                    SizedBox(
                      width: itemWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            right: i.isEven
                                ? BorderSide(
                                    color: DunesColors.resolve(
                                      context,
                                      Color(0xFFF3F0F7),
                                      role: DunesColorRole.border,
                                    ),
                                  )
                                : BorderSide.none,
                            bottom:
                                i <
                                    assetRows.length -
                                        (assetRows.length.isOdd ? 1 : 2)
                                ? BorderSide(
                                    color: DunesColors.resolve(
                                      context,
                                      Color(0xFFF3F0F7),
                                      role: DunesColorRole.border,
                                    ),
                                  )
                                : BorderSide.none,
                          ),
                        ),
                        child: assetRows[i],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 2. 管理与督导金刚区
  Widget _buildSuperviseGridCard(
    List<_SuperviseItemData> items, {
    bool isWide = false,
    String title = '',
    String subtitle = '',
  }) {
    return Container(
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            _cardBorder,
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
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: DunesColors.resolveNullable(
                        context,
                        _themePurple,
                        role: DunesColorRole.surface,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.resolveNullable(context, _deepPurple),
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: DunesColors.resolveNullable(context, _subText),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = isWide
                  ? (constraints.maxWidth >= 960
                        ? 6
                        : (constraints.maxWidth >= 480 ? 4 : 3))
                  : 4;
              const gap = 8.0;
              final itemWidth =
                  ((constraints.maxWidth - (columns - 1) * gap) / columns)
                      .floorToDouble();

              return Wrap(
                spacing: gap,
                runSpacing: 14,
                children: [
                  for (final item in items)
                    SizedBox(
                      width: itemWidth,
                      child: _AlipayGridItem(
                        icon: item.icon,
                        gradientColors: item.gradientColors,
                        title: item.title,
                        subtitle: item.subtitle,
                        onTap: item.onTap,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 3. 数字员工专区
  Widget _buildDigitalEmployeesSection(
    List<DigitalEmployeeItem> items, {
    bool isWide = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: DunesColors.resolveNullable(
                    context,
                    _themePurple,
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'AI 数字员工',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolveNullable(context, _deepPurple),
                ),
              ),
              if (_loadingDigitalEmployees) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _themePurple,
                  ),
                ),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: DunesColors.resolve(
                    context,
                    const Color(0xFFF1EBF9),
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: 12,
                      color: DunesColors.resolveNullable(context, _themePurple),
                    ),
                    SizedBox(width: 2),
                    Text(
                      '7×24h 在岗运行',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.resolveNullable(
                          context,
                          _themePurple,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = isWide
                ? (constraints.maxWidth >= 1050
                      ? 4
                      : (constraints.maxWidth >= 680 ? 3 : 2))
                : (constraints.maxWidth >= 360 ? 2 : 1);
            const gap = 8.0;
            final itemWidth =
                ((constraints.maxWidth - (columns - 1) * gap) / columns)
                    .floorToDouble();

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in items)
                  SizedBox(
                    width: itemWidth,
                    child: _DigitalEmployeeCard(
                      item: item,
                      onTap: () => _onTapDigitalEmployee(item),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// 4. 智能机器人矩阵
  Widget _buildRobotSection(List<RobotRole> robots, {bool isWide = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: DunesColors.resolveNullable(
                    context,
                    _themePurple,
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '智能机器人矩阵',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolveNullable(context, _deepPurple),
                ),
              ),
              if (_loadingRobots) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _themePurple,
                  ),
                ),
              ],
              const Spacer(),
              if (widget.onOpenRobotHome != null)
                InkWell(
                  onTap: widget.onOpenRobotHome,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Text(
                          '服务大厅',
                          style: TextStyle(
                            fontSize: 12,
                            color: DunesColors.resolveNullable(
                              context,
                              _subText,
                            ),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: DunesColors.resolveNullable(context, _subText),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            if (isWide && constraints.maxWidth >= 680) {
              const columns = 2;
              const gap = 12.0;
              final itemWidth =
                  ((constraints.maxWidth - (columns - 1) * gap) / columns)
                      .floorToDouble();

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final robot in robots)
                    SizedBox(
                      width: itemWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          color: DunesColors.resolve(
                            context,
                            Colors.white,
                            role: DunesColorRole.surface,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: DunesColors.resolve(
                              context,
                              _cardBorder,
                              role: DunesColorRole.border,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF331E54,
                              ).withValues(alpha: 0.04),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: _RobotListTile(
                          role: robot,
                          onTap: () {
                            if (widget.onOpenRobot != null) {
                              widget.onOpenRobot!(robot);
                              return;
                            }
                            widget.onOpenRobotHome?.call();
                          },
                        ),
                      ),
                    ),
                ],
              );
            }

            return Container(
              decoration: BoxDecoration(
                color: DunesColors.resolve(
                  context,
                  Colors.white,
                  role: DunesColorRole.surface,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: DunesColors.resolve(
                    context,
                    _cardBorder,
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
                children: [
                  for (var i = 0; i < robots.length; i++) ...[
                    _RobotListTile(
                      role: robots[i],
                      onTap: () {
                        if (widget.onOpenRobot != null) {
                          widget.onOpenRobot!(robots[i]);
                          return;
                        }
                        widget.onOpenRobotHome?.call();
                      },
                    ),
                    if (i < robots.length - 1)
                      Divider(
                        height: 1,
                        indent: 64,
                        endIndent: 16,
                        color: DunesColors.resolve(
                          context,
                          Color(0xFFF3F0F7),
                          role: DunesColorRole.border,
                        ),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildNoAccessView() {
    return ColoredBox(
      color: DunesColors.resolve(
        context,
        _bgSurface,
        role: DunesColorRole.surface,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: DunesColors.resolve(
                    context,
                    const Color(0xFFF0EEF7),
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: DunesColors.resolve(
                      context,
                      _cardBorder,
                      role: DunesColorRole.border,
                    ),
                  ),
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 28,
                  color: DunesColors.resolve(context, DunesColors.text3),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '暂无权限',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.resolve(context, DunesColors.text),
                  context: context,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '当前账号未开通访问权限，如需使用请联系管理员。',
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.text3),
                  height: 1.5,
                  context: context,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuperviseItemData {
  const _SuperviseItemData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final VoidCallback? onTap;
}

/// 支付宝列表风格资产单行组件
class _AlipayAssetRow extends StatelessWidget {
  const _AlipayAssetRow({
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.actionText,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String actionText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // 浅底圆角高质感双色图标
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: DunesColors.resolveNullable(
                    context,
                    iconBgColor,
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  color: DunesColors.resolveNullable(context, iconColor),
                  size: 21,
                ),
              ),
              const SizedBox(width: 14),

              // 主副标题
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.resolveNullable(
                          context,
                          _deepPurple,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: DunesColors.resolveNullable(context, _subText),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              // 右侧辅助说明文案 + 细箭头
              Text(
                actionText,
                style: TextStyle(
                  fontSize: 12.5,
                  color: DunesColors.resolveNullable(
                    context,
                    Color(0xFF9F98AC),
                  ),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: DunesColors.resolveNullable(context, Color(0xFFB5AFBF)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 支付宝金刚区单项组件
class _AlipayGridItem extends StatelessWidget {
  const _AlipayGridItem({
    required this.icon,
    required this.gradientColors,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final List<Color> gradientColors;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 立体微渐变底座 + 高质感白图标
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradientColors,
                  ),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors.last.withValues(alpha: 0.22),
                      blurRadius: 7,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  color: DunesColors.resolve(context, Colors.white),
                  size: 21,
                ),
              ),
              const SizedBox(height: 8),

              // 主标题
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolveNullable(context, _deepPurple),
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: DunesColors.resolveNullable(context, _subText),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 数字员工大卡片组件
class _DigitalEmployeeCard extends StatelessWidget {
  const _DigitalEmployeeCard({required this.item, required this.onTap});

  final DigitalEmployeeItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                _cardBorder,
                role: DunesColorRole.border,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF331E54).withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: DunesColors.resolve(
                        context,
                        const Color(0xFFF0EBF9),
                        role: DunesColorRole.surface,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: DunesColors.resolve(
                          context,
                          const Color(0xFFE2D6F5),
                          role: DunesColorRole.border,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      digitalEmployeeIcon(item.iconKey),
                      color: DunesColors.resolveNullable(context, _themePurple),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: DunesColors.resolveNullable(
                              context,
                              _deepPurple,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: DunesColors.resolve(
                              context,
                              const Color(0xFFEDE7F6),
                              role: DunesColorRole.surface,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'AI 协同助理',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: DunesColors.resolveNullable(
                                context,
                                _themePurple,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.25,
                  color: DunesColors.resolveNullable(context, _subText),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: DunesColors.resolve(
                        context,
                        _themePurple,
                        role: DunesColorRole.surface,
                      ).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '开启对话',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.resolveNullable(
                              context,
                              _themePurple,
                            ),
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 12,
                          color: DunesColors.resolveNullable(
                            context,
                            _themePurple,
                          ),
                        ),
                      ],
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

/// 机器人单行卡片组件
class _RobotListTile extends StatelessWidget {
  const _RobotListTile({required this.role, required this.onTap});

  final RobotRole role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RobotConsultStore.instance,
      builder: (context, _) {
        final store = RobotConsultStore.instance;
        final status = store.hubStatus;
        final isBusy =
            status == RobotConsultStatus.running ||
            status == RobotConsultStatus.queued;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // 头像与状态光标
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: DunesColors.resolveNullable(
                            context,
                            role.accent.withValues(alpha: 0.12),
                            role: DunesColorRole.surface,
                          ),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        alignment: Alignment.center,
                        child: RobotFaceAvatar(
                          role: role,
                          size: 34,
                          animate: true,
                          busy: isBusy,
                        ),
                      ),
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: role.canChat
                                ? DunesColors.resolve(
                                    context,
                                    const Color(0xFF2E7D32),
                                    role: DunesColorRole.surface,
                                  )
                                : DunesColors.resolve(
                                    context,
                                    const Color(0xFFD67E33),
                                    role: DunesColorRole.surface,
                                  ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: DunesColors.resolve(
                                context,
                                Colors.white,
                                role: DunesColorRole.border,
                              ),
                              width: 1.8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),

                  // 机器人名称与职能
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                role.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: DunesColors.resolveNullable(
                                    context,
                                    _deepPurple,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (!role.canChat)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: DunesColors.resolve(
                                    context,
                                    const Color(0xFFFFF3E0),
                                    role: DunesColorRole.surface,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '仅推送',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: DunesColors.resolveNullable(
                                      context,
                                      Color(0xFFB5611B),
                                    ),
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: DunesColors.resolve(
                                    context,
                                    const Color(0xFFE8F5E9),
                                    role: DunesColorRole.surface,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '在线',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: DunesColors.resolveNullable(
                                      context,
                                      Color(0xFF2E7D32),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          role.desc.isNotEmpty ? role.desc : role.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: DunesColors.resolveNullable(
                              context,
                              _subText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 右侧咨询按钮
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: DunesColors.resolve(
                        context,
                        _themePurple,
                        role: DunesColorRole.surface,
                      ).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          role.canChat ? '咨询' : '详情',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.resolveNullable(
                              context,
                              _themePurple,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 15,
                          color: DunesColors.resolveNullable(
                            context,
                            _themePurple,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
