import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:booklibrary/data/book_facets.dart';
import 'package:booklibrary/data/book_metadata.dart';

void main() {
  test('ISBN normalization accepts valid ISBNs and rejects invalid ones', () {
    expect(normalizeIsbn('978-0-14-032872-1'), '9780140328721');
    expect(normalizeIsbn('0-14-032872-6'), '0140328726');
    expect(normalizeIsbn('9780140328720'), isNull);
    expect(normalizeIsbn('not-an-isbn'), isNull);
  });

  test('author names are kept as separate searchable values', () {
    expect(splitAuthorNames('  Roald Dahl, Quentin Blake; Roald Dahl '), [
      'Roald Dahl',
      'Quentin Blake',
    ]);
  });

  test('book text normalization repairs Unicode and groups name variants', () {
    expect(
      normalizeBookText('I\u0307letis\u0327im   Yayınları'),
      'İletişim Yayınları',
    );
    expect(
      normalizeBookItems(['Can Yayinlari', 'can yayınları', ' CAN YAYINLARI ']),
      ['Can Yayinlari'],
    );
    expect(normalizeBookKey('Tarık Tufan'), normalizeBookKey('TARIK TUFAN'));
  });

  test('ISBN API maps and nested fields are retained for Firestore', () {
    final metadata = BookMetadata.fromOpenLibrary(
      '9780140328721',
      {
        'title': 'Fantastic Mr. Fox',
        'authors': [
          {'name': 'Roald Dahl'},
        ],
        'identifiers': {
          'isbn_10': ['0140328726'],
          'goodreads': ['1507552'],
        },
        'number_of_pages': 96,
        'cover': {'large': 'https://example.com/cover.jpg'},
        'subjects': [
          {'name': 'Fiction'},
        ],
        'ebooks': [
          {'availability': 'restricted'},
        ],
      },
      {
        'key': '/works/OL123W',
        'description': 'A fox story.',
        'genres': ['Children'],
      },
      edition: {'physical_format': 'Hardcover'},
      apiData: {
        'identifiers': {
          'goodreads': ['1507552'],
        },
      },
      apiWorkData: {
        'genres': ['Children'],
      },
    );

    expect(metadata.isbn10, '0140328726');
    expect(metadata.coverUrl, 'https://example.com/cover.jpg');
    expect(metadata.subjects, isEmpty);
    expect(metadata.tags, containsAll(<String>['Fiction', 'Children']));
    expect(metadata.toFirestoreFields()['isbnApiData'], isNotEmpty);
    expect(metadata.toFirestoreFields()['isbnApiEditionData'], isNotEmpty);
    expect(metadata.toFirestoreFields()['isbnApiWorkData'], isNotEmpty);
  });

  test('genre and language labels are normalized for the library form', () {
    expect(normalizeGenres(['Fiction', 'Poetry', 'Biography']), [
      'Fiction',
      'Poetry',
      'Biography',
    ]);
    expect(normalizeLanguages(['English, Türkçe']), ['English', 'Turkish']);
  });

  test('publisher logo URL is normalized and persisted when provided', () {
    final metadata = BookMetadata.fromGoogleBooks('9780140328721', {
      'volumeInfo': {
        'title': 'Fantastic Mr. Fox',
        'publisher': 'Penguin',
        'publisher_logo_url': 'http://example.com/penguin.png',
      },
    });

    expect(metadata.publisherLogoUrl, 'https://example.com/penguin.png');
    expect(
      metadata.toFirestoreFields()['publisherLogoUrl'],
      'https://example.com/penguin.png',
    );
  });

  test('Hardcover lookup maps the server response', () async {
    final lookup = BookMetadataLookup(
      client: MockClient((_) async => http.Response('{}', 404)),
      hardcoverLookup: (isbn) async {
        expect(isbn, '9780140328721');
        return {
          'id': 42,
          'title': 'Fantastic Mr. Fox',
          'subtitle': null,
          'isbn_10': '0140328726',
          'isbn_13': '9780140328721',
          'pages': 96,
          'release_date': '1990-01-01',
          'language': {'language': 'English'},
          'image': {'url': 'https://example.com/cover.jpg'},
          'publisher': {'name': 'Puffin'},
          'book': {
            'id': 123,
            'title': 'Fantastic Mr. Fox',
            'description': 'A fox story.',
            'contributions': [
              {
                'author': {'name': 'Roald Dahl'},
              },
            ],
          },
        };
      },
    );
    final result = await lookup.find('9780140328721');
    lookup.dispose();

    expect(result.primary!.metadataSource, 'Hardcover');
    expect(result.primary!.author, 'Roald Dahl');
    expect(result.primary!.publisher, 'Puffin');
    expect(result.primary!.editionId, '42');
  });

  test(
    'Open Library is primary and searches by title and author on ISBN miss',
    () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add(request.url.toString());
        if (request.url.host == 'api2.isbndb.com' ||
            request.url.path == '/isbn/9780140328721.json') {
          return http.Response('{}', 404);
        }
        if (request.url.path == '/search.json') {
          return http.Response(
            jsonEncode({
              'docs': [
                {
                  'title': 'Fantastic Mr. Fox',
                  'author_name': ['Roald Dahl'],
                  'isbn13': ['9780140328721'],
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      final lookup = BookMetadataLookup(client: client, isbnDbKey: 'trial-key');
      final result = await lookup.find(
        '9780140328721',
        title: 'Fantastic Mr. Fox',
        author: 'Roald Dahl',
      );
      lookup.dispose();

      expect(result.primary!.metadataSource, 'Open Library Search');
      expect(result.primary!.author, 'Roald Dahl');
      expect(requests, hasLength(2));
      expect(requests[0], startsWith('https://openlibrary.org/isbn/'));
      expect(requests[1], startsWith('https://openlibrary.org/search.json'));
      expect(
        Uri.parse(requests[1]).queryParameters['title'],
        'Fantastic Mr. Fox',
      );
      expect(Uri.parse(requests[1]).queryParameters['author'], 'Roald Dahl');
    },
  );

  test('title and author search works without an ISBN', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/search.json');
      return http.Response(
        jsonEncode({
          'docs': [
            {
              'title': 'Fantastic Mr. Fox',
              'author_name': ['Roald Dahl'],
              'isbn13': ['9780140328721'],
            },
          ],
        }),
        200,
      );
    });

    final lookup = BookMetadataLookup(client: client);
    final result = await lookup.findByTitleAuthor(
      title: 'Fantastic Mr. Fox',
      author: 'Roald Dahl',
    );
    lookup.dispose();

    expect(result.primary!.title, 'Fantastic Mr. Fox');
    expect(result.primary!.author, 'Roald Dahl');
    expect(result.primary!.isbn, '9780140328721');
  });

  test(
    'comparison returns provider data and explains unavailable providers',
    () async {
      final client = MockClient((request) async {
        if (request.url.host == 'api2.isbndb.com') {
          return http.Response('{}', 503);
        }
        if (request.url.path == '/isbn/9780140328721.json') {
          return http.Response('{}', 404);
        }
        if (request.url.path == '/search.json') {
          return http.Response(
            jsonEncode({
              'docs': [
                {
                  'title': 'Fantastic Mr. Fox',
                  'author_name': ['Roald Dahl'],
                  'isbn13': ['9780140328721'],
                },
              ],
            }),
            200,
          );
        }
        if (request.url.host == 'www.googleapis.com') {
          return http.Response(jsonEncode({'items': []}), 200);
        }
        return http.Response('{}', 404);
      });

      final lookup = BookMetadataLookup(client: client, isbnDbKey: 'trial-key');
      final result = await lookup.compare('9780140328721');
      lookup.dispose();

      expect(
        result.candidates,
        contains(BookMetadataProvider.openLibrarySearch),
      );
      expect(result.errors[BookMetadataProvider.isbnDb], contains('503'));
      expect(
        result.errors[BookMetadataProvider.openLibraryIsbn],
        'No record was found for this ISBN.',
      );
      expect(
        result.errors[BookMetadataProvider.googleBooks],
        'No record was found for this ISBN.',
      );
    },
  );

  test('Google Books lookup sends the ISBN and maps the volume', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.host == 'www.googleapis.com') {
        return http.Response(
          jsonEncode({
            'items': [
              {
                'selfLink': 'https://www.googleapis.com/books/v1/volumes/id',
                'volumeInfo': {
                  'title': 'Fantastic Mr. Fox',
                  'authors': ['Roald Dahl'],
                  'publisher': 'Puffin',
                  'industryIdentifiers': [
                    {'type': 'ISBN_13', 'identifier': '9780140328721'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final lookup = BookMetadataLookup(
      client: client,
      googleBooksKey: 'test-google-key',
    );
    final result = await lookup.find('9780140328721');
    lookup.dispose();

    expect(result.primary!.metadataSource, 'Google Books');
    expect(result.primary!.title, 'Fantastic Mr. Fox');
    expect(result.primary!.author, 'Roald Dahl');
    final request = requests.singleWhere(
      (uri) => uri.host == 'www.googleapis.com',
    );
    expect(request.queryParameters['q'], 'isbn:9780140328721');
    expect(request.queryParameters['key'], 'test-google-key');
  });
}
