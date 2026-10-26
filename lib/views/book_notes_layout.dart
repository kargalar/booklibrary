part of 'book_notes_page.dart';

abstract final class _NotesLabels {
  static const pageTitle = 'Reading journal';
  static const addNote = 'Add note';
  static const addQuote = 'Add quote';
  static const notes = 'Notes';
  static const quotes = 'Quotes';
  static const emptyNotes = 'No notes yet.';
  static const emptyQuotes = 'No quotes yet.';
  static const unrated = 'Not rated';
  static const ratingHints = [
    'Not for me',
    'It was okay',
    'Enjoyed it',
    'Loved it',
    'Unforgettable',
  ];
  static const community = 'Reader reviews';
  static const removeRating = 'Remove rating';
  static const addReview = 'Add review';
  static const editReview = 'Edit my review';
  static const read = 'Read book';
  static const listen = 'Listen';
  static const scanning = 'Scanning...';
  static const scanFailed = 'Could not scan the quote. Try again.';
}

abstract final class _NotesLayout {
  static const maxWidth = 920.0;
  static const twoColumnWidth = 760.0;
  static const gap = 20.0;
}

extension _BookNotesLayout on _BookNotesPageState {
  Widget notesBody() => LayoutBuilder(
    builder: (context, constraints) {
      final hasRating =
          widget.onRate != null ||
          widget.onReview != null ||
          widget.onFavoriteChanged != null ||
          widget.ratings.isNotEmpty ||
          _myRating != null;
      final wide =
          constraints.maxWidth >= _NotesLayout.twoColumnWidth && hasRating;
      final inset = constraints.maxWidth > _NotesLayout.maxWidth
          ? (constraints.maxWidth - _NotesLayout.maxWidth) / 2 + 16
          : 16.0;
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(inset, 4, inset, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: bookHeader()),
                        const SizedBox(width: _NotesLayout.gap),
                        Expanded(flex: 4, child: ratingSection()),
                      ],
                    )
                  else ...[
                    bookHeader(),
                    const SizedBox(height: 8),
                    ratingSection(),
                  ],
                  if (widget.onRead != null || widget.onListen != null) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        if (widget.onRead != null)
                          TextButton.icon(
                            onPressed: saving
                                ? null
                                : () => perform(widget.onRead!),
                            icon: const Icon(Icons.auto_stories_outlined),
                            label: const Text(_NotesLabels.read),
                          ),
                        if (widget.onListen != null)
                          TextButton.icon(
                            onPressed: saving
                                ? null
                                : () => perform(widget.onListen!),
                            icon: const Icon(Icons.headphones_rounded),
                            label: const Text(_NotesLabels.listen),
                          ),
                      ],
                    ),
                  ],
                  if (widget.localOnly && !_syncResolved) ...[
                    const SizedBox(height: 16),
                    syncSection(),
                  ],
                ],
              ),
            ),
          ),
          ...journalSlivers(quote: false, inset: inset),
          ...journalSlivers(quote: true, inset: inset),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(inset, 16, inset, 24),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.onSpotifyUrlsChanged != null ||
                      _spotifyUrls.isNotEmpty)
                    spotifySection(),
                  if (widget.accessibleLibraries != null) ...[
                    const SizedBox(height: 16),
                    librariesSection(),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  List<Widget> journalSlivers({required bool quote, required double inset}) {
    final entries = quote ? quotes : notes;
    final scheme = Theme.of(context).colorScheme;
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(inset, 8, inset, 0),
        sliver: SliverToBoxAdapter(
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                '${quote ? _NotesLabels.quotes : _NotesLabels.notes} \u00b7 ${entries.length}',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (widget.canEdit)
                TextButton.icon(
                  onPressed: saving ? null : () => editEntry(quote: quote),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    quote ? _NotesLabels.addQuote : _NotesLabels.addNote,
                  ),
                ),
            ],
          ),
        ),
      ),
      if (entries.isEmpty)
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          sliver: SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                quote ? _NotesLabels.emptyQuotes : _NotesLabels.emptyNotes,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        )
      else
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          sliver: SliverList.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: scheme.outlineVariant.withAlpha(120),
                    ),
                  ),
                ),
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: SelectableText(
                          entries[index],
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            fontStyle: quote
                                ? FontStyle.italic
                                : FontStyle.normal,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    if (widget.canEdit)
                      PopupMenuButton<String>(
                        tooltip: quote ? 'Quote actions' : 'Note actions',
                        enabled: !saving,
                        onSelected: (value) => value == 'edit'
                            ? editEntry(quote: quote, index: index)
                            : removeEntry(quote: quote, index: index),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget ratingSection() {
    if (widget.onRate == null &&
        widget.onReview == null &&
        widget.onFavoriteChanged == null &&
        widget.ratings.isEmpty &&
        _myRating == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var value = 1; value <= 5; value++)
              IconButton(
                tooltip: '$value stars',
                isSelected: value <= (_myRating ?? 0),
                onPressed: saving || widget.onRate == null
                    ? null
                    : () => rate(value),
                icon: Icon(
                  value <= (_myRating ?? 0)
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 24,
                  color: scheme.primary,
                ),
              ),
            if (widget.onFavoriteChanged != null)
              IconButton(
                tooltip: favorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                onPressed: saving ? null : changeFavorite,
                icon: Icon(
                  favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 22,
                  color: favorite ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _myRating == null
                  ? _NotesLabels.unrated
                  : _NotesLabels.ratingHints[(_myRating! - 1).clamp(0, 4)],
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (widget.onReview != null)
              TextButton(
                onPressed: saving ? null : editReview,
                child: Text(
                  _myReview.isEmpty
                      ? _NotesLabels.addReview
                      : _NotesLabels.editReview,
                ),
              ),
            if (_myRating != null && widget.onRemoveRating != null)
              IconButton(
                tooltip: _NotesLabels.removeRating,
                onPressed: saving ? null : removeRating,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
          ],
        ),
        if (_myReview.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              _myReview,
              style: const TextStyle(fontSize: 14, height: 1.45),
            ),
          ),
        if (widget.ratings.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: const Text(_NotesLabels.community),
            subtitle: Text(
              '${(widget.ratings.fold<int>(0, (sum, rating) => sum + rating.value) / widget.ratings.length).toStringAsFixed(1)} / 5 · ${widget.ratings.length} readers',
            ),
            children: [
              for (final rating in widget.ratings)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(rating.userName),
                  subtitle: rating.review.isEmpty ? null : Text(rating.review),
                  trailing: Text('${rating.value} / 5'),
                ),
            ],
          ),
      ],
    );
  }
}
