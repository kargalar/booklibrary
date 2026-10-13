import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import 'book_facets.dart';

part 'book_metadata_lookup.dart';
part 'book_metadata_parsing.dart';

String? normalizeIsbn(String value) {
  final isbn = value.toUpperCase().replaceAll(RegExp(r'[^0-9X]'), '');
  if (isbn.length != 10 && isbn.length != 13) return null;
  if (!_validIsbn(isbn)) return null;
  return isbn;
}

List<String> splitAuthorNames(String value) =>
    normalizeBookItems(value.split(RegExp(r'[,;]')));

String? _optionalBookText(Object? value) =>
    value is String ? normalizeBookText(value) : null;

Map<String, dynamic> normalizeBookFields(Map<String, dynamic> fields) {
  final normalized = Map<String, dynamic>.from(fields);
  for (final key in [
    'title',
    'author',
    'subtitle',
    'description',
    'publisher',
    'publishedDate',
    'firstPublishDate',
    'languageCode',
    'origin',
    'coverUrl',
    'editionId',
    'workId',
    'previewUrl',
    'sourceUrl',
    'publisherLogoUrl',
    'metadataSource',
    'titleSearch',
  ]) {
    if (normalized[key] is String) {
      normalized[key] = normalizeBookText(normalized[key] as String);
    }
  }
  if (normalized['titleSearch'] is String) {
    normalized['titleSearch'] = normalizeBookKey(
      normalized['titleSearch'] as String,
    );
  }
  if (normalized['isbn'] is String) {
    normalized['isbn'] = normalizeBookText(normalized['isbn'] as String);
  }
  for (final key in [
    'authors',
    'tags',
    'subjectPlaces',
    'subjectPeople',
    'subjectTimes',
    'contributions',
  ]) {
    final value = normalized[key];
    if (value is Iterable) {
      normalized[key] = normalizeBookItems(value.whereType<String>());
    }
  }
  final subjects = normalized['subjects'];
  if (subjects is Iterable) {
    normalized['subjects'] = normalizeGenres(subjects.whereType<String>());
  }
  final author = normalized['author'];
  if (author is String) {
    normalized['authors'] = splitAuthorNames(author);
  }
  return normalized;
}

const _genreAliases = <String, String>{
  'autobiograph': 'Autobiography',
  'otobiyografi': 'Autobiography',
  'memoir': 'Autobiography',
  'biograph': 'Biography',
  'biyografi': 'Biography',
  'science fiction': 'Science fiction',
  'sci fi': 'Science fiction',
  'bilim kurgu': 'Science fiction',
  'fiction': 'Fiction',
  'novel': 'Fiction',
  'roman': 'Fiction',
  'essay': 'Essay',
  'deneme': 'Essay',
  'poetry': 'Poetry',
  'poem': 'Poetry',
  'verse': 'Poetry',
  'siir': 'Poetry',
  'philosoph': 'Philosophy',
  'felsefe': 'Philosophy',
  'short stor': 'Story',
  'story': 'Story',
  'oyku': 'Story',
  'hikaye': 'Story',
  'drama': 'Drama',
  'theater': 'Drama',
  'theatre': 'Drama',
  'tiyatro': 'Drama',
  'mystery': 'Mystery',
  'detective': 'Mystery',
  'crime': 'Mystery',
  'polisiye': 'Mystery',
  'fantasy': 'Fantasy',
  'fantastik': 'Fantasy',
  'history': 'History',
  'tarih': 'History',
  'psycholog': 'Psychology',
  'psikoloji': 'Psychology',
  'children': 'Children',
  'childrens': 'Children',
  'cocuk': 'Children',
};

