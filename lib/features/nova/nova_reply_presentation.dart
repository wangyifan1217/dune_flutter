/// 仅识别灯塔约定的连续查询前缀，普通问答中的同名字段保持原样。
class NovaLighthouseReplyPresentation {
  const NovaLighthouseReplyPresentation({
    required this.body,
    required this.subject,
    required this.period,
    required this.metric,
    required this.source,
    this.empty = false,
  });

  final String body;
  final String subject;
  final String period;
  final String metric;
  final String source;
  final bool empty;

  String get scope =>
      [source, subject, metric].where((value) => value.isNotEmpty).join(' · ');

  String get copyText => [
    if (empty) '暂未找到匹配数据',
    body,
    '',
    scope,
    if (period.isNotEmpty) period,
  ].join('\n');

  static NovaLighthouseReplyPresentation? tryParse(String text) {
    final lines = text.trim().split('\n');
    final fields = <String, String>{};
    final field = RegExp(r'^(查询对象|日期范围|期间|指标|数据来源)[：:]\s*(.+)$');
    var index = 0;
    while (index < lines.length && index < 8) {
      final match = field.firstMatch(lines[index].trim());
      if (match == null) break;
      fields[match[1]!] = match[2]!.trim();
      index++;
    }
    final source = fields['数据来源'] ?? '';
    if (!source.startsWith('灯塔') ||
        !fields.containsKey('查询对象') ||
        index >= lines.length)
      return null;
    var body = lines.skip(index).join('\n').trim();
    if (body.isEmpty) return null;
    final missing = RegExp(
      r'^灯塔里没有「([^」]+)」。(?:没有拿别的名称充数。)?$',
    ).firstMatch(body);
    if (missing != null) {
      body = '当前查询范围内，未找到「${missing[1]}」对应的数据。';
    }
    final period = (fields['日期范围'] ?? fields['期间'] ?? '')
        .replaceAll('Asia/Shanghai，', '')
        .replaceAll('Asia/Shanghai, ', '')
        .replaceAll('（Asia/Shanghai）', '')
        .trim();
    return NovaLighthouseReplyPresentation(
      body: body,
      subject: fields['查询对象']!,
      period: period,
      metric: fields['指标'] ?? '',
      source: source,
      empty: missing != null,
    );
  }
}
