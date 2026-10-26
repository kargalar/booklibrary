import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sql;

part 'local_document_query.dart';
part 'local_document_values.dart';

/// Durable document storage. All writes and read-modify-write operations use
/// SQLite transactions; streams are refreshed only after a successful commit.
class LocalDatabase {
  LocalDatabase(this.database);

  static late LocalDatabase instance;
  final sql.Database database;
  final _changes = StreamController<void>.broadcast(sync: true);

  static Future<LocalDatabase> open({String? path}) async {
    final database = await sql.openDatabase(
      path ?? p.join(await sql.getDatabasesPath(), 'booklibrary_local.db'),
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA synchronous = FULL');
      },
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE documents (path TEXT PRIMARY KEY, collection_path TEXT NOT NULL, data TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE INDEX documents_collection ON documents(collection_path)',
        );
        await db.execute(
          'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      },
    );
    return LocalDatabase(database);
  }

  CollectionReference<Map<String, dynamic>> collection(String path) =>
      CollectionReference(this, path);
  DocumentReference<Map<String, dynamic>> doc(String path) =>
      DocumentReference(this, path);
  LocalWriteBatch batch() => LocalWriteBatch(this);

  Future<T> runTransaction<T>(
    Future<T> Function(LocalTransaction) action,
  ) async {
    final result = await database.transaction((executor) async {
      final transaction = LocalTransaction(this, executor);
      final result = await action(transaction);
      await transaction._apply(executor);
      return result;
    });
    _changes.add(null);
    return result;
  }

  Future<String?> setting(String key) async {
    final rows = await database.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.firstOrNull?['value'] as String?;
  }

  /// Import and its completion marker commit together. A failed import leaves
  /// the existing database intact and can be retried using the original archive.
  Future<void> importArchive(Map<String, dynamic> archive) async {
    if (archive['schemaVersion'] != 1 ||
        archive['documents'] is! Map ||
        archive['user'] is! Map) {
      throw const FormatException('Invalid local migration archive.');
    }
    final documents = Map<String, dynamic>.from(archive['documents'] as Map);
    final user = Map<String, dynamic>.from(archive['user'] as Map);
    if (user['uid'] is! String || (user['uid'] as String).isEmpty) {
      throw const FormatException('The archive has no library identity.');
    }
    await database.transaction((txn) async {
      if ((await txn.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['migrationComplete'],
      )).isNotEmpty) {
        return;
      }
      final batch = txn.batch();
      for (final entry in documents.entries) {
        if (entry.value is! Map || entry.key.split('/').length.isOdd) {
          throw FormatException('Invalid document: ${entry.key}');
        }
        batch.insert('documents', {
          'path': entry.key,
          'collection_path': p.posix.dirname(entry.key),
          'data': jsonEncode(entry.value),
        }, conflictAlgorithm: sql.ConflictAlgorithm.abort);
      }
      batch.insert('settings', {'key': 'user', 'value': jsonEncode(user)});
      batch.insert('settings', {
        'key': 'imagePaths',
        'value': jsonEncode(archive['imagePaths'] ?? {}),
      });
      batch.insert('settings', {
        'key': 'migrationComplete',
        'value': '${documents.length}',
      });
      await batch.commit(noResult: true);
    });
    _changes.add(null);
  }

  Future<Map<String, dynamic>> exportArchive() async =>
      database.transaction((txn) async {
        final rows = await txn.query('documents');
        final user = await txn.query(
          'settings',
          where: 'key = ?',
          whereArgs: ['user'],
        );
        final images = await txn.query(
          'settings',
          where: 'key = ?',
          whereArgs: ['imagePaths'],
        );
        return {
          'schemaVersion': 1,
          'user': jsonDecode(user.single['value'] as String),
          'imagePaths': images.isEmpty
              ? <String, String>{}
              : jsonDecode(images.single['value'] as String),
          'documents': {
            for (final row in rows)
              row['path'] as String: jsonDecode(row['data'] as String),
          },
        };
      });

  Future<void> close() async {
    await _changes.close();
    await database.close();
  }
}

class DocumentReference<T> {
  const DocumentReference(this.store, this.path);
  final LocalDatabase store;
  final String path;
  String get id => p.posix.basename(path);
  CollectionReference<T> get parent =>
      CollectionReference(store, p.posix.dirname(path));
  CollectionReference<Map<String, dynamic>> collection(String name) =>
      store.collection('$path/$name');

