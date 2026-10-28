import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/util/friendly_error.dart';
import '../../core/theme/dunes_theme.dart';
import '../proposal_intake/proposal_intake_ui.dart';
import 'xflow_detail_logic.dart';
import 'xflow_service.dart';

Future<Map<String, dynamic>?> showCompletedProposalPicker(
  BuildContext context,
  XflowService service,
) => showDialog<Map<String, dynamic>>(
  context: context,
  builder: (_) => _CompletedProposalDialog(service: service),
);

class ProposalReferencePicker extends StatefulWidget {
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
  State<ProposalReferencePicker> createState() =>
      _ProposalReferencePickerState();
}

class _ProposalReferencePickerState extends State<ProposalReferencePicker> {
  Future<Map<String, dynamic>>? _detail;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  void didUpdateWidget(covariant ProposalReferencePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (parseLinkedProposalId(oldWidget.value) !=
            parseLinkedProposalId(widget.value) ||
        oldWidget.service != widget.service) {
      _loadDetail();
    }
  }

  void _loadDetail() {
    final id = parseLinkedProposalId(widget.value);
    _detail =
        id > 0 &&
            linkedProposalOpensIntake(parseLinkedProposalSource(widget.value))
        ? widget.service
              .fetchLinkedProposalIntake(id)
              .catchError((_) => <String, dynamic>{})
        : null;
  }