List<String> normalizeGenres(Iterable<String> values) {
  final genres = <String, String>{};
  for (final value in values) {
    final trimmed = normalizeBookText(value);
    if (trimmed.isEmpty) continue;
    final key = _normalizedLabel(trimmed);
    final canonical = _genreAliases.entries
        .firstWhere(
          (alias) => key == alias.key || key.contains(alias.key),
          orElse: () => const MapEntry('', ''),
        )
        .value;
    final label = canonical.isEmpty ? trimmed : canonical;
    genres.putIfAbsent(normalizeBookKey(label), () => label);
  }
  return genres.values.toList();
}

List<String> normalizeLanguages(Iterable<String> values) => values
    .expand((value) => value.split(RegExp(r'[,;/\n]')))
    .map(normalizeLanguage)
    .where((value) => value.isNotEmpty)
    .toSet()
    .toList();

String normalizeLanguage(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? '' : _languageName(trimmed) ?? trimmed;
}

String? normalizeOptionalLanguage(String? value) =>
    value == null ? null : normalizeLanguage(value);

String _normalizedLabel(String value) => normalizeBookKey(value);

bool _validIsbn(String isbn) {
  if (isbn.length == 10) {
    var sum = 0;
    for (var i = 0; i < isbn.length; i++) {
      final value = isbn[i] == 'X' ? 10 : int.tryParse(isbn[i]);
      if (value == null) return false;
      sum += value * (10 - i);
    }
    return sum % 11 == 0;
  }

  var sum = 0;
  for (var i = 0; i < isbn.length; i++) {
    final value = int.tryParse(isbn[i]);
    if (value == null) return false;
    sum += value * (i.isEven ? 1 : 3);
  }
  return sum % 10 == 0;
}

class BookMetadata {
  const BookMetadata({
    required this.isbn,
    required this.title,
    required this.author,
    this.subtitle,
    this.authors = const [],
    this.description,
    this.pageCount,
    this.subjects = const [],
    this.tags = const [],
    this.subjectPlaces = const [],
    this.subjectPeople = const [],
    this.subjectTimes = const [],
    this.contributions = const [],
    this.publisher,
    this.publishedDate,
    this.firstPublishDate,
    this.language,
    this.languageCode,
    this.origin,
    this.coverUrl,
    this.isbn10,
    this.isbn13,
    this.editionId,
    this.workId,
    this.previewUrl,
    this.sourceUrl,
    this.publisherLogoUrl,
    this.metadataSource,
    this.apiData = const {},
    this.apiEditionData = const {},
    this.apiWorkData = const {},
    this.providerData = const {},
  });

  final String isbn;
  final String title;
  final String author;
  final String? subtitle;
  final List<String> authors;
  final String? description;
  final int? pageCount;
  final List<String> subjects;
  final List<String> tags;
  final List<String> subjectPlaces;
  final List<String> subjectPeople;
  final List<String> subjectTimes;
  final List<String> contributions;
  final String? publisher;
  final String? publishedDate;
  final String? firstPublishDate;
  final String? language;
  final String? languageCode;
  final String? origin;
  final String? coverUrl;
  final String? isbn10;
  final String? isbn13;
  final String? editionId;
  final String? workId;
  final String? previewUrl;
  final String? sourceUrl;
  final String? publisherLogoUrl;
  final String? metadataSource;
  // ponytail: raw maps keep new provider fields without another schema; the
  // Firestore document size limit is the ceiling.
  final Map<String, dynamic> apiData;
  final Map<String, dynamic> apiEditionData;
  final Map<String, dynamic> apiWorkData;
  final Map<String, dynamic> providerData;

