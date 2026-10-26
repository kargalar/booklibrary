import 'dart:convert';

import 'package:path/path.dart' as p;

import 'local_database.dart';

abstract final class LocalImages {
  static Map<String, String> _paths = const {};

  static Future<void> load(LocalDatabase database, String documentsPath) async {
    final serialized = await database.setting('imagePaths');
    if (serialized == null) return;
    final mappings = Map<String, String>.from(jsonDecode(serialized) as Map);
    _paths = mappings.map(
      (url, relative) =>
          MapEntry(url, p.join(documentsPath, 'cloud_archive', relative)),
    );
  }

  static String? resolve(String? source) => _paths[source] ?? source;
}
