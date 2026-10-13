import 'package:cloud_firestore/cloud_firestore.dart';

import 'book_facets.dart';
import 'book_metadata.dart';

const readStatus = 'Okundu';
const readingStatus = 'Okunuyor';
const toReadStatus = 'Okunacak';
const noStatusLabel = 'No status';
const defaultPersonalLibraryId = 'home';
const List<String?> bookStatuses = [
  toReadStatus,
  readingStatus,
  readStatus,
  null,
];

bool isCompletedStatus(Object? status) => status == readStatus;

bool isInHomeLibrary(Map<String, dynamic> book) =>
    isInLibrary(book, defaultPersonalLibraryId);

List<String> bookLibraryIds(Map<String, dynamic> book) {
  final value = book['libraryIds'];
  if (value is Iterable) {
    return value
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }
  return book['inHomeLibrary'] == false ? const [] : [defaultPersonalLibraryId];
}

bool isInLibrary(Map<String, dynamic> book, String libraryId) =>
    bookLibraryIds(book).contains(libraryId);

bool isInAnyLibrary(Map<String, dynamic> book) =>
    bookLibraryIds(book).isNotEmpty;

String? canonicalBookStatus(Object? status) => status == null
    ? null
    : status is String && bookStatuses.contains(status)
    ? status
    : toReadStatus;

String bookStatusLabel(String? status) => switch (status) {
  readStatus => 'Read',
  readingStatus => 'Currently reading',
  toReadStatus => 'To read',
  _ => noStatusLabel,
};

bool hasBorrower(Map<String, dynamic> book) {
  final borrower = book['borrower'];
  return borrower is String && borrower.trim().isNotEmpty;
}

int loanDays(Map<String, dynamic> book, [DateTime? now]) {
  final loanedAt = book['loanedAt'];
  if (loanedAt is! Timestamp) return 0;
  return (now ?? DateTime.now()).difference(loanedAt.toDate()).inDays;
}

int readingDays(Map<String, dynamic> book, [DateTime? now]) {
  final startedAt = _dateValue(
    book['readingStartedAt'] ?? book['updatedAt'] ?? book['createdAt'],
  );
  if (startedAt == null) return 1;
  final today = now ?? DateTime.now();
  final startDay = DateTime(startedAt.year, startedAt.month, startedAt.day);
  final currentDay = DateTime(today.year, today.month, today.day);
  return currentDay.difference(startDay).inDays.clamp(0, 365000) + 1;
}

