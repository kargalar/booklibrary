part of 'book_metadata.dart';

class BookMetadataLookup {
  BookMetadataLookup({
    http.Client? client,
    String? isbnDbKey,
    String? googleBooksKey,
    this.hardcoverLookup,
  }) : _client = client ?? http.Client(),
       _isbnDbKey = _cleanKey(isbnDbKey ?? isbnDbApiKey),
       _googleBooksKey = _cleanKey(googleBooksKey ?? googleBooksApiKey);

  final http.Client _client;
  final String? _isbnDbKey;
  final String? _googleBooksKey;
  final Future<Map<String, dynamic>?> Function(String isbn)? hardcoverLookup;

  bool get _hasHardcoverAccess => hardcoverLookup != null;

  // Fallback lookup: providers are deliberately queried one at a time.
  Future<BookMetadataLookupResult> find(
    String rawIsbn, {
    String? title,
    String? author,
  }) => _lookup(rawIsbn, compareAll: false, title: title, author: author);

  Future<BookMetadataLookupResult> findByTitleAuthor({
    required String title,
    String? author,
  }) async {
    final metadata = await _fetchOpenLibrarySearch(
      '',
      title: title,
      author: author,
    );
    if (metadata == null) {
      throw const FormatException(
        'No book was found for this title and author.',
      );
    }
    return BookMetadataLookupResult(
      isbn: metadata.isbn,
      candidates: {BookMetadataProvider.openLibrarySearch: metadata},
      errors: const {},
    );
  }

  Future<BookMetadataLookupResult> compare(
    String rawIsbn, {
    String? title,
    String? author,
  }) => _lookup(rawIsbn, compareAll: true, title: title, author: author);

  Future<BookMetadataLookupResult> _lookup(
    String rawIsbn, {
    required bool compareAll,
    String? title,
    String? author,
  }) async {
    final isbn = normalizeIsbn(rawIsbn);
    if (isbn == null) {
      throw const FormatException('Enter a valid ISBN-10 or ISBN-13.');
    }

    final candidates = <BookMetadataProvider, BookMetadata>{};
    final errors = <BookMetadataProvider, String>{};
    for (final provider in BookMetadataProvider.values) {
      if (provider == BookMetadataProvider.isbnDb && _isbnDbKey == null) {
        if (compareAll) {
          errors[provider] = 'The API key is not configured.';
        }
        continue;
      }
      if (provider == BookMetadataProvider.hardcover && !_hasHardcoverAccess) {
        if (compareAll) {
          errors[provider] = 'An optional metadata provider is not configured.';
        }
        continue;
      }
      try {
        final metadata = await _fetch(
          provider,
          isbn,
          title: title,
          author: author,
        );
        if (metadata == null) {
          if (compareAll) {
            errors[provider] = 'No record was found for this ISBN.';
          }
          continue;
        }
        candidates[provider] = metadata;
        if (!compareAll) break;
      } on Exception catch (error) {
        errors[provider] = _errorMessage(error);
      }
    }
    if (candidates.isEmpty) {
      throw FormatException(
        errors.isEmpty
            ? 'No book record was found for this ISBN.'
            : 'Book details could not be retrieved: ${errors.values.first}',
      );
    }
    return BookMetadataLookupResult(
      isbn: isbn,
      candidates: candidates,
      errors: errors,
    );
  }

  Future<BookMetadata?> _fetch(
    BookMetadataProvider provider,
    String isbn, {
    String? title,
    String? author,
  }) => switch (provider) {
    BookMetadataProvider.isbnDb => _fetchIsbnDb(isbn),
    BookMetadataProvider.hardcover => _fetchHardcover(isbn),
    BookMetadataProvider.openLibraryIsbn => _fetchOpenLibraryIsbn(isbn),
    BookMetadataProvider.openLibrarySearch => _fetchOpenLibrarySearch(
      isbn,
      title: title,
      author: author,
    ),
    BookMetadataProvider.googleBooks => _fetchGoogleBooks(isbn),
  };

  Future<BookMetadata?> _fetchIsbnDb(String isbn) async {
    final response = await _get(
      Uri.https('api2.isbndb.com', '/book/$isbn'),
      headers: {'Authorization': _isbnDbKey!},
    );
    if (response == null) return null;
    final payload = _jsonObject(response.body);
    final book =
        _map(payload['book']) ??
        (payload.containsKey('title') ? payload : null);
    return book == null ? null : BookMetadata.fromIsbnDb(isbn, book);
  }

  Future<BookMetadata?> _fetchHardcover(String isbn) async {
    final edition = await hardcoverLookup?.call(isbn);
    return edition == null ? null : BookMetadata.fromHardcover(isbn, edition);
  }

