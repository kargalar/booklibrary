import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/local_strings.dart';

import '../data/social_repository.dart';
import '../data/spotify_music.dart';
import 'image_shimmer.dart';
import 'spotify_music_card.dart';

part 'book_notes_editor.dart';
part 'book_notes_layout.dart';

class BookNotesPage extends StatefulWidget {
  const BookNotesPage({
    super.key,
    required this.title,
    required this.notes,
    required this.quotes,
    required this.onSave,
    this.onScanQuote,
    this.quoteNotes = const [],
    this.onSaveWithQuoteNotes,
    this.author,
    this.coverPath,
    this.coverUrl,
    this.coverStorageUrl,
    this.localCoverPath,
    this.pageCount,
    this.publisher,
    this.spotifyUrls = const [],
    this.myRating,
    this.ratings = const [],
    this.onRate,
    this.onReview,
    this.onRemoveRating,
    this.isFavorite = false,
    this.onFavoriteChanged,
    this.onEdit,
    this.onSpotifyUrlsChanged,
    this.onLend,
    this.onReturn,
    this.onNudge,
    this.currentUserId,
    this.accessibleLibraries,
    this.onRequestLoan,
    this.canEdit = true,
    this.wishlist = false,
    this.localOnly = false,
    this.syncError,
    this.onRetryUpload,
    this.onRead,
    this.onListen,
    this.onWishlist,
    this.onDelete,
    this.onMoveToLibraries,
  });

  final String title;
  final String? author,
      coverPath,
      coverUrl,
      coverStorageUrl,
      localCoverPath,
      publisher;
  final List<String> spotifyUrls;
  final int? pageCount;
  final bool canEdit, wishlist, isFavorite, localOnly;
  final String? syncError;
  final Future<void> Function()? onRetryUpload;
  final Future<void> Function()? onRead,
      onListen,
      onWishlist,
      onDelete,
      onMoveToLibraries;
  final List<String> notes;
  final List<String> quotes;
  final List<String> quoteNotes;
  final Future<void> Function(List<String>, List<String>, List<String>)?
  onSaveWithQuoteNotes;
  final Future<void> Function(List<String> notes, List<String> quotes) onSave;
  final Future<String?> Function()? onScanQuote;
  final int? myRating;
  final List<BookRating> ratings;
  final Future<void> Function(int value)? onRate;
  final Future<void> Function(int value, String review)? onReview;
  final Future<void> Function()? onRemoveRating;
  final Future<void> Function(bool favorite)? onFavoriteChanged;
  final Future<void> Function()? onEdit;
  final Future<void> Function(List<String> urls)? onSpotifyUrlsChanged;
  final Future<void> Function()? onLend;
  final Future<void> Function()? onReturn;
  final Future<void> Function()? onNudge;
  final String? currentUserId;
  final Future<List<LibraryOwner>>? accessibleLibraries;
  final Future<void> Function(LibraryOwner owner)? onRequestLoan;

  @override
  State<BookNotesPage> createState() => _BookNotesPageState();
}

class _BookNotesPageState extends State<BookNotesPage> {
  late List<String> notes;
  late List<String> quotes;
  late List<String> quoteNotes;
  late bool favorite;
  late int? _myRating;
  late String _myReview;
  late List<String> _spotifyUrls;
  Object? _spotifyRequest;
  Object? _notesRequest;
  Object? _favoriteRequest;
  Object? _ratingRequest;
  bool saving = false;
  bool _syncResolved = false;
  bool _retryingUpload = false;

  @override
  void initState() {
    super.initState();
    notes = List.of(widget.notes);
    quotes = List.of(widget.quotes);
    quoteNotes = _alignedQuoteNotes(widget.quoteNotes, quotes.length);
    favorite = widget.isFavorite;
    _myRating = widget.myRating;
    _myReview = _currentReview(widget.ratings);
    _spotifyUrls = List.of(widget.spotifyUrls);
  }

  String _currentReview(List<BookRating> ratings) =>
      ratings
          .where((rating) => rating.userId == widget.currentUserId)
          .firstOrNull
          ?.review ??
      '';

  List<String> _alignedQuoteNotes(List<String> values, int length) =>
      List.generate(
        length,
        (index) => index < values.length ? values[index] : '',
      );

