import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../robots/robot_character.dart';
import '../robots/robot_consult_store.dart';
import '../robots/robot_models.dart';
import '../robots/robot_service.dart';

const _themePurple = Color(0xFF7B5CD8);
const _hubCardColumns = 3;
const _hubCardGap = 12.0;

double _hubCardWidth(double availableWidth) {
  // Floor so 3×width + 2×gap never exceeds maxWidth (avoids 4th card staying on row 1
  // on wide screens, and prevents FP overflow wrapping early on APP).
  final totalGap = (_hubCardColumns - 1) * _hubCardGap;
  final raw = (availableWidth - totalGap) / _hubCardColumns;
  return raw.floorToDouble().clamp(1.0, availableWidth);
}

/// NOVA Hub：机器人（接口目录）+ 管理入口。
class NativeQianjiHubPage extends StatefulWidget {
  const NativeQianjiHubPage({
    super.key,
    required this.onOpenCursorAccount,
    this.onOpenMeetingSupervise,
    this.onOpenSessionSupervise,
    this.onOpenKbSupervise,
    this.onOpenRobotHome,
    this.onOpenRobot,
    this.session,
  });

  final VoidCallback onOpenCursorAccount;
  final VoidCallback? onOpenMeetingSupervise;
  final VoidCallback? onOpenSessionSupervise;
  final VoidCallback? onOpenKbSupervise;
  final VoidCallback? onOpenRobotHome;
  /// 点击单个机器人名片：由 Host 按 canChat 决定进聊天或提示。
  final ValueChanged<RobotRole>? onOpenRobot;
  final AuthSession? session;

  @override
  State<NativeQianjiHubPage> createState() => _NativeQianjiHubPageState();
}

class _NativeQianjiHubPageState extends State<NativeQianjiHubPage> {
  List<RobotRole> _robots = const [];
  bool _loadingRobots = false;

  bool get _hasAccess =>
      widget.session == null || widget.session!.effectiveQianjiAccess;

  bool get _canUseRobots =>
      widget.session == null || widget.session!.effectiveRobotAccess;

  @override
  void initState() {
    super.initState();
    final store = RobotConsultStore.instance;
    store.bindSession(widget.session);
    _loadRobots();
    if (widget.session != null && widget.session!.effectiveRobotAccess) {
      store.refreshHub();
    }
  }

  Future<void> _loadRobots() async {
    final session = widget.session;
    if (session == null || !session.effectiveRobotAccess) {
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

  @override
  Widget build(BuildContext context) {
    if (!_hasAccess) {
      return _buildNoAccessView();
    }

    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  if (_canUseRobots && (_loadingRobots || _robots.isNotEmpty)) ...[
                    _RobotHubPreview(
                      robots: _robots,
                      loading: _loadingRobots,
                      onOpenRobot: widget.onOpenRobot,
                      onOpenConsultList: widget.onOpenRobotHome,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _NovaHubSection(
                    title: '管理',
                    accent: _themePurple,
                    children: [
                      _NovaHubTile(
                        title: 'Cursor账号',
                        subtitle: '账号与用量',
                        icon: Icons.manage_accounts_outlined,
                        color: _themePurple,
                        onTap: widget.onOpenCursorAccount,
                      ),
                      _NovaHubTile(
                        title: '会议纪要',
                        subtitle: '本人及下级',
                        icon: Icons.fact_check_outlined,
                        color: _themePurple,
                        onTap: widget.onOpenMeetingSupervise,
                      ),
                      _NovaHubTile(
                        title: 'IM会话',
                        subtitle: '本人及下级',
                        icon: Icons.forum_outlined,
                        color: _themePurple,
                        onTap: widget.onOpenSessionSupervise,
                      ),
                      _NovaHubTile(
                        title: '知识库',
                        subtitle: '本人及下级',
                        icon: Icons.folder_shared_outlined,
                        color: _themePurple,
                        onTap: widget.onOpenKbSupervise,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoAccessView() {
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
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
                  border: Border.all(color: const Color(0xFFE8EAED)),
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

class _RobotHubPreview extends StatelessWidget {
  const _RobotHubPreview({
    required this.robots,
    this.loading = false,
    this.onOpenRobot,
    this.onOpenConsultList,
  });

  final List<RobotRole> robots;
  final bool loading;
  final ValueChanged<RobotRole>? onOpenRobot;
  final VoidCallback? onOpenConsultList;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: RobotTheme.purple,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '机器人',
                style: DunesTypography.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: RobotTheme.purple,
                ),
              ),
              if (loading) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = _hubCardWidth(constraints.maxWidth);
              return Wrap(
                spacing: _hubCardGap,
                runSpacing: _hubCardGap,
                children: [
                  for (final robot in robots)
                    _RobotMiniCard(
                      role: robot,
                      width: cardWidth,
                      onTap: () {
                        if (onOpenRobot != null) {
                          onOpenRobot!(robot);
                          return;
                        }
                        onOpenConsultList?.call();
                      },
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RobotMiniCard extends StatelessWidget {
  const _RobotMiniCard({
    required this.role,
    required this.width,
    this.onTap,
  });

  final RobotRole role;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RobotConsultStore.instance,
      builder: (context, _) {
        final store = RobotConsultStore.instance;
        final status = store.hubStatus;
        final active = store.activeCount;
        return Material(
          color: const Color(0xFFF8F7FB),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: role.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: RobotFaceAvatar(
                            role: role,
                            size: 36,
                            animate: true,
                            busy: status == RobotConsultStatus.running ||
                                status == RobotConsultStatus.queued,
                          ),
                        ),
                        if (!role.canChat)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF4E5),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0xFFE8C48A),
                                ),
                              ),
                              child: const Text(
                                '仅推送',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFB07A2B),
                                ),
                              ),
                            ),
                          )
                        else if (status != null)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: _StatusDot(status: status),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      role.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (!role.canChat)
                      const Text(
                        '仅推送通知',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.25,
                          color: DunesColors.text3,
                        ),
                      )
                    else if (status != null)
                      Text(
                        active > 1
                            ? '${status.label} · $active'
                            : status.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: status == RobotConsultStatus.running
                              ? RobotTheme.purple
                              : const Color(0xFFB07A2B),
                        ),
                      )
                    else
                      Text(
                        role.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.25,
                          color: DunesColors.text3,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final RobotConsultStatus status;

  @override
  Widget build(BuildContext context) {
    final running = status == RobotConsultStatus.running;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 3,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: running
          ? const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: RobotTheme.purple,
              ),
            )
          : Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFB07A2B),
                shape: BoxShape.circle,
              ),
            ),
    );
  }
}

class _NovaHubTile {
  const _NovaHubTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
}

class _NovaHubSection extends StatelessWidget {
  const _NovaHubSection({
    required this.title,
    required this.accent,
    required this.children,
  });

  final String title;
  final Color accent;
  final List<_NovaHubTile> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = _hubCardWidth(constraints.maxWidth);
              return Wrap(
                spacing: _hubCardGap,
                runSpacing: _hubCardGap,
                children: [
                  for (final tile in children)
                    _NovaHubCard(tile: tile, width: cardWidth),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NovaHubCard extends StatelessWidget {
  const _NovaHubCard({required this.tile, required this.width});

  final _NovaHubTile tile;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8F7FB),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: tile.onTap,
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: tile.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(tile.icon, color: tile.color, size: 18),
                ),
                const SizedBox(height: 12),
                Text(
                  tile.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tile.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.25,
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
