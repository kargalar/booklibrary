import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/spotify_music.dart';

class SpotifyMusicCard extends StatefulWidget {
  const SpotifyMusicCard({super.key, required this.url});

  final String url;

  @override
  State<SpotifyMusicCard> createState() => _SpotifyMusicCardState();
}

class _SpotifyMusicCardState extends State<SpotifyMusicCard> {
  late Future<SpotifyMusicPreview?> _preview;

  @override
  void initState() {
    super.initState();
    _preview = _loadPreview(widget.url);
  }

  @override
  void didUpdateWidget(covariant SpotifyMusicCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _preview = _loadPreview(widget.url);
    }
  }

  Future<SpotifyMusicPreview?> _loadPreview(String url) async {
    final lookup = SpotifyMusicLookup();
    try {
      return await lookup.lookup(url);
    } on Exception {
      return null;
    } finally {
      lookup.dispose();
    }
  }

  Future<void> _openSpotify() async {
    final url = SpotifyMusicLookup.normalizeUrl(widget.url);
    if (url == null) return;
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (opened || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the Spotify URL.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the Spotify URL.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SpotifyMusicPreview?>(
    future: _preview,
    builder: (context, snapshot) => _card(context, snapshot),
  );

  Widget _card(
    BuildContext context,
    AsyncSnapshot<SpotifyMusicPreview?> snapshot,
  ) {
    const background = Color(0xFF111A15);
    const accent = Color(0xFF1ED760);
    final preview = snapshot.data;
    final waiting = snapshot.connectionState == ConnectionState.waiting;
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      color: background,
      child: InkWell(
        onTap: _openSpotify,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF17271D), background],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _cover(preview?.coverUrl, accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.music_note_rounded,
                          color: accent,
                          size: 17,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'READING MUSIC',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      preview?.title ??
                          (waiting
                              ? 'Loading music details…'
                              : 'Spotify track'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (preview?.subtitle.isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(
                        preview!.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ] else if (!waiting && preview == null) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Track details are unavailable right now.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.play_arrow_rounded,
                                size: 16,
                                color: Colors.black,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Open in Spotify',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (waiting) ...[
                          const SizedBox(width: 9),
                          const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.open_in_new_rounded,
                color: Colors.white54,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover(String? url, Color accent) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      width: 82,
      height: 82,
      child: url == null
          ? ColoredBox(
              color: const Color(0xFF263B2D),
              child: Icon(Icons.graphic_eq_rounded, color: accent, size: 34),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => ColoredBox(
                color: const Color(0xFF263B2D),
                child: Icon(Icons.graphic_eq_rounded, color: accent, size: 34),
              ),
            ),
    ),
  );
}