  Future<DocumentSnapshot<T>> _read(sql.DatabaseExecutor executor) async {
    final rows = await executor.query(
      'documents',
      where: 'path = ?',
      whereArgs: [path],
    );
    return DocumentSnapshot(
      this,
      rows.isEmpty
          ? null
          : decodeLocalValue(jsonDecode(rows.single['data'] as String), store)
                as T,
    );
  }

  Future<DocumentSnapshot<T>> get() => _read(store.database);
  Stream<DocumentSnapshot<T>> snapshots() => _watch(store, get);
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    final batch = store.batch()..set(this, data, options);
    await batch.commit();
  }

  Future<void> update(Map<String, dynamic> data) async {
    final batch = store.batch()..update(this, data);
    await batch.commit();
  }

  Future<void> delete() async {
    final batch = store.batch()..delete(this);
    await batch.commit();
  }
}

class LocalWriteBatch {
  LocalWriteBatch(this.store);
  final LocalDatabase store;
  final _operations = <Future<void> Function(sql.DatabaseExecutor)>[];

  void set<T>(
    DocumentReference<T> ref,
    Map<String, dynamic> data, [
    SetOptions? options,
  ]) =>
      _write(ref, data, merge: options?.merge ?? false, requireExisting: false);
  void update<T>(DocumentReference<T> ref, Map<String, dynamic> data) =>
      _write(ref, data, merge: true, requireExisting: true);
  void delete<T>(DocumentReference<T> ref) {
    _operations.add((executor) async {
      await executor.delete(
        'documents',
        where: 'path = ?',
        whereArgs: [ref.path],
      );
    });
  }

  void _write<T>(
    DocumentReference<T> ref,
    Map<String, dynamic> data, {
    required bool merge,
    required bool requireExisting,
  }) {
    // Freeze inputs before the asynchronous commit.
    final fields = Map<String, dynamic>.from(data);
    _operations.add((executor) async {
      final current = await ref._read(executor);
      if (requireExisting && !current.exists) {
        throw StateError('Document does not exist: ${ref.path}');
      }
      final output = merge && current.exists
          ? Map<String, dynamic>.from(current.data() as Map)
          : <String, dynamic>{};
      for (final entry in fields.entries) {
        _applyField(output, entry.key.split('.'), entry.value);
      }
      await executor.insert('documents', {
        'path': ref.path,
        'collection_path': ref.parent.path,
        'data': jsonEncode(encodeLocalValue(output)),
      }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
    });
  }

  Future<void> _apply(sql.DatabaseExecutor executor) async {
    for (final operation in _operations) {
      await operation(executor);
    }
  }

  Future<void> commit() async {
    await store.database.transaction(_apply);
    store._changes.add(null);
  }
}

class LocalTransaction extends LocalWriteBatch {
  LocalTransaction(super.store, this.executor);
  final sql.DatabaseExecutor executor;
  Future<DocumentSnapshot<T>> get<T>(DocumentReference<T> ref) =>
      ref._read(executor);
}

void _applyField(Map<String, dynamic> data, List<String> path, Object? value) {
  if (path.length > 1) {
    final nested = Map<String, dynamic>.from(data[path.first] as Map? ?? {});
    _applyField(nested, path.sublist(1), value);
    data[path.first] = nested;
    return;
  }
  final key = path.single;
  switch (value) {
    case FieldValue(operation: 'delete'):
      data.remove(key);
    case FieldValue(operation: 'timestamp'):
      data[key] = Timestamp.now();
    case FieldValue(operation: 'union', values: final values):
      final items = List<dynamic>.from(data[key] as List? ?? []);
      for (final item in values) {
        if (!items.any(
          (other) =>
              jsonEncode(encodeLocalValue(other)) ==
              jsonEncode(encodeLocalValue(item)),
        )) {
          items.add(item);
        }
      }
      data[key] = items;
    default:
      data[key] = value;
  }
}

Stream<T> _watch<T>(LocalDatabase store, Future<T> Function() read) {
  late StreamController<T> controller;
  StreamSubscription<void>? subscription;
  Future<void> queue = Future<void>.value();
  void refresh() {
    queue = queue.then((_) async {
      try {
        final value = await read();
        if (!controller.isClosed) controller.add(value);
      } catch (error, trace) {
        if (!controller.isClosed) controller.addError(error, trace);
      }
    });
  }

  controller = StreamController<T>(
    onListen: () {
      subscription = store._changes.stream.listen((_) => refresh());
      refresh();
    },
    onCancel: () async {
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
