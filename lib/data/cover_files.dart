import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

class CoverFiles {
  static const maxBytes = 10 * 1024 * 1024;
  static const _bucketCacheControl = 'public,max-age=31536000';

  static Reference _remote(String uid, String id) =>
      FirebaseStorage.instance.ref('covers/$uid/$id.jpg');

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
    final reference = _remote(uid, id);
    try {
      await reference.putData(
        bytes,
        SettableMetadata(
          contentType: contentType,
          cacheControl: _bucketCacheControl,
          customMetadata: {
            ...?sourceUrl == null ? null : {'sourceCoverUrl': sourceUrl},
          },
        ),
      );
      return await reference.getDownloadURL();
    } catch (_) {
      try {
        await reference.delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') rethrow;
      }
      rethrow;
    }
  }

  static Future<void> delete(String uid, String id) async {
    try {
      await _remote(uid, id).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }
}