  factory BookMetadata.fromFirestore(Map<String, dynamic> data) {
    final author = normalizeBookText(_string(data['author']) ?? '');
    final authors = normalizeBookItems(_strings(data['authors']));
    return BookMetadata(
      isbn: _string(data['isbn']) ?? '',
      title: normalizeBookText(_string(data['title']) ?? 'Untitled book'),
      author: author,
      subtitle: _optionalBookText(data['subtitle']),
      authors: authors.isEmpty ? splitAuthorNames(author) : authors,
      description: _optionalBookText(data['description']),
      pageCount: _int(data['pageCount']),
      subjects: normalizeGenres(_strings(data['subjects'])),
      tags: bookFacetItems(data, 'tags'),
      subjectPlaces: normalizeBookItems(_strings(data['subjectPlaces'])),
      subjectPeople: normalizeBookItems(_strings(data['subjectPeople'])),
      subjectTimes: normalizeBookItems(_strings(data['subjectTimes'])),
      contributions: normalizeBookItems(_strings(data['contributions'])),
      publisher: _optionalBookText(data['publisher']),
      publishedDate: _optionalBookText(data['publishedDate']),
      firstPublishDate: _optionalBookText(data['firstPublishDate']),
      language: normalizeOptionalLanguage(_string(data['language'])),
      languageCode: _optionalBookText(data['languageCode']),
      origin: _optionalBookText(data['origin']),
      coverUrl: _string(data['coverUrl']),
      isbn10: _string(data['isbn10']),
      isbn13: _string(data['isbn13']),
      editionId: _string(data['editionId']),
      workId: _string(data['workId']),
      previewUrl: _string(data['previewUrl']),
      sourceUrl: _string(data['sourceUrl']),
      publisherLogoUrl: _url(data['publisherLogoUrl']),
      metadataSource: _string(data['metadataSource']),
      apiData: _map(data['isbnApiData']) ?? const {},
      apiEditionData: _map(data['isbnApiEditionData']) ?? const {},
      apiWorkData: _map(data['isbnApiWorkData']) ?? const {},
      providerData: _map(data['metadataProviders']) ?? const {},
    );
  }

  factory BookMetadata.fromOpenLibrary(
    String isbn,
    Map<String, dynamic> details,
    Map<String, dynamic>? work, {
    String? previewUrl,
    String? sourceUrl,
    Map<String, dynamic> edition = const {},
    Map<String, dynamic> apiData = const {},
    Map<String, dynamic> apiWorkData = const {},
    String metadataSource = 'Open Library',
    Map<String, dynamic> providerData = const {},
  }) {
    final authors = _names(details['authors']);
    final languages = _languages(details['languages'] ?? edition['languages']);
    final languageCode = languages.isEmpty ? null : languages.first.$1;
    final language = languages.isEmpty
        ? null
        : languages.map((value) => value.$2).join(', ');
    final tags = normalizeBookItems([
      ..._strings(details['subjects']),
      ..._strings(work?['subjects']),
      ..._strings(work?['genres']),
    ]);
    final identifiers =
        _map(details['identifiers']) ?? _map(edition['identifiers']);
    final cover = _map(details['cover']) ?? _map(edition['cover']);
    final editionCovers = [
      ..._ints(details['covers']),
      ..._ints(edition['covers']),
    ];
    final workCovers = _ints(work?['covers']);
    final coverId = [
      ...editionCovers,
      ...workCovers,
    ].firstWhere((value) => value > 0, orElse: () => 0);
    final isbn10 =
        _firstString(details['isbn_10']) ??
        _firstString(identifiers?['isbn_10']) ??
        (isbn.length == 10 ? isbn : null);
    final isbn13 =
        _firstString(details['isbn_13']) ??
        _firstString(identifiers?['isbn_13']) ??
        (isbn.length == 13 ? isbn : null);
    final description =
        _text(
          work?['description'] ??
              details['description'] ??
              edition['description'],
        ) ??
        _text(details['first_sentence']);
    final title = _text(details['title']) ?? 'Untitled book';
    final origin = languageCode == null
        ? null
        : languages.any((value) => value.$1 == 'tur')
        ? 'Yerli'
        : 'Unknown';

    return BookMetadata(
      isbn: isbn,
      title: title,
      author: authors.join(', '),
      subtitle: _text(details['subtitle']),
      authors: authors,
      description: description,
      pageCount: _int(details['number_of_pages']),
      tags: tags,
      subjectPlaces: _strings(
        details['subject_places'] ?? work?['subject_places'],
      ),
      subjectPeople: _strings(
        details['subject_people'] ?? work?['subject_people'],
      ),
      subjectTimes: _strings(
        details['subject_times'] ?? work?['subject_times'],
      ),
      contributions: _strings(details['contributions']),
      publisher: _firstString(details['publishers']),
      publishedDate: _text(details['publish_date']),
      firstPublishDate: _text(work?['first_publish_date']),
      language: language,
      languageCode: languageCode,
      origin: origin,
      coverUrl:
          _string(cover?['large']) ??
          (coverId == 0
              ? null
              : 'https://covers.openlibrary.org/b/id/$coverId-L.jpg?default=false'),
      isbn10: isbn10,
      isbn13: isbn13,
      editionId: _lastPathPart(details['key']),
      workId: _lastPathPart(work?['key']),
      previewUrl: previewUrl,
      sourceUrl: sourceUrl,
      publisherLogoUrl:
          _publisherLogoUrl(details) ??
          _publisherLogoUrl(edition) ??
          _publisherLogoUrl(work),
      metadataSource: metadataSource,
      apiData: Map<String, dynamic>.from(apiData),
      apiEditionData: Map<String, dynamic>.from(edition),
      apiWorkData: Map<String, dynamic>.from(apiWorkData),
      providerData: Map<String, dynamic>.from(providerData),
    );
  }

