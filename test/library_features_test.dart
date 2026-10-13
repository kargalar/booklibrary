import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:epubx_kuebiko/epubx_kuebiko.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:booklibrary/data/book_files.dart';
import 'package:booklibrary/data/library_stats.dart';
import 'package:booklibrary/data/local_book_store.dart';

void main() {
  test('local book changes round-trip through JSON', () {
    const change = LocalBookChange(
      id: 'book-1',
      isNew: true,
      data: {'title': 'Yerel kitap', 'inHomeLibrary': true},
      error: 'Bulut kapalı',
    );

    expect(LocalBookChange.fromJson(change.toJson()).toJson(), change.toJson());
  });

  test(
    'statistics exclude wishlist and detect overdue loans by calendar day',
    () {
      final now = DateTime(2026, 9, 10, 15);
      final stats = LibraryStats([
        {
          'status': 'Okundu',
          'completedAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
        },
        {
          'status': 'Okunuyor',
          'borrower': 'Ada',
          'loanDue': Timestamp.fromDate(DateTime(2026, 9, 9)),
        },
        {
          'status': 'Okunacak',
          'borrower': 'Ece',
          'loanDue': Timestamp.fromDate(DateTime(2026, 9, 10)),
        },
        {'wishlist': true, 'status': 'Okundu'},
        {
          'status': 'Okunacak',
          'borrower': null,
          'loanDue': Timestamp.fromDate(DateTime(2026, 9, 1)),
        },
      ], now);
      expect(stats.total, 4);
      expect(stats.wishlist, 1);
      expect(stats.completed, 1);
      expect(stats.completedThisMonth, 1);
      expect(stats.reading, 1);
      expect(stats.lent, 2);
      expect(stats.overdue, 1);
      expect(stats.completionRate, .25);
      expect(LibraryStats([], now).completionRate, 0);
    },
  );

  test('Okundu status counts as completed', () {
    final stats = LibraryStats([
      {'status': 'Okundu'},
    ], DateTime(2026, 9, 10));

    expect(stats.completed, 1);
    expect(stats.completionRate, 1);
  });

  test('null is a selectable status and is not treated as Okunacak', () {
    expect(bookStatuses, [toReadStatus, readingStatus, readStatus, null]);
    expect(canonicalBookStatus(null), isNull);
    expect(canonicalBookStatus('unknown'), toReadStatus);
  });

  test('books without an ownership flag remain in the home library', () {
    expect(isInHomeLibrary({}), isTrue);
    expect(isInHomeLibrary({'inHomeLibrary': true}), isTrue);
    expect(isInHomeLibrary({'inHomeLibrary': false}), isFalse);
  });

  test('books can belong to multiple personal libraries or Other', () {
    final book = {
      'libraryIds': ['home', 'office'],
    };
    expect(bookLibraryIds(book), ['home', 'office']);
    expect(isInLibrary(book, 'office'), isTrue);
    expect(isInAnyLibrary(book), isTrue);
    expect(isInAnyLibrary({'libraryIds': []}), isFalse);
  });

  test(
    'timeline includes added and completed events in reverse chronology',
    () {
      final events = timelineEventsFromBooks([
        {
          'title': 'Added',
          'createdAt': Timestamp.fromDate(DateTime(2026, 9, 12)),
        },
        {
          'title': 'Finished',
          'status': readStatus,
          'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
          'completedAt': Timestamp.fromDate(DateTime(2026, 9, 4)),
        },
        {
          'title': 'Wishlist',
          'wishlist': true,
          'createdAt': Timestamp.fromDate(DateTime(2026, 9, 13)),
        },
      ]);

      expect(events.length, 3);
      expect(events[0].book['title'], 'Added');
      expect(events[0].type, LibraryTimelineEventType.added);
      expect(events[1].book['title'], 'Finished');
      expect(events[1].type, LibraryTimelineEventType.completed);
      expect(events[2].date, DateTime(2026, 8, 1));
    },
  );

  test('empty borrower names are not treated as active loans', () {
    final book = {
      'borrower': '  ',
      'loanDue': Timestamp.fromDate(DateTime(2026, 9, 1)),
    };
    expect(isOverdue(book, DateTime(2026, 9, 10)), isFalse);
    expect(LibraryStats([book], DateTime(2026, 9, 10)).lent, 0);
  });

  test('loan days are calculated from the loan start date', () {
    expect(
      loanDays({
        'loanedAt': Timestamp.fromDate(DateTime(2026, 9, 7)),
      }, DateTime(2026, 9, 10, 15)),
      3,
    );
  });

  test('reading days are inclusive calendar days', () {
    expect(
      readingDays({
        'readingStartedAt': Timestamp.fromDate(DateTime(2026, 9, 7, 23)),
      }, DateTime(2026, 9, 10, 1)),
      4,
    );
  });

  test('recently completed books are ordered and limited', () {
    final books = recentlyCompletedBooks([
      {
        'title': 'Eski',
        'status': readStatus,
        'completedAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
      },
      {
        'title': 'Yeni',
        'status': readStatus,
        'completedAt': Timestamp.fromDate(DateTime(2026, 9, 10)),
      },
      {'title': 'Devam', 'status': readingStatus},
    ], limit: 1);

    expect(books.map((book) => book['title']), ['Yeni']);
  });

  test('author statistics calculate average pages per author', () {
    final stats = LibraryStats([
      {
        'author': 'Ada Lovelace',
        'pageCount': '100',
        'subjects': ['Bilim Kurgu'],
        'publishedDate': '1999-04-01',
      },
      {
        'authors': ['Ada Lovelace'],
        'pageCount': 200,
        'subjects': ['Bilim Kurgu', 'Roman'],
        'firstPublishDate': '2001',
        'status': 'Okundu',
      },
      {'author': 'Grace Hopper', 'pageCount': 80, 'wishlist': true},
    ], DateTime(2026, 9, 10));

    expect(stats.byAuthor['ada lovelace']!.books, 2);
    expect(stats.byAuthor['ada lovelace']!.averagePageCount, 150);
    expect(stats.byAuthor['ada lovelace']!.totalPages, 300);
    expect(stats.byAuthor['ada lovelace']!.completed, 1);
    expect(stats.totalPages, 300);
    expect(stats.byGenre, {'Science fiction': 2, 'Fiction': 1});
    expect(stats.byYear, {1999: 1, 2001: 1});
    expect(stats.byAuthor.containsKey('grace hopper'), isFalse);
  });

  test('publisher count groups the same work and ignores duplicate names', () {
    final books = [
      {
        'workId': 'OL123W',
        'title': 'Fantastic Mr. Fox',
        'author': 'Roald Dahl',
        'publisher': 'Penguin',
      },
      {
        'workId': 'OL123W',
        'title': 'Fantastic Mr. Fox',
        'author': 'Roald Dahl',
        'publisher': 'Puffin',
      },
      {
        'workId': 'OL123W',
        'title': 'Fantastic Mr. Fox',
        'author': 'Roald Dahl',
        'publisher': 'penguin',
      },
    ];

    final identity = bookIdentity(books.first)!;
    expect(publishersByBook(books)[identity], {'penguin', 'puffin'});
  });

  test('book matching catches equivalent ISBNs and similar titles', () {
    final matches = findBookMatches(
      [
        {
          'title': 'Harry Potter ve Felsefe Taşı',
          'isbn10': '0439554934',
          'author': 'J. K. Rowling',
        },
      ],
      title: 'Harry Potter ve Felsefe Tasi',
      isbn: '9780439554930',
    );

    expect(matches, hasLength(1));
    expect(matches.single.type, BookMatchType.isbn);
    expect(matches.single.blocksAdding, isTrue);
  });

  test('book title similarity tolerates Turkish characters and typos', () {
    expect(bookTitleSimilarity('Küçük Prens', 'Kucuk Prens'), 1);
    expect(
      bookTitleSimilarity('Sefiller', 'Sefiller 1'),
      greaterThanOrEqualTo(.82),
    );
  });

  test('short or weak title fragments do not trigger duplicate warnings', () {
    final books = [
      {'title': 'The Great Gatsby'},
    ];

    expect(findBookMatches(books, title: 'a'), isEmpty);
    expect(
      findBookMatches(books, title: 'Great Gatsby').single.type,
      BookMatchType.similarTitle,
    );
  });

  test('autocomplete matching prefers real word matches', () {
    expect(matchesBookSearchText('roa da', 'Roald Dahl'), isTrue);
    expect(matchesBookSearchText('gatsby', 'The Great Gatsby'), isTrue);
    expect(matchesBookSearchText('xyz', 'The Great Gatsby'), isFalse);
  });

  test('EPUB follows spine rather than manifest or navigation order', () {
    final first = EpubTextContentFile()..Content = '<p>First</p>';
    final second = EpubTextContentFile()..Content = '<p>Second</p>';
    final extra = EpubTextContentFile()..Content = '<p>Appendix</p>';
    final book = EpubBook()
      ..Content = (EpubContent()
        ..Html = {
          'second.xhtml': second,
          'first.xhtml': first,
          'extra.xhtml': extra,
        })
      ..Schema = (EpubSchema()
        ..Package = (EpubPackage()
          ..Manifest = (EpubManifest()
            ..Items = [
              EpubManifestItem()
                ..Id = 'b'
                ..Href = 'second.xhtml',
              EpubManifestItem()
                ..Id = 'a'
                ..Href = 'first.xhtml',
              EpubManifestItem()
                ..Id = 'c'
                ..Href = 'extra.xhtml',
            ])
          ..Spine = (EpubSpine()
            ..Items = [
              EpubSpineItemRef()..IdRef = 'a',
              EpubSpineItemRef()..IdRef = 'b',
              EpubSpineItemRef()
                ..IdRef = 'c'
                ..IsLinear = false,
            ])));
    expect(readingOrder(book), orderedEquals([first, second]));
    expect(() => readingOrder(EpubBook()), throwsFormatException);
  });
}
