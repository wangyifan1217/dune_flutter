import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/dunes_choice_panel.dart';
import '../auth/auth_session.dart';
import '../chat/im_ui_kit.dart';
import '../robots/robot_character.dart';
import '../robots/robot_consult_store.dart';
import '../robots/robot_models.dart';
import '../robots/robot_service.dart';
import '../shell/dunes_main_tab_bar.dart';
import 'digital_auto/digital_employee_service.dart';
import 'qianji_chat_panel.dart';
import 'qianji_chat_service.dart';

/// 新版对话页开关。改为 false 后只保留旧版卡片页。
const bool qianjiHubNewLayoutEnabled = true;

/// 饕板块品牌紫主色系统（与全 App 统一的 #7B5CD8 iOS 质感对齐）。
const _themePurple = ImVisualTokens.purple;
const _deepPurple = Color(0xFF1E192B);
const _subText = Color(0xFF7D778C);
const _cardBorder = Color(0xFFECE7F5);
const _bgSurface = ImVisualTokens.iosGroupedBgLight;

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
    return Stack(
      children: [
        Offstage(
          offstage: _newLayout,
          child: TickerMode(
            enabled: !_newLayout,
            child: Stack(
              children: [
                _buildLegacy(),
                Positioned(
                  top: 0,
                  right: 16,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: ImFrostedIsland(
                        padding: EdgeInsets.zero,
                        child: QianjiPillButton(
                          icon: Icons.auto_awesome_rounded,
                          label: '切换新版',
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _newLayout = true);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Offstage(
          offstage: !_newLayout,
          child: TickerMode(
            enabled: _newLayout,
            child: QianjiChatPanel(
              session: widget.session,
              chatService: widget.chatService,
              scopeGroups: _chatScopeGroups(),
              onSwitchLegacy: () => setState(() => _newLayout = false),
            ),
          ),
        ),
      ],
    );
  }

  List<QianjiChatScopeGroup> _chatScopeGroups() => [
    QianjiChatScopeGroup('业务看板', initiallyExpanded: true, [
      if (widget.onOpenCashFlow != null)
        QianjiChatScope('资金流向', widget.onOpenCashFlow),
      if (widget.onOpenMonthlyBill != null)
        QianjiChatScope('月结', widget.onOpenMonthlyBill),
      if (widget.onOpenFundSecondment != null)
        QianjiChatScope('资金借调', widget.onOpenFundSecondment),
      QianjiChatScope('差旅管理', widget.onOpenTravel),
    ]),
    QianjiChatScopeGroup('工作概览', [
      QianjiChatScope('工作情况', _mergedWorkSituationTap()),
      QianjiChatScope('员工画像', widget.onOpenWorkProfileManagement),
      QianjiChatScope('使用热力', widget.onOpenAppUsage),
    ]),
    QianjiChatScopeGroup('业务查阅', [
      QianjiChatScope('会议纪要', widget.onOpenMeetingSupervise),
      QianjiChatScope('IM会话', widget.onOpenSessionSupervise),
      QianjiChatScope('知识库', widget.onOpenKbSupervise),
      QianjiChatScope('任务', widget.onOpenTaskMonitor),
      QianjiChatScope('日报', widget.onOpenDailyReportMonitor),
      QianjiChatScope('群响应', widget.onOpenGroupReply),
      if (widget.onOpenProposalSla != null)
        QianjiChatScope('提案时效', widget.onOpenProposalSla),
      QianjiChatScope('研发账号', widget.onOpenCursorAccount),
    ]),
  ];

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

    final showSwitchPill = _hasAccess && qianjiHubNewLayoutEnabled;
    final dark = ImVisualTokens.isDark(context);
    final canvasBg = dark ? const Color(0xFF12121A) : const Color(0xFFF0EDF7);
    return ColoredBox(
      color: canvasBg,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  // 顶部柔和品牌紫晕光渐变（自动适配日夜间主题，与苹果大卡片形成通透对比）
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 220,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              dark
                                  ? ImVisualTokens.purple.withValues(alpha: 0.20)
                                  : const Color(0xFFE3D8FA),
                              canvasBg,
                            ],
                            stops: const [0.0, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 页面主体容器（居中最大宽度 1120，Bento 响应式布局）
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 768;
                      final useSplitBento =
                          isWide && constraints.maxWidth >= 900;
                      final horizontalPadding = isWide ? 24.0 : 16.0;

                      return RefreshIndicator(
                        color: ImVisualTokens.accent(context),
                        onRefresh: _refreshAll,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            14,
                            horizontalPadding,
                            dunesAppBottomNavContentPadding(
                              context,
                              fallback: 40,
                            ),
                          ),
                          children: [
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1120,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // 顶部 Apple iOS 柔雾工作台 Hero 概览卡（右侧预留「切换新版」悬浮胶囊位）
                                    _buildHeroOverviewCard(
                                      showSwitchPill: showSwitchPill,
                                      isWide: isWide,
                                      financeCount: assetRows.length,
                                      summaryCount: summaryItems.length,
                                      personalCount: personalItems.length,
                                      digitalCount: _digitalEmployees.length,
                                    ),
                                    SizedBox(height: isWide ? 18 : 14),

                                    // 1. 资金看板（Bento 网格卡片：窄屏 2 列，宽屏 4 列）
                                    if (assetRows.isNotEmpty) ...[
                                      _buildFinanceAssetCard(
                                        assetRows,
                                        isWide: isWide,
                                      ),
                                      SizedBox(height: isWide ? 18 : 14),
                                    ],

                                    // 2. 督导管理区：宽屏左右 Bento 双栏并排，窄屏上下错落
                                    if (useSplitBento &&
                                        summaryItems.isNotEmpty &&
                                        personalItems.isNotEmpty) ...[
                                      IntrinsicHeight(
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(
                                              flex: 5,
                                              child: _buildSuperviseGridCard(
                                                summaryItems,
                                                isWide: isWide,
                                                compactColumns: true,
                                                title: '组织汇总',
                                                subtitle: '部门态势 · 用量与效能',
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              flex: 7,
                                              child: _buildSuperviseGridCard(
                                                personalItems,
                                                isWide: isWide,
                                                compactColumns: true,
                                                title: '业务查阅',
                                                subtitle: lookupSubtitle.isEmpty
                                                    ? '会议纪要 · IM会话 · 知识库'
                                                    : lookupSubtitle,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                    ] else ...[
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
                                        (_loadingRobots ||
                                            _robots.isNotEmpty)) ...[
                                      _buildRobotSection(
                                        _robots,
                                        isWide: isWide,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
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

  /// 顶部 Apple iOS 柔雾工作台 Hero 概览卡
  Widget _buildHeroOverviewCard({
    required bool showSwitchPill,
    required bool isWide,
    required int financeCount,
    required int summaryCount,
    required int personalCount,
    required int digitalCount,
  }) {
    final dark = ImVisualTokens.isDark(context);
    final accent = ImVisualTokens.accent(context);
    final accentText = ImVisualTokens.accentText(context);
    final chips = <(IconData, String)>[
      if (financeCount > 0) (Icons.account_balance_wallet_rounded, '资金 $financeCount 项'),
      if (summaryCount > 0) (Icons.pie_chart_rounded, '汇总 $summaryCount 项'),
      if (personalCount > 0) (Icons.grid_view_rounded, '查阅 $personalCount 项'),
      if (digitalCount > 0) (Icons.smart_toy_rounded, '数字员工 $digitalCount'),
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(
        18,
        16,
        showSwitchPill && !isWide ? 18 : 18,
        16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [const Color(0xFF231F36), const Color(0xFF1A1828)]
              : [const Color(0xFFFFFFFF), const Color(0xFFF6F2FF)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent.withValues(alpha: dark ? 0.28 : 0.16),
          width: 0.9,
        ),
        boxShadow: ImVisualTokens.softCardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(right: showSwitchPill ? 104 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '业务工作台',
                        style: DunesTypography.sans(
                          fontSize: isWide ? 24 : 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.45,
                          color: DunesColors.resolveNullable(
                            context,
                            _deepPurple,
                          ),
                          context: context,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: ImVisualTokens.accentSoftSurface(context),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '模块入口',
                        style: DunesTypography.sans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: accentText,
                          context: context,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '资金看板 · 组织督导 · AI 数字协同',
                  style: DunesTypography.sans(
                    fontSize: 12.5,
                    color: DunesColors.resolveNullable(context, _subText),
                    context: context,
                  ),
                ),
              ],
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chip in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: dark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.white.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: ImVisualTokens.hairlineBorder(context),
                        width: 0.65,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(chip.$1, size: 13, color: accentText),
                        const SizedBox(width: 5),
                        Text(
                          chip.$2,
                          style: DunesTypography.sans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.resolveNullable(
                              context,
                              _deepPurple,
                            ),
                            context: context,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 1. 资金与财务看板（Bento 网格卡片）
  Widget _buildFinanceAssetCard(List<Widget> assetRows, {bool isWide = false}) {
    return Container(
      decoration: BoxDecoration(
        color: ImVisualTokens.cardSurface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ImVisualTokens.hairlineBorder(context),
          width: 0.75,
        ),
        boxShadow: ImVisualTokens.softCardShadow(context),
      ),
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
            child: Row(
              children: [
                Container(
                  width: 3.5,
                  height: 15,
                  decoration: BoxDecoration(
                    gradient: ImVisualTokens.primaryGradient(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '资金看板',
                  style: DunesTypography.sans(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: DunesColors.resolveNullable(context, _deepPurple),
                    context: context,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '账户流向 · 月结 · 差旅',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 11.5,
                      color: DunesColors.resolveNullable(context, _subText),
                      context: context,
                    ),
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = isWide && constraints.maxWidth >= 820
                  ? (assetRows.length >= 4 ? 4 : assetRows.length)
                  : (assetRows.length == 1 ? 1 : 2);
              const gap = 10.0;
              final itemWidth =
                  ((constraints.maxWidth - (columns - 1) * gap) / columns)
                      .floorToDouble();

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final row in assetRows)
                    SizedBox(width: itemWidth, child: row),
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
    bool compactColumns = false,
    String title = '',
    String subtitle = '',
  }) {
    return Container(
      decoration: BoxDecoration(
        color: ImVisualTokens.cardSurface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ImVisualTokens.hairlineBorder(context),
          width: 0.75,
        ),
        boxShadow: ImVisualTokens.softCardShadow(context),
      ),
      padding: const EdgeInsets.fromLTRB(12, 15, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Row(
                children: [
                  Container(
                    width: 3.5,
                    height: 15,
                    decoration: BoxDecoration(
                      gradient: ImVisualTokens.primaryGradient(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: DunesTypography.sans(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: DunesColors.resolveNullable(context, _deepPurple),
                      context: context,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 11.5,
                          color: DunesColors.resolveNullable(context, _subText),
                          context: context,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Builder(
            builder: (context) {
              final int columns;
              if (items.length <= 3) {
                columns = items.length;
              } else if (compactColumns) {
                columns = 4;
              } else if (isWide) {
                columns = 6;
              } else {
                columns = 4;
              }
              const gap = 8.0;
              final rowCount = (items.length / columns).ceil();

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var r = 0; r < rowCount; r++) ...[
                    if (r > 0) const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var c = 0; c < columns; c++) ...[
                          if (c > 0) const SizedBox(width: gap),
                          Expanded(
                            child: (r * columns + c) < items.length
                                ? _AlipayGridItem(
                                    icon: items[r * columns + c].icon,
                                    gradientColors:
                                        items[r * columns + c].gradientColors,
                                    title: items[r * columns + c].title,
                                    subtitle: items[r * columns + c].subtitle,
                                    onTap: items[r * columns + c].onTap,
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ],
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
    final accent = ImVisualTokens.accent(context);
    final accentText = ImVisualTokens.accentText(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 3.5,
                height: 15,
                decoration: BoxDecoration(
                  gradient: ImVisualTokens.primaryGradient(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'AI 数字员工',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: DunesColors.resolveNullable(context, _deepPurple),
                  context: context,
                ),
              ),
              if (_loadingDigitalEmployees) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                ),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: ImVisualTokens.accentSoftSurface(context),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.20),
                    width: 0.6,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 12, color: accentText),
                    const SizedBox(width: 2),
                    Text(
                      '7×24h 在岗运行',
                      style: DunesTypography.sans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: accentText,
                        context: context,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = isWide
                ? (constraints.maxWidth >= 1050
                      ? 4
                      : (constraints.maxWidth >= 680 ? 3 : 2))
                : (constraints.maxWidth >= 360 ? 2 : 1);
            const gap = 10.0;
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
    final accent = ImVisualTokens.accent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 3.5,
                height: 15,
                decoration: BoxDecoration(
                  gradient: ImVisualTokens.primaryGradient(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '智能机器人矩阵',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: DunesColors.resolveNullable(context, _deepPurple),
                  context: context,
                ),
              ),
              if (_loadingRobots) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                ),
              ],
              const Spacer(),
              if (widget.onOpenRobotHome != null)
                ImTapScale(
                  onTap: widget.onOpenRobotHome,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '服务大厅',
                          style: DunesTypography.sans(
                            fontSize: 12,
                            color: ImVisualTokens.accentText(context),
                            fontWeight: FontWeight.w600,
                            context: context,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: ImVisualTokens.accentText(context),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
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
                          color: ImVisualTokens.cardSurface(context),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: ImVisualTokens.hairlineBorder(context),
                            width: 0.75,
                          ),
                          boxShadow: ImVisualTokens.softCardShadow(context),
                        ),
                        clipBehavior: Clip.antiAlias,
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

            return ImGroupedCard(
              radius: 18,
              dividerIndent: 74,
              children: [
                for (final robot in robots)
                  _RobotListTile(
                    role: robot,
                    onTap: () {
                      if (widget.onOpenRobot != null) {
                        widget.onOpenRobot!(robot);
                        return;
                      }
                      widget.onOpenRobotHome?.call();
                    },
                  ),
              ],
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
    final dark = ImVisualTokens.isDark(context);
    final tileBg = dark
        ? Colors.white.withValues(alpha: 0.045)
        : const Color(0xFFF9F7FD);
    return ImTapScale(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      pressedScale: 0.965,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tileBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: ImVisualTokens.hairlineBorder(context),
            width: 0.7,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // 浅底圆角高质感双色图标
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: dark
                        ? iconColor.withValues(alpha: 0.16)
                        : DunesColors.resolveNullable(
                            context,
                            iconBgColor,
                            role: DunesColorRole.surface,
                          ),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: iconColor.withValues(alpha: dark ? 0.25 : 0.14),
                      width: 0.6,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    color: DunesColors.resolveNullable(context, iconColor),
                    size: 19,
                  ),
                ),
                const SizedBox(width: 6),
                // 右侧品牌紫柔雾胶囊标签 + 细箭头
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: ImVisualTokens.accentSoftSurface(context),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              actionText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DunesTypography.sans(
                                fontSize: 10.5,
                                color: ImVisualTokens.accentText(context),
                                fontWeight: FontWeight.w600,
                                context: context,
                              ),
                            ),
                          ),
                          const SizedBox(width: 1),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 13,
                            color: ImVisualTokens.accentText(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DunesTypography.sans(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: DunesColors.resolveNullable(context, _deepPurple),
                context: context,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DunesTypography.sans(
                fontSize: 11.5,
                color: DunesColors.resolveNullable(context, _subText),
                fontWeight: FontWeight.w400,
                context: context,
              ),
            ),
          ],
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
    return ImTapScale(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      borderRadius: BorderRadius.circular(14),
      pressedScale: 0.94,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
          children: [
            // 立体微渐变底座 + 顶部高光细边 + 高质感白图标
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 0.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: gradientColors.last.withValues(alpha: 0.28),
                    blurRadius: 10,
                    spreadRadius: -2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 8),

            // 主标题
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DunesTypography.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: DunesColors.resolveNullable(context, _deepPurple),
                letterSpacing: -0.2,
                context: context,
              ),
            ),
            if (subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 10.5,
                  color: DunesColors.resolveNullable(context, _subText),
                  fontWeight: FontWeight.w400,
                  context: context,
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
    final accent = ImVisualTokens.accent(context);
    final accentText = ImVisualTokens.accentText(context);
    return ImTapScale(
      borderRadius: BorderRadius.circular(16),
      pressedScale: 0.968,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
        decoration: BoxDecoration(
          color: ImVisualTokens.cardSurface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: ImVisualTokens.hairlineBorder(context),
            width: 0.75,
          ),
          boxShadow: ImVisualTokens.softCardShadow(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: ImVisualTokens.accentSoftSurface(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.22),
                      width: 0.6,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    digitalEmployeeIcon(item.iconKey),
                    color: accent,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: DunesColors.resolveNullable(
                            context,
                            _deepPurple,
                          ),
                          context: context,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: ImVisualTokens.accentSoftSurface(context),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'AI 协同助理',
                          style: DunesTypography.sans(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: accentText,
                            context: context,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DunesTypography.sans(
                fontSize: 11.5,
                height: 1.25,
                color: DunesColors.resolveNullable(context, _subText),
                context: context,
              ),
            ),
            const SizedBox(height: 9),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ImVisualTokens.accentSoftSurface(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '开启对话',
                        style: DunesTypography.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: accentText,
                          context: context,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 12,
                        color: accentText,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
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
    final dark = ImVisualTokens.isDark(context);
    final accentText = ImVisualTokens.accentText(context);
    return ListenableBuilder(
      listenable: RobotConsultStore.instance,
      builder: (context, _) {
        final store = RobotConsultStore.instance;
        final status = store.hubStatus;
        final isBusy =
            status == RobotConsultStatus.running ||
            status == RobotConsultStatus.queued;

        return ImTapScale(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.zero,
          pressedScale: 0.985,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                // 头像与状态光标
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: role.accent.withValues(alpha: dark ? 0.18 : 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: role.accent.withValues(alpha: 0.18),
                          width: 0.6,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: RobotFaceAvatar(
                        role: role,
                        size: 35,
                        animate: true,
                        busy: isBusy,
                      ),
                    ),
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 10.5,
                        height: 10.5,
                        decoration: BoxDecoration(
                          color: role.canChat
                              ? const Color(0xFF28A745)
                              : const Color(0xFFE08833),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ImVisualTokens.cardSurface(context),
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
                              style: DunesTypography.sans(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: DunesColors.resolveNullable(
                                  context,
                                  _deepPurple,
                                ),
                                context: context,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (!role.canChat)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD67E33).withValues(
                                  alpha: dark ? 0.18 : 0.12,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '仅推送',
                                style: DunesTypography.sans(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFB5611B),
                                  context: context,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E7D32).withValues(
                                  alpha: dark ? 0.18 : 0.10,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '在线',
                                style: DunesTypography.sans(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF2E7D32),
                                  context: context,
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
                        style: DunesTypography.sans(
                          fontSize: 12,
                          color: DunesColors.resolveNullable(context, _subText),
                          context: context,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // 右侧咨询胶囊
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: ImVisualTokens.accentSoftSurface(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        role.canChat ? '咨询' : '详情',
                        style: DunesTypography.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: accentText,
                          context: context,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 15,
                        color: accentText,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
