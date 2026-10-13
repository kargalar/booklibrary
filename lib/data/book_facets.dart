const bookFacetLabels = <String, String>{
  'tags': 'Etiketler',
  'subjectPlaces': 'Konu yerleri',
  'subjectPeople': 'People',
  'subjectTimes': 'Time periods',
  'contributions': 'Contributors',
};

const _textRepairs = <String, String>{
  '\u00c3\u0087': 'Ç',
  '\u00c3\u0096': 'Ö',
  '\u00c4\u00b0': 'İ',
  '\u00c4\u017e': 'Ğ',
  '\u00c5\u017e': 'Ş',
  '\u00c3\u009c': 'Ü',
  '\u00c3\u00a7': 'ç',
  '\u00c3\u00b6': 'ö',
  '\u00c4\u00b1': 'ı',
  '\u00c4\u009f': 'ğ',
  '\u00c5\u009f': 'ş',
  '\u00c3\u00bc': 'ü',
  '\u00c3': '',
  '\u00c2': '',
  '\u00e2\u0080\u0099': '’',
  '\u00e2\u0080\u009c': '"',
  '\u00e2\u0080\u009d': '"',
  '\u00e2\u0080\u0093': '-',
  '\u00e2\u0080\u0094': '-',
  '\u00e2\u0080\u00a6': '...',
  'I\u0307': 'İ',
  'i\u0307': 'i',
  'S\u0327': 'Ş',
  's\u0327': 'ş',
  'G\u0308': 'Ğ',
  'g\u0308': 'ğ',
  'U\u0308': 'Ü',
  'u\u0308': 'ü',
  'O\u0308': 'Ö',
  'o\u0308': 'ö',
  'C\u0327': 'Ç',
  'c\u0327': 'ç',
};

String normalizeBookText(String value) {
  var normalized = value;
  for (final repair in _textRepairs.entries) {
    normalized = normalized.replaceAll(repair.key, repair.value);
  }
  return normalized
      .replaceAll(RegExp(r'[\u00a0\u2007\u202f]'), ' ')
      .replaceAll('\uFFFD', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String normalizeBookKey(String value) =>
    normalizeBookText(value)
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');

List<String> normalizeBookItems(Iterable<String> values) {
  final items = <String, String>{};
  for (final value in values) {
    final item = normalizeBookText(value);
    if (item.isNotEmpty) items.putIfAbsent(normalizeBookKey(item), () => item);
  }
  return items.values.toList();
}

List<String> bookFacetItems(Map<String, dynamic> book, String key) {
  if (key == 'tags' &&
      !book.containsKey('tags') &&
      '${book['metadataSource']}'.startsWith('Open Library')) {
    final items = <String>[];
    for (final raw in [
      book['isbnApiData'],
      book['isbnApiEditionData'],
      book['isbnApiWorkData'],
    ]) {
      if (raw is! Map) continue;
      for (final value in [raw['subjects'], raw['subject'], raw['genres']]) {
        if (value is! Iterable) continue;
        for (final item in value) {
          final label = item is Map ? item['name'] : item;
          if (label is String) items.add(label);
        }
      }
    }
    return normalizeBookItems(items);
  }
  final value = book[key];
  return value is Iterable
      ? normalizeBookItems(value.whereType<String>())
      : const [];
}

Map<String, int> bookFacetCounts(
  Iterable<Map<String, dynamic>> books,
  String key,
) {
  final counts = <String, int>{};
  final labels = <String, String>{};
  for (final book in books) {
    for (final item in bookFacetItems(book, key)) {
      final label = labels.putIfAbsent(normalizeBookKey(item), () => item);
      counts.update(label, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  return counts;
}

bool matchesBookFacets(
  Map<String, dynamic> book,
  Map<String, String> filters,
) => filters.entries.every(
  (filter) => bookFacetItems(
    book,
    filter.key,
  ).any((item) => normalizeBookKey(item) == normalizeBookKey(filter.value)),
);
