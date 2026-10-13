import 'dart:developer' as developer;
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'audio_book_files.dart';
import 'book_files.dart';
import 'book_metadata.dart';
import 'cover_files.dart';
import 'library_book_snapshot.dart';
import 'library_stats.dart';

class CatalogBook {
  const CatalogBook({
    required this.id,
    required this.metadata,
    this.rank,
    this.addedAt,
  });

  final String id;
  final BookMetadata metadata;
  final int? rank;
  final DateTime? addedAt;
}

class BookRepository {
  BookRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const _canonicalBatchSize = 30;

  static const _canonicalFields = {
    'recordType',
    'isbn',
    'isbn10',
    'isbn13',
    'subtitle',
    'authors',
    'description',
    'pageCount',
    'subjects',
    'tags',
    'subjectPlaces',
    'subjectPeople',
    'subjectTimes',
    'contributions',
    'publisher',
    'publishedDate',
    'firstPublishDate',
    'language',
    'languageCode',
    'origin',
    'coverUrl',
    'editionId',
    'workId',
    'previewUrl',
    'sourceUrl',
    'publisherLogoUrl',
    'metadataSource',
    'isbnApiData',
    'isbnApiEditionData',
    'isbnApiWorkData',
    'metadataProviders',
    'title',
    'author',
    'titleSearch',
    'isbnSearches',
  };

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _books =>
      _firestore.collection('books');

  CollectionReference<Map<String, dynamic>> get _libraryBooks =>
      _firestore.collection('libraryBooks');

  String newLibraryBookId() => _libraryBooks.doc().id;

  Stream<LibraryBookSnapshot> watch(String uid, {bool completedOnly = false}) {
    Query<Map<String, dynamic>> query = _libraryBooks.where(
      'libraryId',
      isEqualTo: uid,
    );
    return query
        .snapshots()
        .asyncMap(
          (snapshot) => _hydrate(snapshot, completedOnly: completedOnly),
        )
        .asBroadcastStream();
  }