  Future<void> editEntry({required bool quote, int? index}) async {
    if (!widget.canEdit) return;
    final entries = quote ? quotes : notes;
    final value = await showModalBottomSheet<_EntryEditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _EntryEditorSheet(
        quote: quote,
        initialText: index == null ? '' : entries[index],
        initialNote: quote && index != null ? quoteNotes[index] : '',
        onScanQuote: quote ? widget.onScanQuote : null,
      ),
    );
    if (value == null || value.text.isEmpty || !mounted) return;
    final updated = List<String>.of(entries);
    final updatedQuoteNotes = List<String>.of(quoteNotes);
    if (index == null) {
      updated.add(value.text);
      if (quote) updatedQuoteNotes.add(value.note);
    } else {
      updated[index] = value.text;
      if (quote) updatedQuoteNotes[index] = value.note;
    }
    await save(
      quote ? notes : updated,
      quote ? updated : quotes,
      updatedQuoteNotes,
    );
  }

  Future<void> removeEntry({required bool quote, required int index}) async {
    final updated = List<String>.of(quote ? quotes : notes)..removeAt(index);
    final updatedQuoteNotes = List<String>.of(quoteNotes);
    if (quote) updatedQuoteNotes.removeAt(index);
    await save(
      quote ? notes : updated,
      quote ? updated : quotes,
      updatedQuoteNotes,
    );
  }

  Future<void> manageSpotifyMusic({int? index}) async {
    final saveSpotifyUrls = widget.onSpotifyUrlsChanged;
    if (saving || saveSpotifyUrls == null) return;
    if (index != null && index >= _spotifyUrls.length) return;

    final controller = TextEditingController(
      text: index == null ? '' : _spotifyUrls[index],
    );
    final formKey = GlobalKey<FormState>();
    String? result;
    try {
      result = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    index == null
                        ? 'Add a Spotify track to this book'
                        : 'Edit Spotify track',
                    style: Theme.of(sheetContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Spotify track or album URL',
                      hintText: 'https://open.spotify.com/track/...',
                      prefixIcon: Icon(Icons.music_note_rounded),
                      helperText:
                          'Copy the link from the Share menu in Spotify.',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'A Spotify URL is required.';
                      }
                      return SpotifyMusicLookup.isValidUrl(value)
                          ? null
                          : 'Enter a valid Spotify URL.';
                    },
                    onFieldSubmitted: (_) {
                      if (formKey.currentState!.validate()) {
                        Navigator.pop(sheetContext, controller.text.trim());
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (index != null)
                        TextButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, ''),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Remove'),
                        ),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Cancel'),
                      ),
                      FilledButton.icon(
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            Navigator.pop(sheetContext, controller.text.trim());
                          }
                        },
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      controller.dispose();
    }

    if (result == null || !mounted) return;
    final nextUrls = List<String>.of(_spotifyUrls);
    if (result.isEmpty) {
      if (index == null) return;
      nextUrls.removeAt(index);
    } else {
      final url = SpotifyMusicLookup.normalizeUrl(result);
      if (url == null) return;
      final duplicate = nextUrls.asMap().entries.any(
        (entry) => entry.key != index && entry.value == url,
      );
      if (duplicate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This Spotify track is already added.')),
        );
        return;
      }
      if (index == null) {
        nextUrls.add(url);
      } else {
        nextUrls[index] = url;
      }
    }
    await _saveSpotifyMusic(nextUrls);
  }

  Future<void> _saveSpotifyMusic(List<String> urls) async {
    final saveSpotifyUrls = widget.onSpotifyUrlsChanged;
    if (saving || saveSpotifyUrls == null) return;
    final previousUrls = List<String>.of(_spotifyUrls);
    final nextUrls = List<String>.of(urls);
    final request = Object();
    _spotifyRequest = request;
    try {
      await perform(() async {
        setState(() => _spotifyUrls = nextUrls);
        try {
          await saveSpotifyUrls(nextUrls);
        } catch (_) {
          if (mounted) setState(() => _spotifyUrls = previousUrls);
          rethrow;
        }
      });
    } finally {
      if (identical(_spotifyRequest, request)) _spotifyRequest = null;
    }
  }

  Future<void> save(
    List<String> nextNotes,
    List<String> nextQuotes,
    List<String> nextQuoteNotes,
  ) async {
    if (saving || !widget.canEdit) return;
    final previousNotes = List<String>.of(notes);
    final previousQuotes = List<String>.of(quotes);
    final previousQuoteNotes = List<String>.of(quoteNotes);
    final nextNotesCopy = List<String>.of(nextNotes);
    final nextQuotesCopy = List<String>.of(nextQuotes);
    final token = Object();
    _notesRequest = token;
    setState(() {
      notes = nextNotesCopy;
      quotes = nextQuotesCopy;
      quoteNotes = List.of(nextQuoteNotes);
    });
    unawaited(
      _persistNotes(
        nextNotesCopy,
        nextQuotesCopy,
        previousNotes,
        previousQuotes,
        List.of(nextQuoteNotes),
        previousQuoteNotes,
        token,
      ),
    );
  }

  Future<void> rate(int value) async {
    if (saving || widget.onRate == null) return;
    final previous = _myRating;
    final token = Object();
    _ratingRequest = token;
    setState(() => _myRating = value);
    unawaited(_persistRating(value, previous, token));
  }

  Future<void> removeRating() async {
    if (saving || widget.onRemoveRating == null) return;
    final previous = _myRating;
    final previousReview = _myReview;
    final token = Object();
    _ratingRequest = token;
    setState(() {
      _myRating = null;
      _myReview = '';
    });
    unawaited(_persistRating(null, previous, token, previousReview));
  }

  Future<void> editReview() async {
    final saveReview = widget.onReview;
    if (saving || saveReview == null) return;
    var selectedRating = _myRating ?? 0;
    var reviewText = _myReview;
    final result = await showModalBottomSheet<({int rating, String review})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _myReview.isEmpty ? 'Add review' : 'Edit my review',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var value = 1; value <= 5; value++)
                      IconButton(
                        tooltip: '$value stars',
                        onPressed: () =>
                            setModalState(() => selectedRating = value),
                        icon: Icon(
                          value <= selectedRating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: Colors.amber.shade700,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: reviewText,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Review',
                    hintText: 'Share your thoughts about the book',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (value) => setModalState(() => reviewText = value),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed:
                          selectedRating == 0 || reviewText.trim().isEmpty
                          ? null
                          : () {
                              final review = reviewText.trim();
                              if (review.isEmpty) return;
                              Navigator.pop(context, (
                                rating: selectedRating,
                                review: review,
                              ));
                            },
                      child: const Text('Publish'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;

    final previousRating = _myRating;
    final previousReview = _myReview;
    setState(() {
      _myRating = result.rating;
      _myReview = result.review;
      saving = true;
    });
    try {
      await saveReview(result.rating, result.review);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _myRating = previousRating;
        _myReview = previousReview;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The review could not be saved.')),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> changeFavorite() async {
    if (saving || widget.onFavoriteChanged == null) return;
    final previous = favorite;
    final next = !favorite;
    final token = Object();
    _favoriteRequest = token;
    setState(() => favorite = next);
    unawaited(_persistFavorite(next, previous, token));
  }

  Future<void> _persistNotes(
    List<String> nextNotes,
    List<String> nextQuotes,
    List<String> previousNotes,
    List<String> previousQuotes,
    List<String> nextQuoteNotes,
    List<String> previousQuoteNotes,
    Object token,
  ) async {
    try {
      if (widget.onSaveWithQuoteNotes case final saveWithNotes?) {
        await saveWithNotes(nextNotes, nextQuotes, nextQuoteNotes);
      } else {
        await widget.onSave(nextNotes, nextQuotes);
      }
    } catch (_) {
      if (mounted && _notesRequest == token) {
        setState(() {
          notes = previousNotes;
          quotes = previousQuotes;
          quoteNotes = previousQuoteNotes;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not save notes.')));
      }
    } finally {
      if (_notesRequest == token) _notesRequest = null;
    }
  }

  Future<void> _persistRating(
    int? next,
    int? previous,
    Object token, [
    String? previousReview,
  ]) async {
    try {
      if (next == null) {
        await widget.onRemoveRating!();
      } else {
        await widget.onRate!(next);
      }
    } catch (_) {
      if (mounted && _ratingRequest == token) {
        setState(() {
          _myRating = previous;
          if (previousReview != null) _myReview = previousReview;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              next == null
                  ? 'Point could not be removed.'
                  : 'Could not save rating.',
            ),
          ),
        );
      }
    } finally {
      if (_ratingRequest == token) _ratingRequest = null;
    }
  }

  Future<void> _persistFavorite(bool next, bool previous, Object token) async {
    try {
      await widget.onFavoriteChanged!(next);
    } catch (_) {
      if (mounted && _favoriteRequest == token) {
        setState(() => favorite = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save favorite.')),
        );
      }
    } finally {
      if (_favoriteRequest == token) _favoriteRequest = null;
    }
  }

  Widget spotifySection() {
    final canEdit = widget.onSpotifyUrlsChanged != null;
    if (_spotifyUrls.isEmpty) {
      if (!canEdit) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      return Card(
        child: ListTile(
          onTap: saving ? null : () => manageSpotifyMusic(),
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            child: Icon(Icons.music_note_rounded, color: scheme.primary),
          ),
          title: const Text(
            'Add music to listen to while reading',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text('Spotify track or album'),
          trailing: IconButton(
            tooltip: 'Add Spotify track',
            onPressed: saving ? null : () => manageSpotifyMusic(),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _spotifyUrls.length; i++) ...[
          SpotifyMusicCard(
            key: ValueKey(_spotifyUrls[i]),
            url: _spotifyUrls[i],
          ),
          if (canEdit)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: saving
                        ? null
                        : () => manageSpotifyMusic(index: i),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit'),
                  ),
                  TextButton.icon(
                    onPressed: saving
                        ? null
                        : () {
                            final nextUrls = List<String>.of(_spotifyUrls)
                              ..removeAt(i);
                            _saveSpotifyMusic(nextUrls);
                          },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Remove'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (canEdit)
          Card(
            child: ListTile(
              onTap: saving ? null : () => manageSpotifyMusic(),
              leading: const Icon(Icons.add_circle_outline_rounded),
              title: const Text(
                'Add another Spotify track',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
      ],
    );
  }

  Widget bookHeader() {
    final scheme = Theme.of(context).colorScheme;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.menu_book_rounded,
        size: 26,
        color: scheme.onPrimaryContainer,
      ),
    );
    final path = widget.localCoverPath?.isNotEmpty == true
        ? widget.localCoverPath
        : widget.coverPath?.startsWith('http') == true
        ? null
        : widget.coverPath;
    final url = widget.coverStorageUrl?.startsWith('http') == true
        ? widget.coverStorageUrl
        : widget.coverPath?.startsWith('http') == true
        ? widget.coverPath
        : widget.coverUrl;
    final cover = SizedBox(
      width: 56,
      height: 84,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: path?.startsWith('http') == true
            ? Image.network(
                path!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const ImageShimmer(borderRadius: 12),
                errorBuilder: (_, _, _) => fallback,
              )
            : path?.isNotEmpty == true
            ? Image.file(
                File(path!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => url?.isNotEmpty == true
                    ? Image.network(
                        url!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => fallback,
                      )
                    : fallback,
              )
            : url?.isNotEmpty == true
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const ImageShimmer(borderRadius: 12),
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
    final details = [
      if (widget.pageCount != null) '${widget.pageCount} pages',
      if (widget.publisher?.isNotEmpty == true) widget.publisher!,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cover,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (widget.author?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  widget.author!,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (details.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  details.join(' • '),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget syncSection() {
    if (!widget.localOnly || _syncResolved) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final failed = widget.syncError?.isNotEmpty == true;
    return Card(
      color: scheme.errorContainer.withAlpha(failed ? 255 : 130),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_rounded,
              color: failed ? scheme.onErrorContainer : scheme.onSurface,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                failed ? LocalStrings.saveFailed : LocalStrings.saving,
                style: TextStyle(
                  color: failed ? scheme.onErrorContainer : scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (widget.onRetryUpload != null)
              TextButton(
                onPressed: _retryingUpload ? null : retryUpload,
                child: _retryingUpload
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Tekrar dene'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> retryUpload() async {
    final retry = widget.onRetryUpload;
    if (retry == null || _retryingUpload) return;
    setState(() => _retryingUpload = true);
    try {
      await retry();
      if (!mounted) return;
      setState(() => _syncResolved = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(LocalStrings.saved)));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : LocalStrings.saveFailed,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _retryingUpload = false);
    }
  }

  Widget librariesSection() {
    if (widget.accessibleLibraries == null) return const SizedBox.shrink();
    return FutureBuilder<List<LibraryOwner>>(
      future: widget.accessibleLibraries,
      builder: (context, snapshot) {
        final libraries = snapshot.data ?? const <LibraryOwner>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Libraries where it is located',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator(),
                  )
                else if (snapshot.hasError)
                  const ListTile(
                    title: Text(
                      'Your libraries could not be loaded. Check your connection and try again.',
                    ),
                  )
                else if (libraries.isEmpty)
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('No accessible library found.'),
                  )
                else
                  for (final library in libraries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.library_books_rounded),
                      title: Text(library.name),
                      subtitle: library.username.isEmpty
                          ? null
                          : Text('@${library.username}'),
                      trailing:
                          library.ownerId == widget.currentUserId ||
                              widget.onRequestLoan == null
                          ? null
                          : TextButton(
                              onPressed: saving
                                  ? null
                                  : () => perform(
                                      () => widget.onRequestLoan!(library),
                                    ),
                              child: const Text('ask for loan'),
                            ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void didUpdateWidget(covariant BookNotesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_spotifyRequest == null &&
        !listEquals(oldWidget.spotifyUrls, widget.spotifyUrls)) {
      _spotifyUrls = List.of(widget.spotifyUrls);
    }
    if (_notesRequest == null) {
      notes = List.of(widget.notes);
      quotes = List.of(widget.quotes);
      quoteNotes = _alignedQuoteNotes(widget.quoteNotes, quotes.length);
    }
    if (_favoriteRequest == null && oldWidget.isFavorite != widget.isFavorite) {
      favorite = widget.isFavorite;
    }
    if (_ratingRequest == null && oldWidget.myRating != widget.myRating) {
      _myRating = widget.myRating;
    }
    if (_ratingRequest == null) _myReview = _currentReview(widget.ratings);
    if (!oldWidget.localOnly && widget.localOnly) _syncResolved = false;
  }

  Future<void> perform(Future<void> Function() action) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : 'The operation could not be completed. Try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(_NotesLabels.pageTitle),
      actions: [
        if (widget.onEdit != null)
          IconButton(
            tooltip: 'Edit',
            onPressed: saving ? null : () => perform(widget.onEdit!),
            icon: const Icon(Icons.edit_rounded),
          ),
        if (widget.onRead != null ||
            widget.onListen != null ||
            widget.onWishlist != null ||
            widget.onDelete != null ||
            widget.onMoveToLibraries != null ||
            widget.onLend != null ||
            widget.onReturn != null ||
            widget.onNudge != null)
          PopupMenuButton<String>(
            enabled: !saving,
            onSelected: (value) {
              final action = {
                'lend': widget.onLend,
                'return': widget.onReturn,
                'nudge': widget.onNudge,
                'read': widget.onRead,
                'listen': widget.onListen,
                'wishlist': widget.onWishlist,
                'delete': widget.onDelete,
                'moveToLibraries': widget.onMoveToLibraries,
              }[value];
              if (action != null) perform(action);
            },
            itemBuilder: (_) => [
              if (widget.onRead != null)
                const PopupMenuItem(
                  value: 'read',
                  child: Text('Read or insert PDF/EPUB'),
                ),
              if (widget.onListen != null)
                const PopupMenuItem(
                  value: 'listen',
                  child: Text('Listen to or add an audiobook'),
                ),
              if (widget.onWishlist != null)
                PopupMenuItem(
                  value: 'wishlist',
                  child: Text(
                    widget.wishlist
                        ? 'Bought · move to collection'
                        : 'Move to purchase list',
                  ),
                ),
              if (widget.onDelete != null)
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('delete book'),
                ),
              if (widget.onMoveToLibraries != null)
                const PopupMenuItem(
                  value: 'moveToLibraries',
                  child: Text('Move to libraries'),
                ),
              if (widget.onLend != null)
                const PopupMenuItem(value: 'lend', child: Text('lend')),
              if (widget.onReturn != null)
                const PopupMenuItem(
                  value: 'return',
                  child: Text('Refund received'),
                ),
              if (widget.onNudge != null)
                const PopupMenuItem(value: 'nudge', child: Text('poke')),
            ],
          ),
      ],
    ),
    body: notesBody(),
  );
}
