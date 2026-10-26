import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'local_database.dart';
import 'local_identity.dart';
import 'local_images.dart';

class LocalBootstrap {
  static const archiveName = 'local_migration_input.json';

  static Future<void> initialize() async {
    final database = await LocalDatabase.open();
    LocalDatabase.instance = database;
    if (await database.setting('migrationComplete') == null) {
      final root = await getApplicationDocumentsDirectory();
      final external = await getExternalStorageDirectory();
      final candidates = [
        File(p.join(root.path, archiveName)),
        if (external != null) File(p.join(external.path, archiveName)),
      ];
      File? source;
      for (final file in candidates) {
        if (await file.exists()) {
          source = file;
          break;
        }
      }
      if (source != null) {
        final archive =
            jsonDecode(await source.readAsString()) as Map<String, dynamic>;
        await _restoreFiles(archive, root, source.parent);
        await database.importArchive(archive);
        final stored = await database.exportArchive();
        final expected = archive['documents'] as Map;
        final actual = stored['documents'] as Map;
        if (actual.length != expected.length ||
            expected.keys.any(
              (key) => jsonEncode(expected[key]) != jsonEncode(actual[key]),
            )) {
          throw StateError(
            'Local migration verification failed. Original archives are preserved.',
          );
        }
        debugPrint(
          'LOCAL_IMPORT_VERIFIED documents=${actual.length} files=${(archive['files'] as List? ?? []).length}',
        );
      } else {
        // An existing installation must never silently open an empty library.
        final nativeRoot = root.parent;
        final oldAccount = Directory(p.join(nativeRoot.path, 'shared_prefs'));
        final hasLegacyData =
            await File(p.join(root.path, 'phone_migration_backup.json'))
                .exists() ||
            await oldAccount.exists() &&
                await oldAccount.list().any(
                  (entry) => p
                      .basename(entry.path)
                      .contains('com.google.firebase.auth'),
                );
        if (hasLegacyData) {
          throw StateError(
            'Your existing library is safe. Complete the local data import before opening it.',
          );
        }
        await database.importArchive({
          'schemaVersion': 1,
          'user': {'uid': 'local', 'displayName': 'Reader'},
          'documents': {
            'users/local': {
              'displayName': 'Reader',
              'username': 'reader',
              'libraryName': 'My library',
            },
          },
        });
      }
    }
    await LocalIdentity.instance.load(database);
    await LocalImages.load(
      database,
      (await getApplicationDocumentsDirectory()).path,
    );
    final integrity = await database.database.rawQuery(
      'PRAGMA integrity_check',
    );
    if (integrity.single.values.single != 'ok') {
      throw StateError('The local database integrity check failed.');
    }
    final counts = await database.database.rawQuery(
      'SELECT collection_path, COUNT(*) AS count FROM documents GROUP BY collection_path',
    );
    debugPrint('LOCAL_LIBRARY_READY ${jsonEncode(counts)}');
  }

  static Future<void> _restoreFiles(
    Map<String, dynamic> archive,
    Directory root,
    Directory staging,
  ) async {
    for (final entry in (archive['files'] as List? ?? const [])) {
      final file = Map<String, dynamic>.from(entry as Map);
      final relative = file['name'] as String;
      final normalized = p.posix.normalize(relative);
      if (normalized != relative ||
          p.posix.isAbsolute(relative) ||
          relative.split('/').contains('..') ||
          relative.contains('\\')) {
        throw const FormatException('Unsafe migration file path.');
      }
      final source = File(
        p.join(staging.path, 'local_migration_files', relative),
      );
      final target = File(p.join(root.path, 'cloud_archive', relative));
      final expectedLength = file['bytes'] as int;
      final expectedHash = file['sha256'] as String;
      Future<bool> valid(File candidate) async =>
          await candidate.exists() &&
          await candidate.length() == expectedLength &&
          (await sha256.bind(candidate.openRead()).first).toString() ==
              expectedHash;
      if (await valid(target)) continue;
      if (!await valid(source)) {
        throw FileSystemException(
          'Migration file is missing or incomplete.',
          relative,
        );
      }
      await target.parent.create(recursive: true);
      final pending = File('${target.path}.importing');
      await source.copy(pending.path);
      if (!await valid(pending)) {
        throw FileSystemException(
          'Migration copy validation failed.',
          relative,
        );
      }
      if (await target.exists()) {
        throw FileSystemException(
          'An existing archive file differs; it has been preserved.',
          relative,
        );
      }
      await pending.rename(target.path);
    }
  }
}