  Future<BookMetadata?> _fetchOpenLibraryIsbn(String isbn) async {
    final response = await _get(
      Uri.https('openlibrary.org', '/isbn/$isbn.json'),
    );
    if (response == null) return null;
    final edition = _jsonObject(response.body);
    if (edition.isEmpty) return null;

    var details = edition;
    final authorNames = await _openLibraryAuthorNames(edition['authors']);
    if (authorNames.isNotEmpty) {
      details = {
        ...edition,
        'authors': [
          for (final name in authorNames) {'name': name},
        ],
      };
    }

    Map<String, dynamic>? work;
    final workKey = _string(_firstMap(edition['works'])?['key']);
    if (workKey != null) {
      try {
        final workResponse = await _get(
          Uri.https('openlibrary.org', '$workKey.json'),
        );
        if (workResponse != null) work = _jsonObject(workResponse.body);
      } on Exception {
        // Edition data is enough to show and save a book.
      }
    }
    return BookMetadata.fromOpenLibrary(
      isbn,
      details,
      work,
      edition: edition,
      sourceUrl: 'https://openlibrary.org/isbn/$isbn',
      apiData: edition,
      apiWorkData: work ?? const {},
      metadataSource: 'Open Library ISBN',
      providerData: {
        'openLibraryIsbn': edition,
        ...?work == null ? null : {'openLibraryWork': work},
      },
    );
  }

  Future<BookMetadata?> _fetchOpenLibrarySearch(
    String isbn, {
    String? title,
    String? author,
  }) async {
    final titleQuery = title?.trim();
    final authorQuery = author?.trim();
    final query = <String, String>{
      if (titleQuery?.isNotEmpty == true) 'title': titleQuery!,
      if (authorQuery?.isNotEmpty == true) 'author': authorQuery!,
      if (titleQuery?.isNotEmpty != true && authorQuery?.isNotEmpty != true)
        'isbn': isbn,
      'limit': '5',
      'fields': 'title,subtitle,author_name,number_of_pages_median,subject,publisher,publish_date,first_publish_year,language,isbn10,isbn13,cover_i,key',
    };
    final response = await _get(
      Uri.https('openlibrary.org', '/search.json', query),
    );
    if (response == null) return null;
    final docs = _maps(_jsonObject(response.body)['docs']);
    if (docs.isEmpty) return null;
    final document = docs.firstWhere(
      (value) =>
          _containsIsbn(value['isbn'], isbn) ||
          _containsIsbn(value['isbn10'], isbn) ||
          _containsIsbn(value['isbn13'], isbn),
      orElse: () => docs.first,
    );
    final resolvedIsbn = isbn.isEmpty
        ? _firstString(document['isbn13']) ??
              _firstString(document['isbn10']) ??
              ''
        : isbn;
    return BookMetadata.fromOpenLibrarySearch(resolvedIsbn, document);
  }

  Future<List<String>> _openLibraryAuthorNames(Object? value) async {
    final keys = _maps(value)
        .map(
          (item) =>
              _string(item['key']) ?? _string(_map(item['author'])?['key']),
        )
        .whereType<String>()
        .take(8)
        .toList();
    if (keys.isEmpty) return [];
    final names = await Future.wait(
      keys.map((key) async {
        try {
          final response = await _get(
            Uri.https('openlibrary.org', '$key.json'),
          );
          return response == null
              ? null
              : _string(_jsonObject(response.body)['name']);
        } on Exception {
          return null;
        }
      }),
    );
    return names.whereType<String>().toSet().toList();
  }

  Future<BookMetadata?> _fetchGoogleBooks(String isbn) async {
    final query = <String, String>{
      'q': 'isbn:$isbn',
      'maxResults': '5',
      'printType': 'books',
      ...?_googleBooksKey == null ? null : {'key': _googleBooksKey},
    };
    final response = await _get(
      Uri.https('www.googleapis.com', '/books/v1/volumes', query),
    );
    if (response == null) return null;
    final items = _maps(_jsonObject(response.body)['items']);
    if (items.isEmpty) return null;
    final volume = items.firstWhere(
      (value) => _containsIsbn(
        _map(value['volumeInfo'])?['industryIdentifiers'],
        isbn,
      ),
      orElse: () => items.first,
    );
    return BookMetadata.fromGoogleBooks(isbn, volume);
  }

  Future<http.Response?> _get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _client
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'BookLibrary/1.0',
            ...headers,
          },
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw FormatException(
        'The provider returned no response (${response.statusCode}).',
      );
    }
    return response;
  }

  void dispose() => _client.close();
}
