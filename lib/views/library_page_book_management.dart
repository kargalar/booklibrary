part of 'library_page.dart';

// This extension keeps the legacy State API split by concern without duplicating state.
// ignore_for_file: invalid_use_of_protected_member
extension _LibraryPageStatePart4 on _LibraryPageState {
  Future<void> openNotes(LibraryBookDocument doc) async {
    final ratingsStream = social.ratingDetails(doc.id);
    final favoriteStream = social.favoriteForUser(bookId: doc.id, userId: uid);
    final bookStream = social.sharedBooks(doc.data()['ownerId'] as String);
    final libraries = social.librariesContainingBook(uid, doc.data());
    List<String> entries(Object? value) => value is Iterable
        ? value
              .whereType<String>()
              .map((entry) => entry.trim())
              .where((entry) => entry.isNotEmpty)
              .toList()
        : <String>[];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StreamBuilder<LibraryBookSnapshot>(
          stream: bookStream,
          builder: (context, bookSnapshot) {
            final current =
                _mergeLocalBooks(bookSnapshot.data?.docs ?? const [])
                    .where((book) => book.id == doc.id)
                    .firstOrNull ??
                doc;
            final data = current.data();
            return StreamBuilder<List<BookRating>>(
              stream: ratingsStream,
              builder: (context, snapshot) {
                final ratings = snapshot.data ?? const <BookRating>[];
                final mine = ratings
                    .where((rating) => rating.userId == uid)
                    .firstOrNull;
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: favoriteStream,
                  builder: (context, favoriteSnapshot) => BookNotesPage(
                    title: data['title'] as String? ?? 'book notes',
                    author: _bookText(data, 'author'),
                    coverPath: _bookText(data, 'coverPath'),
                    coverUrl: _bookText(data, 'coverUrl'),
                    coverStorageUrl: _bookText(data, 'coverStorageUrl'),
                    localCoverPath: _bookText(data, 'legacyCoverPath'),
                    pageCount: data['pageCount'] is num
                        ? (data['pageCount'] as num).toInt()
                        : null,
                    publisher: _bookText(data, 'publisher'),
                    spotifyUrls: _spotifyUrlsFor(data),
                    currentUserId: uid,
                    canEdit: _canManageBook(data),
                    localOnly:
                        data['syncStatus'] == 'pending' ||
                        data['syncStatus'] == 'failed',
                    syncError: data['syncError'] as String?,
                    onRetryUpload:
                        data['syncStatus'] == 'pending' ||
                            data['syncStatus'] == 'failed'
                        ? () => _retryLocalBook(current.id)
                        : null,
                    onRead: data['ownerId'] == uid
                        ? () => openBook(current)
                        : null,
                    onListen: data['ownerId'] == uid
                        ? () => openAudio(current)
                        : null,
                    onWishlist: data['ownerId'] == uid
                        ? () => _updateBookOptimistically(
                            current,
                            {'wishlist': data['wishlist'] != true},
                            () => vm.update(current.id, {
                              'wishlist': data['wishlist'] != true,
                            }),
                            failureMessage: 'Failed to update wishlist.',
                          )
                        : null,
                    wishlist: data['wishlist'] == true,
                    onDelete: data['ownerId'] == uid
                        ? () async {
                            if (await _deleteBook(current) && context.mounted) {
                              Navigator.of(context).pop();
                            }
                          }
                        : null,
                    onMoveToLibraries:
                        data['ownerId'] == uid && !isInHomeLibrary(data)
                        ? () => _moveToLibraries(current)
                        : null,
                    notes: entries(data['notes']),
                    quotes: entries(data['quotes']),
                    onScanQuote: _canCaptureCover && _canManageBook(data)
                        ? () async {
                            final scanned = await Navigator.of(context)
                                .push<String>(
                                  MaterialPageRoute(
                                    builder: (_) => const QuoteScanPage(),
                                  ),
                                );
                            return scanned;
                          }
                        : null,
                    onSave: (notes, quotes) => _updateBookOptimistically(
                      current,
                      {'notes': notes, 'quotes': quotes},
                      () => vm.update(current.id, {
                        'notes': notes,
                        'quotes': quotes,
                      }),
                      failureMessage: 'Could not save notes.',
                    ),
                    myRating: mine?.value,
                    ratings: ratings,
                    isFavorite: favoriteSnapshot.data?.exists == true,
                    onFavoriteChanged: (favorite) => social.setFavorite(
                      bookId: doc.id,
                      userId: uid,
                      favorite: favorite,
                    ),
                    onRate: (value) async {
                      final user = LocalIdentity.instance.currentUser;
                      if (user == null) return;
                      await social.rateBook(
                        bookId: doc.id,
                        user: user,
                        value: value,
                        review: mine?.review ?? '',
                      );
                      _ratingAverages.remove(doc.id);
                      _ratingSummaries.remove(doc.id);
                    },
                    onReview: (value, review) async {
                      final user = LocalIdentity.instance.currentUser;
                      if (user == null) return;
                      await social.rateBook(
                        bookId: doc.id,
                        user: user,
                        value: value,
                        review: review,
                      );
                      _ratingAverages.remove(doc.id);
                      _ratingSummaries.remove(doc.id);
                    },
                    onRemoveRating: mine == null
                        ? null
                        : () async {
                            await social.removeRating(
                              bookId: doc.id,
                              userId: uid,
                            );
                            _ratingAverages.remove(doc.id);
                            _ratingSummaries.remove(doc.id);
                          },
                    onEdit: _canManageBook(data)
                        ? () => editBook(current)
                        : null,
                    onSpotifyUrlsChanged: _canManageBook(data)
                        ? (urls) => _updateSpotifyUrls(current, urls)
                        : null,
                    onLend: _canManageBook(data) && !hasBorrower(data)
                        ? () => lend(current)
                        : null,
                    onReturn: _canManageBook(data) && hasBorrower(data)
                        ? () => _updateBookOptimistically(
                            current,
                            {
                              'borrower': null,
                              'borrowerId': null,
                              'borrowerUserId': null,
                              'loanRequestId': null,
                              'loanDue': null,
                              'loanedAt': null,
                            },
                            () => vm.update(current.id, {
                              'borrower': null,
                              'borrowerId': null,
                              'borrowerUserId': null,
                              'loanRequestId': null,
                              'loanDue': null,
                              'loanedAt': null,
                              'returnedAt': FieldValue.serverTimestamp(),
                            }),
                            failureMessage:
                                'The return process could not be completed.',
                          )
                        : null,
                    onNudge:
                        data['ownerId'] == uid &&
                            data['borrowerUserId'] is String
                        ? () => social.nudgeBorrower(
                            bookId: doc.id,
                            ownerId: uid,
                            borrowerId: data['borrowerUserId'] as String,
                            bookTitle: data['title'] as String? ?? 'book',
                          )
                        : null,
                    accessibleLibraries: libraries,
                    onRequestLoan: (library) async {
                      final user = LocalIdentity.instance.currentUser;
                      if (user == null || library.bookId.isEmpty) return;
                      await social.requestLoan(
                        bookId: library.bookId,
                        ownerId: library.ownerId,
                        bookTitle: data['title'] as String? ?? 'book',
                        requester: user,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Request sent to ${library.name}.'),
                          ),
                        );
                      }
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<bool> _deleteBook(LibraryBookDocument doc) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Delete the book?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(doc.data()['title'] as String? ?? ''),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return false;

    var deleted = false;
    await run(() async {
      await vm.delete(uid, doc.id);
      deleted = true;
    });
    return deleted;
  }

  Future<void> _moveToLibraries(LibraryBookDocument doc) async {
    final data = doc.data();
    if (data['ownerId'] != uid || isInHomeLibrary(data)) return;

    final choices = await _libraryChoices();
    final existing = await social.librariesContainingBook(uid, data);
    if (!mounted) return;

    final editableIds = choices
        .where((choice) => choice.editable)
        .map((choice) => choice.ownerId)
        .toSet();
    final selected = existing
        .map((library) => library.ownerId)
        .where(editableIds.contains)
        .toSet();
    selected.remove(uid);
    final selectedLibraries = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .75,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Move to libraries',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Select the libraries where the book will be found.',
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final choice in choices)
                          CheckboxListTile(
                            value: selected.contains(choice.ownerId),
                            enabled: choice.editable,
                            title: Text(choice.name),
                            subtitle: choice.editable
                                ? null
                                : const Text('Salt okunur'),
                            secondary: choice.editable
                                ? null
                                : const Icon(Icons.lock_outline_rounded),
                            onChanged: choice.editable
                                ? (value) => update(() {
                                    if (value == true) {
                                      selected.add(choice.ownerId);
                                    } else {
                                      selected.remove(choice.ownerId);
                                    }
                                  })
                                : null,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(
                          sheetContext,
                          Set<String>.from(selected),
                        ),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (selectedLibraries == null || !mounted) return;
    await run(
      () => vm.setLibraryTargets(uid, doc.id, editableIds, selectedLibraries),
    );
  }

  Future<void> _updateBookOptimistically(
    LibraryBookDocument doc,
    Map<String, dynamic> updates,

    Future<void> Function() persist, {
    String failureMessage = 'The book could not be updated.',
  }) async {
    if (!mounted) return;
    final data = doc.data();
    final previous = <String, dynamic>{};
    final missing = <String>{};
    for (final key in updates.keys) {
      if (data.containsKey(key)) {
        previous[key] = data[key];
      } else {
        missing.add(key);
      }
    }
    setState(() => data.addAll(updates));
    unawaited(
      _persistBookUpdate(
        doc,
        updates,
        previous,
        missing,
        persist,
        failureMessage,
      ),
    );
  }

  List<String> _spotifyUrlsFor(Map<String, dynamic> data) {
    final value = data['spotifyUrls'];
    if (value is Iterable) {
      return value
          .whereType<String>()
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toSet()
          .toList();
    }

    final legacyUrl = _bookText(data, 'spotifyUrl') ?? '';
    return legacyUrl.isEmpty ? const [] : [legacyUrl];
  }

  Future<void> _updateSpotifyUrls(
    LibraryBookDocument doc,
    List<String> urls,
  ) async {
    final updates = <String, dynamic>{'spotifyUrls': urls, 'spotifyUrl': null};
    final localChange = _localBookChanges[doc.id];
    if (localChange == null) {
      try {
        await vm.update(doc.id, updates);
      } catch (_) {
        throw const FormatException('Could not save the Spotify URL.');
      }
      return;
    }

    final updatedChange = LocalBookChange(
      id: localChange.id,
      isNew: localChange.isNew,
      data: {...localChange.data, ...updates},
      error: localChange.error,
    );
    await _saveLocalBook(updatedChange);
    if (localChange.error == null) {
      unawaited(_syncLocalBook(updatedChange, showWarning: false));
    }
  }

  Future<void> _persistBookUpdate(
    LibraryBookDocument doc,
    Map<String, dynamic> updates,
    Map<String, dynamic> previous,
    Set<String> missing,

    Future<void> Function() persist,
    String failureMessage,
  ) async {
    try {
      await persist();
    } catch (error, stackTrace) {
      developer.log(
        'Book update failed',
        name: 'LibraryPage.update',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      final currentData = _bookDocs
          .where((book) => book.id == doc.id)
          .firstOrNull
          ?.data();
      final rollbackData = currentData ?? doc.data();
      final canRollback = updates.entries.every(
        (entry) => rollbackData[entry.key] == entry.value,
      );
      if (!canRollback) return;
      setState(() {
        for (final key in updates.keys) {
          if (missing.contains(key)) {
            rollbackData.remove(key);
          } else {
            rollbackData[key] = previous[key];
          }
        }
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  Future<void> action(String value, LibraryBookDocument doc) async {
    if (value == _clearStatusAction || bookStatuses.contains(value)) {
      final status = value == _clearStatusAction ? null : value;
      if (doc.data()['status'] == status) return;
      final now = DateTime.now();
      _updateBookOptimistically(
        doc,
        {
          'status': status,
          'readingStartedAt': status == readingStatus ? now : null,
          'completedAt': status == readStatus ? now : null,
        },
        () => vm.updateStatus(doc.id, status),
        failureMessage: 'Book status could not be updated.',
      );
      return;
    }
    switch (value) {
      case 'edit':
        await editBook(doc);
      case 'read':
        await openBook(doc);
      case 'file':
        await openBook(doc, replace: true);
      case 'lend':
        await lend(doc);
      case 'return':
        await _updateBookOptimistically(
          doc,
          {
            'borrower': null,
            'borrowerId': null,
            'borrowerUserId': null,
            'loanRequestId': null,
            'loanDue': null,
            'loanedAt': null,
          },
          () => vm.update(doc.id, {
            'borrower': null,
            'borrowerId': null,
            'borrowerUserId': null,
            'loanRequestId': null,
            'loanDue': null,
            'loanedAt': null,
            'returnedAt': FieldValue.serverTimestamp(),
          }),
          failureMessage: 'The return process could not be completed.',
        );
      case 'acquire':
        final libraryId = selectedPersonalLibraryId.isEmpty
            ? defaultPersonalLibraryId
            : selectedPersonalLibraryId;
        await _updateBookOptimistically(
          doc,
          {
            'wishlist': false,
            'inHomeLibrary': true,
            'libraryIds': [libraryId],
          },
          () => vm.update(doc.id, {
            'wishlist': false,
            'inHomeLibrary': true,
            'libraryIds': [libraryId],
          }),
          failureMessage: 'The book could not be included in the collection.',
        );
      case 'delete':
        await _deleteBook(doc);
    }
  }

  List<LibraryBookDocument> filtered(List<LibraryBookDocument> docs) {
    final query = normalizeBookSearchText(search.text);
    return docs.where((doc) {
      final data = doc.data();
      final authors = authorsFromBook(data);
      final genres = data['subjects'] is Iterable
          ? normalizeGenres(data['subjects'].whereType<String>())
          : const <String>[];
      final pageCount = _numberValue(data['pageCount']);
      final publishYear = _publishedYear(data);
      final rating = _ratingAverages[doc.id];
      final loaned = hasBorrower(data);
      final hasReadingFile =
          _hasStoredFileFormat(data['readingFormat']) ||
          _localReadingFileIds.contains(doc.id);
      final hasAudioFile =
          _hasStoredFileFormat(data['audioFormat']) ||
          _localAudioFileIds.contains(doc.id);
      final inFileType =
          fileTypeFilter == _allFileTypes ||
          fileTypeFilter == _readingFileType && hasReadingFile ||
          fileTypeFilter == _audioFileType && hasAudioFile;
      final inTab = showWishlist && tab == 1
          ? data['wishlist'] == true
          : switch (tab) {
              0 =>
                data['wishlist'] != true &&
                    canonicalBookStatus(data['status']) == readingStatus,
              2 => data['wishlist'] != true && loaned,
              _ => data['wishlist'] != true,
            };
      final inAuthor =
          authorFilter == 'All' ||
          authors.any(
            (author) =>
                normalizeBookKey(author) == normalizeBookKey(authorFilter),
          );
      final inGenre =
          genreFilter == 'All' ||
          genres.any(
            (genre) => normalizeBookKey(genre) == normalizeBookKey(genreFilter),
          );
      final inPages =
          (minPageFilter == null ||
              pageCount != null && pageCount >= minPageFilter!) &&
          (maxPageFilter == null ||
              pageCount != null && pageCount <= maxPageFilter!);
      final inRating =
          minRatingFilter == null ||
          rating != null && rating >= minRatingFilter!;
      final inYear =
          (fromYearFilter == null ||
              publishYear != null && publishYear >= fromYearFilter!) &&
          (toYearFilter == null ||
              publishYear != null && publishYear <= toYearFilter!);
      final inSelectedLibrary = selectedPersonalLibraryId.isEmpty
          ? isInHomeLibrary(data)
          : isInLibrary(data, selectedPersonalLibraryId);
      final inCollection = switch (collectionFilter) {
        _homeCollection => inSelectedLibrary,
        _readingHistoryCollection =>
          selectedLibraryOwnerId == uid
              ? !isInAnyLibrary(data)
              : !isInLibrary(data, selectedPersonalLibraryId),
        _ => true,
      };
      return inTab &&
          (tab != 1 || showWishlist || inCollection) &&
          (tab != 1 || inFileType) &&
          (tab != 1 ||
              showWishlist ||
              inAuthor &&
                  inGenre &&
                  matchesBookFacets(data, facetFilters) &&
                  inPages &&
                  inRating &&
                  inYear &&
                  _matchesStatusFilter(data['status'])) &&
          (tab != 1 ||
              query.isEmpty ||
              matchesBookSearchText(
                query,
                '${data['title']} ${data['author']}',
              ));
    }).toList();
  }

  List<LibraryBookDocument> _recentlyRead(
    List<LibraryBookDocument> docs, {
    int limit = 6,
  }) {
    final byData = Map<Map<String, dynamic>, LibraryBookDocument>.identity();
    for (final doc in docs) {
      byData[doc.data()] = doc;
    }
    return recentlyCompletedBooks(
      byData.keys,
      limit: limit,
    ).map((data) => byData[data]!).toList(growable: false);
  }

  num? _numberValue(Object? value) {
    if (value is num) return value;
    return value is String ? num.tryParse(value.trim()) : null;
  }

  bool _matchesStatusFilter(Object? rawStatus) {
    if (filter == _allFileTypes) return true;
    final status = canonicalBookStatus(rawStatus);
    return filter == _noStatusFilter ? status == null : status == filter;
  }

  int? _publishedYear(Map<String, dynamic> data) => publishedYearOf(data);

  Future<void> _loadRatingAverages(List<LibraryBookDocument> docs) async {
    final values = await Future.wait(
      docs.map(
        (doc) async =>
            MapEntry(doc.id, (await _ratingSummaryFor(doc.id)).average),
      ),
    );
    _ratingAverages.addEntries(values);
  }

  Future<_RatingSummary> _ratingSummaryFor(String bookId) =>
      _ratingSummaries.putIfAbsent(bookId, () async {
        final snapshot = await social.ratings(bookId).first;
        final ratings = snapshot.docs
            .map(BookRating.fromDocument)
            .where((rating) => rating.value >= 1 && rating.value <= 5)
            .toList(growable: false);
        if (ratings.isEmpty) return const _RatingSummary();
        final total = ratings.fold<int>(
          0,
          (total, rating) => total + rating.value,
        );
        return _RatingSummary(
          count: ratings.length,
          average: total / ratings.length,
          myRating: ratings
              .where((rating) => rating.userId == uid)
              .firstOrNull
              ?.value,
        );
      });

  Future<void> _loadLocalFileAvailability(
    List<LibraryBookDocument> docs,
  ) async {
    await Future.wait([
      for (final doc in docs)
        if (!_hasStoredFileFormat(doc.data()['readingFormat']))
          () async {
            try {
              if (await BookFiles.find(uid, doc.id) != null) {
                _localReadingFileIds.add(doc.id);
              }
            } catch (_) {}
          }(),
      for (final doc in docs)
        if (!_hasStoredFileFormat(doc.data()['audioFormat']))
          () async {
            try {
              if (await AudioBookFiles.find(uid, doc.id) != null) {
                _localAudioFileIds.add(doc.id);
              }
            } catch (_) {}
          }(),
    ]);
  }
}