  factory BookMetadata.fromIsbnDb(
    String isbn,
    Map<String, dynamic> book,
  ) => BookMetadata(
    isbn: isbn,
    title: _text(book['title']) ?? _text(book['title_long']) ?? 'Untitled book',
    author: _strings(book['authors']).join(', '),
    authors: _strings(book['authors']),
    description:
        _text(book['overview']) ??
        _text(book['synopsis']) ??
        _text(book['excerpt']),
    pageCount: _int(book['pages']),
    subjects: normalizeGenres(_strings(book['subjects'])),
    publisher: _text(book['publisher']),
    publishedDate: _text(book['date_published']),
    language: normalizeOptionalLanguage(_text(book['language'])),
    coverUrl: _string(book['image_original']) ?? _string(book['image']),
    isbn10: _string(book['isbn10']) ?? (isbn.length == 10 ? isbn : null),
    isbn13: _string(book['isbn13']) ?? (isbn.length == 13 ? isbn : null),
    publisherLogoUrl: _publisherLogoUrl(book),
    metadataSource: 'ISBNdb',
    sourceUrl: 'https://isbndb.com/book/$isbn',
    apiData: Map<String, dynamic>.from(book),
    providerData: {'isbnDb': Map<String, dynamic>.from(book)},
  );

  factory BookMetadata.fromOpenLibrarySearch(
    String isbn,
    Map<String, dynamic> document,
  ) {
    final languages = _languageValues(document['language']);
    final authors = _strings(document['author_name']);
    final coverId = _int(document['cover_i']);
    final workKey = _string(document['key']);
    final language = languages.map((value) => value.$2).join(', ');
    return BookMetadata(
      isbn: isbn,
      title: _text(document['title']) ?? 'Untitled book',
      author: authors.join(', '),
      subtitle: _text(document['subtitle']),
      authors: authors,
      pageCount: _int(document['number_of_pages_median']),
      tags: normalizeBookItems(_strings(document['subject'])),
      subjectPlaces: _strings(document['place']),
      subjectPeople: _strings(document['person']),
      subjectTimes: _strings(document['time']),
      publisher: _firstString(document['publisher']),
      publishedDate: _firstString(document['publish_date']),
      firstPublishDate: _int(document['first_publish_year'])?.toString(),
      language: language.isEmpty ? null : language,
      languageCode: languages.isEmpty ? null : languages.first.$1,
      origin: languages.any((value) => value.$1 == 'tur') ? 'Yerli' : null,
      coverUrl: coverId == null || coverId < 1
          ? null
          : 'https://covers.openlibrary.org/b/id/$coverId-L.jpg?default=false',
      isbn10:
          _firstString(document['isbn10']) ??
          _firstString(document['isbn_10']) ??
          (isbn.length == 10 ? isbn : null),
      isbn13:
          _firstString(document['isbn13']) ??
          _firstString(document['isbn_13']) ??
          (isbn.length == 13 ? isbn : null),
      workId: _lastPathPart(workKey),
      sourceUrl: workKey == null ? null : 'https://openlibrary.org$workKey',
      publisherLogoUrl: _publisherLogoUrl(document),
      metadataSource: 'Open Library Search',
      apiData: Map<String, dynamic>.from(document),
      providerData: {'openLibrarySearch': Map<String, dynamic>.from(document)},
    );
  }

