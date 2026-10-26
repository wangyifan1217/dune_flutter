import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'nova_markdown.dart';

/// 灯塔回答正文的排版：把服务端按行写的结果整理成更好读的块。
///
/// - 连续两行以上「指标 数值（环比 ±x%）」→ 指标卡片（数值加粗、环比上绿下红）；
/// - 「按省份：」这类小节行 → 加粗小标题；
/// - 「1. 名称：…」排名行 → 名称加粗；
/// - 「金额来自灯塔查询，没有另行估算」「还可以说：…」等固定尾注去掉（来源在底部，追问在按钮里）。
///
/// 只改展示，复制、转发仍用原文。
sealed class NovaReplyBlock {
  const NovaReplyBlock();
}

class NovaReplyMarkdown extends NovaReplyBlock {
  const NovaReplyMarkdown(this.markdown);
  final String markdown;
}

class NovaReplyKpis extends NovaReplyBlock {
  const NovaReplyKpis(this.items);
  final List<NovaReplyKpi> items;
}

class NovaReplyKpi {
  const NovaReplyKpi({
    required this.label,
    required this.value,
    this.delta = '',
    this.direction = 0,
  });

  final String label;
  final String value;

  /// 「环比 +3.2%」这类说明；没有时为空。
  final String delta;

  /// 1 上升，-1 下降，0 持平或未知。
  final int direction;
}

final _kpiLine = RegExp(
  r'^(?:[-·•]\s*)?([一-龥A-Za-z（）()/]{1,12})[ ：:]\s*([-+]?\d[\d,]*(?:\.\d+)?\s*(?:万|亿|元|%|‰)?)\s*(?:[（(]((?:环比|同比|日均环比)\s*[+\-−]?\d[\d.]*%)[）)])?[。]?$',
);
final _sectionLine = RegExp(r'^([^\s：:，,。|#*\d][^\s：:，,。|]{0,13})[：:]$');
final _rankLine = RegExp(r'^(\d{1,2})\.\s+([^：:*\n|]{1,40})[：:]\s*(.+)$');
final _boilerplate = RegExp(
  r'^(?:金额(?:和单位|全部)?来自灯塔[^。]*没有另行估算。?|排序使用灯塔返回的[^。]*没有另行估算。?|还可以说[：:].*)$',
);

/// 去掉固定尾注后的正文，复制等场景也可以用。
String novaCleanLighthouseBody(String body) {
  final lines = body.split('\n');
  final kept = <String>[
    for (final line in lines)
      if (!_boilerplate.hasMatch(line.trim())) line,
  ];
  return kept.join('\n').trim();
}

NovaReplyKpi? _parseKpi(String line) {
  final m = _kpiLine.firstMatch(line.trim());
  if (m == null) return null;
  final delta = (m[3] ?? '').replaceAll('−', '-');
  var direction = 0;
  if (delta.isNotEmpty &&
      !RegExp(r'^[^\d]*[+\-]?0(?:\.0+)?%$').hasMatch(delta)) {
    direction = delta.contains('-') ? -1 : 1;
  }
  return NovaReplyKpi(
    label: m[1]!.trim(),
    value: m[2]!.replaceAll(' ', ''),
    delta: delta,
    direction: direction,
  );
}

List<NovaReplyBlock> novaReplyBlocks(String body) {
  final lines = novaCleanLighthouseBody(body).split('\n');
  final blocks = <NovaReplyBlock>[];
  final text = <String>[];
  void flushText() {
    final joined = text.join('\n').trim();
    if (joined.isNotEmpty) blocks.add(NovaReplyMarkdown(joined));
    text.clear();
  }

  var i = 0;
  while (i < lines.length) {
    // 指标块：至少连续两行。
    final run = <NovaReplyKpi>[];
    var j = i;
    while (j < lines.length) {
      final kpi = _parseKpi(lines[j]);
      if (kpi == null) break;
      run.add(kpi);
      j++;
    }
    if (run.length >= 2) {
      flushText();
      blocks.add(NovaReplyKpis(run));
      i = j;
      continue;
    }
    final line = lines[i];
    final trimmed = line.trim();
    final inTable = trimmed.startsWith('|');
    final section = inTable ? null : _sectionLine.firstMatch(trimmed);
    final rank = inTable ? null : _rankLine.firstMatch(trimmed);
    if (section != null) {
      if (text.isNotEmpty && text.last.trim().isNotEmpty) text.add('');
      text.add('**${section[1]}**');
    } else if (rank != null && !rank[2]!.contains('**')) {
      text.add('${rank[1]}. **${rank[2]!.trim()}**：${rank[3]}');
    } else {
      text.add(line);
    }
    i++;
  }
  flushText();
  return blocks;
}

/// 渲染 [novaReplyBlocks] 的结果。
class NovaReplyBlocksView extends StatelessWidget {
  const NovaReplyBlocksView({super.key, required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final blocks = novaReplyBlocks(body);
    if (blocks.isEmpty) {
      return NovaMarkdownBody(text: body, manageSelection: false);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: switch (blocks[i]) {
              NovaReplyMarkdown(:final markdown) => NovaMarkdownBody(
                text: markdown,
                manageSelection: false,
              ),
              NovaReplyKpis(:final items) => _NovaKpiGrid(items: items),
            },
          ),
      ],
    );
  }
}

class _NovaKpiGrid extends StatelessWidget {
  const _NovaKpiGrid({required this.items});

  final List<NovaReplyKpi> items;

  static String _deltaText(NovaReplyKpi item) {
    if (item.direction > 0) return '↑ ${item.delta}';
    if (item.direction < 0) return '↓ ${item.delta}';
    return item.delta;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tileColor = dark ? const Color(0xFF26232D) : const Color(0xFFF6F4FB);
    final label = DunesColors.resolve(context, DunesColors.text3);
    final ink = DunesColors.resolve(context, DunesColors.text);
    const up = Color(0xFF1FA463);
    const down = Color(0xFFE5484D);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final columns = constraints.maxWidth >= 520
            ? 4
            : constraints.maxWidth >= 300
            ? 3
            : 2;
        final cols = items.length < columns ? items.length : columns;
        final width = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              Container(
                width: width,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: tileColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: label, height: 1.3),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (item.delta.isNotEmpty)
                      Text(
                        _deltaText(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: item.direction > 0
                              ? up
                              : item.direction < 0
                              ? down
                              : label,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
