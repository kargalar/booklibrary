part of 'library_page.dart';

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.doc,
    required this.busy,
    required this.compact,
    required this.canManage,
    required this.publisherCount,
    required this.ratingCount,
    required this.ratingAverage,
    this.myRating,
    this.fileFuture,
    this.audioFuture,
    this.hasRemoteFile = false,
    this.hasRemoteAudio = false,
    this.loading = false,
    this.audioLoading = false,
    required this.onTap,
    required this.onLongPress,
    required this.onRead,
    this.onEdit,
    this.onDelete,
    this.onMoveToLibraries,
    this.onListen,
  });
  final LibraryBookDocument doc;
  final bool busy;
  final bool compact;
  final bool canManage;
  final int publisherCount;
  final int ratingCount;
  final double? ratingAverage;
  final int? myRating;
  final Future<File?>? fileFuture;
  final Future<File?>? audioFuture;
  final bool hasRemoteFile;
  final bool hasRemoteAudio;
  final bool loading;
  final bool audioLoading;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRead;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onMoveToLibraries;
  final VoidCallback? onListen;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    return _render(context, data);
  }

  Widget _render(BuildContext context, Map<String, dynamic> data) {
    final scheme = Theme.of(context).colorScheme;
    final title = data['title'] as String? ?? 'untitled book';
    final author = data['author'] as String? ?? '';
    final wishlist = data['wishlist'] == true;
    final notesCount = _entryCount(data['notes']);
    final quotesCount = _entryCount(data['quotes']);
    final progress = (data['readingProgress'] as num?)?.toDouble() ?? 0;
    final borrower = hasBorrower(data) ? data['borrower'] as String : null;
    final loanLabel = borrower == null
        ? null
        : 'With $borrower for ${loanDays(data)} days';
    final overdue = isOverdue(data, DateTime.now());
    final bookStatus = canonicalBookStatus(data['status']);
    final inLibrary = isInAnyLibrary(data);
    final localOnly =
        data['syncStatus'] == 'pending' || data['syncStatus'] == 'failed';
    final syncing = data['syncStatus'] == 'pending';
    final syncFailed = data['syncStatus'] == 'failed';
    final statusLabel = localOnly
        ? syncFailed
              ? 'Could not upload to cloud'
              : 'Uploading to cloud'
        : wishlist
        ? 'purchase list'
        : overdue
        ? 'Overdue · $loanLabel'
        : borrower != null
        ? 'On loan · $loanLabel'
        : !inLibrary
        ? 'Other · ${bookStatusLabel(bookStatus)}'
        : null;
    final statusIcon = localOnly
        ? Icons.cloud_off_rounded
        : wishlist
        ? Icons.shopping_cart_rounded
        : overdue
        ? Icons.warning_amber_rounded
        : borrower != null
        ? Icons.swap_horiz_rounded
        : switch (bookStatus) {
            readStatus => Icons.check_circle_rounded,
            readingStatus => Icons.menu_book_rounded,
            null => Icons.remove_circle_outline_rounded,
            _ => Icons.bookmark_border_rounded,
          };
    final statusColor = localOnly
        ? syncFailed
              ? scheme.error
              : scheme.tertiary
        : wishlist || overdue || borrower != null
        ? null
        : _bookStatusColor(bookStatus);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withAlpha(90)),
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: busy ? null : onTap,
            onLongPress: canManage && !busy ? onLongPress : null,
            onSecondaryTapUp:
                busy ||
                    (onEdit == null &&
                        onDelete == null &&
                        onMoveToLibraries == null)
                ? null
                : (details) =>
                      _showContextMenu(context, details.globalPosition),
            child: compact
                ? _compactLayout(
                    context,
                    data,
                    title,
                    author,
                    overdue,
                    progress,
                    notesCount: notesCount,
                    quotesCount: quotesCount,
                    bookStatus: bookStatus,
                    isBorrowed: borrower != null,
                    loanLabel: loanLabel,
                    statusColor: statusColor,
                  )
                : _editorialLayout(
                    context,
                    data,
                    title,
                    author,
                    statusLabel,
                    statusIcon,
                    overdue,
                    notesCount,
                    quotesCount,
                    progress,
                    statusColor: statusColor,
                  ),
          ),
          if (syncing)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        MediaQuery.sizeOf(context).width - position.dx,
        MediaQuery.sizeOf(context).height - position.dy,
      ),
      items: [
        if (onEdit != null)
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (onDelete != null)
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        if (onMoveToLibraries != null)
          const PopupMenuItem(
            value: 'moveToLibraries',
            child: Text('Move to libraries'),
          ),
      ],
    );
    switch (action) {
      case 'edit':
        await onEdit?.call();
      case 'delete':
        await onDelete?.call();
      case 'moveToLibraries':
        await onMoveToLibraries?.call();
    }
  }

  Widget _compactLayout(
    BuildContext context,
    Map<String, dynamic> data,
    String title,
    String author,
    bool overdue,
    double progress, {
    required int notesCount,
    required int quotesCount,
    required String? bookStatus,
    required bool isBorrowed,
    required String? loanLabel,
    Color? statusColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final wishlist = data['wishlist'] == true;
    final localOnly =
        data['syncStatus'] == 'pending' || data['syncStatus'] == 'failed';
    final syncFailed = data['syncStatus'] == 'failed';
    final statusColorValue = statusColor ?? _bookStatusColor(bookStatus);
    return Padding(
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: .68,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _BookCover(
                  title: title,
                  coverPath: data['coverPath'] as String?,
                  coverUrl: data['coverUrl'] as String?,
                  coverStorageUrl: data['coverStorageUrl'] as String?,
                  localCoverPath: data['legacyCoverPath'] as String?,
                  borderRadius: 10,
                ),
                Positioned(
                  left: 7,
                  right: 7,
                  bottom: 7,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (ratingCount > 0)
                        _coverCount(
                          Icons.star_rounded,
                          '${ratingAverage!.toStringAsFixed(1)} ($ratingCount)',
                          'Average score and number of people scoring',
                        ),
                      if (notesCount > 0)
                        _coverCount(
                          Icons.note_alt_outlined,
                          notesCount,
                          'Number of notes',
                        ),
                      if (quotesCount > 0)
                        _coverCount(
                          Icons.format_quote_rounded,
                          quotesCount,
                          'Number of citations',
                        ),
                    ],
                  ),
                ),
                Positioned(
                  top: 7,
                  right: 7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _coverSignal(
                        localOnly
                            ? Icons.cloud_off_rounded
                            : wishlist
                            ? Icons.shopping_cart_rounded
                            : switch (bookStatus) {
                                readStatus => Icons.check_circle_rounded,
                                readingStatus => Icons.menu_book_rounded,
                                null => Icons.remove_circle_outline_rounded,
                                _ => Icons.bookmark_border_rounded,
                              },
                        localOnly
                            ? syncFailed
                                  ? scheme.error
                                  : scheme.tertiary
                            : wishlist
                            ? scheme.secondary
                            : statusColorValue,
                        localOnly
                            ? syncFailed
                                  ? 'Failed to upload to cloud · Try again from details'
                                  : 'Saved on this device · Uploading to the cloud'
                            : wishlist
                            ? 'wish list'
                            : bookStatusLabel(bookStatus),
                      ),
                      if (isBorrowed) ...[
                        const SizedBox(width: 4),
                        _coverSignal(
                          overdue
                              ? Icons.warning_amber_rounded
                              : Icons.swap_horiz_rounded,
                          overdue ? scheme.error : scheme.tertiary,
                          overdue
                              ? 'Overdue · ${loanLabel ?? 'On loan'}'
                              : loanLabel ?? 'on loan',
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            author.isEmpty ? 'Author not specified' : author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
          ),
          if (bookStatus == readingStatus) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 12, color: scheme.primary),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    'Reading for ${readingDays(data)} days',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (progress > 0) ...[
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value: progress.clamp(0, 1).toDouble(),
              minHeight: 3,
              borderRadius: BorderRadius.circular(4),
              semanticsLabel: 'Reading progress',
            ),
          ],
          _actionStrip(context, progress: progress, compact: true),
        ],
      ),
    );
  }

  Widget _coverCount(IconData icon, Object count, String tooltip) => Tooltip(
    message: tooltip,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(165),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _coverSignal(IconData icon, Color color, String tooltip) => Tooltip(
    message: tooltip,
    child: Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(165),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 15, color: color),
    ),
  );

  Widget _editorialLayout(
    BuildContext context,
    Map<String, dynamic> data,
    String title,
    String author,
    String? statusLabel,
    IconData statusIcon,
    bool overdue,
    int notesCount,
    int quotesCount,
    double progress, {
    Color? statusColor,
  }) => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              height: 128,
              child: _BookCover(
                title: title,
                coverPath: data['coverPath'] as String?,
                coverUrl: data['coverUrl'] as String?,
                coverStorageUrl: data['coverStorageUrl'] as String?,
                localCoverPath: data['legacyCoverPath'] as String?,
                borderRadius: 6,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusPill(
                    label: statusLabel,
                    semanticLabel:
                        statusLabel ??
                        bookStatusLabel(canonicalBookStatus(data['status'])),
                    icon: statusIcon,
                    warning: overdue,
                    color: statusColor,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800, height: 1.08),
                  ),
                  const SizedBox(height: 4),
                  _authorText(context, author, maxLines: 2),
                  const SizedBox(height: 8),
                  _detailsLine(context, notesCount, quotesCount),
                ],
              ),
            ),
          ],
        ),
        _actionStrip(context, progress: progress),
      ],
    ),
  );

  Widget _authorText(BuildContext context, String author, {int maxLines = 1}) =>
      Text(
        author.isEmpty ? 'Author not specified' : author,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
        ),
      );

  Widget _detailsLine(BuildContext context, int notesCount, int quotesCount) =>
      Wrap(
        spacing: 7,
        runSpacing: 2,
        children: [
          _ratingText(context),
          _iconCount(
            context,
            Icons.note_alt_outlined,
            notesCount,
            'Number of notes',
          ),
          _iconCount(
            context,
            Icons.format_quote_rounded,
            quotesCount,
            'Number of citations',
          ),
          if (publisherCount > 1)
            Text('$publisherCount publishers', style: _mutedTextStyle(context)),
        ],
      );

  Widget _iconCount(
    BuildContext context,
    IconData icon,
    int count,
    String tooltip,
  ) => Tooltip(
    message: tooltip,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 2),
        Text('$count', style: _mutedTextStyle(context)),
      ],
    ),
  );

  Widget _ratingText(BuildContext context) => Text(
    '★ ${ratingAverage?.toStringAsFixed(1) ?? '0'}'
    '${ratingAverage == null ? '' : ' ($ratingCount)'}'
    '${myRating == null ? '' : ' · Ben: $myRating/5'}',
    style: _mutedTextStyle(context),
  );

  TextStyle _mutedTextStyle(BuildContext context) => TextStyle(
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    fontSize: 10,
    fontWeight: FontWeight.w600,
  );

  Widget _actionStrip(
    BuildContext context, {
    required double progress,
    bool compact = false,
  }) => FutureBuilder<File?>(
    future: fileFuture,
    builder: (context, fileSnapshot) => FutureBuilder<File?>(
      future: audioFuture,
      builder: (context, audioSnapshot) {
        final hasFile = fileSnapshot.data != null || hasRemoteFile;
        final hasAudio =
            onListen != null && (audioSnapshot.data != null || hasRemoteAudio);
        final showAudioLoading = audioLoading && onListen != null;
        if (!hasFile && !hasAudio && !loading && !showAudioLoading) {
          return const SizedBox.shrink();
        }
        final listeningProgress = doc.data()['listeningProgress'];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              children: [
                if (loading)
                  _loadingButton('PDF / EPUB indiriliyor', compact: compact)
                else if (hasFile)
                  _actionButton(
                    icon: Icons.menu_book_rounded,
                    label: 'Oku',
                    tooltip: 'read the book',
                    onPressed: onRead,
                    compact: compact,
                  ),
                if (hasFile && hasAudio) const SizedBox(width: 8),
                if (showAudioLoading)
                  _loadingButton('Audiobook downloading', compact: compact)
                else if (hasAudio)
                  _actionButton(
                    icon: Icons.headphones_rounded,
                    label: 'listen',
                    tooltip: 'Listen to the audiobook',
                    onPressed: onListen!,
                    compact: compact,
                  ),
              ],
            ),
            if (hasFile && progress > 0)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1).toDouble(),
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(4),
                  semanticsLabel: 'Reading progress',
                ),
              ),
            if (hasAudio && listeningProgress is num)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: LinearProgressIndicator(
                  value: listeningProgress.toDouble().clamp(0, 1),
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(4),
                  semanticsLabel: 'Dinleme ilerlemesi',
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _actionButton({
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback onPressed,
    required bool compact,
  }) {
    if (compact) {
      return IconButton.filledTonal(
        onPressed: busy ? null : onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 18),
      );
    }
    return Expanded(
      child: FilledButton.tonalIcon(
        onPressed: busy ? null : onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
      ),
    );
  }

  Widget _loadingButton(String label, {required bool compact}) {
    final indicator = const SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    if (compact) {
      return IconButton.filledTonal(
        onPressed: null,
        tooltip: label,
        icon: indicator,
      );
    }
    return Expanded(
      child: FilledButton.tonalIcon(
        onPressed: null,
        icon: indicator,
        label: Text(label),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
      ),
    );
  }

  int _entryCount(Object? value) =>
      value is Iterable ? value.whereType<String>().length : 0;
}
