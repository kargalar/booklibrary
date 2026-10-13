part of 'library_page.dart';

// This extension keeps the legacy State API split by concern without duplicating state.
// ignore_for_file: invalid_use_of_protected_member
extension _LibraryPageStatePart7 on _LibraryPageState {
  Future<void> _savePersonalLibraries(List<PersonalLibrary> libraries) async {
    try {
      await social.savePersonalLibraries(uid, libraries);
      if (mounted) setState(() => _personalLibraries = libraries);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : 'Libraries could not be registered.',
            ),
          ),
        );
      }
    }
  }

  Widget
  _librarySelector() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: social.friendLinks(uid),
    builder: (context, snapshot) {
      final friendIds = _friendIds(snapshot.data?.docs ?? const []).toList()
        ..sort();
      for (final link in snapshot.data?.docs ?? const []) {
        final members = link.data()['memberIds'];
        final friendId = members is Iterable
            ? members.whereType<String>().firstWhere(
                (id) => id != uid,
                orElse: () => '',
              )
            : '';
        final permissions = link.data()['permissions'];
        _editableLibraries[friendId] =
            permissions is Map && permissions[uid] == 'edit';
      }
      return FutureBuilder<List<UserProfile?>>(
        future: Future.wait(friendIds.map(_profileFor)),
        builder: (context, profiles) {
          if (profiles.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 36,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final profileValues = profiles.data ?? const <UserProfile?>[];
          final labels = <String, String>{
            for (var index = 0; index < friendIds.length; index++)
              friendIds[index]: _libraryName(
                friendIds[index],
                index < profileValues.length
                    ? profileValues[index]?.libraryName
                    : null,
              ),
          };
          final selectedFriend = friendIds.contains(selectedLibraryOwnerId);
          final selectedFriendIndex = friendIds.indexOf(selectedLibraryOwnerId);
          final selectedFriendProfile =
              selectedFriendIndex >= 0 &&
                  selectedFriendIndex < profileValues.length
              ? profileValues[selectedFriendIndex]
              : null;
          final selectedFriendLibraryId =
              selectedFriendProfile?.personalLibraries.any(
                    (library) => library.id == selectedPersonalLibraryId,
                  ) ==
                  true
              ? selectedPersonalLibraryId
              : selectedFriendProfile?.personalLibraries.firstOrNull?.id ??
                    defaultPersonalLibraryId;
          final selectedPersonalId =
              _personalLibraries.any(
                (library) => library.id == selectedPersonalLibraryId,
              )
              ? selectedPersonalLibraryId
              : _personalLibraries.first.id;
          final value = selectedFriend
              ? '$_sharedPersonalLibraryActionPrefix$selectedLibraryOwnerId|$selectedFriendLibraryId'
              : _personalLibraryActionPrefix + selectedPersonalId;
          return PopupMenuButton<String>(
            tooltip: 'Select library',
            onSelected: (selected) {
              if (selected == _renameLibraryAction) {
                unawaited(_renameLibrary());
              } else if (selected == _newLibraryAction) {
                unawaited(_createLibrary());
              } else if (selected.startsWith(_personalLibraryActionPrefix)) {
                unawaited(
                  _selectPersonalLibrary(
                    selected.substring(_personalLibraryActionPrefix.length),
                  ),
                );
              } else if (selected.startsWith(
                _sharedPersonalLibraryActionPrefix,
              )) {
                final parts = selected
                    .substring(_sharedPersonalLibraryActionPrefix.length)
                    .split('|');
                if (parts.length == 2) {
                  unawaited(_selectSharedPersonalLibrary(parts[0], parts[1]));
                }
              } else {
                unawaited(_selectLibrary(selected));
              }
            },
            itemBuilder: (context) => [
              for (final library in _personalLibraries)
                PopupMenuItem(
                  value: _personalLibraryActionPrefix + library.id,
                  child: Row(
                    children: [
                      Expanded(child: Text(library.name)),
                      if (value == _personalLibraryActionPrefix + library.id)
                        const Icon(Icons.check_rounded, size: 18),
                    ],
                  ),
                ),
              if (friendIds.isNotEmpty) const PopupMenuDivider(),
              for (var index = 0; index < friendIds.length; index++)
                for (final library
                    in profileValues[index]?.personalLibraries ??
                        const <PersonalLibrary>[])
                  PopupMenuItem(
                    value:
                        '$_sharedPersonalLibraryActionPrefix${friendIds[index]}|${library.id}',
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${labels[friendIds[index]] ?? 'Library'} · ${library.name}',
                          ),
                        ),
                        if (value ==
                            '$_sharedPersonalLibraryActionPrefix${friendIds[index]}|${library.id}')
                          const Icon(Icons.check_rounded, size: 18),
                      ],
                    ),
                  ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _newLibraryAction,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.add_rounded),
                  title: Text('new library'),
                ),
              ),
              if (!selectedFriend)
                const PopupMenuItem(
                  value: _renameLibraryAction,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_rounded),
                    title: Text('change name'),
                  ),
                ),
            ],
            child: Text(
              selectedFriend
                  ? '${labels[selectedLibraryOwnerId] ?? defaultLibraryName} · ${selectedFriendProfile?.personalLibraries.where((library) => library.id == selectedFriendLibraryId).firstOrNull?.name ?? ''}'
                  : _selectedPersonalLibraryName(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.4),
            ),
          );
        },
      );
    },
  );

  Widget _searchField() => TextField(
    controller: search,
    focusNode: searchFocusNode,
    onChanged: (_) => setState(() {
      _visibleBookCount = _booksPerPage;
    }),
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search_rounded),
      hintText: tab == 2
          ? 'Search loan records'
          : 'Search for a book or author',
      suffixIcon: search.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'clear search',
              onPressed: () {
                search.clear();
                setState(() {
                  _visibleBookCount = _booksPerPage;
                });
              },
              icon: const Icon(Icons.close_rounded),
            ),
    ),
  );

  Widget _sectionHeading(int count, {String? title}) => Row(
    children: [
      Text(
        title ??
            switch (tab) {
              0 => 'You are reading now',
              1 => showWishlist ? 'my wish list' : 'My Books',
              2 => 'Currently on loan',
              _ => 'Your collection',
            },
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withAlpha(18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('$count'),
      ),
    ],
  );

  Widget _buildBooksScroll({
    required List<LibraryBookDocument> visible,
    required List<LibraryBookDocument> pageDocs,
    List<LibraryBookDocument> recentlyRead = const [],
    required Map<String, Set<String>> publishers,
    required bool wide,
    required double topPadding,
    required List<Widget> header,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final hasMore = pageDocs.length < visible.length;
      final columnCount = _bookColumnCount(constraints.maxWidth);
      return NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 500 && hasMore) {
            _loadMoreBooks(visible.length);
          }
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                wide ? 34 : 20,
                topPadding,
                wide ? 34 : 20,
                0,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  ...header,
                  _sectionHeading(visible.length),
                  const SizedBox(height: 12),
                  if (visible.isEmpty) _emptyState(),
                ]),
              ),
            ),
            if (pageDocs.isNotEmpty)
              _bookGrid(
                pageDocs,
                publishers,
                columnCount: columnCount,
                wide: wide,
              ),
            if (recentlyRead.isNotEmpty) ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  wide ? 34 : 20,
                  28,
                  wide ? 34 : 20,
                  12,
                ),
                sliver: SliverToBoxAdapter(
                  child: _sectionHeading(
                    recentlyRead.length,
                    title: 'Last things you read',
                  ),
                ),
              ),
              _bookGrid(
                recentlyRead,
                publishers,
                columnCount: columnCount,
                wide: wide,
              ),
            ],
            if (hasMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      );
    },
  );

  int _bookColumnCount(double width) {
    if (tab >= 2) return 2;
    return width >= 1100
        ? 6
        : width >= 800
        ? 5
        : width >= 560
        ? 4
        : 3;
  }

  Widget _bookGrid(
    List<LibraryBookDocument> docs,
    Map<String, Set<String>> publishers, {
    required int columnCount,
    required bool wide,
  }) {
    final compact = tab < 2;
    final rowCount = (docs.length + columnCount - 1) ~/ columnCount;

    Widget bookCard(LibraryBookDocument doc) {
      final identity = bookIdentity(doc.data());
      return FutureBuilder<_RatingSummary>(
        key: ValueKey(doc.id),
        future: _ratingSummaryFor(doc.id),
        builder: (context, summary) {
          final rating = summary.data ?? const _RatingSummary();
          return _BookCard(
            doc: doc,
            busy: busy || doc.data()['syncStatus'] == 'pending',
            compact: compact,
            publisherCount: identity == null
                ? 0
                : publishers[identity]?.length ?? 0,
            ratingCount: rating.count,
            ratingAverage: rating.average,
            myRating: rating.myRating,
            canManage: tab == 0 || _canManageBook(doc.data()),
            fileFuture: doc.data()['ownerId'] == uid
                ? _bookFiles.putIfAbsent(
                    doc.id,
                    () => BookFiles.find(uid, doc.id),
                  )
                : null,
            audioFuture: doc.data()['ownerId'] == uid
                ? _audioFiles.putIfAbsent(
                    doc.id,
                    () => AudioBookFiles.find(uid, doc.id),
                  )
                : null,
            hasRemoteFile:
                doc.data()['ownerId'] == uid &&
                (_hasStoredFileFormat(doc.data()['readingFormat']) ||
                    _localReadingFileIds.contains(doc.id)),
            hasRemoteAudio:
                doc.data()['ownerId'] == uid &&
                (_hasStoredFileFormat(doc.data()['audioFormat']) ||
                    _localAudioFileIds.contains(doc.id)),
            loading: _loadingReadingBookIds.contains(doc.id),
            audioLoading: _loadingAudioBookIds.contains(doc.id),
            onTap: () async {
              await openNotes(doc);
              if (!mounted) return;
              _ratingSummaries.remove(doc.id);
              _ratingAverages.remove(doc.id);
              setState(() {});
            },
            onLongPress: () => _chooseStatus(doc),
            onRead: () => openBook(doc),
            onListen: doc.data()['ownerId'] == uid
                ? () => openAudio(doc)
                : null,
            onEdit: _canManageBook(doc.data()) ? () => editBook(doc) : null,
            onDelete: doc.data()['ownerId'] == uid
                ? () async {
                    await _deleteBook(doc);
                  }
                : null,
            onMoveToLibraries:
                doc.data()['ownerId'] == uid && !isInHomeLibrary(doc.data())
                ? () => _moveToLibraries(doc)
                : null,
          );
        },
      );
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: wide ? 34 : 20),
      sliver: SliverList.builder(
        itemCount: rowCount,
        itemBuilder: (context, rowIndex) {
          final start = rowIndex * columnCount;
          return Padding(
            padding: EdgeInsets.only(
              bottom: rowIndex + 1 == rowCount
                  ? 0
                  : compact
                  ? 14
                  : 4,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var column = 0; column < columnCount; column++) ...[
                  if (column > 0) const SizedBox(width: 12),
                  Expanded(
                    child: start + column < docs.length
                        ? bookCard(docs[start + column])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    final scheme = Theme.of(context).colorScheme;
    final wishlist = tab == 1 && showWishlist;
    final loans = tab == 2;
    final reading = tab == 0;
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            wishlist
                ? Icons.bookmark_add_rounded
                : loans
                ? Icons.swap_horiz_rounded
                : Icons.auto_stories_rounded,
            size: 46,
            color: scheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            wishlist
                ? 'Your purchase list is still empty'
                : loans
                ? 'No books on loan'
                : reading
                ? 'There is no book you are reading right now'
                : 'The book you are looking for was not found',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            wishlist
                ? 'Start saving the books you want to buy.'
                : loans
                ? 'You can keep track of the books you have lent here.'
                : reading
                ? 'Put a book from your library in Reading status.'
                : 'Start by adding a new book to your collection.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Future<void> _openLibraryStats(List<LibraryBookDocument> docs) async {
    final homeDocs = docs
        .where(
          (doc) => selectedPersonalLibraryId.isEmpty
              ? isInHomeLibrary(doc.data())
              : isInLibrary(doc.data(), selectedPersonalLibraryId),
        )
        .toList();
    final stats = LibraryStats(
      homeDocs.map((doc) => doc.data()),
      DateTime.now(),
    );
    final ratingsFuture = _loadMyRatings(homeDocs);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text('${_selectedPersonalLibraryName()} istatistikleri'),
          ),
          body: SafeArea(
            child: FutureBuilder<Map<String, int>>(
              future: ratingsFuture,
              builder: (context, snapshot) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _statsPage(stats, homeDocs, snapshot.data ?? const {}),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<Map<String, int>> _loadMyRatings(
    Iterable<LibraryBookDocument> docs,
  ) async {
    final values = await Future.wait(
      docs.where((doc) => doc.data()['wishlist'] != true).map((doc) async {
        final rating = await social.ratingForUser(bookId: doc.id, userId: uid);
        return rating == null ? null : MapEntry(doc.id, rating);
      }),
    );
    return {
      for (final value in values.whereType<MapEntry<String, int>>())
        value.key: value.value,
    };
  }

  Map<String, List<int>> _ratingsByAuthor(
    Iterable<LibraryBookDocument> docs,
    Map<String, int> ratings,
  ) {
    final grouped = <String, List<int>>{};
    for (final doc in docs) {
      final rating = ratings[doc.id];
      if (rating == null) continue;
      for (final author in authorsFromBook(doc.data())) {
        grouped.putIfAbsent(normalizeBookKey(author), () => []).add(rating);
      }
    }
    return grouped;
  }

  Widget _statsPage(
    LibraryStats stats,
    List<LibraryBookDocument> docs,
    Map<String, int> ratings,
  ) {
    final authorRatings = _ratingsByAuthor(docs, ratings);
    final ratingValues = ratings.values.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _completionCard(stats),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 560 ? 2 : 3;
            const gap = 12.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            final metrics = [
              (
                Icons.library_books_rounded,
                'Total books',
                stats.total,
                const Color(0xFF3E4CFF),
              ),
              (
                Icons.menu_book_rounded,
                'Total pages',
                stats.totalPages,
                const Color(0xFF7B61FF),
              ),
              (
                Icons.fact_check_rounded,
                'Known page',
                stats.booksWithPageCount,
                const Color(0xFFE0A458),
              ),
              (
                Icons.menu_book_rounded,
                'reading',
                stats.reading,
                const Color(0xFFE76F51),
              ),
              (
                Icons.check_circle_rounded,
                'read',
                stats.completed,
                const Color(0xFF2A9D8F),
              ),
              (
                Icons.bookmark_rounded,
                'Want to read',
                stats.wishlist,
                const Color(0xFF6A4C93),
              ),
              (
                Icons.calendar_month_rounded,
                'This month',
                stats.completedThisMonth,
                const Color(0xFFBC6C25),
              ),
              (
                Icons.swap_horiz_rounded,
                'on loan',
                stats.lent,
                const Color(0xFF167D7F),
              ),
              (
                Icons.warning_amber_rounded,
                'Geciken',
                stats.overdue,
                const Color(0xFFD1495B),
              ),
            ];
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width: width,
                    child: _MetricCard(
                      icon: metric.$1,
                      label: metric.$2,
                      value: metric.$3,
                      color: metric.$4,
                    ),
                  ),
              ],
            );
          },
        ),
        if (ratingValues.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ratingSummary(ratingValues),
        ],
        const SizedBox(height: 16),
        _authorStatsSection(stats, authorRatings),
        const SizedBox(height: 16),
        _distributionSection(
          'Books by genre',
          stats.byGenre,
          Icons.category_rounded,
        ),
        const SizedBox(height: 12),
        _distributionSection(
          'Books by publication year',
          stats.byYear.map((year, value) => MapEntry('$year', value)),
          Icons.event_rounded,
        ),
        const SizedBox(height: 18),
        _timelineSection(docs),
      ],
    );
  }
}
