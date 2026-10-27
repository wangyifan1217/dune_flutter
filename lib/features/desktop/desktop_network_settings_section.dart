import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/desktop_network_settings.dart';
import '../../core/network/network_diagnostics.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';

class DesktopNetworkSettingsSection extends StatefulWidget {
  const DesktopNetworkSettingsSection({
    super.key,
    this.session,
    this.settings,
    this.diagnostics,
  });
  final AuthSession? session;
  final DesktopNetworkSettings? settings;
  final DesktopNetworkDiagnostics? diagnostics;

  @override
  State<DesktopNetworkSettingsSection> createState() =>
      _DesktopNetworkSettingsSectionState();
}

class _DesktopNetworkSettingsSectionState
    extends State<DesktopNetworkSettingsSection> {
  late final DesktopNetworkSettings _settings =
      widget.settings ?? DesktopNetworkSettings.instance;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  List<NetworkProbeResult> _results = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_changed);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await _settings.ensureLoaded();
    } catch (_) {
      _error = '网络偏好读取失败，请稍后重试';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _changed() {
    if (mounted) setState(() => _results = const []);
  }

  @override
  void dispose() {
    _settings.removeListener(_changed);
    super.dispose();
  }

  Future<void> _select(DesktopNetworkMode? mode) async {
    if (mode == null || _saving || _testing) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _settings.setMode(mode);
      if (mounted) showDunesToast(context, '网络设置已保存，新请求已切换连接方式');
    } catch (_) {
      if (mounted) setState(() => _error = '网络设置保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    if (_testing || _saving) return;
    setState(() {
      _testing = true;
      _results = const [];
      _error = null;
    });
    try {
      final results = await (widget.diagnostics ?? DesktopNetworkDiagnostics())
          .run(widget.session);
      if (mounted) setState(() => _results = results);
    } catch (_) {
      if (mounted) setState(() => _error = '检测未完成，请稍后重试');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = DunesColors.resolve(context, DunesColors.text3);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('连接方式', style: TextStyle(fontWeight: FontWeight.w600)),
              DropdownButton<DesktopNetworkMode>(
                key: const ValueKey('desktop-network-mode'),
                value: _settings.mode,
                onChanged: _loading || _saving || _testing ? null : _select,
                items: const [
                  DropdownMenuItem(
                    value: DesktopNetworkMode.defaultConnection,
                    child: Text('默认连接'),
                  ),
                  DropdownMenuItem(
                    value: DesktopNetworkMode.direct,
                    child: Text('直连，不使用代理'),
                  ),
                ],
              ),
              OutlinedButton.icon(
                key: const ValueKey('desktop-network-test'),
                onPressed: _loading || _saving || _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check_rounded, size: 18),
                label: Text(_testing ? '检测中…' : '测试连接'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '直连会忽略业务请求、消息连接和常规下载使用的代理；无法绕过系统 VPN / TUN，也不影响外部浏览器。',
            style: TextStyle(fontSize: 12, height: 1.6, color: muted),
          ),
          Text(
            '新请求立即生效，消息连接会自动重连；正在生成的回复或文件传输将继续完成。独立窗口重新打开后生效。',
            style: TextStyle(fontSize: 12, height: 1.6, color: muted),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.coral),
                ),
              ),
            ),
          for (final result in _results)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    result.skipped
                        ? Icons.remove_circle_outline
                        : result.success
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 17,
                    color: result.skipped
                        ? muted
                        : result.success
                        ? Colors.green.shade700
                        : DunesColors.resolve(context, DunesColors.coral),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${result.name}：${result.message}',
                      style: const TextStyle(fontSize: 12, height: 1.5),
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
