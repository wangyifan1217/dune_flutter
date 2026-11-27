import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import 'hr_performance_service.dart';
import 'hr_performance_template_ui.dart';
import 'hr_performance_task_evidence.dart';

List<Map<String, dynamic>> hrMaps(dynamic value) =>
    (value is List ? value : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
double hrNumber(dynamic value) {
  final v = double.tryParse('$value');
  if (v == null || !v.isFinite) throw const FormatException('请填写有效数字');
  return v;
}

String hrText(dynamic v) => '${v ?? ''}'.trim();

Future<bool> hrConfirmAction(
  BuildContext context, {
  required String title,
  required String message,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: hrConfigTheme(context),
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            title.startsWith('确认') ? title : '确认$title',
            style: DunesTypography.sans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DunesColors.resolve(context, DunesColors.text),
            ),
          ),
          content: SingleChildScrollView(
            child: Text(
              message,
              style: DunesTypography.sans(
                fontSize: 13.5,
                height: 1.5,
                color: DunesColors.resolve(context, DunesColors.text2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('hr-confirm-action'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.pop(context, true);
              },
              child: const Text('确认提交'),
            ),
          ],
        ),
      ),
    ) ==
    true;

Future<Map<String, dynamic>?> hrFormSheet(
  BuildContext context, {
  required String title,
  required Map<String, dynamic> values,
  required List<Widget> Function(Map<String, dynamic>, StateSetter) fields,
  required Map<String, dynamic> Function(Map<String, dynamic>) submit,
  String submitLabel = '提交',
  String? message,
  bool confirmSubmission = true,
  String Function()? confirmationMessage,
  Future<void> Function(Map<String, dynamic>)? submitInSheet,
  double maxWidth = 520,
}) {
  String? error;
  var submitting = false;
  return showHrConfigPanel<Map<String, dynamic>>(
    context,
    Theme(
      data: hrConfigTheme(context),
      child: StatefulBuilder(
        builder: (context, update) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final border = DunesColors.resolve(
            context,
            const Color(0xFFE5E5EA),
            role: DunesColorRole.border,
          );
          final subtleBg = hrConfigSurface(
            context,
            isDark ? const Color(0xFF282538) : const Color(0xFFF5F5F7),
          );
          return SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: border.withValues(alpha: 0.6),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: DunesTypography.sans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: submitting
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (message != null && message.trim().isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: subtleBg,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 16,
                                  color: hrConfigColor(
                                    context,
                                    DunesColors.brandPurple,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    message,
                                    style: DunesTypography.sans(
                                      fontSize: 12.5,
                                      height: 1.45,
                                      color: DunesColors.resolve(
                                        context,
                                        DunesColors.text2,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ...fields(values, update),
                        if (error != null && submitInSheet == null)
                          Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.error.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              error!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (error != null && submitInSheet != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        error!,
                        key: const ValueKey('hr-sheet-submit-error'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  decoration: BoxDecoration(
                    color: subtleBg.withValues(alpha: 0.65),
                    border: Border(
                      top: BorderSide(
                        color: border.withValues(alpha: 0.6),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: submitting
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const ValueKey('hr-sheet-submit'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: submitting
                            ? null
                            : () async {
                                HapticFeedback.selectionClick();
                                try {
                                  final result = submit(values);
                                  if (submitInSheet != null) {
                                    update(() {
                                      submitting = true;
                                      error = null;
                                    });
                                  }
                                  if (confirmSubmission &&
                                      !await hrConfirmAction(
                                        context,
                                        title: title,
                                        message:
                                            confirmationMessage?.call() ??
                                            '$title\n${message ?? '请核对填写的内容，确认后提交。'}${hrText(result['reason']).isEmpty ? '' : '\n原因：${result['reason']}'}${hrText(result['target']).isEmpty ? '' : '\n目标阶段：${hrPerformanceStageLabels[hrText(result['target'])] ?? result['target']}'}',
                                      )) {
                                    return;
                                  }
                                  if (!context.mounted) return;
                                  if (submitInSheet != null) {
                                    await submitInSheet(result);
                                  }
                                  if (!context.mounted) return;
                                  Navigator.pop(context, result);
                                } on FormatException catch (e) {
                                  if (context.mounted) {
                                    update(() => error = e.message);
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    update(() => error = '$e');
                                  }
                                } finally {
                                  if (context.mounted && submitting) {
                                    update(() => submitting = false);
                                  }
                                }
                              },
                        child: Text(submitting ? '提交中…' : submitLabel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
    maxWidth: maxWidth,
    fitContent: true,
  );
}

Widget hrReasonField(
  Map<String, dynamic> values, {
  String label = '说明 / 理由',
  String keyName = 'reason',
  TextEditingController? controller,
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 10),
  child: TextFormField(
    key: ValueKey('hr-$keyName'),
    controller: controller,
    initialValue: controller == null ? hrText(values[keyName]) : null,
    minLines: 2,
    maxLines: 5,
    decoration: InputDecoration(
      labelText: label,
      hintText: '请填写$label',
      filled: true,
    ),
    onChanged: (v) => values[keyName] = v,
  ),
);

Future<Map<String, dynamic>?> showHrUrgeSheet(
  BuildContext context, {
  required String scope,
}) => hrFormSheet(
  context,
  title: '发送督办',
  submitLabel: '发送督办',
  message: '$scope\n将向所列考核的当前节点办理人发送提醒。',
  values: {'reason': ''},
  fields: (v, update) => [
    Text(
      '督办内容（必填）',
      style: TextStyle(
        fontSize: 12,
        color: hrConfigColor(context, const Color(0xFF827A8C)),
      ),
    ),
    const SizedBox(height: 5),
    ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: TextFormField(
        key: const ValueKey('hr-reason'),
        initialValue: hrText(v['reason']),
        minLines: 1,
        maxLines: 4,
        style: const TextStyle(fontSize: 13),
        decoration: const InputDecoration(
          hintText: '填写需要提醒的内容',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (value) => v['reason'] = value,
      ),
    ),
  ],
  submit: (v) {
    final reason = hrText(v['reason']);
    if (reason.isEmpty) throw const FormatException('请填写督办内容');
    return {'reason': reason};
  },
);

Future<Map<String, dynamic>?> showHrReasonSheet(
  BuildContext context, {
  required String title,
  String? message,
  List<String>? targets,
  int minLength = 0,
  String submitLabel = '确认',
  String Function(String target)? scopePreview,
}) {
  final values = {'reason': '', 'target': targets?.firstOrNull};
  final reasonCtrl = TextEditingController();
  const quickReasons = [
    ('分数偏差较大', '分数与初评偏差较大，请核实依据'),
    ('补充佐证材料', '请补充关键工作成果与佐证材料'),
    ('系数需校准', '绩效等级/系数需重新校准'),
  ];
  return hrFormSheet(
    context,
    title: title,
    message: message,
    submitLabel: submitLabel,
    values: values,
    confirmationMessage: scopePreview == null
        ? null
        : () {
            final target = hrText(values['target']);
            return [
              '目标阶段：${hrPerformanceStageLabels[target] ?? target}',
              scopePreview(target),
              ?message,
              '原因：${hrText(values['reason'])}',
            ].join('\n');
          },
    fields: (v, update) => [
      if (targets != null)
        HrSelect<String>(
          initialValue: hrText(v['target']),
          decoration: const InputDecoration(labelText: '处理方式'),
          items: targets
              .map(
                (x) => DropdownMenuItem(
                  value: x,
                  child: Text(
                    hrPerformanceStageLabels[x] ?? (x == 'reject' ? '驳回申诉' : x),
                  ),
                ),
              )
              .toList(),
          onChanged: (x) => update(() => v['target'] = x),
        ),
      if (scopePreview != null) Text(scopePreview(hrText(v['target']))),
      if (targets == null && minLength > 0) ...[
        Text(
          '快捷理由',
          style: DunesTypography.sans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DunesColors.resolve(context, DunesColors.text2),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final item in quickReasons)
              ActionChip(
                label: Text(item.$1),
                labelStyle: DunesTypography.sans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: DunesColors.resolve(context, DunesColors.text),
                ),
                backgroundColor: hrConfigSurface(
                  context,
                  const Color(0xFFF5F5F7),
                ),
                side: BorderSide.none,
                shape: const StadiumBorder(),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  reasonCtrl.text = item.$2;
                  update(() => v['reason'] = item.$2);
                },
              ),
          ],
        ),
        const SizedBox(height: 4),
      ],
      hrReasonField(v, controller: reasonCtrl),
    ],
    submit: (v) {
      if (hrText(v['reason']).runes.length < minLength) {
        throw FormatException('说明至少 $minLength 个字');
      }
      return {
        'reason': hrText(v['reason']),
        if (targets != null) 'target': v['target'],
      };
    },
  ).whenComplete(reasonCtrl.dispose);
}

String hrScoreEditImpact(HrPerformanceRecord record) =>
    const ['ready_final', 'final'].contains(record.stage)
    ? '保存后将退回 HR 审核，原送审或终审办理将失效，需要重新送审。'
    : record.stage == 'hr'
    ? '保存后保留在 HR 审核，须按修改后的分数重新审核。'
    : '保存后保留当前阶段，按修改后的分数继续办理。';

Future<Map<String, dynamic>?> showHrScoreSheet(
  BuildContext context,
  HrPerformanceRecord record,
  Map<String, dynamic> config, {
  required String title,
  required bool initial,
  bool self = false,
  bool hrEdit = false,
  Future<void> Function(Map<String, dynamic>)? submitInSheet,
}) {
  final lines = [
    for (final line in record.lines)
      {
        ...line,
        'score':
            '${(self ? line['selfScore'] : line['score']) ?? (hrEdit ? null : line['suggestedScore']) ?? ''}',
        'remark': '${(self ? line['selfRemark'] : line['remark']) ?? ''}',
      },
  ];
  final scoreCtrls = <String, TextEditingController>{
    for (final line in lines)
      '${line['indicatorId']}': TextEditingController(
        text: hrText(line['score']),
      ),
  };
  final reasonCtrl = TextEditingController();
  const quickEditReasons = [
    '部门横向校准',
    '结合任务佐证微调',
    '修正评分笔误',
  ];
  final hasSuggestedScores = lines.any((l) => l['suggestedScore'] != null);
  final rules = Map<String, dynamic>.from(config['rules'] as Map? ?? {});
  String? scoreError(Map<String, dynamic> line) {
    final value = hrText(line['score']);
    if (value.isEmpty) return '请填写得分';
    final score = double.tryParse(value);
    final max = line['directScore'] == true
        ? ((line['weight'] as num?)?.toDouble() ?? 0)
        : 100.0;
    if (score == null || !score.isFinite || score < 0 || score > max) {
      return '请输入 0–$max 的得分';
    }
    final decimal = (rules['decimalPlaces'] as num?)?.toInt() ?? 1;
    final multiplier = math.pow(10, decimal);
    if ((score * multiplier - (score * multiplier).round()).abs() > 0.00001) {
      return '最多 $decimal 位小数';
    }
    return null;
  }

  bool needsRemark(Map<String, dynamic> line) {
    if (!initial || scoreError(line) != null) return false;
    final score = double.parse(hrText(line['score']));
    final max = line['directScore'] == true
        ? ((line['weight'] as num?)?.toDouble() ?? 0)
        : 100.0;
    final suggested = (line['suggestedScore'] as num?)?.toDouble();
    return suggested == null ||
        (suggested - score).abs() > 0.00001 ||
        (line['directScore'] == true && max > 0 ? score * 100 / max : score) <
            ((rules['remarkBelow'] as num?)?.toDouble() ?? 60);
  }

  return hrFormSheet(
    context,
    title: title,
    maxWidth: 760,
    values: {'lines': lines, 'reason': ''},
    submitLabel: self ? '提交自评' : (initial ? '提交初评' : '保存并提交'),
    submitInSheet: submitInSheet,
    message: hrEdit
        ? '可同时核对或修改每项指标得分与备注，并填写改分理由。${hrScoreEditImpact(record)}'
        : initial
        ? '按每项满分填写得分；无建议分、与建议分不一致或低于备注线时须填写备注。'
        : '改动任何分数都须填写改分理由。',
    fields: (v, update) => [
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: hrConfigSurface(context, DunesColors.brandPurpleSoft),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '共 ${lines.length} 项 · ${lines.where((l) => scoreError(l) == null && (!needsRemark(l) || hrText(l['remark']).isNotEmpty)).length} 项已填写完整',
                style: DunesTypography.sans(
                  fontSize: 12.5,
                  color: hrConfigColor(context, hrConfigPurple),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '预估总分 ${(lines.fold<double>(0, (n, l) => n + (double.tryParse('${l['score']}') ?? 0) * (l['directScore'] == true ? 1 : ((l['weight'] as num?)?.toDouble() ?? 0) / 100)) + record.bonuses.fold<double>(0, (n, b) => n + ((b['points'] as num?)?.toDouble() ?? 0))).toStringAsFixed(1)}',
              style: DunesTypography.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: hrConfigColor(context, hrConfigPurple),
              ),
            ),
            if (hasSuggestedScores) ...[
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  HapticFeedback.selectionClick();
                  update(() {
                    for (final l in lines) {
                      final s = l['suggestedScore'];
                      if (s != null) {
                        final txt = '$s';
                        l['score'] = txt;
                        scoreCtrls['${l['indicatorId']}']?.text = txt;
                      }
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: hrConfigSurface(context, Colors.white),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '一键填入建议分',
                    style: DunesTypography.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: hrConfigColor(context, hrConfigPurple),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      for (final line in lines)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: hrConfigSurface(context, Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hrConfigBorder(context, const Color(0xFFE5E5EA)),
              width: 0.7,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${line['name']}',
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: DunesColors.resolve(context, DunesColors.text),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: hrConfigSurface(
                          context,
                          DunesColors.brandPurpleSoft,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        self && line['directScore'] == true
                            ? '满分 ${line['weight']} 分'
                            : '权重 ${line['weight']}%',
                        style: DunesTypography.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: hrConfigColor(context, hrConfigPurple),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: hrConfigSurface(
                          context,
                          const Color(0xFFF5F5F7),
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '建议分 ${line['suggestedScore'] ?? '无'}',
                        style: DunesTypography.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: DunesColors.resolve(
                            context,
                            DunesColors.text2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (hrText(line['instructions']).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      hrText(line['instructions']),
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: DunesColors.resolve(context, DunesColors.text2),
                      ),
                    ),
                  ),
                if (hrMaps(line['bands']).isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: hrConfigSurface(
                        context,
                        const Color(0xFFF5F5F7),
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final band in hrMaps(line['bands']))
                          Text(
                            '${band['min']}–${band['max']} 分：${band['description']}',
                            style: DunesTypography.sans(
                              fontSize: 11.5,
                              height: 1.45,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 112,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '指标得分',
                              style: TextStyle(
                                fontSize: 12,
                                color: hrConfigColor(
                                  context,
                                  const Color(0xFF827A8C),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            TextFormField(
                              key: ValueKey('hr-score-${line['indicatorId']}'),
                              controller: scoreCtrls['${line['indicatorId']}'],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: '填写得分',
                                suffixText: '分',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              onChanged: (x) => update(() => line['score'] = x),
                            ),
                          ],
                        ),
                      ),
                      if (initial || hrEdit) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hrEdit
                                    ? '指标备注（可查看/修改）'
                                    : needsRemark(line)
                                    ? '评分备注（必填）'
                                    : '评分备注（选填）',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: hrConfigColor(
                                    context,
                                    const Color(0xFF827A8C),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              TextFormField(
                                key: ValueKey(
                                  'hr-remark-${line['indicatorId']}',
                                ),
                                initialValue: hrText(line['remark']),
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: hrEdit ? '可查看或修改该项备注' : '填写评分说明',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                minLines: 1,
                                maxLines: 3,
                                onChanged: (x) =>
                                    update(() => line['remark'] = x),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                if (scoreError(line) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      scoreError(line)!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (initial &&
                    needsRemark(line) &&
                    hrText(line['remark']).isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      '无建议分、与建议分不同或低于备注线时需要说明',
                      style: TextStyle(
                        fontSize: 11,
                        color: hrConfigColor(context, const Color(0xFF827A8C)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      Container(
        margin: const EdgeInsets.only(top: 2, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: hrConfigSurface(context, const Color(0xFFF5F5F7)),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          '指标得分：${lines.fold<double>(0, (n, l) => n + (double.tryParse('${l['score']}') ?? 0) * (l['directScore'] == true ? 1 : ((l['weight'] as num?)?.toDouble() ?? 0) / 100)).toStringAsFixed(1)}  ·  本月加减分：${record.bonuses.fold<double>(0, (n, b) => n + ((b['points'] as num?)?.toDouble() ?? 0)).toStringAsFixed(1)}',
          style: DunesTypography.sans(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: DunesColors.resolve(context, DunesColors.text),
          ),
        ),
      ),
      if (!initial) ...[
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final chip in quickEditReasons)
              ActionChip(
                label: Text(chip),
                labelStyle: DunesTypography.sans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: DunesColors.resolve(context, DunesColors.text),
                ),
                backgroundColor: hrConfigSurface(
                  context,
                  const Color(0xFFF5F5F7),
                ),
                side: BorderSide.none,
                shape: const StadiumBorder(),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  reasonCtrl.text = chip;
                  update(() => v['reason'] = chip);
                },
              ),
          ],
        ),
        hrReasonField(
          v,
          label: '改分理由（改动时必填）',
          controller: reasonCtrl,
        ),
      ],
    ],
    submit: (v) {
      final incomplete = lines
          .where(
            (l) =>
                scoreError(l) != null ||
                (needsRemark(l) && hrText(l['remark']).isEmpty),
          )
          .map((l) => '${l['name']}')
          .toList();
      if (incomplete.isNotEmpty) {
        throw FormatException('请检查 ${incomplete.join('、')} 的得分或必填备注');
      }
      final result = <Map<String, dynamic>>[];
      for (final l in lines) {
        final score = hrNumber(l['score']);
        final maxScore = l['directScore'] == true
            ? ((l['weight'] as num?)?.toDouble() ?? 0)
            : 100.0;
        if (score < 0 || score > maxScore) {
          throw FormatException('指标分须为 0–$maxScore');
        }
        final decimal = (rules['decimalPlaces'] as num?)?.toInt() ?? 1;
        final multiplier = math.pow(10, decimal);
        if ((score * multiplier - (score * multiplier).round()).abs() >
            0.00001) {
          throw FormatException('最多 $decimal 位小数');
        }
        if (initial &&
            (l['suggestedScore'] == null ||
                (hrNumber(l['suggestedScore']) - score).abs() > 0.00001 ||
                (l['directScore'] == true && maxScore > 0
                        ? score * 100 / maxScore
                        : score) <
                    ((rules['remarkBelow'] as num?)?.toDouble() ?? 60)) &&
            hrText(l['remark']).isEmpty) {
          throw FormatException('${l['name']}须填写评分备注');
        }
        result.add({
          'indicatorId': l['indicatorId'],
          'score': score,
          'remark': hrText(l['remark']),
        });
      }
      if (hrEdit && hrText(v['reason']).isEmpty) {
        throw const FormatException('请填写改分理由');
      }
      if (!initial &&
          lines.any((l) {
            final old = record.lines.firstWhere(
              (x) => x['indicatorId'] == l['indicatorId'],
            );
            return old['score'] != hrNumber(l['score']);
          }) &&
          hrText(v['reason']).isEmpty) {
        throw const FormatException('请填写改分理由');
      }
      return {'lines': result, 'reason': hrText(v['reason'])};
    },
  ).whenComplete(() {
    for (final c in scoreCtrls.values) {
      c.dispose();
    }
    reasonCtrl.dispose();
  });
}

Future<Map<String, dynamic>?> showHrAdjustmentSheet(
  BuildContext context,
  HrPerformanceRecord record,
  Map<String, dynamic> options,
) {
  final config = Map<String, dynamic>.from(options['config'] as Map);
  final library = hrMaps(config['indicators']);
  final indicators = <String, Map<String, dynamic>>{
    for (final i in library) '${i['id']}': i,
  };
  for (final l in record.lines) {
    indicators.putIfAbsent(
      '${l['indicatorId']}',
      () => {
        'id': l['indicatorId'],
        'name': l['name'],
        'enabled': false,
        'weight': l['weight'],
      },
    );
  }
  final weights = <String, String>{
    for (final l in record.lines) '${l['indicatorId']}': '${l['weight']}',
  };
  final taskMap = <int, Map<String, dynamic>>{
    for (final t in [...record.evidence, ...hrMaps(options['tasks'])])
      (t['id'] as num).toInt(): t,
  };
  final selected = record.evidence.map((t) => (t['id'] as num).toInt()).toSet();
  return hrFormSheet(
    context,
    title: '申请调整考核指标与任务',
    maxWidth: 760,
    values: {'reason': ''},
    message: '一次只能有一条待审批申请。主管通过前，原考核表保持不变。',
    fields: (v, update) {
      final weightSum = weights.values.fold<double>(
        0,
        (a, b) => a + (double.tryParse(b) ?? 0),
      );
      final weightValid = (weightSum - 100).abs() < 0.01;
      return [
        for (final i in indicators.values)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            decoration: BoxDecoration(
              color: weights.containsKey('${i['id']}')
                  ? hrConfigSurface(context, DunesColors.brandPurpleSoft)
                        .withValues(alpha: 0.45)
                  : hrConfigSurface(context, const Color(0xFFF5F5F7)),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: weights.containsKey('${i['id']}')
                    ? hrConfigColor(
                        context,
                        hrConfigPurple,
                      ).withValues(alpha: 0.3)
                    : hrConfigBorder(context, const Color(0xFFE5E5EA)),
                width: 0.7,
              ),
            ),
            child: Column(
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${i['name']}',
                    style: DunesTypography.sans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.resolve(context, DunesColors.text),
                    ),
                  ),
                  subtitle: i['enabled'] != true
                      ? const Text('指标已停用，现有快照可保留')
                      : null,
                  value: weights.containsKey('${i['id']}'),
                  onChanged:
                      i['enabled'] != true && !weights.containsKey('${i['id']}')
                      ? null
                      : (checked) => update(() {
                          HapticFeedback.selectionClick();
                          if (checked == true) {
                            weights['${i['id']}'] = '${i['weight'] ?? 0}';
                          } else {
                            weights.remove('${i['id']}');
                          }
                        }),
                ),
                if (weights.containsKey('${i['id']}'))
                  TextFormField(
                    key: ValueKey('hr-weight-${i['id']}'),
                    initialValue: weights['${i['id']}'],
                    decoration: const InputDecoration(
                      labelText: '权重 %',
                      filled: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (x) => update(() => weights['${i['id']}'] = x),
                  ),
              ],
            ),
          ),
        Container(
          margin: const EdgeInsets.only(top: 2, bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: (weightValid
                    ? const Color(0xFF1F9D76)
                    : const Color(0xFFD97706))
                .withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '权重合计 ${weightSum.toStringAsFixed(1)}%${weightValid ? '（已满 100%）' : '（需等于 100%）'}',
            key: const ValueKey('hr-weight-total'),
            style: DunesTypography.sans(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: weightValid
                  ? const Color(0xFF1A8463)
                  : const Color(0xFFD97706),
            ),
          ),
        ),
        Text(
          '任务证据（仅本人在考核月完成的任务）',
          style: DunesTypography.sans(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: DunesColors.resolve(context, DunesColors.text2),
          ),
        ),
        const SizedBox(height: 6),
        for (final e in taskMap.entries)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: hrConfigSurface(context, const Color(0xFFF5F5F7)),
              borderRadius: BorderRadius.circular(11),
            ),
            child: CheckboxListTile(
              title: HrTaskEvidenceContent(
                task: e.value,
                ownerName: record.name,
              ),
              value: selected.contains(e.key),
              onChanged: (x) => update(() {
                HapticFeedback.selectionClick();
                if (x == true) {
                  selected.add(e.key);
                } else {
                  selected.remove(e.key);
                }
              }),
            ),
          ),
        hrReasonField(v, label: '调整原因（必填）'),
      ];
    },
    submit: (v) {
      final total = weights.values.fold<double>(0, (a, b) => a + hrNumber(b));
      if ((total - 100).abs() > 0.00001) {
        throw const FormatException('权重合计必须为 100%');
      }
      if (hrText(v['reason']).isEmpty) throw const FormatException('请填写调整原因');
      return {
        'reason': hrText(v['reason']),
        'lines': [
          for (final e in weights.entries)
            {'indicatorId': e.key, 'weight': hrNumber(e.value)},
        ],
        'evidenceIds': selected.toList(),
      };
    },
  );
}

Future<Map<String, dynamic>?> showHrBonusSheet(
  BuildContext context,
  Map<String, dynamic> config, {
  HrPerformanceRecord? record,
}) {
  final rules = config['rules'] is Map ? config['rules'] as Map : const {};
  final singleCap = hrNumber(
    record?.snapshot['singleDeductionCap'] ?? rules['singleDeductionCap'] ?? 5,
  );
  final monthlyCap = hrNumber(rules['monthlyDeductionCap'] ?? 20);
  final items = hrMaps(
    config['adjustmentItems'],
  ).where((i) => i['enabled'] == true).toList();
  if (items.isEmpty) return Future.value(null);
  return hrFormSheet(
    context,
    title: '录入本月加减分',
    message:
        '扣分单次最多 ${singleCap.toStringAsFixed(0)} 分，每月累计最多 ${monthlyCap.toStringAsFixed(0)} 分。'
        '${record?.snapshot['deductionInstructions'] == null ? '' : '\n${record!.snapshot['deductionInstructions']}'}',
    values: {
      'itemId': items.first['id'],
      'points': '${items.first['points']}',
      'source': '',
    },
    fields: (v, update) => [
      HrSelect<String>(
        initialValue: '${v['itemId']}',
        items: items
            .map(
              (i) => DropdownMenuItem(
                value: '${i['id']}',
                child: Text(
                  '${i['name']} · ${i['direction'] == 'add' ? '加分' : '扣分'}',
                ),
              ),
            )
            .toList(),
        onChanged: (x) => update(() => v['itemId'] = x),
      ),
      TextFormField(
        initialValue: '${v['points']}',
        decoration: const InputDecoration(labelText: '分值（正数）'),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (x) => v['points'] = x,
      ),
      hrReasonField(
        v,
        label:
            items.firstWhere((i) => i['id'] == v['itemId'])['requireSource'] ==
                true
            ? '来源说明（必填）'
            : '来源说明（选填）',
        keyName: 'source',
      ),
    ],
    submit: (v) {
      final item = items.firstWhere((i) => i['id'] == v['itemId']);
      if (item['direction'] == 'deduct' && hrNumber(v['points']) > singleCap) {
        throw FormatException('本模板单次扣分不得超过 ${singleCap.toStringAsFixed(0)} 分');
      }
      if (hrNumber(v['points']) <= 0 ||
          (items.firstWhere((i) => i['id'] == v['itemId'])['requireSource'] ==
                  true &&
              hrText(v['source']).isEmpty)) {
        throw const FormatException('请填写正数分值和来源说明');
      }
      return {
        'itemId': v['itemId'],
        'points': hrNumber(v['points']),
        'source': hrText(v['source']),
      };
    },
  );
}

Future<Map<String, dynamic>?> showHrAssignmentSheet(
  BuildContext context,
  HrPerformanceRecord record,
  Map<String, dynamic> config, {
  bool switchTemplate = false,
  List<Map<String, dynamic>> positions = const [],
}) => hrFormSheet(
  context,
  title: switchTemplate ? '切换考核模板' : '补配本周期考核表',
  message: switchTemplate
      ? '当前模板：${record.snapshot['templateName']}。切换后仍处于${record.stageLabel}。'
      : '部门和主管跟随当前组织关系。这里可补配本周期模板和人员资料。',
  confirmationMessage: switchTemplate
      ? () => '新模板将替换原指标和草稿评分，待处理的指标调整申请将失效。变更会记录在操作日志。'
      : null,
  values: {'reason': ''},
  fields: (v, update) => [
    if (['opening', 'indicators'].contains(record.stage)) ...[
      HrSelect<int>(
        decoration: InputDecoration(labelText: '岗位（当前：${record.position}）'),
        items: positions
            .map(
              (d) => DropdownMenuItem(
                value: (d['id'] as num).toInt(),
                child: Text('${d['name']}'),
              ),
            )
            .toList(),
        onChanged: (x) => v['positionId'] = x,
      ),
      TextFormField(
        initialValue: hrText(record.snapshot['hiredAt']),
        decoration: const InputDecoration(labelText: '入职日期（YYYY-MM-DD，未修改则保持）'),
        onChanged: (x) => v['hiredAt'] = x,
      ),
      TextFormField(
        initialValue: hrText(record.snapshot['probationEndAt']),
        decoration: const InputDecoration(labelText: '试用期截止（YYYY-MM-DD，可清空）'),
        onChanged: (x) => v['probationEndAt'] = x,
      ),
    ],
    if (switchTemplate || ['opening', 'indicators'].contains(record.stage))
      HrSelect<String>(
        decoration: InputDecoration(
          labelText: switchTemplate ? '新考核模板' : '本周期模板（留空保持）',
        ),
        items: hrMaps(config['templates'])
            .where((t) => switchTemplate || t['enabled'] == true)
            .map(
              (t) => DropdownMenuItem(
                value: '${t['id']}',
                child: Text('${t['name']}'),
              ),
            )
            .toList(),
        onChanged: (x) => v['templateId'] = x,
      ),
    hrReasonField(v),
  ],
  submit: (v) {
    if (hrText(v['reason']).isEmpty) throw const FormatException('请填写修改原因');
    if (switchTemplate && v['templateId'] == null) {
      throw const FormatException('请选择新的考核模板');
    }
    if ([
      'templateId',
      'positionId',
      'hiredAt',
      'probationEndAt',
    ].every((key) => v[key] == null)) {
      throw const FormatException('请选择要补配的内容');
    }
    return v;
  },
);

/// 与绩效弹层统一的单选入口，长名单支持搜索。
class HrSelect<T> extends StatefulWidget {
  const HrSelect({
    super.key,
    this.searchHint = '搜索',
    this.initialValue,
    this.decoration = const InputDecoration(),
    required this.items,
    required this.onChanged,
  });
  final String searchHint;
  final T? initialValue;
  final InputDecoration decoration;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  @override
  State<HrSelect<T>> createState() => _HrSelectState<T>();
}

class _HrSelectState<T> extends State<HrSelect<T>> {
  T? value;
  @override
  void initState() {
    super.initState();
    value = widget.initialValue;
  }

  Future<void> choose() async {
    String query = '';
    final selected = await showHrConfigPanel<DropdownMenuItem<T>>(
      context,
      HrConfigPanel(
        title: widget.decoration.labelText ?? '选择',
        child: StatefulBuilder(
          builder: (context, update) {
            final choices = widget.items.where((item) {
              final child = item.child;
              final label = child is Text ? (child.data ?? '') : '';
              return query.isEmpty ||
                  label.toLowerCase().contains(query.toLowerCase());
            }).toList();
            return SizedBox(
              height: (choices.length * 48.0 + 76).clamp(
                150.0,
                MediaQuery.sizeOf(context).height * .6,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: widget.searchHint,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) => update(() => query = v.trim()),
                    ),
                  ),
                  Expanded(
                    child: choices.isEmpty
                        ? const Center(child: Text('没有匹配的选项'))
                        : ListView(
                            children: [
                              for (final item in choices)
                                ListTile(
                                  selected: item.value == value,
                                  selectedColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  title: item.child,
                                  trailing: item.value == value
                                      ? const Icon(Icons.check_rounded)
                                      : null,
                                  onTap: () => Navigator.pop(context, item),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      maxWidth: 440,
      fitContent: true,
    );
    if (selected == null || !mounted) return;
    setState(() => value = selected.value);
    widget.onChanged(selected.value);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.items.where((item) => item.value == value).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: choose,
        child: InputDecorator(
          decoration: widget.decoration.copyWith(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: const Icon(Icons.expand_more_rounded),
          ),
          child: selected.isEmpty
              ? const Text('请选择', style: TextStyle(color: Colors.grey))
              : DefaultTextStyle.merge(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                  child: selected.first.child,
                ),
        ),
      ),
    );
  }
}