  Stream<List<CatalogBook>> watchDiscoverCatalog() => _books
      .where('recordType', isEqualTo: 'book')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(
              (document) => CatalogBook(
                id: document.id,
                metadata: BookMetadata.fromFirestore(document.data()),
                rank: _asIntOrNull(document.data()['discoverRank']),
                addedAt: _asDateTime(document.data()['discoverImportedAt']),
              ),
            )
            .toList(growable: false),
      );

  Stream<Set<String>> watchLibraryBookIds(String uid) => _libraryBooks
      .where('libraryId', isEqualTo: uid)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((document) => document.data()['bookId'])
            .whereType<String>()
            .toSet(),
      );

  Future<List<BookMatch>> findDuplicates({
    required String uid,
    required String title,
    String? isbn,
  }) async {
    final snapshot = await _libraryBooks
        .where('libraryId', isEqualTo: uid)
        .get();
    final hydrated = await _hydrate(snapshot);
    return findBookMatches(
      hydrated.docs.map((doc) => doc.data()),
      title: title,
      isbn: isbn,
    );
  }

  Future<String> add({
    required String uid,
    required String title,
    required String author,
    BookMetadata? metadata,
    String? isbn,
    String? coverPath,
    bool wishlist = false,
    bool inHomeLibrary = true,
    List<String>? libraryIds,
    String? relationId,
  }) async {
    final selectedLibraryIds =
        (libraryIds ??
                (inHomeLibrary ? [defaultPersonalLibraryId] : const <String>[]))
            .where((id) => id.trim().isNotEmpty)
            .toSet()
            .toList();
    final metadataBook =
        metadata ??
        BookMetadata(isbn: isbn ?? '', title: title, author: author);
    final canonicalId = _canonicalBookId(metadataBook);
    final canonical = _books.doc(canonicalId);
    final relation = relationId == null
        ? _libraryBooks.doc()
        : _libraryBooks.doc(relationId);

    await _firestore.runTransaction((transaction) async {
      final relationSnapshot = await transaction.get(relation);
      final canonicalSnapshot = await transaction.get(canonical);
      final current = canonicalSnapshot.data() ?? const <String, dynamic>{};
      final ownerCounts = _ownerCounts(current['libraryOwnerCounts']);
      if (!relationSnapshot.exists) {
        ownerCounts[uid] = (ownerCounts[uid] ?? 0) + 1;
      }
      final canonicalFields =
          _canonicalFieldsFor(metadataBook, title: title, author: author)
            ..['recordType'] = 'book'
            ..['libraryCount'] =
                _asInt(current['libraryCount']) +
                (relationSnapshot.exists ? 0 : 1)
            ..['libraryOwnerCounts'] = ownerCounts;
      if (!canonicalSnapshot.exists) {
        canonicalFields['createdAt'] = FieldValue.serverTimestamp();
      }

      transaction.set(canonical, canonicalFields, SetOptions(merge: true));
      transaction.set(relation, {
        'libraryId': uid,
        'bookId': canonicalId,
        'status': null,
        'wishlist': wishlist,
        'inHomeLibrary': selectedLibraryIds.contains(defaultPersonalLibraryId),
        'libraryIds': selectedLibraryIds,
        ...?coverPath == null ? null : {'coverPath': coverPath},
        'createdAt':
            relationSnapshot.data()?['createdAt'] ??
            FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    return relation.id;
  }

  Future<List<BookMetadata>> searchCatalog({
    String? title,
    String? isbn,
  }) async {
    final normalizedIsbn = isbn == null ? null : normalizeIsbn(isbn);
    Query<Map<String, dynamic>> query = _books;
    if (normalizedIsbn != null) {
      query = query.where('isbnSearches', arrayContains: normalizedIsbn);
    } else {
      final searchText = normalizeBookSearchText(title ?? '');
      if (searchText.length < 2) return [];
      query = query
          .orderBy('titleSearch')
          .startAt([searchText])
          .endAt(['$searchText\uf8ff'])
          .limit(10);
    }
    final snapshot = await query.limit(10).get();
    return snapshot.docs
        .where((document) => document.data()['recordType'] == 'book')
        .map((document) => BookMetadata.fromFirestore(document.data()))
        .toList();
  }

  Future<void> update(String id, Map<String, dynamic> data) async {
    final relation = _libraryBooks.doc(id);
    final relationSnapshot = await relation.get();
    final relationData = relationSnapshot.data();
    final bookId = relationData?['bookId'];
    if (!relationSnapshot.exists || bookId is! String || bookId.isEmpty) {
      throw StateError('The book-library relationship could not be found.');
    }

    final normalized = normalizeBookFields(data)
      ..remove('libraryId')
      ..remove('bookId')
      ..remove('ownerId');
    final canonical = <String, dynamic>{};
    final personal = <String, dynamic>{};
    for (final entry in normalized.entries) {
      final target = _canonicalFields.contains(entry.key)
          ? canonical
          : personal;
      target[entry.key] = entry.value;
    }

    final batch = _firestore.batch();
    if (canonical.isNotEmpty) {
      final canonicalReference = _books.doc(bookId);
      final canonicalSnapshot = await canonicalReference.get();
      final current = canonicalSnapshot.data() ?? const <String, dynamic>{};
      final merged = {...current, ...canonical};
      canonical['titleSearch'] = normalizeBookSearchText(
        merged['title'] as String? ?? '',
      );
      canonical['isbnSearches'] = _isbnSearches(merged);
      canonical['updatedAt'] = FieldValue.serverTimestamp();
      batch.set(canonicalReference, canonical, SetOptions(merge: true));
      personal['updatedAt'] = FieldValue.serverTimestamp();
    }
    if (personal.isNotEmpty) {
      personal['updatedAt'] ??= FieldValue.serverTimestamp();
      batch.update(relation, personal);
    }
    if (canonical.isNotEmpty || personal.isNotEmpty) await batch.commit();
  }

  Future<void> updateStatus(String id, String? status) =>
      _libraryBooks.doc(id).update({
        'status': status,
        'readingStartedAt': status == readingStatus
            ? FieldValue.serverTimestamp()
            : FieldValue.delete(),
        'completedAt': isCompletedStatus(status)
            ? FieldValue.serverTimestamp()
            : FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> setLibraryTargets({
    required String uid,
    required String id,
    required Set<String> availableLibraryIds,
    required Set<String> selectedLibraryIds,
  }) async {
    final source = _libraryBooks.doc(id);
    final sourceSnapshot = await source.get();
    final sourceData = sourceSnapshot.data();
    if (!sourceSnapshot.exists || sourceData?['libraryId'] != uid) {
      throw StateError('You can only move this book from your own library.');
    }
    final canonicalId = sourceData?['bookId'];
    if (canonicalId is! String || canonicalId.isEmpty) {
      throw StateError('The shared book record could not be found.');
    }

    final libraryIds = {...availableLibraryIds, uid};
    final selected = selectedLibraryIds.intersection(libraryIds);
    final existing = <String, DocumentReference<Map<String, dynamic>>>{};
    final newRelations = <String, DocumentReference<Map<String, dynamic>>>{};
    for (final libraryId in libraryIds) {
      if (libraryId == uid) continue;
      // ponytail: owner-scoped scan is enough for a personal shared library; add a composite index if it grows large.
      final matches = await _libraryBooks
          .where('libraryId', isEqualTo: libraryId)
          .get();
      final match = matches.docs
          .where((document) => document.data()['bookId'] == canonicalId)
          .firstOrNull;
      if (match != null) {
        existing[libraryId] = match.reference;
      } else if (selected.contains(libraryId)) {
        newRelations[libraryId] = _libraryBooks.doc();
      }
    }

    final canonical = _books.doc(canonicalId);
    await _firestore.runTransaction((transaction) async {
      final currentSource = await transaction.get(source);
      final currentBook = await transaction.get(canonical);
      final currentTargets = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in existing.entries) {
        currentTargets[entry.key] = await transaction.get(entry.value);
      }
      if (!currentSource.exists || currentSource.data()?['libraryId'] != uid) {
        throw StateError('This book is no longer in your library.');
      }

      final sourceData = currentSource.data()!;
      transaction.update(source, {'updatedAt': FieldValue.serverTimestamp()});

      var delta = 0;
      final ownerCounts = _ownerCounts(
        currentBook.data()?['libraryOwnerCounts'],
      );
      for (final libraryId in libraryIds) {
        if (libraryId == uid) continue;
        final target = currentTargets[libraryId];
        if (selected.contains(libraryId)) {
          if (target?.exists == true) {
            transaction.update(existing[libraryId]!, {
              'wishlist': false,
              'inHomeLibrary': true,
              'libraryIds': [defaultPersonalLibraryId],
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            final reference = newRelations[libraryId];
            if (reference == null) continue;
            transaction.set(reference, {
              'libraryId': libraryId,
              'bookId': canonicalId,
              'status': sourceData['status'],
              'wishlist': false,
              'inHomeLibrary': true,
              'libraryIds': [defaultPersonalLibraryId],
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            ownerCounts[libraryId] = (ownerCounts[libraryId] ?? 0) + 1;
            delta++;
          }
        } else if (target != null &&
            target.exists &&
            target.data()?['wishlist'] != true) {
          transaction.delete(existing[libraryId]!);
          final count = ownerCounts[libraryId] ?? 0;
          if (count <= 1) {
            ownerCounts.remove(libraryId);
          } else {
            ownerCounts[libraryId] = count - 1;
          }
          delta--;
        }
      }

      if (delta == 0) return;
      final rawCount = currentBook.data()?['libraryCount'];
      if (currentBook.data()?['recordType'] != 'book' || rawCount is! num) {
        throw StateError('The shared book record requires migration.');
      }
      final count = rawCount.toInt() + delta;
      if (count < 1) {
        throw StateError('The library count for this book is invalid.');
      }
      transaction.update(canonical, {
        'libraryCount': count,
        'libraryOwnerCounts': ownerCounts,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> delete(String uid, String id) async {
    final relation = _libraryBooks.doc(id);
    final snapshot = await relation.get();
    final data = snapshot.data();
    if (!snapshot.exists) return;
    if (data?['libraryId'] != uid) {
      throw StateError('You do not have permission to delete this book.');
    }
    final canonicalId = data?['bookId'];
    if (canonicalId is! String || canonicalId.isEmpty) {
      throw StateError('The shared book record could not be found.');
    }

    final canonical = _books.doc(canonicalId);
    await _firestore.runTransaction((transaction) async {
      final currentRelation = await transaction.get(relation);
      final currentBook = await transaction.get(canonical);
      if (!currentRelation.exists) return;
      if (currentRelation.data()?['libraryId'] != uid) {
        throw StateError('You do not have permission to delete this book.');
      }

      transaction.delete(relation);
      if (!currentBook.exists || currentBook.data()?['recordType'] != 'book') {
        return;
      }

      final bookData = currentBook.data();
      final rawCount = bookData?['libraryCount'];
      final ownerCounts = _ownerCounts(bookData?['libraryOwnerCounts']);
      final ownerCount = ownerCounts[uid] ?? 0;
      if (rawCount is! num || ownerCount <= 0) {
        developer.log(
          'Canonical book metadata is incomplete; relation deleted only.',
          name: 'BookRepository.delete',
          error: {'bookId': canonicalId, 'libraryCount': rawCount},
        );
        return;
      }

      final count = rawCount.toInt();
      if (count <= 1 && ownerCount == 1) {
        transaction.delete(canonical);
        return;
      }

      if (count <= 1) return;
      if (ownerCount == 1) {
        ownerCounts.remove(uid);
      } else {
        ownerCounts[uid] = ownerCount - 1;
      }
      transaction.update(canonical, {
        'libraryCount': count - 1,
        'libraryOwnerCounts': ownerCounts,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    await Future.wait([
      _bestEffortCleanup('reading files', () => BookFiles.delete(uid, id)),
      _bestEffortCleanup('audio files', () => AudioBookFiles.delete(uid, id)),
      _bestEffortCleanup('cover storage', () => CoverFiles.delete(uid, id)),
      _bestEffortCleanup(
        'local cover',
        () => _deleteLocalCover(data?['coverPath']),
      ),
    ]);
  }

  Future<void> _bestEffortCleanup(
    String name,
    Future<void> Function() cleanup,
  ) async {
    try {
      await cleanup();
    } catch (error, stackTrace) {
      developer.log(
        'Book cleanup failed: $name',
        name: 'BookRepository.delete',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<LibraryBookSnapshot> _hydrate(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    bool completedOnly = false,
  }) async {
    final relationDocs =
        snapshot.docs
            .where(
              (doc) =>
                  !completedOnly || isCompletedStatus(doc.data()['status']),
            )
            .toList()
          ..sort(
            (first, second) =>
                _dateValue(second.data()['createdAt'])
                    .compareTo(_dateValue(first.data()['createdAt'])),
          );
    final canonicalIds = relationDocs
        .map((doc) => doc.data()['bookId'])
        .whereType<String>()
        .toSet();
    final canonicalIdList = canonicalIds.toList(growable: false);
    final canonicalSnapshots = await Future.wait([
      for (
        var start = 0;
        start < canonicalIdList.length;
        start += _canonicalBatchSize
      )
        _books
            .where(
              FieldPath.documentId,
              whereIn: canonicalIdList
                  .skip(start)
                  .take(_canonicalBatchSize)
                  .toList(growable: false),
            )
            .get(),
    ]);
    final canonicalById = {
      for (final snapshot in canonicalSnapshots)
        for (final document in snapshot.docs) document.id: document.data(),
    };
    return LibraryBookSnapshot(
      snapshot,
      relationDocs
          .map((relation) {
            final relationData = relation.data();
            final bookId = relationData['bookId'];
            return LibraryBookDocument(relation, {
              ...?bookId is String ? canonicalById[bookId] : null,
              ...relationData,
              'bookId': bookId,
              'ownerId': relationData['libraryId'],
            });
          })
          .toList(growable: false),
    );
  }

  DateTime _dateValue(Object? value) => value is Timestamp
      ? value.toDate()
      : DateTime.fromMillisecondsSinceEpoch(0);

  String _canonicalBookId(BookMetadata book) => 'book_${_catalogId(book)}';

  String _catalogId(BookMetadata book) {
    final isbns = _isbnSearches(book.toFirestoreFields());
    if (isbns.isNotEmpty) return 'isbn_${isbns.first}';
    return 'title_${Uri.encodeComponent(normalizeBookSearchText(book.title))}_'
        '${Uri.encodeComponent(normalizeBookSearchText(book.author))}';
  }

  Map<String, dynamic> _canonicalFieldsFor(
    BookMetadata book, {
    String? title,
    String? author,
  }) {
    final bookTitle = title ?? book.title;
    final bookAuthor = author ?? book.author;
    return normalizeBookFields({
      ...book.toFirestoreFields(),
      'title': bookTitle,
      'author': bookAuthor,
      'authors': splitAuthorNames(bookAuthor),
      'titleSearch': normalizeBookSearchText(bookTitle),
      'isbnSearches': _isbnSearches(book.toFirestoreFields()),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  List<String> _isbnSearches(Map<String, dynamic> fields) {
    final values = <String>{};
    for (final value in [fields['isbn'], fields['isbn10'], fields['isbn13']]) {
      final normalized = normalizeIsbn(value is String ? value : '');
      if (normalized != null) values.add(normalized);
    }
    return values.toList();
  }

  Map<String, int> _ownerCounts(Object? value) {
    if (value is! Map) return {};
    return {
      for (final entry in value.entries)
        if (entry.key is String && entry.value is num)
          entry.key as String: (entry.value as num).toInt(),
    };
  }

  int _asInt(Object? value) => value is num ? value.toInt() : 0;

  int? _asIntOrNull(Object? value) => value is num ? value.toInt() : null;

  DateTime? _asDateTime(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime date => date,
    _ => null,
  };

  Future<void> _deleteLocalCover(Object? value) async {
    if (value is! String || value.isEmpty) return;
    final root = await getApplicationDocumentsDirectory();
    final directory = p.normalize(p.join(root.path, 'covers'));
    final path = p.normalize(value);
    if (p.dirname(path) != directory) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
