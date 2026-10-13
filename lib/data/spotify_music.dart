import 'dart:convert';

import 'package:http/http.dart' as http;

class SpotifyMusicPreview {
  const SpotifyMusicPreview({
    required this.url,
    required this.title,
    this.artist,
    this.album,
    this.coverUrl,
  });

  final String url;
  final String title;
  final String? artist;
  final String? album;
  final String? coverUrl;

  String get subtitle => [
    if (artist?.isNotEmpty == true) artist!,
    if (album?.isNotEmpty == true) album!,
  ].join(' \u{00B7} ');
}

class SpotifyMusicLookup {
  SpotifyMusicLookup({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  static const _requestTimeout = Duration(seconds: 8);
  static const _musicTypes = {'track', 'album', 'artist', 'playlist'};

  static final _metaTagPattern = RegExp(r'<meta\b[^>]*>', caseSensitive: false);
  static final _attributePattern = RegExp(
    r'''([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
    caseSensitive: false,
  );

  final http.Client _client;
  final bool _ownsClient;

  static String? normalizeUrl(String value) {
    final input = value.trim();
    if (input.isEmpty) return null;

    if (input.startsWith('spotify:')) {
      final parts = input.split(':');
      if (parts.length != 3 || !_musicTypes.contains(parts[1])) return null;
      if (parts[2].isEmpty) return null;
      return 'https://open.spotify.com/${parts[1]}/${parts[2]}';
    }

    final uri = Uri.tryParse(input);
    if (uri == null || uri.scheme.toLowerCase() != 'https') return null;

    final host = uri.host.toLowerCase();
    if (host == 'spotify.link') {
      if (uri.pathSegments.isEmpty || uri.pathSegments.first.isEmpty) {
        return null;
      }
      return uri.replace(queryParameters: const <String, String>{}).toString();
    }
    if (host != 'open.spotify.com') return null;

    final segments = uri.pathSegments;
    final typeIndex = segments.indexWhere(_musicTypes.contains);
    if (typeIndex == -1 || typeIndex + 1 >= segments.length) return null;
    if (segments[typeIndex + 1].isEmpty) return null;

    final itemType = segments[typeIndex];
    final itemId = segments[typeIndex + 1];
    return Uri.https('open.spotify.com', '/$itemType/$itemId').toString();
  }

  static bool isValidUrl(String value) => normalizeUrl(value) != null;

  Future<SpotifyMusicPreview> lookup(String value) async {
    final url = normalizeUrl(value);
    if (url == null) {
      throw const FormatException(
        'Ge\u{00E7}erli bir Spotify m\u{00FC}zik ba\u{011F}lant\u{0131}s\u{0131} girin.',
      );
    }

    final uri = Uri.https('open.spotify.com', '/oembed', {'url': url});
    final response = await _client.get(uri).timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw const FormatException(
        'Spotify par\u{00E7}a bilgisi al\u{0131}namad\u{0131}.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Spotify yan\u{0131}t\u{0131} okunamad\u{0131}.',
      );
    }

    final title = decoded['title'];
    if (title is! String || title.trim().isEmpty) {
      throw const FormatException(
        'Spotify par\u{00E7}a ad\u{0131} bulunamad\u{0131}.',
      );
    }

    final pageMetadata = await _lookupPageMetadata(url);
    final thumbnail = decoded['thumbnail_url'];

    return SpotifyMusicPreview(
      url: url,
      title: title.trim(),
      artist: pageMetadata.artist,
      album: pageMetadata.album,
      coverUrl: thumbnail is String && thumbnail.startsWith('https://')
          ? thumbnail
          : null,
    );
  }

  Future<({String? artist, String? album})> _lookupPageMetadata(
    String url,
  ) async {
    try {
      final response = await _client
          .get(Uri.parse(url), headers: const {'User-Agent': 'Mozilla/5.0'})
          .timeout(_requestTimeout);
      if (response.statusCode != 200) return (artist: null, album: null);

      final description = _openGraphDescription(response.body);
      if (description == null) return (artist: null, album: null);

      final parts = description
          .split(' \u{00B7} ')
          .map((part) => part.trim())
          .toList();
      if (parts.length < 3 || !_describesMusic(parts[2])) {
        return (artist: null, album: null);
      }
      return (
        artist: parts.first.isEmpty ? null : parts.first,
        album: parts[1].isEmpty ? null : parts[1],
      );
    } on Exception {
      return (artist: null, album: null);
    }
  }

  String? _openGraphDescription(String html) {
    for (final tag in _metaTagPattern.allMatches(html)) {
      final attributes = <String, String>{};
      for (final attribute in _attributePattern.allMatches(tag.group(0)!)) {
        attributes[attribute.group(1)!.toLowerCase()] =
            attribute.group(2) ?? attribute.group(3) ?? '';
      }
      if (attributes['property'] == 'og:description') {
        return _decodeHtmlEntities(attributes['content'] ?? '');
      }
    }
    return null;
  }

  bool _describesMusic(String value) {
    final kind = value.toLowerCase();
    return kind.contains('song') ||
        kind.contains('track') ||
        kind.contains('\u{015F}ark\u{0131}') ||
        kind.contains('album') ||
        kind.contains('alb\u{00FC}m');
  }

  String _decodeHtmlEntities(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
