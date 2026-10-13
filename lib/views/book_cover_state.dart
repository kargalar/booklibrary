part of 'library_page.dart';

class _BookCoverState extends State<_BookCover> {
  Future<File?>? cachedCover;

  @override
  void initState() {
    super.initState();
    _updateCache();
  }

  @override
  void didUpdateWidget(covariant _BookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl) _updateCache();
  }

  void _updateCache() {
    final url = widget.coverUrl;
    cachedCover = url == null || url.isEmpty
        ? null
        : _coverCache.putIfAbsent(url, () => _cacheCover(url));
  }

  @override
  Widget build(BuildContext context) {
    final localPath = widget.localCoverPath?.isNotEmpty == true
        ? widget.localCoverPath
        : widget.coverPath?.startsWith('http') == true
        ? null
        : widget.coverPath;
    final remotePath = widget.coverStorageUrl?.startsWith('http') == true
        ? widget.coverStorageUrl
        : widget.coverPath?.startsWith('http') == true
        ? widget.coverPath
        : null;
    if (localPath?.isNotEmpty == true) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Image.file(
          File(localPath!),
          fit: widget.fit,
          cacheWidth: _coverCacheWidth,
          cacheHeight: _coverCacheHeight,
          semanticLabel: widget.title,
          errorBuilder: (_, _, _) => remotePath == null
              ? _networkCover(context)
              : _networkImage(context, remotePath),
        ),
      );
    }
    return remotePath == null
        ? _networkCover(context)
        : _networkImage(context, remotePath);
  }

  Widget _networkCover(BuildContext context) {
    final future = cachedCover;
    if (future == null) return _fallback(context);
    return FutureBuilder<File?>(
      future: future,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: Image.file(
              file,
              fit: widget.fit,
              cacheWidth: _coverCacheWidth,
              cacheHeight: _coverCacheHeight,
              semanticLabel: widget.title,
              errorBuilder: (_, _, _) => _networkImage(context),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _coverPlaceholder(context);
        }
        return _networkImage(context);
      },
    );
  }

  Widget _networkImage(BuildContext context, [String? url]) {
    final source = url ?? widget.coverUrl;
    if (source?.isNotEmpty != true) return _fallback(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Image.network(
        source!,
        fit: widget.fit,
        cacheWidth: _coverCacheWidth,
        cacheHeight: _coverCacheHeight,
        semanticLabel: widget.title,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _coverPlaceholder(context),
        errorBuilder: (_, _, _) => _fallback(context),
      ),
    );
  }

  Widget _coverPlaceholder(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(widget.borderRadius),
    ),
  );

  Widget _fallback(BuildContext context) {
    final title = widget.title;
    final index =
        title.codeUnits.fold<int>(0, (total, char) => total + char) %
        _coverColors.length;
    final color = _coverColors[index];
    final letter = title.trim().isEmpty ? '?' : title.trim()[0].toUpperCase();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, Color.lerp(color, Colors.black, .22)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            bottom: -22,
            child: Icon(
              Icons.auto_stories_rounded,
              size: 116,
              color: Colors.white.withAlpha(24),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_stories_rounded, color: Colors.white70),
                const Spacer(),
                Text(
                  letter,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    height: .9,
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  width: 34,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white70,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