List<Map<String, dynamic>> recentlyCompletedBooks(
  Iterable<Map<String, dynamic>> books, {
  int limit = 6,
}) {
  final completed = books
      .where(
        (book) => book['wishlist'] != true && isCompletedStatus(book['status']),
      )
      .toList();
  completed.sort(
    (first, second) =>
        (_dateValue(second['completedAt']) ??
                _dateValue(second['updatedAt']) ??
                DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(
              _dateValue(first['completedAt']) ??
                  _dateValue(first['updatedAt']) ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            ),
  );
  return completed.take(limit).toList(growable: false);
}

bool isOverdue(Map<String, dynamic> book, DateTime now) {
  final due = book['loanDue'];
  return hasBorrower(book) &&
      due is Timestamp &&
      due.toDate().isBefore(DateTime(now.year, now.month, now.day));
}

List<String> authorsFromBook(Map<String, dynamic> book) {
  final authors = book['authors'];
  if (authors is Iterable) {
    final names = normalizeBookItems(authors.whereType<String>());
    if (names.isNotEmpty) return names;
  }
  final author = book['author'];
  return author is String ? splitAuthorNames(author) : const [];
}

List<String> genresFromBook(Map<String, dynamic> book) {
  final subjects = book['subjects'];
  return subjects is Iterable
      ? normalizeGenres(subjects.whereType<String>())
      : const [];
}

int? pageCountOf(Map<String, dynamic> book) {
  final value = book['pageCount'];
  final pages = value is num ? value : num.tryParse('$value');
  return pages == null || pages <= 0 ? null : pages.toInt();
}

int? publishedYearOf(Map<String, dynamic> book) {
  for (final key in ['firstPublishDate', 'publishedDate']) {
    final year = RegExp(r'(?<!\d)(1[5-9]\d{2}|20\d{2}|21\d{2})(?!\d)')
        .firstMatch('${book[key]}')
        ?.group(0);
    final parsed = int.tryParse(year ?? '');
    if (parsed != null) return parsed;
  }
  return null;
}

enum BookMatchType { isbn, exactTitle, similarTitle }

class BookMatch {
  const BookMatch({required this.book, required this.type, this.score = 1});

  final Map<String, dynamic> book;
  final BookMatchType type;
  final double score;

  String get reason => switch (type) {
    BookMatchType.isbn => 'Same ISBN',
    BookMatchType.exactTitle => 'Same title',
    BookMatchType.similarTitle => 'Very similar title',
  };

  bool get blocksAdding =>
      type == BookMatchType.isbn || type == BookMatchType.exactTitle;
}

List<BookMatch> findBookMatches(
  Iterable<Map<String, dynamic>> books, {
  required String title,
  String? isbn,
}) {
  final incomingIsbns = _isbnValues(isbn);
  final normalizedTitle = normalizeBookSearchText(title);
  final matches = <BookMatch>[];
  for (final book in books) {
    final existingIsbns = {
      for (final key in ['isbn', 'isbn10', 'isbn13']) ..._isbnValues(book[key]),
    };
    if (incomingIsbns.isNotEmpty && incomingIsbns.any(existingIsbns.contains)) {
      matches.add(BookMatch(book: book, type: BookMatchType.isbn));
      continue;
    }

    final existingTitle = book['title'];
    if (existingTitle is! String || existingTitle.trim().isEmpty) continue;
    final normalizedExistingTitle = normalizeBookSearchText(existingTitle);
    if (normalizedTitle.isEmpty || normalizedExistingTitle.isEmpty) continue;
    if (normalizedTitle == normalizedExistingTitle) {
      matches.add(BookMatch(book: book, type: BookMatchType.exactTitle));
      continue;
    }
    final score = bookTitleSimilarity(normalizedTitle, normalizedExistingTitle);
    if (score >= 0.9) {
      matches.add(
        BookMatch(
          book: book,
          type: score == 1
              ? BookMatchType.exactTitle
              : BookMatchType.similarTitle,
          score: score,
        ),
      );
    }
  }
  matches.sort((a, b) {
    final typeOrder = a.type.index.compareTo(b.type.index);
    return typeOrder == 0 ? b.score.compareTo(a.score) : typeOrder;
  });
  return matches;
}

double bookTitleSimilarity(String first, String second) {
  final a = _normalizeSearchText(first);
  final b = _normalizeSearchText(second);
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  final shortest = a.length < b.length ? a.length : b.length;
  final longest = a.length > b.length ? a.length : b.length;
  if (shortest < 4) return 0;
  if (a.contains(b) || b.contains(a)) {
    return shortest / longest >= 0.5 ? 0.92 : 0;
  }

  final previous = List<int>.generate(b.length + 1, (index) => index);
  for (var row = 1; row <= a.length; row++) {
    var diagonal = previous[0];
    previous[0] = row;
    for (var column = 1; column <= b.length; column++) {
      final above = previous[column];
      previous[column] = a[row - 1] == b[column - 1]
          ? diagonal
          : 1 + [diagonal, above, previous[column - 1]].reduce(_min);
      diagonal = above;
    }
  }
  return 1 - previous[b.length] / longest;
}

int _min(int first, int second) => first < second ? first : second;

String _normalizeSearchText(String value) => normalizeBookKey(value);

String normalizeBookSearchText(String value) => _normalizeSearchText(value);

bool matchesBookSearchText(String query, String candidate) {
  final normalizedQuery = normalizeBookSearchText(query);
  final normalizedCandidate = normalizeBookSearchText(candidate);
  if (normalizedQuery.length < 2 || normalizedCandidate.isEmpty) return false;
  if (normalizedCandidate.contains(normalizedQuery)) return true;
  final queryWords = normalizedQuery.split(' ');
  final candidateWords = normalizedCandidate.split(' ');
  return queryWords.every(
    (queryWord) => candidateWords.any(
      (candidateWord) => candidateWord.startsWith(queryWord),
    ),
  );
}

Set<String> _isbnValues(Object? value) {
  final isbn = value is String ? normalizeIsbn(value) : null;
  if (isbn == null) return const {};
  final values = {isbn};
  if (isbn.length == 10) {
    final body = '978${isbn.substring(0, 9)}';
    var sum = 0;
    for (var i = 0; i < body.length; i++) {
      sum += int.parse(body[i]) * (i.isEven ? 1 : 3);
    }
    values.add('$body${(10 - sum % 10) % 10}');
  } else if (isbn.startsWith('978')) {
    final body = isbn.substring(3, 12);
    var sum = 0;
    for (var i = 0; i < body.length; i++) {
      sum += int.parse(body[i]) * (10 - i);
    }
    final check = (11 - sum % 11) % 11;
    values.add('$body${check == 10 ? 'X' : check}');
  }
  return values;
}

String? bookIdentity(Map<String, dynamic> book) {
  final workId = book['workId'];
  if (workId != null && '$workId'.trim().isNotEmpty) {
    return 'work:${_normalizeBookValue(workId)}';
  }
  final title = book['title'];
  final authors = authorsFromBook(book).map(_normalizeBookValue).toList()
    ..sort();
  if (title is! String || title.trim().isEmpty || authors.isEmpty) return null;
  return 'title:${_normalizeBookValue(title)}|authors:${authors.join('|')}';
}

bool sameBook(Map<String, dynamic> first, Map<String, dynamic> second) {
  final isbns = {
    for (final key in ['isbn', 'isbn10', 'isbn13']) ..._isbnValues(first[key]),
  };
  if ([
    for (final key in ['isbn', 'isbn10', 'isbn13']) ..._isbnValues(second[key]),
  ].any(isbns.contains)) {
    return true;
  }
  if (first['workId'] != null &&
      second['workId'] != null &&
      first['workId'] == second['workId']) {
    return true;
  }
  final firstTitle = normalizeBookSearchText('${first['title'] ?? ''}');
  final secondTitle = normalizeBookSearchText('${second['title'] ?? ''}');
  final authors = authorsFromBook(first).map(normalizeBookSearchText).toSet();
  return firstTitle.isNotEmpty &&
      firstTitle == secondTitle &&
      authorsFromBook(second)
          .map(normalizeBookSearchText)
          .any(authors.contains);
}

Map<String, Set<String>> publishersByBook(
  Iterable<Map<String, dynamic>> books,
) {
  final publishers = <String, Set<String>>{};
  for (final book in books) {
    final identity = bookIdentity(book);
    final publisher = book['publisher'];
    if (identity == null || publisher is! String || publisher.trim().isEmpty) {
      continue;
    }
    publishers
        .putIfAbsent(identity, () => <String>{})
        .add(_normalizeBookValue(publisher));
  }
  return publishers;
}

String _normalizeBookValue(Object value) => normalizeBookKey(value.toString());

class AuthorStats {
  AuthorStats(this.name);

  final String name;
  int books = 0;
  int completed = 0;
  int booksWithPageCount = 0;
  int totalPages = 0;

  double get completionRate => books == 0 ? 0 : completed / books;
  double get averagePageCount =>
      booksWithPageCount == 0 ? 0 : totalPages / booksWithPageCount;
}

class LibraryStats {
  LibraryStats(Iterable<Map<String, dynamic>> books, DateTime now) {
    for (final book in books) {
      if (book['wishlist'] == true) {
        wishlist++;
        continue;
      }
      total++;
      final status = book['status'];
      if (status == readingStatus) reading++;
      if (isCompletedStatus(status)) completed++;
      if (hasBorrower(book)) lent++;
      if (isOverdue(book, now)) overdue++;
      final pageCount = pageCountOf(book);
      if (pageCount != null) {
        booksWithPageCount++;
        totalPages += pageCount;
      }
      for (final genre in genresFromBook(book)) {
        byGenre.update(genre, (value) => value + 1, ifAbsent: () => 1);
      }
      final publishedYear = publishedYearOf(book);
      if (publishedYear != null) {
        byYear.update(publishedYear, (value) => value + 1, ifAbsent: () => 1);
      }
      for (final author in authorsFromBook(book)) {
        final key = normalizeBookKey(author);
        final authorStats = byAuthor.putIfAbsent(
          key,
          () => AuthorStats(author),
        );
        authorStats.books++;
        if (isCompletedStatus(status)) authorStats.completed++;
        if (pageCount != null) {
          authorStats.booksWithPageCount++;
          authorStats.totalPages += pageCount;
        }
      }
      final finished = book['completedAt'];
      if (isCompletedStatus(status) &&
          finished is Timestamp &&
          finished.toDate().year == now.year &&
          finished.toDate().month == now.month) {
        completedThisMonth++;
      }
    }
  }
  int total = 0, reading = 0, completed = 0, wishlist = 0;
  int lent = 0, overdue = 0, completedThisMonth = 0;
  int totalPages = 0, booksWithPageCount = 0;
  final Map<String, AuthorStats> byAuthor = {};
  final Map<String, int> byGenre = {};
  final Map<int, int> byYear = {};
  double get completionRate => total == 0 ? 0 : completed / total;
}

enum LibraryTimelineEventType { added, completed }

class LibraryTimelineEvent {
  const LibraryTimelineEvent({
    required this.book,
    required this.date,
    required this.type,
  });

  final Map<String, dynamic> book;
  final DateTime date;
  final LibraryTimelineEventType type;
}

List<LibraryTimelineEvent> timelineEventsFromBooks(
  Iterable<Map<String, dynamic>> books,
) {
  final events = <LibraryTimelineEvent>[];
  for (final book in books) {
    if (book['wishlist'] == true) continue;
    final addedAt = _timelineDate(book['createdAt']);
    if (addedAt != null) {
      events.add(
        LibraryTimelineEvent(
          book: book,
          date: addedAt,
          type: LibraryTimelineEventType.added,
        ),
      );
    }
    final completedAt = _timelineDate(book['completedAt']);
    if (isCompletedStatus(book['status']) && completedAt != null) {
      events.add(
        LibraryTimelineEvent(
          book: book,
          date: completedAt,
          type: LibraryTimelineEventType.completed,
        ),
      );
    }
  }
  events.sort((a, b) => b.date.compareTo(a.date));
  return events;
}

DateTime? _dateValue(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  _ => null,
};

DateTime? _timelineDate(Object? value) => _dateValue(value);
