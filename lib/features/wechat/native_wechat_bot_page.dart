import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/file_download.dart' as file_dl;
import '../chat/gallery_save.dart' as gallery;
import '../shell/dunes_toast.dart';
import 'wechat_personal_models.dart';
import 'wechat_personal_service.dart';

class NativeWechatBotPage extends StatefulWidget {
  const NativeWechatBotPage({
    super.key,
    required this.session,
    required this.onBack,
  });

  final AuthSession session;
  final VoidCallback onBack;

  @override
  State<NativeWechatBotPage> createState() => _NativeWechatBotPageState();
}

class _NativeWechatBotPageState extends State<NativeWechatBotPage> {
  late final WechatPersonalService _service = WechatPersonalService(
    session: widget.session,
  );

  WechatPersonalStatus? _status;
  bool _loading = true;
  bool _startingQr = false;
  bool _saving = false;
  bool _unbinding = false;
  String? _error;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  int _remainSeconds = 0;

  Uint8List? get _qrBytes {
    final b64 = _status?.qrImageBase64;
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadStatus());
  }

  @override
  void dispose() {
    _stopPolling();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _service.fetchStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
      if (!status.bound && status.qrImageBase64 != null) {
        _beginPolling(status.expiresAt);
      } else {
        _stopPolling();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e, fallback: '加载失败，请稍后重试');
        _loading = false;
      });
    }
  }

  Future<void> _startQr() async {
    if (_startingQr) return;
    setState(() {
      _startingQr = true;
      _error = null;
    });
    try {
      final status = await _service.startQr();
      if (!mounted) return;
      setState(() {
        _status = status;
        _startingQr = false;
      });
      _beginPolling(status.expiresAt);
    } catch (e) {
      if (!mounted) return;
      setState(() => _startingQr = false);
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '获取二维码失败'),
      );
    }
  }

  void _beginPolling(int? expiresAt) {
    _stopPolling();
    _syncCountdown(expiresAt);
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      unawaited(_pollOnce(expiresAt));
    });
  }

  Future<void> _pollOnce(int? expiresAt) async {
    if (expiresAt != null) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (now > expiresAt) {
        _stopPolling();
        if (!mounted) return;
        setState(() {
          _status = (_status ??
                  const WechatPersonalStatus(bound: false, status: 'expired'))
              .copyWith(status: 'expired');
          _remainSeconds = 0;
        });
        showDunesToast(context, '二维码已过期，请重新获取');
        return;
      }
    }

    try {
      final status = await _service.fetchStatus();
      if (!mounted) return;
      if (status.bound) {
        _stopPolling();
        setState(() {
          _status = status;
          _remainSeconds = 0;
        });
        showDunesToast(context, '微信助手已绑定');
        return;
      }
      setState(() => _status = status.copyWith(
            qrImageBase64: status.qrImageBase64 ?? _status?.qrImageBase64,
            guideText: status.guideText ?? _status?.guideText,
            expiresAt: status.expiresAt ?? _status?.expiresAt,
          ));
    } catch (_) {
      // 轮询失败不打断流程，下一轮继续。
    }
  }

  void _syncCountdown(int? expiresAt) {
    _countdownTimer?.cancel();
    if (expiresAt == null) {
      setState(() => _remainSeconds = 0);
      return;
    }
    void tick() {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final remain = expiresAt - now;
      if (!mounted) return;
      setState(() => _remainSeconds = remain > 0 ? remain : 0);
      if (remain <= 0) _countdownTimer?.cancel();
    }

    tick();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  Future<void> _saveQr() async {
    final bytes = _qrBytes;
    if (bytes == null || _saving) return;
    setState(() => _saving = true);
    try {
      await gallery.saveImageToGallery(bytes, 'wechat_bot_qr.png');
      if (!mounted) return;
      showDunesToast(context, '已保存到相册');
    } catch (e) {
      try {
        await file_dl.saveBytesAsFile(bytes, 'wechat_bot_qr.png');
        if (!mounted) return;
        showDunesToast(context, '已保存');
      } catch (_) {
        if (!mounted) return;
        showDunesToast(
          context,
          '保存失败：${friendlyErrorText(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _unbind() async {
    if (_unbinding) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解绑微信助手'),
        content: const Text('解绑后需重新扫码才能在微信中使用。确定解绑吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解绑', style: TextStyle(color: DunesColors.coral)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _unbinding = true);
    try {
      await _service.unbind();
      if (!mounted) return;
      showDunesToast(context, '已解绑');
      await _loadStatus();
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '解绑失败'),
      );
    } finally {
      if (mounted) setState(() => _unbinding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onBack),
        title: const Text('微信助手'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadStatus,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            _buildIntro(),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _buildError()
            else if (_status?.isActive == true)
              _buildBoundCard()
            else
              _buildBindCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '专属微信 Bot',
            style: DunesTypography.sans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '扫码绑定后，可在微信中直接向你的专属助手提问。',
            style: DunesTypography.sans(
              fontSize: 14,
              height: 1.45,
              color: DunesColors.text2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: DunesTypography.sans(fontSize: 14, color: DunesColors.text2),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loadStatus,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildBoundCard() {
    final status = _status!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_rounded, size: 56, color: Color(0xFF07C160)),
          const SizedBox(height: 12),
          Text(
            '已绑定',
            style: DunesTypography.sans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '状态：${status.status}',
            style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
          ),
          const SizedBox(height: 8),
          Text(
            '可在微信中直接向助手提问。',
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 14,
              height: 1.4,
              color: DunesColors.text2,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: _unbinding ? null : _unbind,
            style: OutlinedButton.styleFrom(
              foregroundColor: DunesColors.coral,
              side: const BorderSide(color: DunesColors.coral),
              minimumSize: const Size(double.infinity, 44),
            ),
            child: _unbinding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('解绑'),
          ),
        ],
      ),
    );
  }

  Widget _buildBindCard() {
    final bytes = _qrBytes;
    final guide = _status?.guideText?.trim();
    final expired = _status?.isExpired == true ||
        (_remainSeconds <= 0 && bytes != null && _status?.expiresAt != null);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        children: [
          if (bytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                bytes,
                width: 240,
                height: 240,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
            const SizedBox(height: 12),
            if (_remainSeconds > 0)
              Text(
                '剩余 $_remainSeconds 秒',
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.text3,
                ),
              )
            else if (expired)
              Text(
                '二维码已过期',
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.coral,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              guide?.isNotEmpty == true
                  ? guide!
                  : '请保存二维码到相册，打开微信「扫一扫 → 相册」识别并确认。',
              textAlign: TextAlign.center,
              style: DunesTypography.sans(
                fontSize: 14,
                height: 1.45,
                color: DunesColors.text2,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: (_saving || expired) ? null : _saveQr,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_saving ? '保存中…' : '保存到相册'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
                backgroundColor: const Color(0xFF07C160),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _startingQr ? null : _startQr,
              child: Text(_startingQr ? '获取中…' : '重新获取二维码'),
            ),
          ] else ...[
            Text(
              guide?.isNotEmpty == true
                  ? guide!
                  : '获取专属授权二维码后，保存到相册并用微信扫码确认即可绑定。',
              textAlign: TextAlign.center,
              style: DunesTypography.sans(
                fontSize: 14,
                height: 1.45,
                color: DunesColors.text2,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _startingQr ? null : _startQr,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
                backgroundColor: const Color(0xFF07C160),
              ),
              child: _startingQr
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('获取二维码'),
            ),
          ],
        ],
      ),
    );
  }
}
