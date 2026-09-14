import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../profile/work_profile_kpi.dart';

const _accent = Color(0xFF3D7A8C);

/// 指标明细：一行一个指标，把「本月 / 上月 / 环比 / 得分（满分）」摆开，
/// 替代原来用「；」拼成一长串、看不出分是怎么来的写法。
class KpiMetricList extends StatelessWidget {
  const KpiMetricList({required this.metrics});

  final List<WorkProfileKpiMetric> metrics;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEDEFF2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          for (var i = 0; i < metrics.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: i == metrics.length - 1
                    ? null
                    : const Border(
                        bottom: BorderSide(color: Color(0xFFF1F3F5)),
                      ),
              ),
              child: _MetricRow(metric: metrics[i]),
            ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.metric});

  final WorkProfileKpiMetric metric;

  @override
  Widget build(BuildContext context) {
    final cap = metric.maxPoints > 0 ? metric.maxPoints : metric.weight;
    final pts = metric.points;
    final fill = (pts != null && cap > 0) ? (pts / cap).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                metric.label,
                style: const TextStyle(fontSize: 13, color: DunesColors.text2),
              ),
            ),
            Text(
              _points(metric),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: pts == null ? DunesColors.text3 : DunesColors.text,
              ),
            ),
            if (cap > 0)
              Text(
                ' / ${cap.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: fill,
            minHeight: 4,
            backgroundColor: const Color(0xFFF1F3F5),
            valueColor: AlwaysStoppedAnimation<Color>(
              pts == null ? const Color(0xFFD7DBDE) : _accent,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _detail(metric),
          style: TextStyle(fontSize: 11, color: _detailColor(metric)),
        ),
      ],
    );
  }

  static String _points(WorkProfileKpiMetric m) {
    if (m.points != null) return m.points!.toStringAsFixed(1);
    return m.status == 'manual' ? '待填' : '—';
  }

  static String _detail(WorkProfileKpiMetric m) {
    if (m.status == 'manual') {
      return '不自动打分，需人工填写';
    }
    if (m.status == 'none') {
      return m.kind == 'users' || m.kind == 'newUsers'
          ? '两期里缺一期用户数，本指标不计分'
          : '上期为 0，环比算不出来，本指标不计分';
    }
    if (m.note.isNotEmpty && m.momPct == null) {
      return m.note; // 例如能源回款的「默认已回」
    }
    final cur = _value(m, m.current);
    final prev = _value(m, m.previous);
    final mom = m.momPct == null
        ? ''
        : m.kind == 'margin'
            ? '　环比 ${m.momPct! >= 0 ? '+' : ''}${m.momPct!.toStringAsFixed(1)}pp'
            : '　环比 ${m.momPct! >= 0 ? '+' : ''}${m.momPct!.toStringAsFixed(1)}%';
    if (cur == '—' && prev == '—') return mom.trim();
    return '本月 $cur · 上月 $prev$mom';
  }

  static Color _detailColor(WorkProfileKpiMetric m) {
    if (m.status == 'manual') return const Color(0xFFB07A2B);
    if (m.status == 'none') return DunesColors.text3;
    if (m.momPct == null) return DunesColors.text3;
    if (m.momPct! > 0) return const Color(0xFF2A7A5E);
    if (m.momPct! < 0) return const Color(0xFFA5473C);
    return DunesColors.text3;
  }

  static String _value(WorkProfileKpiMetric m, double? v) {
    if (v == null) return '—';
    switch (m.kind) {
      case 'margin':
        return '${(v * 100).toStringAsFixed(1)}%';
      case 'users':
      case 'newUsers':
        return _plain(v);
      default:
        return kpiMoney(v);
    }
  }
}

/// 营收/利润按万、亿压一下：原来直接打 1966626.30，读数要一位一位数。
String kpiMoney(double? v) {
  if (v == null) return '—';
  final abs = v.abs();
  if (abs >= 100000000) return '${(v / 100000000).toStringAsFixed(2)}亿';
  if (abs >= 10000) return '${(v / 10000).toStringAsFixed(2)}万';
  return _plain(v);
}

String _plain(double? v) {
  if (v == null) return '—';
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}
