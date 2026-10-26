import 'local_database.dart';

class LibraryBookSnapshot {
  const LibraryBookSnapshot(this._source, this.docs);

  final QuerySnapshot<Map<String, dynamic>> _source;
  final List<LibraryBookDocument> docs;

  SnapshotMetadata get metadata => _source.metadata;

  int get size => docs.length;
}

class LibraryBookDocument {
  const LibraryBookDocument(this._source, this._data) : _id = null;

  const LibraryBookDocument.local(this._id, this._data) : _source = null;

  final DocumentSnapshot<Map<String, dynamic>>? _source;
  final String? _id;
  final Map<String, dynamic> _data;

  String get id => _source?.id ?? _id!;

  DocumentReference<Map<String, dynamic>> get reference => _source!.reference;

  SnapshotMetadata get metadata => _source!.metadata;

  bool get exists => true;

  Map<String, dynamic> data() => _data;

  dynamic get(Object field) => _data[field];

  dynamic operator [](Object field) => _data[field];
}
