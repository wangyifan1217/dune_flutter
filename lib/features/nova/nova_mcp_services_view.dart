import 'package:flutter/material.dart';

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
    return ColoredBox(color: const Color(0xFFF6F8FC), child: _buildBody());
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (!_canUse) {
      return _EmptyHint(
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text(
          'MCP 数字员工',
          style: DunesTypography.sans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF191D24),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '接入沙丘现有 MCP 能力，点进去就是原来的助理对话。',
          style: DunesTypography.sans(
            fontSize: 12.5,
            color: const Color(0xFF86909C),
          ),
        ),
        const SizedBox(height: 14),
        for (final item in _items) ...[
          _McpEmployeeCard(item: item, onTap: () => _onTap(item)),
          const SizedBox(height: 12),
        ],
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
            const Icon(Icons.hub_outlined, size: 36, color: Color(0xFFC2C7D0)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: DunesTypography.sans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF4E5969),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: DunesTypography.sans(
                fontSize: 13,
                height: 1.45,
                color: const Color(0xFF86909C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _McpEmployeeCard extends StatelessWidget {
  const _McpEmployeeCard({required this.item, required this.onTap});

  final DigitalEmployeeItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEEF0F5)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A2B3B60),
                offset: Offset(0, 4),
                blurRadius: 14,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1EBFA),
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Icon(
                  digitalEmployeeIcon(item.iconKey),
                  color: const Color(0xFF6B3FE2),
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
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF191D24),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DunesTypography.sans(
                        fontSize: 12.5,
                        color: const Color(0xFF86909C),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: Color(0xFFCFD5DF),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
