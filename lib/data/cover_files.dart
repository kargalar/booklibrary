import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class CoverFiles {
  static const maxBytes = 10 * 1024 * 1024;

  static Future<String> saveFromUrl(
    String uid,
    String id,
    String sourceUrl,
  ) async {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException('The cover image URL is invalid.');
    }

    final response = await http
        .get(uri, headers: {'Accept': 'image/*'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        response.bodyBytes.isEmpty) {
      throw const FormatException('The cover image could not be downloaded.');
    }

    final contentType = response.headers['content-type']
        ?.split(';')
        .first
        .trim();
    if (contentType != null && !contentType.startsWith('image/')) {
      throw const FormatException(
        'The API did not return a valid cover image.',
      );
    }

    return _saveBytes(
      uid,
      id,
      response.bodyBytes,
      contentType: contentType?.isNotEmpty == true
          ? contentType!
          : 'image/jpeg',
      sourceUrl: sourceUrl,
    );
  }

  static Future<String> saveFromFile(String uid, String id, File source) async {
    final bytes = await source.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException(
        'The cover image is empty or exceeds the 10 MB limit.',
      );
    }
    return _saveBytes(uid, id, bytes, contentType: 'image/jpeg');
  }

  static Future<String> _saveBytes(
    String uid,
    String id,
    Uint8List bytes, {
    required String contentType,
    String? sourceUrl,
  }) async {
    // Byte-preserving optimization: JPEG re-encoding is lossy even at quality 100.
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException(
        'The cover image is empty or exceeds the 10 MB limit.',
      );
    }
    final root = await getApplicationDocumentsDirectory();
    final target = File(
      p.join(
        root.path,
        'covers',
        '${uid}_${id}_${DateTime.now().microsecondsSinceEpoch}.jpg',
      ),
    );
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  // Existing cover files may be referenced by another imported record.
  // They are retained until an explicit archive cleanup is requested.
  static Future<void> delete(String uid, String id) async {}
}