  factory BookMetadata.fromGoogleBooks(
    String isbn,
    Map<String, dynamic> volume,
  ) {
    final info = _map(volume['volumeInfo']) ?? volume;
    final identifiers = _maps(info['industryIdentifiers']);
    String? identifier(String type) {
      for (final value in identifiers) {
        if (_string(value['type']) == type) {
          return _string(value['identifier']);
        }
      }
      return null;
    }

    final languageCode = _string(info['language']);
    final cover = _map(info['imageLinks']);
    final coverUrl =
        _string(cover?['thumbnail']) ?? _string(cover?['smallThumbnail']);
    return BookMetadata(
      isbn: isbn,
      title: _text(info['title']) ?? 'Untitled book',
      author: _strings(info['authors']).join(', '),
      subtitle: _text(info['subtitle']),
      authors: _strings(info['authors']),
      description: _text(info['description']),
      pageCount: _int(info['pageCount']),
      subjects: normalizeGenres(_strings(info['categories'])),
      publisher: _text(info['publisher']),
      publishedDate: _text(info['publishedDate']),
      language: _languageName(languageCode),
      languageCode: languageCode,
      coverUrl: coverUrl?.replaceFirst('http://', 'https://'),
      isbn10: identifier('ISBN_10') ?? (isbn.length == 10 ? isbn : null),
      isbn13: identifier('ISBN_13') ?? (isbn.length == 13 ? isbn : null),
      previewUrl: _string(info['previewLink']),
      sourceUrl:
          _string(info['canonicalVolumeLink']) ?? _string(volume['selfLink']),
      publisherLogoUrl: _publisherLogoUrl(info) ?? _publisherLogoUrl(volume),
      metadataSource: 'Google Books',
      apiData: Map<String, dynamic>.from(volume),
      providerData: {'googleBooks': Map<String, dynamic>.from(volume)},
    );
  }

  factory BookMetadata.fromHardcover(
    String isbn,
    Map<String, dynamic> edition,
  ) {
    final book = _map(edition['book']) ?? const <String, dynamic>{};
    final authors = _names(book['contributions']);
    final editionId = _string(edition['id']?.toString());
    final bookId = _string(book['id']?.toString());
    final language = _map(edition['language']);
    final languageValue =
        _text(language?['language']) ?? _text(language?['name']);
    return BookMetadata(
      isbn: isbn,
      title: _text(edition['title']) ?? _text(book['title']) ?? 'Untitled book',
      author: authors.join(', '),
      subtitle: _text(edition['subtitle']) ?? _text(book['subtitle']),
      authors: authors,
      description: _text(book['description']) ?? _text(edition['description']),
      pageCount: _int(edition['pages']) ?? _int(book['pages']),
      subjects: normalizeGenres([
        ..._strings(edition['genres']),
        ..._strings(book['genres']),
      ]),
      publisher: _text(_map(edition['publisher'])?['name']),
      publishedDate: _text(edition['release_date']),
      language: languageValue == null ? null : normalizeLanguage(languageValue),
      coverUrl:
          _url(_map(edition['image'])?['url']) ??
          _url(_map(book['image'])?['url']),
      isbn10: _string(edition['isbn_10']) ?? (isbn.length == 10 ? isbn : null),
      isbn13: _string(edition['isbn_13']) ?? (isbn.length == 13 ? isbn : null),
      editionId: editionId,
      workId: bookId,
      sourceUrl: editionId == null
          ? (book['slug'] == null
                ? 'https://hardcover.app'
                : 'https://hardcover.app/books/${book['slug']}')
          : 'https://hardcover.app/edition/id/$editionId',
      metadataSource: 'Hardcover',
      apiData: Map<String, dynamic>.from(edition),
      apiWorkData: book,
      providerData: {
        'hardcover': {'edition': edition, 'book': book},
      },
    );
  }

