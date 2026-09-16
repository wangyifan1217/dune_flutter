/// 把后台「更新说明」解析成「软件更新」页用的标题 / 简介 / 注意事项。
class ParsedReleaseNotes {
  const ParsedReleaseNotes({
    required this.headline,
    required this.summary,
    required this.notices,
  });

  final String headline;
  final String summary;
  final List<String> notices;
}

const kDefaultReleaseHeadline = '版本更新';
const kForceReleaseHeadline = '重要更新';
const kDefaultReleaseSummary = '亲爱的用户，本次更新优化了部分场景的使用体验，推荐您进行更新。';
const kDefaultReleaseNotices = <String>[
  '本次更新不会删除您的用户数据，但仍建议您在更新前做好必要备份。',
  '更新完成后如遇到异常，请退出后重新打开应用。',
  '如在使用过程中遇到问题，请联系管理员寻求支持。',
];

final _numberedPrefix = RegExp(r'^\s*(?:\d+[\.．、\)]\s*|[-•●]\s+)');

ParsedReleaseNotes parseReleaseNotes(
  String raw, {
  bool forceUpdate = false,
}) {
  final defaultHeadline = forceUpdate
      ? kForceReleaseHeadline
      : kDefaultReleaseHeadline;
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (text.isEmpty) {
    return ParsedReleaseNotes(
      headline: defaultHeadline,
      summary: kDefaultReleaseSummary,
      notices: List<String>.from(kDefaultReleaseNotices),
    );
  }

  final lines = text.split('\n').map((e) => e.trim()).toList();
  var noticeStart = -1;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty) continue;
    if (line.startsWith('更新注意事项') || line == '注意事项' || line == '注意事项：') {
      noticeStart = i + 1;
      break;
    }
  }

  late final List<String> introLines;
  late final List<String> noticeLines;
  if (noticeStart >= 0) {
    introLines = lines.sublist(0, noticeStart - 1);
    noticeLines = lines.sublist(noticeStart);
  } else {
    final firstNumbered = lines.indexWhere(_isNoticeLine);
    if (firstNumbered > 0) {
      introLines = lines.sublist(0, firstNumbered);
      noticeLines = lines.sublist(firstNumbered);
    } else if (firstNumbered == 0) {
      introLines = const <String>[];
      noticeLines = lines;
    } else {
      introLines = lines;
      noticeLines = const <String>[];
    }
  }

  var headline = defaultHeadline;
  var summary = kDefaultReleaseSummary;
  final intro = introLines.where((e) => e.isNotEmpty).toList();
  if (intro.isNotEmpty) {
    final first = intro.first.replaceAll(RegExp(r'[：:]+$'), '');
    if (_looksLikeHeadline(first) && intro.length > 1) {
      headline = first;
      final rest = intro.sublist(1).join('\n').trim();
      if (rest.isNotEmpty) summary = rest;
    } else {
      summary = intro.join('\n');
    }
  }

  final notices = noticeLines
      .where((e) => e.isNotEmpty)
      .map(_stripNoticePrefix)
      .where((e) => e.isNotEmpty)
      .toList();
  return ParsedReleaseNotes(
    headline: headline,
    summary: summary,
    notices: notices.isEmpty
        ? List<String>.from(kDefaultReleaseNotices)
        : notices,
  );
}

bool _looksLikeHeadline(String line) {
  if (line.length > 18) return false;
  if (_isNoticeLine(line)) return false;
  return !line.contains('。') && !line.contains('，');
}

bool _isNoticeLine(String line) => _numberedPrefix.hasMatch(line);

String _stripNoticePrefix(String line) {
  return line.replaceFirst(_numberedPrefix, '').trim();
}
