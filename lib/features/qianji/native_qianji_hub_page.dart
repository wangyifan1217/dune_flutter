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
    this.onOpenEfficiencyAnalysis,
    this.onOpenEfficiencyBossPreview,
    this.onOpenAppUsage,
    this.onOpenFundSecondment,
    this.onOpenCashFlow,
    this.onOpenMonthlyBill,
    this.onOpenTravel,
    this.onOpenRobotHome,
    this.onOpenRobot,
    this.onOpenDigitalEmployee,
    this.session,
  });

  final VoidCallback onOpenCursorAccount;
  final VoidCallback? onOpenMeetingSupervise;
  final VoidCallback? onOpenSessionSupervise;
  final VoidCallback? onOpenKbSupervise;
  final VoidCallback? onOpenEfficiencyAnalysis;
  final VoidCallback? onOpenEfficiencyBossPreview;
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

  @override
  State<NativeQianjiHubPage> createState() => _NativeQianjiHubPageState();
}

class _NativeQianjiHubPageState extends State<NativeQianjiHubPage> {
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
    await Future.wait([
      _loadRobots(),
      _loadDigitalEmployees(),
    ]);
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
        ({
          String title,
          String subtitle,
          IconData icon,
          VoidCallback onTap,
        })> items,
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
    if (!_hasAccess) {
      return _buildNoAccessView();
    }

    final assetRows = <Widget>[
      if (widget.onOpenCashFlow != null)
        _AlipayAssetRow(
          icon: Icons.account_balance_rounded,
          iconBgColor: const Color(0xFFE8F5E9),
          iconColor: const Color(0xFF2E7D32),
          title: '资金流向',
          subtitle: '公司账户 · 由大到小',
          actionText: '实时看板',
          onTap: widget.onOpenCashFlow!,
        ),
      if (widget.onOpenMonthlyBill != null)
        _AlipayAssetRow(
          icon: Icons.receipt_long_rounded,
          iconBgColor: const Color(0xFFEDE7F6),
          iconColor: _themePurple,
          title: '月结',
          subtitle: '应收 · 应付',
          actionText: '账单台账',
          onTap: widget.onOpenMonthlyBill!,
        ),
      if (widget.onOpenFundSecondment != null)
        _AlipayAssetRow(
          icon: Icons.account_balance_wallet_rounded,
          iconBgColor: const Color(0xFFFFF3E0),
          iconColor: const Color(0xFFE65100),
          title: '资金借调',
          subtitle: '已通过借款单',
          actionText: '借还明细',
          onTap: widget.onOpenFundSecondment!,
        ),
      if (widget.onOpenTravel != null)
        _AlipayAssetRow(
          icon: Icons.flight_takeoff_rounded,
          iconBgColor: const Color(0xFFE0F7FA),
          iconColor: const Color(0xFF00838F),
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
        subtitle: widget.onOpenEfficiencyAnalysis != null &&
                widget.onOpenEfficiencyBossPreview != null
            ? '态势 · 能效'
            : (widget.session?.workSituationViewAll == true
                ? '全部部门'
                : '本人及下级'),
        icon: Icons.groups_outlined,
        gradientColors: const [Color(0xFF8B6BE8), Color(0xFF6743D3)],
        onTap: workSituationTap,
      ),
      _SuperviseItemData(
        title: '使用热力',
        subtitle: widget.session?.appUsageViewAll == true
            ? '全部人员'
            : '本人及下级',
        icon: Icons.grid_view_rounded,
        gradientColors: const [Color(0xFF6B5CE8), Color(0xFF4A3BC7)],
        onTap: widget.onOpenAppUsage,
      ),
    ];

    final personalItems = <_SuperviseItemData>[
      _SuperviseItemData(
        title: '会议纪要',
        subtitle: '本人及下级',
        icon: Icons.fact_check_outlined,
        gradientColors: const [Color(0xFF9E43C2), Color(0xFF7A25A0)],
        onTap: widget.onOpenMeetingSupervise,
      ),
      _SuperviseItemData(
        title: 'IM会话',
        subtitle: '本人及下级',
        icon: Icons.forum_outlined,
        gradientColors: const [Color(0xFF4884E8), Color(0xFF2E63BE)],
        onTap: widget.onOpenSessionSupervise,
      ),
      _SuperviseItemData(
        title: '知识库',
        subtitle: '本人及下级',
        icon: Icons.folder_shared_outlined,
        gradientColors: const [Color(0xFFD67E33), Color(0xFFB5611B)],
        onTap: widget.onOpenKbSupervise,
      ),
      _SuperviseItemData(
        title: 'Cursor账号',
        subtitle: '账号与用量',
        icon: Icons.manage_accounts_outlined,
        gradientColors: const [Color(0xFF4A3E66), Color(0xFF322849)],
        onTap: widget.onOpenCursorAccount,
      ),
    ];

