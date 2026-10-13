part of 'book_metadata.dart';

String? _cleanKey(String value) => value.trim().isEmpty ? null : value.trim();

String _errorMessage(Exception error) =>
    error is FormatException ? error.message : 'Connection error';

Map<String, dynamic> _jsonObject(String value) {
  final decoded = jsonDecode(value);
  return _map(decoded) ?? <String, dynamic>{};
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

String? _url(Object? value) {
  final raw = _string(value) ?? _string(_map(value)?['url']);
  if (raw == null) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return raw.replaceFirst('http://', 'https://');
}

String? _publisherLogoUrl(Object? value) {
  final data = _map(value);
  if (data == null) return null;
  for (final key in [
    'publisherLogoUrl',
    'publisher_logo_url',
    'publisherLogo',
    'publisher_logo',
    'publisherIconUrl',
    'publisher_icon_url',
    'publisherIcon',
    'publisher_icon',
    'logoUrl',
    'logo_url',
    'iconUrl',
    'icon_url',
    'logo',
  ]) {
    final logoUrl = _url(data[key]);
    if (logoUrl != null) return logoUrl;
  }
  final publisher = _map(data['publisher']);
  return publisher == null ? null : _publisherLogoUrl(publisher);
}

String? _text(Object? value) {
  if (value is Map) {
    return _text(value['value'] ?? value['name'] ?? value['text']);
  }
  return _string(value);
}

int? _int(Object? value) => value is int ? value : int.tryParse('$value');

String? _firstString(Object? value) {
  if (value is String) return _string(value);
  if (value is List) {
    for (final item in value) {
      final result = _firstString(item);
      if (result != null) return result;
    }
  }
  if (value is Map) return _firstString(value['name']);
  return null;
}

List<String> _strings(Object? value) {
  if (value is! List) return [];
  return value.map(_text).whereType<String>().toSet().toList();
}

List<Map<String, dynamic>> _maps(Object? value) {
  if (value is! List) return [];
  return value.map(_map).whereType<Map<String, dynamic>>().toList();
}

List<String> _names(Object? value) {
  if (value is! List) return [];
  return value
      .map((item) {
        final map = _map(item);
        return _string(map?['name']) ?? _string(_map(map?['author'])?['name']);
      })
      .whereType<String>()
      .toSet()
      .toList();
}

List<int> _ints(Object? value) {
  if (value is! List) return [];
  return value.map(_int).whereType<int>().toList();
}

List<(String, String)> _languages(Object? value) {
  if (value is! List) return [];
  return value
      .map((item) {
        final key = _string(_map(item)?['key']);
        final code = key?.split('/').last;
        return code == null ? null : (code, _languageName(code) ?? code);
      })
      .whereType<(String, String)>()
      .toSet()
      .toList();
}

List<(String, String)> _languageValues(Object? value) {
  if (value is! List) return [];
  return value
      .map((item) {
        final map = _map(item);
        final raw =
            _string(item) ?? _string(map?['key']) ?? _string(map?['code']);
        final code = raw?.split('/').last.toLowerCase();
        return code == null ? null : (code, _languageName(code) ?? code);
      })
      .whereType<(String, String)>()
      .toSet()
      .toList();
}

String? _languageName(String? code) =>
    code == null ? null : _languageNameMap[_normalizedLabel(code)];

bool _containsIsbn(Object? value, String isbn) {
  if (value is String) return normalizeIsbn(value) == isbn;
  if (value is List) return value.any((item) => _containsIsbn(item, isbn));
  if (value is Map) {
    return _containsIsbn(
      value['identifier'] ??
          value['isbn'] ??
          value['isbn10'] ??
          value['isbn13'],
      isbn,
    );
  }
  return false;
}

String? _lastPathPart(Object? value) {
  final text = _string(value);
  return text?.split('/').last;
}

Map<String, String> get _languageNameMap => const {
  'ar': 'Arabic',
  'ara': 'Arabic',
  'de': 'German',
  'deu': 'German',
  'en': 'English',
  'eng': 'English',
  'fr': 'French',
  'fra': 'French',
  'it': 'Italian',
  'ita': 'Italian',
  'ja': 'Japanese',
  'jpn': 'Japanese',
  'ru': 'Russian',
  'rus': 'Russian',
  'es': 'Spanish',
  'spa': 'Spanish',
  'tr': 'Turkish',
  'tur': 'Turkish',
  'arabic': 'Arabic',
  'almanca': 'German',
  'german': 'German',
  'ingilizce': 'English',
  'english': 'English',
  'fransizca': 'French',
  'french': 'French',
  'italyanca': 'Italian',
  'italian': 'Italian',
  'japonca': 'Japanese',
  'japanese': 'Japanese',
  'rusca': 'Russian',
  'russian': 'Russian',
  'ispanyolca': 'Spanish',
  'spanish': 'Spanish',
  'turkce': 'Turkish',
  'turkish': 'Turkish',
};

Map<String, dynamic>? _firstMap(Object? value) {
  if (value is! List || value.isEmpty) return null;
  return _map(value.first);
}
