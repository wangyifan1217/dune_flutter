import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../workbench/native_avatar_sheet.dart';

/// A local, replaceable view-model for the current user's work portrait.
///
/// Integrations can replace [modules] with service-backed states without
/// changing the page layout. The initial snapshot intentionally contains no
/// fabricated business values.
class UserWorkProfileSnapshot {
  const UserWorkProfileSnapshot({required this.modules});

  final List<UserWorkProfileModule> modules;

  factory UserWorkProfileSnapshot.connecting() {
    return UserWorkProfileSnapshot(
      modules: UserWorkProfileModuleType.values
          .map(UserWorkProfileModule.connecting)
          .toList(growable: false),
    );
  }
}

enum UserWorkProfileModuleType {
  workRhythm('工作节奏', Icons.schedule_rounded, Color(0xFF7651B8)),
  collaboration('协作沉淀', Icons.groups_rounded, Color(0xFF9062B8)),
  knowledge('知识成长', Icons.auto_stories_rounded, Color(0xFF6F69BE)),
  business('业务投入', Icons.rocket_launch_rounded, Color(0xFFB1689C)),
  performance('绩效发展', Icons.trending_up_rounded, Color(0xFF8C5A91)),
  benefits('薪酬福利', Icons.volunteer_activism_rounded, Color(0xFF9A6B55));

  const UserWorkProfileModuleType(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

enum UserWorkProfileModuleStatus { connecting, ready, unavailable }

class UserWorkProfileModule {
  const UserWorkProfileModule({
    required this.type,
    required this.status,
    this.summary = '',
  });

  final UserWorkProfileModuleType type;
  final UserWorkProfileModuleStatus status;
  final String summary;

  factory UserWorkProfileModule.connecting(UserWorkProfileModuleType type) {
    return UserWorkProfileModule(
      type: type,
      status: UserWorkProfileModuleStatus.connecting,
    );
  }
}

/// A self-only personal work portrait.
///
/// It reads identity exclusively from [AuthSession], makes no requests, and
/// starts every module in an explicit “数据对接中” state.
class NativeUserWorkProfilePage extends StatelessWidget {
  const NativeUserWorkProfilePage({
    super.key,
    required this.session,
    required this.onBack,
    this.snapshot,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final UserWorkProfileSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final portrait = snapshot ?? UserWorkProfileSnapshot.connecting();
    final name = (session.displayName ?? '').trim().isEmpty
        ? (session.phone.trim().isEmpty ? '我' : session.phone.trim())
        : session.displayName!.trim();
    final identityParts = <String>[
      if (session.departmentName.trim().isNotEmpty)
        session.departmentName.trim(),
      if (session.jobTitle.trim().isNotEmpty) session.jobTitle.trim(),
    ];

    return ColoredBox(
      color: const Color(0xFFF8F5FC),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(onBack: onBack),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _IdentityHero(
                    name: name,
                    identityLine: identityParts.isEmpty
                        ? '我的个人工作画像'
                        : identityParts.join(' · '),
                    avatarUrl: session.avatarUrl,
                    avatarPreset: session.avatarPreset,
                  ),
                  const SizedBox(height: 16),
                  const _ExplanationCard(),
                  const SizedBox(height: 22),
                  _ConnectingRadarCard(modules: portrait.modules),
                  const SizedBox(height: 22),
                  Text(
                    '我的工作画像',
                    style: DunesTypography.sans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF312249),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '以下模块仅展示当前登录用户，数据完成接入后会在此更新。',
                    style: DunesTypography.sans(
                      fontSize: 13,
                      color: const Color(0xFF766B86),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final module in portrait.modules) ...[
                    _ModuleCard(module: module),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFFCFAFF),
        border: Border(bottom: BorderSide(color: Color(0xFFE7DFF0))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回我的',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: const Color(0xFF4A3866),
          ),
          const SizedBox(width: 2),
          Text(
            '个人工作画像',
            style: DunesTypography.sans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF312249),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityHero extends StatelessWidget {
  const _IdentityHero({
    required this.name,
    required this.identityLine,
    required this.avatarUrl,
    required this.avatarPreset,
  });

  final String name;
  final String identityLine;
  final String avatarUrl;
  final String avatarPreset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF604084), Color(0xFF8E6BBC), Color(0xFFA286C6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33543675),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          NativeAvatarCircle(
            size: 72,
            avatarPreset: avatarPreset,
            avatarUrl: avatarUrl,
            fallbackText: name.characters.first,
            borderColor: const Color(0x99FFFFFF),
            borderWidth: 2,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SELF · WORK PORTRAIT',
                  style: TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  identityLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: const Color(0xEFFFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExplanationCard extends StatelessWidget {
  const _ExplanationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6DCF0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFFF0E8FA),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF7651B8),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '这里将汇总你在工作中的节奏、协作与成长轨迹，帮助你回顾自己的投入与发展。当前仅使用登录身份展示页面结构，不读取或推断任何业务数据。',
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: Color(0xFF5D536B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectingRadarCard extends StatelessWidget {
  const _ConnectingRadarCard({required this.modules});

  final List<UserWorkProfileModule> modules;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6DCF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '能力维度',
            style: DunesTypography.sans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF342740),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '六个维度将在数据接入后生成个人发展趋势',
            style: TextStyle(fontSize: 12, color: Color(0xFF817589)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 250,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final labels = modules
                    .map((module) => module.type.label)
                    .toList();
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size(constraints.maxWidth, 250),
                      painter: _RadarGridPainter(axisCount: labels.length),
                    ),
                    const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hub_outlined,
                          size: 26,
                          color: Color(0xFF8464AE),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '数据对接中',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF685174),
                          ),
                        ),
                      ],
                    ),
                    for (var index = 0; index < labels.length; index++)
                      _RadarLabel(
                        label: labels[index],
                        index: index,
                        total: labels.length,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RadarLabel extends StatelessWidget {
  const _RadarLabel({
    required this.label,
    required this.index,
    required this.total,
  });

  final String label;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final angle = -math.pi / 2 + math.pi * 2 * index / total;
    final offset = Offset(math.cos(angle) * 98, math.sin(angle) * 98);
    return Transform.translate(
      offset: offset,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF665374),
        ),
      ),
    );
  }
}

