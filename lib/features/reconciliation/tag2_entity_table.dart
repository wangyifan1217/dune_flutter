import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'tag2_entity_models.dart';
import 'tag3_daily_models.dart';

class Tag2EntityTable extends StatelessWidget {
  const Tag2EntityTable({
    super.key,
    required this.rows,
    required this.comments,
    required this.busyKeys,
    required this.onDrill,
    required this.onConfirm,
    required this.onComment,
  });

  final List<Tag2EntityRow> rows;
  final List<Tag3DailyComment> comments;
  final Set<String> busyKeys;
  final void Function(Tag2EntityRow row, Tag2EntityAmount amount) onDrill;
  final ValueChanged<Tag2EntityRow> onConfirm;
  final ValueChanged<Tag2EntityRow> onComment;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          '这一天没有你负责的主体。',
          style: DunesTypography.sans(fontSize: 14, color: DunesColors.text3),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: rows.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = rows[index];
        final mine = [
          for (final item in comments)
            if (item.rowKey == row.rowKey) item,
        ];
        return _Tag2EntityCard(
          row: row,
          comments: mine,
          busy: busyKeys.contains(row.rowKey),
          onDrill: onDrill,
          onConfirm: onConfirm,
          onComment: onComment,
        );
      },
    );
  }
}

class _Tag2EntityCard extends StatelessWidget {
  const _Tag2EntityCard({
    required this.row,
    required this.comments,
    required this.busy,
    required this.onDrill,
    required this.onConfirm,
    required this.onComment,
  });

  final Tag2EntityRow row;
  final List<Tag3DailyComment> comments;
  final bool busy;
  final void Function(Tag2EntityRow row, Tag2EntityAmount amount) onDrill;
  final ValueChanged<Tag2EntityRow> onConfirm;
  final ValueChanged<Tag2EntityRow> onComment;

  @override
  Widget build(BuildContext context) {
    final status = row.statusLabel;
    return Material(
      color: row.isTotal ? const Color(0xFFF7F8FA) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.title,
                    style: DunesTypography.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                ),
                if (status.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: row.confirmationStatus == 'ALL_CONFIRMED'
                          ? DunesColors.greenSoft
                          : DunesColors.amberSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      status,
                      style: DunesTypography.sans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: row.confirmationStatus == 'ALL_CONFIRMED'
                            ? DunesColors.green
                            : DunesColors.amber,
                      ),
                    ),
                  ),
              ],
            ),
            if (row.supplierName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                row.supplierName,
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text3,
                ),
              ),
            ],
            if (row.currentHandlers.isNotEmpty ||
                row.businessBy.isNotEmpty ||
                row.operationBy.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                [
                  if (row.businessBy.isNotEmpty) '业务 ${row.businessBy}',
                  if (row.operationBy.isNotEmpty) '运营 ${row.operationBy}',
                  if (row.currentHandlers.isNotEmpty &&
                      row.confirmationStatus != 'ALL_CONFIRMED')
                    '待 ${row.currentHandlers}',
                ].join(' · '),
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text2,
                ),
              ),
            ],
            const SizedBox(height: 10),
            _AmountGrid(row: row, onDrill: onDrill),
            if (comments.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final item in comments.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${item.userName.isEmpty ? '同事' : item.userName} · ${item.kindLabel}${item.displayBody.isEmpty ? '' : '：${item.displayBody}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: DunesColors.text2,
                      height: 1.35,
                    ),
                  ),
                ),
            ],
            if (row.showConfirm || row.showComment) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (row.showConfirm)
                    FilledButton(
                      onPressed: busy ? null : () => onConfirm(row),
                      child: Text(busy ? '提交中' : '确认'),
                    ),
                  if (row.showComment) ...[
                    if (row.showConfirm) const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: busy ? null : () => onComment(row),
                      child: const Text('提意见'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AmountGrid extends StatelessWidget {
  const _AmountGrid({required this.row, required this.onDrill});

  final Tag2EntityRow row;
  final void Function(Tag2EntityRow row, Tag2EntityAmount amount) onDrill;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final amount in row.amounts)
              SizedBox(
                width: width,
                child: _AmountCell(
                  amount: amount,
                  onTap: amount.drill && !row.isTotal
                      ? () => onDrill(row, amount)
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AmountCell extends StatelessWidget {
  const _AmountCell({required this.amount, this.onTap});

  final Tag2EntityAmount amount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final value = amount.display.isEmpty ? '-' : amount.display;
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            amount.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: DunesTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: onTap == null ? DunesColors.text : DunesColors.accent,
            ),
          ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: onTap == null
          ? child
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: child,
            ),
    );
  }
}

Future<String?> showTag2EntityActionDialog({
  required BuildContext context,
  required Tag2EntityRow row,
  required bool confirm,
}) {
  if (confirm) {
    final who = row.canConfirmStage == 'OPERATION' ? '运营' : '业务';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('二次确认'),
          content: Text('确定以$who确认「${row.title}」？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(''),
              child: const Text('确定确认'),
            ),
          ],
        );
      },
    );
  }
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _Tag2CommentDialog(title: row.title),
  );
}

class _Tag2CommentDialog extends StatefulWidget {
  const _Tag2CommentDialog({required this.title});

  final String title;

  @override
  State<_Tag2CommentDialog> createState() => _Tag2CommentDialogState();
}

class _Tag2CommentDialogState extends State<_Tag2CommentDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = _controller.text.trim();
    final tooLong = body.runes.length > 512;
    return AlertDialog(
      title: const Text('提意见'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: DunesTypography.sans(fontSize: 13, color: DunesColors.text2),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '1～512 字，不改变确认状态',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: body.isEmpty || tooLong
              ? null
              : () => Navigator.of(context).pop(body),
          child: const Text('提交'),
        ),
      ],
    );
  }
}

Future<void> showTag2EntityDrilldown({
  required BuildContext context,
  required String title,
  required Tag2EntityDrilldown data,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final rows = data.rows;
      return SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                title,
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        '没有明细',
                        style: DunesTypography.sans(
                          fontSize: 14,
                          color: DunesColors.text3,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: rows.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final lines = <Widget>[];
                        for (final entry in row.entries) {
                          final label =
                              tag2EntityDrillLabels[entry.key] ?? entry.key;
                          final value = '${entry.value ?? ''}'.trim();
                          if (value.isEmpty || value == 'null') continue;
                          lines.add(
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '$label：$value',
                                style: DunesTypography.sans(
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          );
                        }
                        return Material(
                          color: const Color(0xFFF5F6F8),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: lines,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}
