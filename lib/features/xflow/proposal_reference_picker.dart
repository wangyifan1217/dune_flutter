import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/util/friendly_error.dart';
import 'xflow_detail_logic.dart';
import 'xflow_service.dart';

Future<Map<String, dynamic>?> showCompletedProposalPicker(
  BuildContext context, XflowService service,
) => showDialog<Map<String, dynamic>>(
  context: context,
  builder: (_) => _CompletedProposalDialog(service: service),
);

class ProposalReferencePicker extends StatelessWidget {
  const ProposalReferencePicker({
    super.key,
    required this.service,
    required this.value,
    required this.onChanged,
  });
  final XflowService service;
  final dynamic value;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('关联提案 *', style: TextStyle(fontWeight: FontWeight.w600)),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            formatProposalDisplay(value).isEmpty
                ? '选择已完成的销售或采购提案'
                : formatProposalDisplay(value),
          ),
          subtitle: value is Map && value['kind'] != null
              ? Text(value['kind'] == 'purchase' ? '采购提案' : '销售提案')
              : null,
          trailing: const Icon(Icons.search),
          onTap: () async {
            final picked = await showCompletedProposalPicker(context, service);
            if (picked != null) onChanged(picked);
          },
        ),
        if (value != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => onChanged(null),
              child: const Text('清除关联'),
            ),
          ),
      ],
    ),
  );
}

class _CompletedProposalDialog extends StatefulWidget {
  const _CompletedProposalDialog({required this.service});
  final XflowService service;
  @override
  State<_CompletedProposalDialog> createState() =>
      _CompletedProposalDialogState();
}

class _CompletedProposalDialogState extends State<_CompletedProposalDialog> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _kind = '';
  int _page = 1, _total = 0, _request = 0;
  bool _busy = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _debounce?.cancel();
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
      _items = const [];
    });
    try {
      final data = await widget.service.fetchCompletedProposalIntakes(
        query: _search.text,
        kind: _kind,
        page: _page,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _items = (data['items'] as List? ?? const [])
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        _total = (data['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _error = friendlyErrorText(e));
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 560,
      height: MediaQuery.sizeOf(context).height * .75,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '选择已完成提案',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: '搜索提案编号或名称',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) {
                _debounce?.cancel();
                ++_request;
                setState(() {
                  _busy = true;
                  _items = const [];
                  _page = 1;
                });
                _debounce = Timer(const Duration(milliseconds: 280), _load);
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final kind in const {
                  '': '全部',
                  'sales': '销售提案',
                  'purchase': '采购提案',
                }.entries)
                  ChoiceChip(
                    label: Text(kind.value),
                    selected: _kind == kind.key,
                    onSelected: (_) {
                      _kind = kind.key;
                      _page = 1;
                      unawaited(_load());
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          TextButton(onPressed: _load, child: const Text('重试')),
                        ],
                      ),
                    )
                  : _items.isEmpty
                  ? const Center(child: Text('暂无有权引用的已完成提案'))
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final row = _items[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${row['title'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${row['kind'] == 'purchase' ? '采购提案' : '销售提案'} · ${row['code']}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(
                            context,
                            linkedProposalIntakePayload(
                              id: int.parse(
                                '${row['proposalId'] ?? row['id']}',
                              ),
                              code: '${row['code'] ?? ''}',
                              title: '${row['title'] ?? ''}',
                              kind: '${row['kind'] ?? ''}',
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    '共 $_total 份 · 第 $_page 页',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: '上一页',
                  onPressed: _busy || _page <= 1
                      ? null
                      : () {
                          _page--;
                          unawaited(_load());
                        },
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: '下一页',
                  onPressed: _busy || _page * 20 >= _total
                      ? null
                      : () {
                          _page++;
                          unawaited(_load());
                        },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