class _RadarGridPainter extends CustomPainter {
  const _RadarGridPainter({required this.axisCount});

  final int axisCount;

  @override
  void paint(Canvas canvas, Size size) {
    if (axisCount < 3) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .31;
    final gridPaint = Paint()
      ..color = const Color(0xFFE6DCF0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = const Color(0xFFD8CAE8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final factor in [.25, .5, .75, 1.0]) {
      final path = Path();
      for (var index = 0; index < axisCount; index++) {
        final angle = -math.pi / 2 + math.pi * 2 * index / axisCount;
        final point =
            center +
            Offset(
              math.cos(angle) * radius * factor,
              math.sin(angle) * radius * factor,
            );
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }
    for (var index = 0; index < axisCount; index++) {
      final angle = -math.pi / 2 + math.pi * 2 * index / axisCount;
      canvas.drawLine(
        center,
        center + Offset(math.cos(angle) * radius, math.sin(angle) * radius),
        axisPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarGridPainter oldDelegate) =>
      oldDelegate.axisCount != axisCount;
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final UserWorkProfileModule module;

  @override
  Widget build(BuildContext context) {
    final isConnecting =
        module.status == UserWorkProfileModuleStatus.connecting;
    final summary = module.summary.trim().isEmpty
        ? '数据对接中'
        : module.summary.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9E2EF)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: module.type.color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(module.type.icon, color: module.type.color, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  module.type.label,
                  style: DunesTypography.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF342740),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  summary,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    color: const Color(0xFF817589),
                  ),
                ),
              ],
            ),
          ),
          if (isConnecting)
            const Icon(
              Icons.hourglass_top_rounded,
              color: Color(0xFF9A7FB8),
              size: 19,
            ),
        ],
      ),
    );
  }
}