  Map<String, dynamic> toFirestoreFields({bool includeEmpty = false}) {
    final fields = <String, dynamic>{
      'isbn': normalizeIsbn(isbn) ?? normalizeBookText(isbn),
      'isbn10': normalizeIsbn(isbn10 ?? ''),
      'isbn13': normalizeIsbn(isbn13 ?? ''),
      'subtitle': _optionalBookText(subtitle),
      'authors': normalizeBookItems(authors),
      'description': _optionalBookText(description),
      'pageCount': pageCount,
      'subjects': normalizeGenres(subjects),
      'tags': normalizeBookItems(tags),
      'subjectPlaces': normalizeBookItems(subjectPlaces),
      'subjectPeople': normalizeBookItems(subjectPeople),
      'subjectTimes': normalizeBookItems(subjectTimes),
      'contributions': normalizeBookItems(contributions),
      'publisher': _optionalBookText(publisher),
      'publishedDate': _optionalBookText(publishedDate),
      'firstPublishDate': _optionalBookText(firstPublishDate),
      'language': language == null
          ? null
          : normalizeLanguages([language!]).join(', '),
      'languageCode': _optionalBookText(languageCode),
      'origin': _optionalBookText(origin),
      'coverUrl': _optionalBookText(coverUrl),
      'editionId': _optionalBookText(editionId),
      'workId': _optionalBookText(workId),
      'previewUrl': _optionalBookText(previewUrl),
      'sourceUrl': _optionalBookText(sourceUrl),
      'publisherLogoUrl': _optionalBookText(publisherLogoUrl),
      'metadataSource': _optionalBookText(metadataSource),
      'isbnApiData': apiData,
      'isbnApiEditionData': apiEditionData,
      'isbnApiWorkData': apiWorkData,
      'metadataProviders': providerData,
    };
    if (!includeEmpty) {
      fields.removeWhere((_, value) {
        return value == null ||
            value is String && value.isEmpty ||
            value is List && value.isEmpty ||
            value is Map && value.isEmpty;
      });
    }
    return fields;
  }

