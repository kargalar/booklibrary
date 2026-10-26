import 'dart:io';
import 'dart:convert';

import 'package:booklibrary/data/book_metadata.dart';
import 'package:booklibrary/data/book_repository.dart';
import 'package:booklibrary/data/local_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late LocalDatabase store;
  late String path;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('booklibrary_database_');
    path = '${directory.path}/library.db';
    store = await LocalDatabase.open(path: path);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Map<String, dynamic> archive({Map<String, dynamic>? documents}) => {
    'schemaVersion': 1,
    'user': {'uid': 'original-user'},
    'documents':
        documents ??
        {
          'books/shared': {'title': 'Original', 'recordType': 'book'},
          'libraryBooks/relation': {
            'bookId': 'shared',
            'libraryId': 'original-user',
            'notes': ['Preserved note'],
            'completedAt': {
              '__type': 'timestamp',
              'seconds': 123,
              'nanoseconds': 456789123,
            },
          },
          'libraryBooks/relation/ratings/original-user': {'value': 5},
        },
    'imagePaths': {'https://example.com/cover': 'covers/original.jpg'},
  };

  test('migration survives reopening with IDs, nested records and timestamp precision intact', () async {
    final input = archive();
    await store.importArchive(input);
    await store.close();
    store = await LocalDatabase.open(path: path);
    final exported = await store.exportArchive();
    expect(exported['documents'], input['documents']);
    expect(exported['user'], input['user']);
    expect(await store.setting('imagePaths'), isNotNull);
    final book = (await store.doc('libraryBooks/relation').get()).data()!;
    expect(book['completedAt'], const Timestamp(123, 456789123));
    final snapshot = await BookRepository(database: store)
        .watch('original-user')
        .first;
    expect(snapshot.docs.single.id, 'relation');
    expect(snapshot.docs.single.data()['notes'], ['Preserved note']);
  });

  test(
    'invalid imports roll back documents and completion marker and can retry',
    () async {
      await expectLater(
        store.importArchive(
          archive(
            documents: {
              'books/first': {'title': 'First'},
              'invalid': {'title': 'Invalid'},
            },
          ),
        ),
        throwsFormatException,
      );
      expect((await store.collection('books').get()).docs, isEmpty);
      expect(await store.setting('migrationComplete'), isNull);
      await store.importArchive(archive());
      expect(await store.setting('migrationComplete'), '3');
    },
  );

  test('completed migration never overwrites later local edits', () async {
    await store.importArchive(archive());
    await store.doc('books/shared').update({'title': 'Local edit'});
    await store.importArchive(archive());
    expect(
      (await store.doc('books/shared').get()).data()!['title'],
      'Local edit',
    );
  });

  test('failed multi-document batch rolls back every write', () async {
    await store.doc('books/one').set({'title': 'Original'});
    final batch = store.batch()
      ..update(store.doc('books/one'), {'title': 'Changed'})
      ..update(store.doc('books/missing'), {'title': 'Missing'});
    await expectLater(batch.commit(), throwsStateError);
    expect((await store.doc('books/one').get()).data()!['title'], 'Original');
  });

  test('offline create, notes, status, search, ratings and delete persist correctly', () async {
    final repository = BookRepository(database: store);
    final id = await repository.add(
      uid: 'reader',
      title: 'Offline Book',
      author: 'Author',
      metadata: const BookMetadata(
        isbn: '9780140328721',
        title: 'Offline Book',
        author: 'Author',
      ),
    );
    await repository.update(id, {
      'notes': FieldValue.arrayUnion(['Note', 'Note']),
      'custom': {'nested': true},
    });
    await repository.updateStatus(id, 'Okundu');
    final snapshot = await repository.watch('reader').first;
    expect(snapshot.docs.single.data()['notes'], ['Note']);
    expect(snapshot.docs.single.data()['completedAt'], isA<Timestamp>());
    expect(
      (await repository.searchCatalog(title: 'Offline')).single.title,
      'Offline Book',
    );
    await store.doc('libraryBooks/$id/ratings/reader').set({'value': 4});
    expect((await store.collection('libraryBooks/$id/ratings').get()).size, 1);
    // No filesystem cleanup is needed for this record.
    await repository.delete('reader', id);
    expect((await repository.watch('reader').first).docs, isEmpty);
  });

  test('dotted updates, array union and field deletion are durable', () async {
    final ref = store.doc('books/one');
    await ref.set({
      'permissions': {'reader': 'read', 'other': 'edit'},
      'notes': ['one'],
      'old': true,
    });
    await ref.update({
      'permissions.reader': 'edit',
      'notes': FieldValue.arrayUnion(['one', 'two']),
      'old': FieldValue.delete(),
    });
    expect((await ref.get()).data(), {
      'permissions': {'reader': 'edit', 'other': 'edit'},
      'notes': ['one', 'two'],
    });
  });

  test('concurrent transactions do not lose updates', () async {
    final ref = store.doc('books/count');
    await ref.set({'value': 0});
    await Future.wait(
      List.generate(
        10,
        (_) => store.runTransaction((txn) async {
          final value = (await txn.get(ref)).data()!['value'] as int;
          txn.update(ref, {'value': value + 1});
        }),
      ),
    );
    expect((await ref.get()).data()!['value'], 10);
  });

  const migrationPath = String.fromEnvironment('MIGRATION_ARCHIVE');
  if (migrationPath.isNotEmpty) {
    test('the complete real archive round-trips without changing a single document', () async {
      final input = jsonDecode(
        await File(migrationPath).readAsString(),
      ) as Map<String, dynamic>;
      await store.importArchive(input);
      final exported = await store.exportArchive();
      expect(exported['documents'], input['documents']);
      expect(exported['user'], input['user']);
      final uid = (input['user'] as Map)['uid'] as String;
      final expected = (input['documents'] as Map).entries
          .where(
            (entry) =>
                entry.key.toString().startsWith('libraryBooks/') &&
                entry.key.toString().split('/').length == 2 &&
                (entry.value as Map)['libraryId'] == uid,
          )
          .length;
      final books = await BookRepository(database: store).watch(uid).first;
      expect(books.size, expected);
      expect(
        books.docs.every(
          (doc) => (doc.data()['title'] as String? ?? '').isNotEmpty,
        ),
        isTrue,
      );
    });
  }
}
