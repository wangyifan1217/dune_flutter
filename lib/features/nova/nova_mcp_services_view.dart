import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../qianji/digital_auto/digital_employee_service.dart';
import '../shell/dunes_toast.dart';

/// 小饕「服务」页：只展示沙丘现有的 MCP 数字员工，不另做对话。
class NovaMcpServicesView extends StatefulWidget {
  const NovaMcpServicesView({
    super.key,
    required this.session,
    this.onOpenDigitalEmployee,
  });

  final AuthSession session;
  final ValueChanged<DigitalEmployeeItem>? onOpenDigitalEmployee;

  static const fallbackEmployees = <DigitalEmployeeItem>[
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

  @override
  State<NovaMcpServicesView> createState() => _NovaMcpServicesViewState();
}

class _NovaMcpServicesViewState extends State<NovaMcpServicesView> {
  List<DigitalEmployeeItem> _items = const [];
  bool _loading = false;

  bool get _canUse => widget.session.effectiveDigitalEmployeeAccess;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_canUse) {
      setState(() {
        _items = const [];
        _loading = false;
      });
      return;
    }
    if (!widget.session.digitalEmployeeAccessKnown) {
      setState(() {
        _items = NovaMcpServicesView.fallbackEmployees;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final list = await DigitalEmployeeService(
        session: widget.session,
      ).listEmployees();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loading = false;
      });
    }
  }

  void _onTap(DigitalEmployeeItem item) {
    if (item.comingSoon || widget.onOpenDigitalEmployee == null) {
      showDunesToast(context, '${item.name}即将上线');
      return;
    }
    switch (item.screenId) {
      case 'QJMA':
      case 'QJTO':
      case 'QJAM':
      case 'QJDE':
        widget.onOpenDigitalEmployee!(item);
        return;
      default:
        showDunesToast(context, '${item.name}即将上线');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF5F5F7),
        role: DunesColorRole.surface,
      ),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: DunesColors.resolve(context, DunesColors.brandPurple),
        ),
      );
    }
    if (!_canUse) {
      return const _EmptyHint(
        title: '暂无 MCP 服务权限',
        subtitle: '开通数字员工后，可在这里进入会议纪要、渠道对接和资管助理。',
      );
    }
    if (_items.isEmpty) {
      return const _EmptyHint(
        title: '暂无可用的 MCP 服务',
        subtitle: '当前账号下还没有可使用的数字员工。',
      );
    }
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'MCP 数字员工',
            style: DunesTypography.sans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: DunesColors.resolve(context, DunesColors.text),
              context: context,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '接入沙丘现有 MCP 能力，点进去就是原来的助理对话。',
            style: DunesTypography.sans(
              fontSize: 13,
              color: DunesColors.resolve(context, DunesColors.text2),
              context: context,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              DunesColors.imSurface,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                DunesColors.borderSoft,
                role: DunesColorRole.border,
              ),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: DunesColors.text.withValues(alpha: 0.04),
                offset: const Offset(0, 6),
                blurRadius: 20,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _items.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 74),
                    child: Divider(
                      height: 0.6,
                      thickness: 0.6,
                      color: DunesColors.resolve(
                        context,
                        DunesColors.borderSoft,
                        role: DunesColorRole.border,
                      ),
                    ),
                  ),
                _McpEmployeeCard(item: _items[i], onTap: () => _onTap(_items[i])),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: DunesColors.resolve(
                  context,
                  DunesColors.bgSoft,
                  role: DunesColorRole.surface,
                ),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.hub_outlined,
                size: 28,
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: DunesTypography.sans(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: DunesColors.resolve(context, DunesColors.text),
                context: context,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: DunesTypography.sans(
                fontSize: 13,
                height: 1.45,
                color: DunesColors.resolve(context, DunesColors.text2),
                context: context,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _McpEmployeeCard extends StatefulWidget {
  const _McpEmployeeCard({required this.item, required this.onTap});

  final DigitalEmployeeItem item;
  final VoidCallback onTap;

  @override
  State<_McpEmployeeCard> createState() => _McpEmployeeCardState();
}

class _McpEmployeeCardState extends State<_McpEmployeeCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return AnimatedScale(
      scale: _pressed ? 0.985 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          splashColor: DunesColors.brandPurple.withValues(alpha: 0.06),
          highlightColor: DunesColors.resolve(
            context,
            DunesColors.bgSoft,
            role: DunesColorRole.surface,
          ).withValues(alpha: 0.7),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: DunesColors.resolve(
                      context,
                      DunesColors.brandPurpleSoft,
                      role: DunesColorRole.surface,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    digitalEmployeeIcon(item.iconKey),
                    color: DunesColors.resolve(
                      context,
                      DunesColors.brandPurple,
                    ),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: DunesColors.resolve(context, DunesColors.text),
                          context: context,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 12.5,
                          color: DunesColors.resolve(context, DunesColors.text2),
                          context: context,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: DunesColors.resolve(context, DunesColors.text3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
