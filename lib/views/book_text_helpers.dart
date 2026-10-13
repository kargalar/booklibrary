part of 'library_page.dart';

String? _bookText(Map<String, dynamic> book, String key) {
  final value = book[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}
