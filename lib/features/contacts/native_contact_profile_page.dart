import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'contact_models.dart';
import 'contact_service.dart';

class NativeContactProfilePage extends StatefulWidget {
  const NativeContactProfilePage({
    super.key,
    required this.session,
    required this.contactHint,
    required this.onBack,
    required this.onOpenPrivateChat,
  });

  final AuthSession session;
  final NativeContact? contactHint;
  final VoidCallback onBack;
  final ValueChanged<int> onOpenPrivateChat;

  @override
  State<NativeContactProfilePage> createState() => _NativeContactProfilePageState();
}

class _NativeContactProfilePageState extends State<NativeContactProfilePage> {
  late final ContactService _service;
  NativeContact? _contact;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = ContactService(session: widget.session);
    _load();
  }

  void _toast(String message) {
    if (!mounted) return;
    showDunesToast(
      context,
      message,
      kind: dunesToastLooksLikeError(message)
          ? DunesToastKind.error
          : DunesToastKind.normal,
    );
  }

  Future<void> _load() async {
    final hint = widget.contactHint;
    if (hint == null || hint.userId <= 0) {
      setState(() {
        _loading = false;
        _error = '联系人不存在';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fresh = await _service.fetchContact(hint.userId);
      if (!mounted) return;
      setState(() {
        _contact = fresh ?? hint;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _contact = hint;
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: DunesColors.stageBg,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_contact == null) {
      return Scaffold(
        backgroundColor: DunesColors.stageBg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? '联系人不存在', style: const TextStyle(color: DunesColors.text3)),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: widget.onBack, child: const Text('返回')),
            ],
          ),
        ),
      );
    }

    final c = _contact!;
    final name = c.displayLabel.isEmpty ? '未命名' : c.displayLabel;
    final title = c.primaryRole.trim();
    final department = (c.department ?? '').trim();
    final rows = <(String, String)>[
      ('手机', (c.phone ?? '').trim().isEmpty ? '-' : c.phone!.trim()),
      ('部门', department.isEmpty ? '-' : department),
      ('职位', title.isEmpty ? '-' : title),
    ];

    return Scaffold(
      backgroundColor: DunesColors.stageBg,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _ContactHero(
              initial: name.substring(0, 1),
              name: name,
              department: department,
              roleTag: title,
              onBack: widget.onBack,
            ),
            _ActionBar(
              onMessage: () => widget.onOpenPrivateChat(c.userId),
              onVoice: () => _toast('语音功能即将上线'),
              onVideo: () => _toast('视频功能即将上线'),
            ),
            const SizedBox(height: 2),
            const _SectionLabel('基本信息'),
            ...rows.map((row) => _InfoRow(label: row.$1, value: row.$2)),
          ],
        ),
      ),
    );
  }
}

class _ContactHero extends StatelessWidget {
  const _ContactHero({
    required this.initial,
    required this.name,
    required this.department,
    required this.roleTag,
    required this.onBack,
  });

  final String initial;
  final String name;
  final String department;
  final String roleTag;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            DunesColors.accent,
            DunesColors.accentDeep,
            Color(0xFF1A201F),
          ],
          stops: [0, 0.6, 1],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -50,
            right: -40,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0xFF5F8B8F).withValues(alpha: 0.25),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.65],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -30,
            left: -20,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0xFFFFB4E8).withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.65],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: _HeroButton(icon: Icons.chevron_left_rounded, onTap: onBack),
          ),
          Align(
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 44),
                Container(
                  width: 84,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, Color(0xFFE9DEFF)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color.fromRGBO(47, 93, 98, 0.6),
                        blurRadius: 36,
                        spreadRadius: -8,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Text(
                    initial,
                    style: DunesTypography.sans(
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.accentDeep,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: DunesTypography.sans(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.015 * 18,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    if (roleTag.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [DunesColors.accent, Color(0xFF5F8B8F)],
                          ),
                        ),
                        child: Text(
                          roleTag,
                          style: DunesTypography.mono(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.05 * 8.5,
                            color: Colors.white,
                            height: 1.5,
                          ),
                        ),
                      ),
                  ],
                ),
                if (department.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    department,
                    textAlign: TextAlign.center,
                    style: DunesTypography.mono(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.72),
                      letterSpacing: 0.02 * 10,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onMessage,
    required this.onVoice,
    required this.onVideo,
  });

  final VoidCallback onMessage;
  final VoidCallback onVoice;
  final VoidCallback onVideo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
      color: DunesColors.bgApp,
      child: Row(
        children: [
          Expanded(
            child: _ActionCard(
              primary: true,
              icon: Icons.chat_bubble_outline,
              label: '发消息',
              onTap: onMessage,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionCard(
              icon: Icons.call_outlined,
              label: '语音',
              onTap: onVoice,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionCard(
              icon: Icons.videocam_outlined,
              label: '视频',
              onTap: onVideo,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            color: primary ? null : DunesColors.bgSoft,
            gradient: primary
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [DunesColors.accent, DunesColors.accentDeep],
                  )
                : null,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: primary ? DunesColors.accentDeep : DunesColors.borderSoft),
            boxShadow: primary
                ? const [
                    BoxShadow(
                      color: Color.fromRGBO(47, 93, 98, 0.4),
                      blurRadius: 10,
                      spreadRadius: -3,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: primary ? Colors.white : DunesColors.text2),
              const SizedBox(height: 5),
              Text(
                label,
                style: DunesTypography.sans(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: primary ? Colors.white : DunesColors.text2,
                  letterSpacing: -0.005 * 10,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 5),
      decoration: const BoxDecoration(
        color: DunesColors.stageBg,
        border: Border(
          top: BorderSide(color: DunesColors.borderSoft),
          bottom: BorderSide(color: DunesColors.borderSoft),
        ),
      ),
      child: Text(
        label,
        style: DunesTypography.mono(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          color: DunesColors.text3,
          letterSpacing: 0.06 * 8.5,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: DunesTypography.mono(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: DunesColors.text3,
                letterSpacing: 0.04 * 9,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: DunesTypography.mono(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: DunesColors.text,
                letterSpacing: 0.005 * 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
