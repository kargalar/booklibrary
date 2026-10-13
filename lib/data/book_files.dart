import 'dart:io';

import 'package:epubx_kuebiko/epubx_kuebiko.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BookFiles {
  static const maxBytes = 100 * 1024 * 1024;

  static Future<void> delete(String uid, String id) async {
    final root = await getApplicationDocumentsDirectory();
    final preferences = await SharedPreferences.getInstance();
    for (final format in const ['pdf', 'epub']) {
      final file = File(p.join(root.path, 'books', uid, '$id.$format'));
      if (await file.exists()) await file.delete();
      await preferences.remove('$uid.$id.$format.position');
      await preferences.remove('$uid.$id.$format.offset');
      try {
        await _remote(uid, id, format).delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') rethrow;
      }
    }
    try {
      await _remote(uid, id).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }

  static Future<File?> find(String uid, String id, {String? extension}) async {
    final root = await getApplicationDocumentsDirectory();
    final formats = extension == null
        ? const ['pdf', 'epub']
        : [extension.toLowerCase().replaceFirst('.', '')];
    for (final format in formats) {
      final file = File(p.join(root.path, 'books', uid, '$id.$format'));
      if (await file.exists()) return file;
    }
    return null;
  }

  static Future<File?> import(
    String uid,
    String id, {
    void Function(double progress)? onProgress,
  }) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'epub'],
    );
    if (result.isEmpty) return null;
    final sourcePath = result.single.path;
    if (sourcePath == null) {
      throw const FormatException('The selected file is not accessible.');
    }
    return save(uid, id, File(sourcePath), onProgress: onProgress);
  }

  static Future<File?> pick() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'epub'],
    );
    if (result.isEmpty) return null;
    final sourcePath = result.single.path;
    if (sourcePath == null) {
      throw const FormatException('The selected file is not accessible.');
    }
    final source = File(sourcePath);
    await _validate(source);
    return source;
  }

  static Reference _remote(String uid, String id, [String? format]) =>
      FirebaseStorage.instance.ref(
        'books/$uid/$id/reading${format == null ? '' : '.$format'}',
      );

  static Future<File?> download({
    required String localUid,
    required String ownerId,
    required String id,
    required String extension,
    void Function(double progress)? onProgress,
  }) async {
    final format = extension.toLowerCase().replaceFirst('.', '');
    if (!{'pdf', 'epub'}.contains(format)) return null;
    final root = await getApplicationDocumentsDirectory();
    final target = File(p.join(root.path, 'books', localUid, '$id.$format'));
    await target.parent.create(recursive: true);
    try {
      try {
        await _downloadRemote(_remote(ownerId, id, format), target, onProgress);
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') rethrow;
        await _downloadRemote(_remote(ownerId, id), target, onProgress);
      }
      final other = File(
        p.join(target.parent.path, '$id${format == 'pdf' ? '.epub' : '.pdf'}'),
      );
      if (await other.exists()) await other.delete();
      return target;
    } on FirebaseException catch (error) {
      if (await target.exists()) await target.delete();
      if (error.code == 'object-not-found') return null;
      rethrow;
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  static Future<void> upload(
    String uid,
    String id,
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    final extension = p.extension(file.path).toLowerCase();
    if (!['.pdf', '.epub'].contains(extension)) {
      throw const FormatException('Only PDF or EPUB files can be uploaded.');
    }
    final format = extension.substring(1);
    final task = _remote(uid, id, format).putFile(
      file,
      SettableMetadata(
        contentType: extension == '.pdf'
            ? 'application/pdf'
            : 'application/epub+zip',
      ),
    );
    await for (final snapshot in task.snapshotEvents) {
      if (snapshot.totalBytes > 0) {
        onProgress?.call(
          (snapshot.bytesTransferred / snapshot.totalBytes)
              .clamp(0, 1)
              .toDouble(),
        );
      }
    }
    onProgress?.call(1);
  }

  static Future<File> save(
    String uid,
    String id,
    File source, {
    void Function(double progress)? onProgress,
  }) async {
    final target = await saveLocal(uid, id, source);
    await upload(uid, id, target, onProgress: onProgress);
    return target;
  }

  static Future<File> saveLocal(String uid, String id, File source) async {
    await _validate(source);
    final extension = p.extension(source.path).toLowerCase();
    final bytes = await source.readAsBytes();
    final root = await getApplicationDocumentsDirectory();
    final target = File(p.join(root.path, 'books', uid, '$id$extension'));
    await target.parent.create(recursive: true);
    final pending = File('${target.path}.tmp');
    await pending.writeAsBytes(bytes, flush: true);
    final backup = File('${target.path}.bak');
    var replaced = false;
    if (await backup.exists()) await backup.delete();
    if (await target.exists()) {
      await target.rename(backup.path);
      replaced = true;
    }
    try {
      await pending.rename(target.path);
    } catch (_) {
      if (replaced && await backup.exists()) {
        if (await target.exists()) await target.delete();
        await backup.rename(target.path);
      }
      rethrow;
    }
    if (replaced && await backup.exists()) {
      await backup.delete();
    }
    final prefs = await SharedPreferences.getInstance();
    final key = '$uid.$id.${extension.substring(1)}';
    await prefs.remove('$key.position');
    await prefs.remove('$key.offset');
    final other = File(
      p.join(
        target.parent.path,
        '$id${extension == '.pdf' ? '.epub' : '.pdf'}',
      ),
    );
    if (await other.exists()) await other.delete();
    return target;
  }

  static Future<void> _validate(File source) async {
    final extension = p.extension(source.path).toLowerCase();
    if (!['.pdf', '.epub'].contains(extension)) {
      throw const FormatException('Select a PDF or EPUB file.');
    }
    if (await source.length() > maxBytes) {
      throw const FormatException('The file cannot exceed 100 MB.');
    }
    final bytes = await source.readAsBytes();
    if (extension == '.epub') {
      readingOrder(await EpubReader.readBook(bytes));
    } else if (bytes.length < 5 ||
        String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw const FormatException('This is not a valid PDF file.');
    } else {
      await pdfrxFlutterInitialize();
      final document = await PdfDocument.openFile(source.path);
      await document.dispose();
    }
  }

  static Future<void> _downloadRemote(
    Reference remote,
    File target,
    void Function(double progress)? onProgress,
  ) async {
    final task = remote.writeToFile(target);
    await for (final snapshot in task.snapshotEvents) {
      if (snapshot.totalBytes > 0) {
        onProgress?.call(
          (snapshot.bytesTransferred / snapshot.totalBytes)
              .clamp(0, 1)
              .toDouble(),
        );
      }
    }
    onProgress?.call(1);
  }
}

List<EpubTextContentFile> readingOrder(EpubBook book) {
  final html = book.Content?.Html ?? {};
  final manifest = {
    for (final item
        in book.Schema?.Package?.Manifest?.Items ?? <EpubManifestItem>[])
      item.Id: item.Href,
  };
  final ordered = <EpubTextContentFile>[];
  for (final item
      in book.Schema?.Package?.Spine?.Items ?? <EpubSpineItemRef>[]) {
    final href = manifest[item.IdRef];
    final content = html[href] ?? html[Uri.decodeFull(href ?? '')];
    if (content != null && item.IsLinear != false) ordered.add(content);
  }
  if (ordered.isEmpty) ordered.addAll(html.values);
  if (ordered.isEmpty) {
    throw const FormatException('No readable chapters were found in the EPUB.');
  }
  return ordered;
}
