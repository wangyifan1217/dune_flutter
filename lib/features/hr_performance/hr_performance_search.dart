bool hrPerformanceMatchesSearch(String query, Iterable<String> values) {
  final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
  final content = values.join(' ').toLowerCase();
  return terms.every(content.contains);
}
