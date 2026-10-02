import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import 'cursor_supervise_models.dart';
import 'cursor_supervise_service.dart';

const _themePurple = Color(0xFF7B5CD8);

/// Cursor 账号监管 · 日消耗明细（日期 / 模型 / 美元 / tokens·M）。
class NativeQianjiCursorAccountDetailPage extends StatefulWidget {
  const NativeQianjiCursorAccountDetailPage({
    super.key,
    required this.session,
    required this.bindingId,
    required this.onBack,
  });

  final AuthSession session;
  final int bindingId;
  final VoidCallback onBack;

  @override
  State<NativeQianjiCursorAccountDetailPage> createState() =>
      _NativeQianjiCursorAccountDetailPageState();
}

class _NativeQianjiCursorAccountDetailPageState
    extends State<NativeQianjiCursorAccountDetailPage> {
  late final CursorSuperviseService _service = CursorSuperviseService(
    session: widget.session,
  );

  bool _loading = true;
  String? _error;
  CursorSuperviseDailySpendResult? _data;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.fetchDailySpend(bindingId: widget.bindingId);
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (_data?.displayName.trim().isNotEmpty ?? false)
        ? _data!.displayName.trim()
        : ((_data?.email.trim().isNotEmpty ?? false)
              ? _data!.email.trim()
              : '用量明细');

    return ColoredBox(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF5F6F8),
        role: DunesColorRole.surface,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 16, 8),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: widget.onBack,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_ios_new,
                            size: 14,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text2,
                            ),
                          ),
                          SizedBox(width: 2),
                          Text(
                            '监管',
                            style: TextStyle(
                              fontSize: 13,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.resolveNullable(
                          context,
                          _themePurple,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_data?.email.trim().isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _data!.email.trim(),
                  style: TextStyle(
                    fontSize: 12,
                    color: DunesColors.resolve(context, DunesColors.text3),
                  ),
                ),
              ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Text(
            friendlyErrorText(_error, fallback: '加载失败，请稍后重试'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: DunesColors.resolve(context, DunesColors.text2),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: () => unawaited(_load()),
              child: const Text('重试'),
            ),
          ),
        ],
      );
    }
    final items = _data?.items ?? const <CursorSuperviseDailySpendItem>[];
    if (items.isEmpty) {
      return Center(
        child: Text(
          '暂无用量明细',
          style: TextStyle(
            color: DunesColors.resolve(context, DunesColors.text3),
            fontSize: 14,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: DunesColors.resolve(
                context,
                const Color(0xFFF0EEF7),
                role: DunesColorRole.surface,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    '日期',
                    style: _headStyle.copyWith(
                      color: DunesColors.resolveNullable(
                        context,
                        _headStyle.color,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    '模型',
                    style: _headStyle.copyWith(
                      color: DunesColors.resolveNullable(
                        context,
                        _headStyle.color,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    '消费(\$)',
                    style: _headStyle.copyWith(
                      color: DunesColors.resolveNullable(
                        context,
                        _headStyle.color,
                      ),
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Tokens',
                    style: _headStyle.copyWith(
                      color: DunesColors.resolveNullable(
                        context,
                        _headStyle.color,
                      ),
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final it in items) ...[
            _SpendRow(item: it),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

const _headStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  color: _themePurple,
);

class _SpendRow extends StatelessWidget {
  const _SpendRow({required this.item});

  final CursorSuperviseDailySpendItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE8EAED),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              item.day.isEmpty ? '—' : item.day,
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text2),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              item.model.isEmpty ? '—' : item.model,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DunesColors.resolve(context, DunesColors.text),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              item.spendDollarLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DunesColors.resolve(context, DunesColors.text),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              item.tokensMLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
