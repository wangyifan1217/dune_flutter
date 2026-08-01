import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/dunes_theme.dart';
import '../shell/dunes_toast.dart';
import 'auth_service.dart';
import 'auth_session.dart';

/// 组织员工展示长期邀请二维码，供外部用户扫码注册。
class InviteQrPage extends StatefulWidget {
  const InviteQrPage({super.key, required this.session});

  final AuthSession session;

  @override
  State<InviteQrPage> createState() => _InviteQrPageState();
}

class _InviteQrPageState extends State<InviteQrPage> {
  final _auth = AuthService();
  bool _loading = true;
  String? _error;
  RegistrationInvite? _invite;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final invite = await _auth.fetchMyInvite(token: widget.session.token);
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _loading = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '加载邀请码失败';
        _loading = false;
      });
    }
  }

  Future<void> _copyCode() async {
    final code = _invite?.code.trim() ?? '';
    if (code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    showDunesToast(context, '邀请码已复制');
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        title: const Text('邀请外部用户'),
        backgroundColor: Colors.white,
        foregroundColor: DunesColors.text,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: DunesTypography.sans(
                            fontSize: 14,
                            color: DunesColors.coral,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('重试')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '我的邀请二维码',
                            style: DunesTypography.sans(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '外部用户请在沙丘 App 登录页选择「扫码邀请注册」扫描此码。'
                            '同一二维码可长期多次使用；管理员可禁用。',
                            textAlign: TextAlign.center,
                            style: DunesTypography.sans(
                              fontSize: 13,
                              color: DunesColors.text3,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (!(invite?.enabled ?? false))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                '该邀请码已被禁用',
                                style: DunesTypography.sans(
                                  fontSize: 14,
                                  color: DunesColors.coral,
                                ),
                              ),
                            ),
                          QrImageView(
                            data: invite?.qrPayload ?? '',
                            size: 220,
                            backgroundColor: Colors.white,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            invite?.code ?? '',
                            style: DunesTypography.sans(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '已关联申请 ${invite?.inviteCount ?? 0} 次',
                            style: DunesTypography.sans(
                              fontSize: 12,
                              color: DunesColors.text3,
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _copyCode,
                            icon: const Icon(Icons.copy_outlined, size: 18),
                            label: const Text('复制邀请码'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