    return ColoredBox(
      color: _bgSurface,
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
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFFEFE9FA),
                            Color(0xFFF7F4FD),
                            _bgSurface,
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
                              _buildFinanceAssetCard(
                                assetRows,
                                isWide: isWide,
                              ),
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
                                subtitle: '会议 · 会话 · 知识 · 账号',
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
  Widget _buildFinanceAssetCard(
    List<Widget> assetRows, {
    bool isWide = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
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
                    color: _themePurple,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '资金看板',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: _deepPurple,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '账户流向 · 月结 · 差旅',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _subText,
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
                        const Divider(
                          height: 1,
                          indent: 64,
                          endIndent: 16,
                          color: Color(0xFFF3F0F7),
                        ),
                    ],
                  ],
                );
              }

              const columns = 2;
              final itemWidth = (constraints.maxWidth / columns).floorToDouble();
              return Wrap(
                children: [
                  for (var i = 0; i < assetRows.length; i++)
                    SizedBox(
                      width: itemWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            right: i.isEven
                                ? const BorderSide(color: Color(0xFFF3F0F7))
                                : BorderSide.none,
                            bottom: i <
                                    assetRows.length -
                                        (assetRows.length.isOdd ? 1 : 2)
                                ? const BorderSide(color: Color(0xFFF3F0F7))
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
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
                      color: _themePurple,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: _deepPurple,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: _subText,
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
                  color: _themePurple,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'AI 数字员工',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _deepPurple,
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
                  color: const Color(0xFFF1EBF9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 12, color: _themePurple),
                    SizedBox(width: 2),
                    Text(
                      '7×24h 在岗运行',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _themePurple,
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
  Widget _buildRobotSection(
    List<RobotRole> robots, {
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
                  color: _themePurple,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '智能机器人矩阵',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _deepPurple,
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
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Text(
                          '服务大厅',
                          style: TextStyle(
                            fontSize: 12,
                            color: _subText,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: _subText,
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _cardBorder),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF331E54).withValues(alpha: 0.04),
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cardBorder),
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
                      const Divider(
                        height: 1,
                        indent: 64,
                        endIndent: 16,
                        color: Color(0xFFF3F0F7),
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
      color: _bgSurface,
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
                  color: const Color(0xFFF0EEF7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _cardBorder),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  size: 28,
                  color: DunesColors.text3,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '暂无权限',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '当前账号未开通访问权限，如需使用请联系管理员。',
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text3,
                  height: 1.5,
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
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor, size: 21),
              ),
              const SizedBox(width: 14),

              // 主副标题
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _deepPurple,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _subText,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              // 右侧辅助说明文案 + 细箭头
              Text(
                actionText,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF9F98AC),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Color(0xFFB5AFBF),
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
                child: Icon(icon, color: Colors.white, size: 21),
              ),
              const SizedBox(height: 8),

              // 主标题
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _deepPurple,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),

              // 副标题小说明
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: _subText,
                  fontWeight: FontWeight.w400,
                ),
              ),
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _cardBorder),
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
                      color: const Color(0xFFF0EBF9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2D6F5)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      digitalEmployeeIcon(item.iconKey),
                      color: _themePurple,
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
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _deepPurple,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDE7F6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'AI 协同助理',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: _themePurple,
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
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.25,
                  color: _subText,
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
                      color: _themePurple.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '开启对话',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: _themePurple,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 12,
                          color: _themePurple,
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
        final isBusy = status == RobotConsultStatus.running ||
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
                          color: role.accent.withValues(alpha: 0.12),
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
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFD67E33),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.8),
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
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: _deepPurple,
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
                                  color: const Color(0xFFFFF3E0),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '仅推送',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFB5611B),
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
                                  color: const Color(0xFFE8F5E9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '在线',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2E7D32),
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
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: _subText,
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
                      color: _themePurple.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          role.canChat ? '咨询' : '详情',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _themePurple,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 15,
                          color: _themePurple,
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
