import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'proposal_intake_ui.dart';
import 'proposal_view_style.dart';
import 'settlement_catalog.dart';

typedef SupplierProductSearch =
    Future<List<ChannelProductHit>> Function(String keyword);

/// 旧值始终按原来的字符串保存，只有用户确认修改时才重新拼接。
class SupplierProductPickerField extends StatelessWidget {
  const SupplierProductPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.search,
    this.readOnly = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final SupplierProductSearch search;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('supplier-product-picker'),
      onTap: readOnly
          ? null
          : () async {
              final result = await showDialog<String>(
                context: context,
                builder: (_) =>
                    _SupplierProductPicker(initial: value, search: search),
              );
              if (context.mounted && result != null) onChanged(result);
            },
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration:
            proposalInputDecoration(
              context: context,
              hint: '搜索并选择供应商产品',
              readOnly: readOnly,
              forceUnderline: kProposalPrototypeFormEnabled,
            ).copyWith(
              suffixIcon: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: DunesColors.resolve(context, ProposalPalette.text3),
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 22,
                minHeight: 22,
              ),
            ),
        child: Text(
          value.trim().isEmpty ? '搜索并选择供应商产品' : value,
          style: TextStyle(
            fontSize: 12,
            height: 1.3,
            color: DunesColors.resolve(
              context,
              value.trim().isEmpty
                  ? ProposalPalette.text3
                  : ProposalPalette.text,
            ),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _SupplierProductPicker extends StatefulWidget {
  const _SupplierProductPicker({required this.initial, required this.search});
  final String initial;
  final SupplierProductSearch search;
  @override
  State<_SupplierProductPicker> createState() => _SupplierProductPickerState();
}

class _SupplierProductPickerState extends State<_SupplierProductPicker> {
  late final List<String> selected;
  Timer? timer;
  int sequence = 0;
  bool searching = false, changed = false;
  String query = '', error = '';
  List<ChannelProductHit> results = const [];

  @override
  void initState() {
    super.initState();
    selected = widget.initial
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @override
  void dispose() {
    timer?.cancel();
    sequence++;
    super.dispose();
  }

  void search(String text) {
    timer?.cancel();
    final current = ++sequence;
    final keyword = text.trim();
    setState(() {
      query = keyword;
      results = const [];
      error = '';
      searching = keyword.isNotEmpty;
    });
    if (keyword.isEmpty) return;
    timer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final found = await widget.search(keyword);
        if (!mounted || current != sequence) return;
        setState(() {
          results = found;
          searching = false;
        });
      } catch (_) {
        if (!mounted || current != sequence) return;
        setState(() {
          error = '查询失败，请检查网络后重试';
          searching = false;
        });
      }
    });
  }

  void toggle(String code, bool checked) {
    setState(() {
      if (checked) {
        if (!selected.contains(code)) selected.add(code);
      } else {
        selected.removeWhere((item) => item == code);
      }
      changed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final items = results.where((item) {
      final code = item.productCode.trim();
      return code.isNotEmpty &&
          code != '无' &&
          !code.contains('|') &&
          !code.contains(',') &&
          seen.add(code);
    }).toList();
    final status = searching
        ? '搜索中…'
        : error.isNotEmpty
        ? error
        : query.isEmpty
        ? '输入关键词后搜索供应商产品'
        : items.isEmpty
        ? '没有找到匹配的供应商产品'
        : '';
    final ink = DunesColors.resolve(context, ProposalPalette.text);
    final muted = DunesColors.resolve(context, ProposalPalette.text3);
    final purple = DunesColors.resolve(context, ProposalPalette.purple);
    final surface = DunesColors.resolve(
      context,
      Colors.white,
      role: DunesColorRole.surface,
    );
    final soft = DunesColors.resolve(
      context,
      ProposalPalette.soft,
      role: DunesColorRole.surface,
    );
    final border = DunesColors.resolve(
      context,
      ProposalPalette.borderSoft,
      role: DunesColorRole.border,
    );
    Widget option({
      required String code,
      required String title,
      String subtitle = '',
    }) {
      final active = selected.contains(code);
      return Material(
        key: ValueKey('supplier-product-option-$code'),
        color: active ? soft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => toggle(code, !active),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            color: ink,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                color: muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    active ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 18,
                    color: active
                        ? purple
                        : DunesColors.resolve(
                            context,
                            ProposalPalette.borderStrong,
                            role: DunesColorRole.border,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 420,
        height: math.min(350.0, MediaQuery.sizeOf(context).height * .65),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '选择供应商产品',
                      style: TextStyle(
                        fontSize: 14,
                        color: ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '已选 ${selected.toSet().length} 项',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      tooltip: '关闭',
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: muted),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const ValueKey('supplier-product-search'),
                onChanged: search,
                style: TextStyle(fontSize: 13, color: ink),
                decoration:
                    proposalInputDecoration(
                      context: context,
                      hint: '输入产品名称或编码搜索',
                    ).copyWith(
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: muted,
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      filled: true,
                      fillColor: soft,
                    ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                itemCount: 2 + (status.isNotEmpty ? 1 : items.length),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '若找不到供应商产品，请联系业务侧添加。',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: DunesColors.resolve(
                                context,
                                ProposalPalette.amber,
                              ),
                            ),
                          ),
                          if (selected.isNotEmpty) ...[
                            const SizedBox(height: 7),
                            Text(
                              '选择顺序即优先级',
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final code in selected.toSet())
                                  InputChip(
                                    label: Text(
                                      code,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    labelStyle: TextStyle(
                                      fontSize: 11,
                                      color: purple,
                                    ),
                                    backgroundColor: soft,
                                    side: BorderSide.none,
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    deleteIcon: Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: purple,
                                    ),
                                    onDeleted: () => toggle(code, false),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  }
                  if (index == 1) return option(code: '无', title: '无');
                  if (status.isNotEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 18,
                        horizontal: 8,
                      ),
                      child: Column(
                        children: [
                          Text(
                            status,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                          if (error.isNotEmpty)
                            TextButton(
                              onPressed: () => search(query),
                              child: const Text('重试'),
                            ),
                        ],
                      ),
                    );
                  }
                  final item = items[index - 2];
                  final code = item.productCode.trim();
                  return option(
                    code: code,
                    title: item.productName.trim().isEmpty
                        ? code
                        : item.productName,
                    subtitle: [
                      code,
                      if (item.supplierName.trim().isNotEmpty)
                        item.supplierName,
                      if (item.syncSource.trim().isNotEmpty) item.syncSource,
                    ].join(' · '),
                  );
                },
              ),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: border)),
              ),
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: muted,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      changed ? selected.join('|') : widget.initial,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: purple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(58, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('确定'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
