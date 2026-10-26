part of 'library_page.dart';

// This extension keeps the legacy State API split by concern without duplicating state.
// ignore_for_file: invalid_use_of_protected_member
extension _LibraryPageStatePart6 on _LibraryPageState {
  Widget _loadingBookCard() => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AspectRatio(
            aspectRatio: .68,
            child: ImageShimmer(borderRadius: 10),
          ),
          const SizedBox(height: 8),
          _shimmerBlock(height: 12, borderRadius: 4),
          const SizedBox(height: 5),
          FractionallySizedBox(
            widthFactor: .68,
            child: _shimmerBlock(height: 10, borderRadius: 4),
          ),
        ],
      ),
    ),
  );

  Widget _shimmerBlock({
    double width = double.infinity,
    required double height,
    double borderRadius = 6,
  }) => SizedBox(
    width: width,
    height: height,
    child: ImageShimmer(borderRadius: borderRadius),
  );

  Widget _buildSidebar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 248,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _BrandMark(),
          const SizedBox(height: 42),
          _navItem(0, Icons.home_rounded, 'home page'),
          _navItem(5, Icons.explore_rounded, 'Discover'),
          _navItem(1, Icons.auto_stories_rounded, 'my library'),
          _navItem(4, Icons.person_rounded, 'Profile'),
          const Spacer(),
          _profileTile(),
        ],
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final selected =
        tab == index || (index == 1 && tab == 2) || (index == 4 && tab == 3);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        selected: selected,
        onTap: () => _selectTab(index),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        selectedTileColor: scheme.primary.withAlpha(24),
        iconColor: selected ? scheme.primary : scheme.onSurfaceVariant,
        textColor: selected ? scheme.primary : scheme.onSurfaceVariant,
        leading: Icon(icon),
        title: Text(
          label,
          style: TextStyle(fontWeight: selected ? FontWeight.w700 : null),
        ),
      ),
    );
  }

  Widget _profileTile() => FutureBuilder<UserProfile?>(
    future: _profileFor(uid),
    builder: (context, snapshot) {
      final username = snapshot.data?.username.trim() ?? '';
      final label = username.isEmpty ? 'Profile' : '@$username';
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        onTap: () => _selectTab(4),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          child: Text(
            (username.isEmpty ? 'P' : username).characters.first.toUpperCase(),
          ),
        ),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('my personal library'),
      );
    },
  );

  Widget _buildBottomNavigation() => NavigationBar(
    selectedIndex: switch (tab) {
      0 => 0,
      1 || 2 => 1,
      5 => 2,
      _ => 3,
    },
    onDestinationSelected: (value) => _selectTab(switch (value) {
      0 => 0,
      1 => 1,
      2 => 5,
      _ => 4,
    }),
    destinations: [
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: 'home page',
      ),
      const NavigationDestination(
        icon: Icon(Icons.auto_stories_outlined),
        selectedIcon: Icon(Icons.auto_stories_rounded),
        label: 'library',
      ),
      const NavigationDestination(
        icon: Icon(Icons.explore_outlined),
        selectedIcon: Icon(Icons.explore_rounded),
        label: 'Discover',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline_rounded),
        selectedIcon: Icon(Icons.person_rounded),
        label: 'Profile',
      ),
    ],
  );

  Widget _buildContent(
    List<LibraryBookDocument> docs, {
    LibraryBookSnapshot? initialBooks,
    bool wide = false,
  }) {
    if (tab == 5) return DiscoverPage(uid: uid, viewModel: vm);
    if (tab == 1) return _buildLibraryContent(docs, wide: wide);
    final List<LibraryBookDocument> visible = tab < 3
        ? filtered(docs)
        : const [];
    final shownCount = visible.length < _visibleBookCount
        ? visible.length
        : _visibleBookCount;
    final pageDocs = visible.take(shownCount).toList();
    final bookContent = tab < 3
        ? Column(
            children: [
              _buildTopBar(wide),
              Expanded(
                child: _buildBooksScroll(
                  visible: visible,
                  pageDocs: pageDocs,
                  recentlyRead: tab == 0 ? _recentlyRead(docs) : const [],
                  publishers: publishersByBook(docs.map((doc) => doc.data())),
                  wide: wide,
                  topPadding: 8,
                  header: [
                    if (tab != 0) _searchField(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          )
        : const SizedBox.shrink();
    if (tab < 3) return bookContent;
    if (tab == 3) {
      return Column(
        children: [
          _buildTopBar(wide),
          Expanded(child: SocialPage(uid: uid)),
        ],
      );
    }
    return Column(
      children: [
        _buildTopBar(wide),
        Expanded(
          child: ProfilePage(
            uid: uid,
            embedded: true,
            booksStream: homeStream,
            initialBooks: initialBooks,
            onOpenFriends: () => _selectTab(3),
          ),
        ),
      ],
    );
  }

  Widget _buildLibraryContent(
    List<LibraryBookDocument> docs, {
    bool wide = false,
  }) {
    final visible = filtered(docs);
    final shownCount = visible.length < _visibleBookCount
        ? visible.length
        : _visibleBookCount;
    final pageDocs = visible.take(shownCount).toList();

    return Column(
      children: [
        _buildLibraryHeader(docs, wide, visible.length),
        if (showLibrarySearch)
          Padding(
            padding: EdgeInsets.fromLTRB(wide ? 34 : 20, 12, wide ? 34 : 20, 0),
            child: _searchField(),
          ),
        Expanded(
          child: _buildBooksScroll(
            visible: visible,
            pageDocs: pageDocs,
            publishers: publishersByBook(docs.map((doc) => doc.data())),
            wide: wide,
            topPadding: 16,
            header: [_libraryFilterChips(docs), const SizedBox(height: 22)],
          ),
        ),
      ],
    );
  }

  Widget _buildLibraryHeader(
    List<LibraryBookDocument> docs,
    bool wide,
    int visibleCount,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 34 : 20, 18, wide ? 34 : 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _librarySelector(),
                const SizedBox(height: 3),
                Text(
                  '$visibleCount books',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Search for a book or author',
            onPressed: () => setState(() {
              showLibrarySearch = !showLibrarySearch;
              if (!showLibrarySearch) search.clear();
              _visibleBookCount = _booksPerPage;
            }),
            icon: Icon(
              showLibrarySearch ? Icons.close_rounded : Icons.search_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Filter',
            onPressed: () => _openFilters(docs),
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: 'Statistics',
            onPressed: () => _openLibraryStats(docs),
            icon: const Icon(Icons.insights_rounded),
          ),
          if (wide)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: scheme.primary.withAlpha(24),
                foregroundColor: scheme.primary,
                child: Text(_userInitial),
              ),
            ),
        ],
      ),
    );
  }

  Widget _libraryFilterChips(List<LibraryBookDocument> docs) {
    final genres = _genreCounts(docs);
    final status = filter;
    final selectedLibraryLabel =
        selectedLibraryOwnerId == uid && selectedPersonalLibraryId.isNotEmpty
        ? _selectedPersonalLibraryName()
        : 'In the library';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _libraryChoiceChip(
                'All',
                !showWishlist &&
                    status == _allFileTypes &&
                    genreFilter == _allFileTypes,
                () => setState(() {
                  showWishlist = false;
                  filter = _allFileTypes;
                  genreFilter = _allFileTypes;
                  _visibleBookCount = _booksPerPage;
                }),
                icon: Icons.library_books_outlined,
                selectedColor: Theme.of(context).colorScheme.primary,
              ),
              _libraryChoiceChip(
                'Currently reading',
                !showWishlist && status == readingStatus,
                () => setState(() {
                  showWishlist = false;
                  filter = readingStatus;
                  _visibleBookCount = _booksPerPage;
                }),
                icon: Icons.menu_book_rounded,
                selectedColor: Colors.blue.shade700,
              ),
              _libraryChoiceChip(
                'Read',
                !showWishlist && status == readStatus,
                () => setState(() {
                  showWishlist = false;
                  filter = readStatus;
                  _visibleBookCount = _booksPerPage;
                }),
                icon: Icons.check_circle_outline_rounded,
                selectedColor: Colors.green.shade700,
              ),
              _libraryChoiceChip(
                noStatusLabel,
                !showWishlist && status == _noStatusFilter,
                () => setState(() {
                  showWishlist = false;
                  filter = _noStatusFilter;
                  _visibleBookCount = _booksPerPage;
                }),
                icon: Icons.remove_circle_outline_rounded,
                selectedColor: Colors.grey.shade700,
              ),
              _libraryChoiceChip(
                'Wish list',
                showWishlist,
                () => setState(() {
                  showWishlist = true;
                  filter = _allFileTypes;
                  _visibleBookCount = _booksPerPage;
                }),
                icon: Icons.bookmark_border_rounded,
                selectedColor: Colors.orange.shade800,
              ),
              _libraryChoiceChip(
                'loan list',
                tab == 2,
                () => _selectTab(2),
                icon: Icons.swap_horiz_rounded,
                selectedColor: Colors.deepPurple.shade600,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Kapsam',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _libraryChoiceChip(
                selectedLibraryLabel,
                !showWishlist && collectionFilter == _homeCollection,
                () => setState(() {
                  showWishlist = false;
                  collectionFilter = _homeCollection;
                  _visibleBookCount = _booksPerPage;
                }),
                icon: Icons.home_rounded,
                selectedColor: Colors.teal.shade700,
              ),
              _libraryChoiceChip(
                'Other',
                !showWishlist && collectionFilter == _readingHistoryCollection,
                () => setState(() {
                  showWishlist = false;
                  collectionFilter = _readingHistoryCollection;
                  _visibleBookCount = _booksPerPage;
                }),
                icon: Icons.history_rounded,
                selectedColor: Colors.indigo.shade700,
              ),
              _libraryChoiceChip(
                'All',
                !showWishlist && collectionFilter == _allCollections,
                () => setState(() {
                  showWishlist = false;
                  collectionFilter = _allCollections;
                  _visibleBookCount = _booksPerPage;
                }),
                icon: Icons.all_inclusive_rounded,
                selectedColor: Colors.deepPurple.shade700,
              ),
            ],
          ),
        ),
        if (genres.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Kategoriler',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _libraryChoiceChip(
                  'All (${docs.length})',
                  genreFilter == _allFileTypes,
                  () => setState(() {
                    genreFilter = _allFileTypes;
                    _visibleBookCount = _booksPerPage;
                  }),
                ),
                for (final entry in genres.entries.take(6))
                  _libraryChoiceChip(
                    '${entry.key} (${entry.value})',
                    genreFilter == entry.key,
                    () => setState(() {
                      genreFilter = entry.key;
                      _visibleBookCount = _booksPerPage;
                    }),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _libraryChoiceChip(
    String label,
    bool selected,
    VoidCallback onTap, {
    IconData? icon,
    Color? selectedColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final accent = selectedColor ?? scheme.primary;
    final activeBackground = Color.alphaBlend(
      accent.withAlpha(42),
      scheme.surface,
    );
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? accent : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
            ],
            Text(label),
          ],
        ),
        selected: selected,
        selectedColor: activeBackground,
        side: selected
            ? BorderSide(color: accent.withAlpha(90))
            : BorderSide.none,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: selected ? accent : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Map<String, int> _genreCounts(Iterable<LibraryBookDocument> docs) {
    final counts = <String, int>{};
    for (final doc in docs) {
      final subjects = doc.data()['subjects'];
      if (subjects is! Iterable) continue;
      for (final genre in normalizeGenres(
        subjects.whereType<String>(),
      ).toSet()) {
        counts[genre] = (counts[genre] ?? 0) + 1;
      }
    }
    return Map.fromEntries(
      counts.entries.toList()..sort(
        (a, b) => b.value == a.value
            ? a.key.compareTo(b.key)
            : b.value.compareTo(a.value),
      ),
    );
  }

  void _loadMoreBooks(int total) {
    if (_visibleBookCount >= total) return;
    setState(() {
      _visibleBookCount = (_visibleBookCount + _booksPerPage)
          .clamp(0, total)
          .toInt();
    });
  }

  Widget _buildTopBar(bool wide) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 34 : 20, 22, wide ? 34 : 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pageTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pageSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (wide) ...[
            const SizedBox(width: 4),
            CircleAvatar(
              radius: 18,
              backgroundColor: scheme.primary.withAlpha(24),
              foregroundColor: scheme.primary,
              child: Text(_userInitial),
            ),
          ],
          if (tab == 4)
            IconButton(
              tooltip: 'Settings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              ),
              icon: const Icon(Icons.settings_rounded),
            ),
        ],
      ),
    );
  }

  String get _userInitial {
    final user = LocalIdentity.instance.currentUser;
    final value = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!
        : user?.email ?? 'O';
    return value.characters.first.toUpperCase();
  }

  Future<UserProfile?> _profileFor(String ownerId) =>
      _libraryProfiles.putIfAbsent(ownerId, () => social.profile(ownerId));

  Future<void> _renameLibrary() async {
    if (!mounted) return;
    final library = _personalLibraries
        .where((library) => library.id == selectedPersonalLibraryId)
        .firstOrNull;
    if (library == null) return;
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RenameLibrarySheet(
        initialName: library.name,
        title: 'Change library name',
      ),
    );
    if (name == null || !mounted) return;
    final libraries = [
      for (final item in _personalLibraries)
        item.id == library.id
            ? PersonalLibrary(id: item.id, name: name.trim())
            : item,
    ];
    await _savePersonalLibraries(libraries);
  }

  Future<void> _createLibrary() async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          const _RenameLibrarySheet(initialName: '', title: 'new library'),
    );
    if (name == null || !mounted) return;
    final library = PersonalLibrary(
      id: social.newPersonalLibraryId(),
      name: name.trim(),
    );
    await _savePersonalLibraries([..._personalLibraries, library]);
    if (mounted) unawaited(_selectPersonalLibrary(library.id));
  }
}
