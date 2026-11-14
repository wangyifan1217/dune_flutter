import 'dart:convert';
import 'package:flutter/material.dart';

import 'hr_performance_template_ui.dart';

Future<Map<String, dynamic>?> showHrTemplateItemEditor(
  BuildContext context,
  Map<String, dynamic> item, {
  required bool direct,
}) => showHrConfigPanel<Map<String, dynamic>>(
  context,
  _ItemEditor(item: item, direct: direct),
);

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({required this.item, required this.direct});
  final Map<String, dynamic> item;
  final bool direct;
  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final Map<String, dynamic> draft = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(widget.item)) as Map,
  );
  late final snapshot = Map<String, dynamic>.from(draft['snapshot'] as Map);
  late final bands = (snapshot['bands'] as List? ?? [])
      .map((b) => Map<String, dynamic>.from(b as Map))
      .toList();
  String? error;

  Widget field(
    String label,
    String initial,
    ValueChanged<String> change, {
    bool number = false,
    int lines = 1,
    Key? fieldKey,
  }) => HrConfigLabel(
    label,
    child: TextFormField(
      key: fieldKey,
      initialValue: initial,
      maxLines: lines,
      style: TextStyle(
        fontSize: 14,
        color: hrConfigColor(context, const Color(0xFF302B39)),
      ),
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: InputDecoration(hintText: number ? '请输入分值' : '请输入$label'),
      onChanged: change,
    ),
  );

  void submit() {
    final weight = (draft['weight'] as num?)?.toDouble();
    if (weight == null ||
        !weight.isFinite ||
        weight <= 0 ||
        weight > 100 ||
        bands.any((band) {
          final min = (band['min'] as num?)?.toDouble();
          final max = (band['max'] as num?)?.toDouble();
          return min == null ||
              max == null ||
              !min.isFinite ||
              !max.isFinite ||
              min < 0 ||
              max < min ||
              max > (widget.direct ? weight : 100) ||
              '${band['description'] ?? ''}'.trim().isEmpty;
        })) {
      setState(() => error = '请核对权重及分档范围，分档不得超过该指标满分');
      return;
    }
    snapshot['bands'] = bands;
    draft['snapshot'] = snapshot;
    Navigator.pop(context, draft);
  }

  @override
  Widget build(BuildContext context) => HrConfigPanel(
    title: '编辑 ${snapshot['name']}',
    footer: Row(
      children: [
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: '完成模板指标编辑',
          child: FilledButton.icon(
            onPressed: submit,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('完成编辑'),
          ),
        ),
      ],
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${snapshot['project']} · 仅修改当前模板的评分标准',
            style: TextStyle(
              fontSize: 12,
              color: hrConfigColor(context, const Color(0xFF8C8298)),
            ),
          ),
          const SizedBox(height: 18),
          field(
            '本模板指标权重（%）',
            '${draft['weight']}',
            (v) => draft['weight'] = double.tryParse(v),
            number: true,
            fieldKey: const ValueKey('hr-template-item-weight'),
          ),
          const SizedBox(height: 16),
          field(
            '本模板评分说明',
            '${snapshot['instructions'] ?? ''}',
            (v) => snapshot['instructions'] = v,
            lines: 3,
            fieldKey: const ValueKey('hr-template-item-instructions'),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '评分分档',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(
                  () => bands.add({'min': 0.0, 'max': 0.0, 'description': ''}),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('添加分档'),
              ),
            ],
          ),
          if (bands.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                '可添加不同得分区间对应的考核标准',
                style: TextStyle(
                  fontSize: 12,
                  color: hrConfigColor(context, const Color(0xFF8C8298)),
                ),
              ),
            ),
          for (var index = 0; index < bands.length; index++)
            Container(
              key: ObjectKey(bands[index]),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hrConfigBorder(context, const Color(0xFFECE7F3)),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        '分档 ${index + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '删除模板分档',
                        onPressed: () => setState(() => bands.removeAt(index)),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: field(
                          '最低分',
                          '${bands[index]['min']}',
                          (v) => bands[index]['min'] = double.tryParse(v),
                          number: true,
                          fieldKey: ValueKey('hr-band-min-$index'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: field(
                          '最高分',
                          '${bands[index]['max']}',
                          (v) => bands[index]['max'] = double.tryParse(v),
                          number: true,
                          fieldKey: ValueKey('hr-band-max-$index'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  field(
                    '评分标准',
                    '${bands[index]['description'] ?? ''}',
                    (v) => bands[index]['description'] = v,
                    lines: 3,
                    fieldKey: ValueKey('hr-band-description-$index'),
                  ),
                ],
              ),
            ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
        ],
      ),
    ),
  );
}