  BookMetadata copyWith({
    String? title,
    String? author,
    String? subtitle,
    List<String>? authors,
    String? description,
    int? pageCount,
    List<String>? subjects,
    List<String>? tags,
    List<String>? subjectPlaces,
    List<String>? subjectPeople,
    List<String>? subjectTimes,
    List<String>? contributions,
    String? publisher,
    String? publishedDate,
    String? firstPublishDate,
    String? language,
    String? languageCode,
    String? origin,
    String? coverUrl,
    String? isbn10,
    String? isbn13,
    String? editionId,
    String? workId,
    String? previewUrl,
    String? sourceUrl,
    String? publisherLogoUrl,
    String? metadataSource,
    Map<String, dynamic>? apiData,
    Map<String, dynamic>? apiEditionData,
    Map<String, dynamic>? apiWorkData,
    Map<String, dynamic>? providerData,
  }) => BookMetadata(
    isbn: isbn,
    title: title ?? this.title,
    author: author ?? this.author,
    subtitle: subtitle ?? this.subtitle,
    authors: authors ?? this.authors,
    description: description ?? this.description,
    pageCount: pageCount ?? this.pageCount,
    subjects: subjects ?? this.subjects,
    tags: tags ?? this.tags,
    subjectPlaces: subjectPlaces ?? this.subjectPlaces,
    subjectPeople: subjectPeople ?? this.subjectPeople,
    subjectTimes: subjectTimes ?? this.subjectTimes,
    contributions: contributions ?? this.contributions,
    publisher: publisher ?? this.publisher,
    publishedDate: publishedDate ?? this.publishedDate,
    firstPublishDate: firstPublishDate ?? this.firstPublishDate,
    language: language ?? this.language,
    languageCode: languageCode ?? this.languageCode,
    origin: origin ?? this.origin,
    coverUrl: coverUrl ?? this.coverUrl,
    isbn10: isbn10 ?? this.isbn10,
    isbn13: isbn13 ?? this.isbn13,
    editionId: editionId ?? this.editionId,
    workId: workId ?? this.workId,
    previewUrl: previewUrl ?? this.previewUrl,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    publisherLogoUrl: publisherLogoUrl ?? this.publisherLogoUrl,
    metadataSource: metadataSource ?? this.metadataSource,
    apiData: apiData ?? this.apiData,
    apiEditionData: apiEditionData ?? this.apiEditionData,
    apiWorkData: apiWorkData ?? this.apiWorkData,
    providerData: providerData ?? this.providerData,
  );
}

enum BookMetadataProvider {
  openLibraryIsbn,
  openLibrarySearch,
  isbnDb,
  hardcover,
  googleBooks,
}

extension BookMetadataProviderLabel on BookMetadataProvider {
  String get label => switch (this) {
    BookMetadataProvider.isbnDb => 'ISBNdb',
    BookMetadataProvider.hardcover => 'Hardcover',
    BookMetadataProvider.openLibraryIsbn => 'Open Library ISBN',
    BookMetadataProvider.openLibrarySearch => 'Open Library Search',
    BookMetadataProvider.googleBooks => 'Google Books',
  };
}

enum BookMetadataField {
  title,
  author,
  subtitle,
  description,
  pageCount,
  subjects,
  publisher,
  publishedDate,
  language,
  coverUrl,
  publisherLogoUrl,
  isbn10,
  isbn13,
  previewUrl,
}

extension BookMetadataFieldLabel on BookMetadataField {
  String get label => switch (this) {
    BookMetadataField.title => 'Title',
    BookMetadataField.author => 'Author',
    BookMetadataField.subtitle => 'Subtitle',
    BookMetadataField.description => 'Description',
    BookMetadataField.pageCount => 'Page count',
    BookMetadataField.subjects => 'Subjects',
    BookMetadataField.publisher => 'Publisher',
    BookMetadataField.publishedDate => 'Publication date',
    BookMetadataField.language => 'Language',
    BookMetadataField.coverUrl => 'Cover image',
    BookMetadataField.publisherLogoUrl => 'Publisher logo',
    BookMetadataField.isbn10 => 'ISBN-10',
    BookMetadataField.isbn13 => 'ISBN-13',
    BookMetadataField.previewUrl => 'Preview URL',
  };
}

class BookMetadataLookupResult {
  const BookMetadataLookupResult({
    required this.isbn,
    required this.candidates,
    required this.errors,
  });

  final String isbn;
  final Map<BookMetadataProvider, BookMetadata> candidates;
  final Map<BookMetadataProvider, String> errors;

  BookMetadata? get primary =>
      candidates.isEmpty ? null : candidates.values.first;

  Map<String, dynamic> get providerData => {
    for (final entry in candidates.entries) entry.key.name: entry.value.apiData,
  };
}

const isbnDbApiKey = String.fromEnvironment('ISBNDB_API_KEY');
const googleBooksApiKey = String.fromEnvironment('GOOGLE_BOOKS_API_KEY');
