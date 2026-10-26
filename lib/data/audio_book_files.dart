import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioBookFiles {
  static const extensions = ['mp3', 'm4a', 'm4b', 'wav', 'ogg', 'flac'];
  static const maxBytes = 2 * 1024 * 1024 * 1024;

  static Future<void> delete(String uid, String id) async {
    final directory = await _directory(uid, id);
    if (await directory.exists()) await directory.delete(recursive: true);
    final preferences = await SharedPreferences.getInstance();
    final key = '$uid.$id.audio.file';
    final name = preferences.getString(key);
    await preferences.remove(key);
    if (name != null && p.basename(name) == name) {
      await preferences.remove('$uid.$id.audio.$name.position');
      await preferences.remove('$uid.$id.audio.$name.speed');
    }
  }

  static Future<Directory> _directory(String uid, String id) async => Directory(
    p.join(
      (await getApplicationDocumentsDirectory()).path,
      'books',
      uid,
      'audio',
      id,
    ),
  );

  static Future<File?> find(String uid, String id) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('$uid.$id.audio.file');
    if (name == null) {
      final root = await getApplicationDocumentsDirectory();
      final archived = File(
        p.join(root.path, 'cloud_archive', 'books', uid, id, 'audio'),
      );
      return await archived.exists() ? archived : null;
    }
    if (p.basename(name) != name) return null;
    final file = File(p.join((await _directory(uid, id)).path, name));
    return await file.exists() ? file : null;
  }

  static Future<File?> pick() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (result.isEmpty) return null;
    final path = result.single.path;
    if (path == null) {
      throw const FormatException('The audio file is not accessible.');
    }
    final file = File(path);
    final size = await file.length();
    if (size == 0 ||
        size > maxBytes ||
        !extensions.contains(
          p.extension(path).replaceFirst('.', '').toLowerCase(),
        )) {
      throw const FormatException('Select a valid audio file (up to 2 GB).');
    }
    final player = AudioPlayer();
    try {
      await player.setSource(DeviceFileSource(path));
      final duration = await player.getDuration();
      if (duration == null || duration <= Duration.zero) {
        throw const FormatException('The audio file could not be processed.');
      }
    } finally {
      await player.dispose();
    }
    return file;
  }

  static Future<File?> download({
    required String localUid,
    required String ownerId,
    required String id,
    required String extension,
    void Function(double progress)? onProgress,
  }) async {
    return await find(localUid, id) ?? await find(ownerId, id);
  }

  static Future<File> save(
    String uid,
    String id,
    File source, {
    void Function(double progress)? onProgress,
  }) async {
    final target = await saveLocal(uid, id, source);
    onProgress?.call(1);
    return target;
  }

  static Future<File> saveLocal(String uid, String id, File source) async {
    final directory = await _directory(uid, id);
    await directory.create(recursive: true);
    final previous = await find(uid, id);
    final target = File(
      p.join(
        directory.path,
        '${DateTime.now().microsecondsSinceEpoch}${p.extension(source.path).toLowerCase()}',
      ),
    );
    try {
      await source.copy(target.path);
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        '$uid.$id.audio.file',
        p.basename(target.path),
      )) {
        throw const FileSystemException('The audio file could not be saved.');
      }
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
    // The replacement is committed before removing the previous local copy.
    if (previous != null) {
      try {
        await previous.delete();
      } on FileSystemException {
        /* Keep the saved replacement. */
      }
    }
    return target;
  }
}
