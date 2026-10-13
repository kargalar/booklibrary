import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalBookChange {
  const LocalBookChange({
    required this.id,
    required this.isNew,
    required this.data,
    this.error,
  });

  factory LocalBookChange.fromJson(Map<String, dynamic> json) {
    return LocalBookChange(
      id: json['id'] as String,
      isNew: json['isNew'] == true,
      data: Map<String, dynamic>.from(json['data'] as Map),
      error: json['error'] as String?,
    );
  }

  final String id;
  final bool isNew;
  final Map<String, dynamic> data;
  final String? error;

  LocalBookChange copyWith({String? error}) =>
      LocalBookChange(id: id, isNew: isNew, data: data, error: error);

  Map<String, dynamic> toJson() => {
    'id': id,
    'isNew': isNew,
    'data': data,
    ...?error == null ? null : {'error': error},
  };
}

class LocalBookStore {
  LocalBookStore(this.uid);

  final String uid;
  Future<void> _queue = Future<void>.value();

  Future<List<LocalBookChange>> load() => _serial(() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (value) =>
                LocalBookChange.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(growable: false);
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  });

  Future<void> save(LocalBookChange change) => _serial(() async {
    final changes = await _read();
    final index = changes.indexWhere((item) => item.id == change.id);
    if (index == -1) {
      changes.add(change);
    } else {
      changes[index] = change;
    }
    await _write(changes);
  });

  Future<bool> remove(String id, {LocalBookChange? expected}) =>
      _serial(() async {
        final changes = await _read();
        final index = changes.indexWhere((item) => item.id == id);
        if (index == -1 ||
            expected != null &&
                jsonEncode(changes[index].toJson()) !=
                    jsonEncode(expected.toJson())) {
          return false;
        }
        changes.removeAt(index);
        await _write(changes);
        return true;
      });

  Future<File> _file() async {
    final root = await getApplicationDocumentsDirectory();
    return File(p.join(root.path, 'local_books', '$uid.json'));
  }

  Future<List<LocalBookChange>> _read() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (value) =>
                LocalBookChange.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList();
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  Future<void> _write(List<LocalBookChange> changes) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(changes.map((change) => change.toJson()).toList()),
      flush: true,
    );
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }
}