  @override
  Widget build(BuildContext context) {
    Color c(Color value, [DunesColorRole role = DunesColorRole.foreground]) =>
        DunesColors.resolve(context, value, role: role);
    final value = widget.value;
    final data = value is Map ? value : const {};
    final title = '${data['title'] ?? ''}'.trim();
    final code = '${data['code'] ?? ''}'.trim();
    final selected = parseLinkedProposalId(value) > 0;
    const purple = Color(0xFF5B46BC);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.link_rounded, size: 17, color: c(purple)),
            const SizedBox(width: 6),
            Text(
              '关联提案 *',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: c(ProposalPalette.text),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                final picked = await showCompletedProposalPicker(
                  context,
                  widget.service,
                );
                if (picked != null) widget.onChanged(picked);
              },
              icon: Icon(
                selected ? Icons.swap_horiz_rounded : Icons.add_rounded,
                size: 16,
              ),
              label: Text(selected ? '更换提案' : '选择提案'),
              style: TextButton.styleFrom(
                foregroundColor: c(purple),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        if (!selected)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              '请选择已完成的销售或采购提案',
              style: TextStyle(color: c(ProposalPalette.text3), fontSize: 12),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: c(const Color(0xFFF8F6FE), DunesColorRole.surface),
              border: Border.all(
                color: c(const Color(0xFFE5DFF7), DunesColorRole.border),
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c(
                          const Color(0xFFECE7FA),
                          DunesColorRole.surface,
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        Icons.description_outlined,
                        color: c(purple),
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.isEmpty
                                ? formatProposalDisplay(value)
                                : title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: c(ProposalPalette.text),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              data['kind'] == 'purchase' ? '采购提案' : '销售提案',
                              if (code.isNotEmpty) code,
                              '已完成',
                            ].join('  ·  '),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: c(ProposalPalette.text3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                FutureBuilder<Map<String, dynamic>>(
                  future: _detail,
                  builder: (context, snapshot) {
                    final detail = snapshot.data ?? const {};
                    final form = detail['form'] is Map
                        ? detail['form'] as Map
                        : const {};
                    final facts = <String>[
                      if ('${form['marketOwner2'] ?? ''}'.trim().isNotEmpty)
                        '责任人  ${form['marketOwner2']}',
                      if ('${form['product'] ?? ''}'.trim().isNotEmpty)
                        '产品  ${form['product']}',
                      if ('${form['projectName'] ?? ''}'.trim().isNotEmpty)
                        '项目  ${form['projectName']}',
                      if ('${form['salesScale'] ?? ''}'.trim().isNotEmpty)
                        '年化规模  ${form['salesScale']} 万',
                    ];
                    if (facts.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 5,
                        children: [
                          for (final fact in facts)
                            Text(
                              fact,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: c(ProposalPalette.text2),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => widget.onChanged(null),
                    style: TextButton.styleFrom(
                      foregroundColor: c(ProposalPalette.text3),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('清除关联', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
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
  Widget build(BuildContext context) {
    Color color(
      Color value, [
      DunesColorRole role = DunesColorRole.foreground,
    ]) => DunesColors.resolve(context, value, role: role);
    const purple = Color(0xFF5B46BC);
    return Dialog(
      backgroundColor: color(Colors.white, DunesColorRole.surface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 560,
        height: (MediaQuery.sizeOf(context).height * .75).clamp(300.0, 640.0),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color(
                        const Color(0xFFEEEAFB),
                        DunesColorRole.surface,
                      ),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.description_outlined,
                      color: color(purple),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '选择已完成提案',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: color(ProposalPalette.text),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '选择与你相关的销售或采购提案',
                          style: TextStyle(
                            fontSize: 11,
                            color: color(ProposalPalette.text3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: color(ProposalPalette.text3),
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: '搜索提案编号或名称',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: color(ProposalPalette.text3),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: color(purple),
                    size: 20,
                  ),
                  filled: true,
                  fillColor: color(
                    const Color(0xFFF7F6FB),
                    DunesColorRole.surface,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: color(
                        const Color(0xFFE7E3F2),
                        DunesColorRole.border,
                      ),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: color(
                        const Color(0xFFE7E3F2),
                        DunesColorRole.border,
                      ),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: color(purple)),
                  ),
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
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final kind in const {
                      '': '全部',
                      'sales': '销售提案',
                      'purchase': '采购提案',
                    }.entries)
                      Theme(
                        data: Theme.of(context).copyWith(
                          splashColor: color(purple).withValues(alpha: .12),
                          highlightColor: color(purple).withValues(alpha: .08),
                          hoverColor: color(purple).withValues(alpha: .06),
                          colorScheme: Theme.of(context).colorScheme.copyWith(
                            primary: color(purple),
                            secondary: color(purple),
                          ),
                        ),
                        child: ChoiceChip(
                          label: Text(kind.value),
                          selected: _kind == kind.key,
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: _kind == kind.key
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: color(
                              _kind == kind.key
                                  ? purple
                                  : ProposalPalette.text2,
                            ),
                          ),
                          backgroundColor: color(
                            const Color(0xFFF5F3F9),
                            DunesColorRole.surface,
                          ),
                          selectedColor: color(
                            const Color(0xFFEDE8FC),
                            DunesColorRole.surface,
                          ),
                          color: WidgetStateProperty.resolveWith((states) {
                            final selected = states.contains(
                              WidgetState.selected,
                            );
                            final pressed = states.contains(
                              WidgetState.pressed,
                            );
                            return color(
                              pressed
                                  ? const Color(0xFFDDD4F8)
                                  : selected
                                  ? const Color(0xFFEDE8FC)
                                  : const Color(0xFFF5F3F9),
                              DunesColorRole.surface,
                            );
                          }),
                          pressElevation: 0,
                          side: BorderSide(
                            color: color(
                              _kind == kind.key
                                  ? const Color(0xFFCABEF2)
                                  : const Color(0xFFE9E6F0),
                              DunesColorRole.border,
                            ),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            _kind = kind.key;
                            _page = 1;
                            unawaited(_load());
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _busy
                    ? Center(
                        child: CircularProgressIndicator(color: color(purple)),
                      )
                    : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            TextButton(
                              onPressed: _load,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : _items.isEmpty
                    ? const Center(child: Text('暂无有权引用的已完成提案'))
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final row = _items[i];
                          return Material(
                            color: color(
                              const Color(0xFFF9F8FC),
                              DunesColorRole.surface,
                            ),
                            borderRadius: BorderRadius.circular(11),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                                side: BorderSide(
                                  color: color(
                                    const Color(0xFFEEEAF5),
                                    DunesColorRole.border,
                                  ),
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 3,
                              ),
                              title: Text(
                                '${row['title'] ?? ''}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: color(ProposalPalette.text),
                                ),
                              ),
                              subtitle: Text(
                                '${row['kind'] == 'purchase' ? '采购提案' : '销售提案'} · ${row['code']}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: color(ProposalPalette.text3),
                                ),
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: color(purple),
                              ),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: color(ProposalPalette.text3),
                      ),
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
}
