part of 'local_database.dart';

class Query<T> {
  Query(
    this.store,
    this.path, {
    List<bool Function(String, Map<String, dynamic>)>? filters,
    this.sortField,
    this.descending = false,
    this.maximum,
    this.start,
    this.end,
  }) : filters = filters ?? [];
  final LocalDatabase store;
  final String path;
  final List<bool Function(String, Map<String, dynamic>)> filters;
  final String? sortField;
  final bool descending;
  final int? maximum;
  final Object? start;
  final Object? end;

  Query<T> _copy({
    List<bool Function(String, Map<String, dynamic>)>? filters,
    String? sortField,
    bool? descending,
    int? maximum,
    Object? start,
    Object? end,
  }) => Query(
    store,
    path,
    filters: filters ?? this.filters,
    sortField: sortField ?? this.sortField,
    descending: descending ?? this.descending,
    maximum: maximum ?? this.maximum,
    start: start ?? this.start,
    end: end ?? this.end,
  );
  Query<T> where(
    Object field, {
    Object? isEqualTo,
    Object? arrayContains,
    List<Object?>? whereIn,
  }) => _copy(
    filters: [
      ...filters,
      (id, data) {
        final value = field == FieldPath.documentId ? id : data[field];
        if (whereIn != null) return whereIn.contains(value);
        if (arrayContains != null) {
          return value is Iterable && value.contains(arrayContains);
        }
        return value == isEqualTo;
      },
    ],
  );
  Query<T> orderBy(String field, {bool descending = false}) =>
      _copy(sortField: field, descending: descending);
  Query<T> startAt(List<Object?> values) => _copy(start: values.single);
  Query<T> endAt(List<Object?> values) => _copy(end: values.single);
  Query<T> limit(int maximum) => _copy(maximum: maximum);

  Future<QuerySnapshot<T>> get() async {
    final rows = await store.database.query(
      'documents',
      where: 'collection_path = ?',
      whereArgs: [path],
    );
    var docs = rows
        .map((row) {
          final reference = DocumentReference<T>(store, row['path'] as String);
          return QueryDocumentSnapshot<T>(
            reference,
            decodeLocalValue(jsonDecode(row['data'] as String), store) as T,
          );
        })
        .where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (!filters.every((filter) => filter(doc.id, data))) return false;
          if (sortField != null) {
            final value = data[sortField];
            if (value == null) return false;
            if (start != null && _compare(value, start) < 0) return false;
            if (end != null && _compare(value, end) > 0) return false;
          }
          return true;
        })
        .toList();
    docs.sort((a, b) {
      if (sortField == null) return a.id.compareTo(b.id);
      final result = _compare(
        (a.data() as Map)[sortField],
        (b.data() as Map)[sortField],
      );
      return (descending ? -result : result);
    });
    if (maximum != null) docs = docs.take(maximum!).toList();
    return QuerySnapshot(docs);
  }

  Stream<QuerySnapshot<T>> snapshots() => _watch(store, get);
}

int _compare(Object? first, Object? second) {
  if (first is Timestamp && second is Timestamp) return first.compareTo(second);
  if (first is num && second is num) return first.compareTo(second);
  return '$first'.compareTo('$second');
}

class CollectionReference<T> extends Query<T> {
  CollectionReference(super.store, super.path);
  String get id => p.posix.basename(path);
  DocumentReference<T> doc([String? id]) =>
      DocumentReference(store, '$path/${id ?? _newId()}');
  Future<DocumentReference<T>> add(Map<String, dynamic> data) async {
    final reference = doc();
    await reference.set(data);
    return reference;
  }
}

String _newId() {
  final random = Random.secure();
  return List.generate(
    20,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class DocumentSnapshot<T> {
  const DocumentSnapshot(this.reference, this._data);
  final DocumentReference<T> reference;
  final T? _data;
  String get id => reference.id;
  bool get exists => _data != null;
  SnapshotMetadata get metadata => const SnapshotMetadata();
  T? data() => _data;
  dynamic operator [](Object key) => (_data as Map)[key];
}

class QueryDocumentSnapshot<T> extends DocumentSnapshot<T> {
  const QueryDocumentSnapshot(super.reference, T super.data);
  @override
  T data() => super.data() as T;
}

class QuerySnapshot<T> {
  const QuerySnapshot(this.docs);
  final List<QueryDocumentSnapshot<T>> docs;
  int get size => docs.length;
  SnapshotMetadata get metadata => const SnapshotMetadata();
}

class SnapshotMetadata {
  const SnapshotMetadata();
  bool get hasPendingWrites => false;
  bool get isFromCache => false;
}

class FieldPath {
  static const documentId = '__documentId';
}

class SetOptions {
  const SetOptions({this.merge = false});
  final bool merge;
}
