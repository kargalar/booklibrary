part of 'library_page.dart';

// This extension keeps the legacy State API split by concern without duplicating state.
// ignore_for_file: invalid_use_of_protected_member
extension _LibraryPageStatePart5 on _LibraryPageState {
  Future<void> _openFilters(List<LibraryBookDocument> docs) async {
    await _loadLocalFileAvailability(docs);
    if (!mounted) return;
    final minPages = TextEditingController(text: minPageFilter?.toString());
    final maxPages = TextEditingController(text: maxPageFilter?.toString());
    final fromYear = TextEditingController(text: fromYearFilter?.toString());
    final toYear = TextEditingController(text: toYearFilter?.toString());
    final selection = await showModalBottomSheet<_LibraryFilterSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        var selectedAuthor = authorFilter;
        var selectedGenre = genreFilter;
        final selectedFacets = Map<String, String>.from(facetFilters);
        var selectedFileType = fileTypeFilter;
        var selectedRating = minRatingFilter;
        String? error;
        final authors =
            docs.expand((doc) => authorsFromBook(doc.data())).toSet().toList()
              ..sort();
        final genres = <String>{};
        for (final doc in docs) {
          final subjects = doc.data()['subjects'];
          if (subjects is Iterable) {
            genres.addAll(normalizeGenres(subjects.whereType<String>()));
          }
        }
        final genreOptions = genres.toList()..sort();
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                4,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Book filters',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Basic filters',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'File type',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final option in const [
                          (_allFileTypes, 'All'),
                          (_readingFileType, 'PDF / EPUB'),
                          (_audioFileType, 'audiobook'),
                        ])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: selectedFileType == option.$1
                                  ? FilledButton(
                                      onPressed: () => setSheetState(
                                        () => selectedFileType = option.$1,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(option.$2),
                                      ),
                                    )
                                  : OutlinedButton(
                                      onPressed: () => setSheetState(
                                        () => selectedFileType = option.$1,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(option.$2),
                                      ),
                                    ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: RawAutocomplete<String>(
                            initialValue: TextEditingValue(
                              text: authorFilter == 'All' ? '' : authorFilter,
                            ),
                            displayStringForOption: (value) => value,
                            optionsBuilder: (value) {
                              final query = value.text.trim();
                              if (query.isEmpty) return const <String>[];
                              return authors
                                  .where(
                                    (author) =>
                                        matchesBookSearchText(query, author),
                                  )
                                  .take(8);
                            },
                            onSelected: (value) =>
                                setSheetState(() => selectedAuthor = value),
                            fieldViewBuilder:
                                (context, controller, focusNode, onSubmitted) =>
                                    TextField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      onChanged: (value) => setSheetState(() {
                                        selectedAuthor = authors.contains(value)
                                            ? value
                                            : 'All';
                                      }),
                                      onSubmitted: (_) => onSubmitted(),
                                      decoration: const InputDecoration(
                                        labelText: 'Search for author',
                                        prefixIcon: Icon(Icons.search_rounded),
                                      ),
                                    ),
                            optionsViewBuilder:
                                (context, onSelected, options) => Material(
                                  elevation: 4,
                                  borderRadius: BorderRadius.circular(12),
                                  child: ListView(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    children: [
                                      for (final author in options)
                                        ListTile(
                                          dense: true,
                                          title: Text(author),
                                          onTap: () => onSelected(author),
                                        ),
                                    ],
                                  ),
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: genreOptions.contains(selectedGenre)
                                ? selectedGenre
                                : 'All',
                            decoration: const InputDecoration(
                              labelText: 'Genre',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'All',
                                child: Text('All genres'),
                              ),
                              ...genreOptions.map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              ),
                            ],
                            onChanged: (value) => setSheetState(
                              () => selectedGenre = value ?? 'All',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        initiallyExpanded: false,
                        leading: const Icon(Icons.tune_rounded),
                        title: const Text('Advanced filters'),
                        subtitle: const Text(
                          'Page, score, year and other information',
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final facet in bookFacetLabels.entries)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: DropdownButtonFormField<String>(
                                      initialValue:
                                          selectedFacets[facet.key] ?? '',
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: facet.value,
                                      ),
                                      items: [
                                        const DropdownMenuItem(
                                          value: '',
                                          child: Text('All'),
                                        ),
                                        for (final value in ({
                                          ...bookFacetCounts(
                                            docs.map((doc) => doc.data()),
                                            facet.key,
                                          ).keys,
                                          if (selectedFacets[facet.key] != null)
                                            selectedFacets[facet.key]!,
                                        }.toList()..sort()))
                                          DropdownMenuItem(
                                            value: value,
                                            child: Text(
                                              value,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                      onChanged: (value) => setSheetState(() {
                                        if (value == null || value.isEmpty) {
                                          selectedFacets.remove(facet.key);
                                        } else {
                                          selectedFacets[facet.key] = value;
                                        }
                                      }),
                                    ),
                                  ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: minPages,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Min. page',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: maxPages,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Max. page',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Minimum rating',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                    Text(
                                      selectedRating == null
                                          ? 'All points'
                                          : '$selectedRating and up',
                                    ),
                                  ],
                                ),
                                Slider(
                                  value: (selectedRating ?? 0).toDouble(),
                                  min: 0,
                                  max: 5,
                                  divisions: 5,
                                  label: selectedRating == null
                                      ? 'All'
                                      : '$selectedRating',
                                  onChanged: (value) => setSheetState(
                                    () => selectedRating = value.round() == 0
                                        ? null
                                        : value.round(),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: fromYear,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'First year of publication',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: toYear,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Last publication year',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(
                              context,
                              const _LibraryFilterSelection(),
                            ),
                            child: const Text('Clear'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              final minPage = int.tryParse(
                                minPages.text.trim(),
                              );
                              final maxPage = int.tryParse(
                                maxPages.text.trim(),
                              );
                              final startYear = int.tryParse(
                                fromYear.text.trim(),
                              );
                              final endYear = int.tryParse(toYear.text.trim());
                              final hasInvalidNumber =
                                  (minPages.text.trim().isNotEmpty &&
                                      minPage == null) ||
                                  (maxPages.text.trim().isNotEmpty &&
                                      maxPage == null) ||
                                  (fromYear.text.trim().isNotEmpty &&
                                      startYear == null) ||
                                  (toYear.text.trim().isNotEmpty &&
                                      endYear == null);
                              if (hasInvalidNumber ||
                                  (minPage != null && minPage < 0) ||
                                  (maxPage != null && maxPage < 0) ||
                                  (minPage != null &&
                                      maxPage != null &&
                                      minPage > maxPage) ||
                                  (startYear != null && startYear < 1000) ||
                                  (endYear != null && endYear < 1000) ||
                                  (startYear != null &&
                                      endYear != null &&
                                      startYear > endYear)) {
                                setSheetState(
                                  () => error = 'Check range values.',
                                );
                                return;
                              }
                              Navigator.pop(
                                context,
                                _LibraryFilterSelection(
                                  author: selectedAuthor,
                                  genre: selectedGenre,
                                  facets: selectedFacets,
                                  fileType: selectedFileType,
                                  minPages: minPage,
                                  maxPages: maxPage,
                                  minRating: selectedRating,
                                  fromYear: startYear,
                                  toYear: endYear,
                                ),
                              );
                            },
                            child: const Text('Uygula'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    minPages.dispose();
    maxPages.dispose();
    fromYear.dispose();
    toYear.dispose();
    if (selection == null || !mounted) return;
    try {
      if (selection.minRating != null) await _loadRatingAverages(docs);
      if (!mounted) return;
      setState(() {
        authorFilter = selection.author;
        genreFilter = selection.genre;
        facetFilters = selection.facets;
        fileTypeFilter = selection.fileType;
        minPageFilter = selection.minPages;
        maxPageFilter = selection.maxPages;
        minRatingFilter = selection.minRating;
        fromYearFilter = selection.fromYear;
        toYearFilter = selection.toYear;
        _visibleBookCount = _booksPerPage;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Points could not be loaded.')),
        );
      }
    }
  }

  Iterable<LibraryBookDocument> _titleOptions(TextEditingValue value) {
    final query = value.text.trim();
    if (query.length < 2) return const [];
    return _bookDocs
        .where((book) {
          final title = book.data()['title'];
          return title is String && matchesBookSearchText(query, title);
        })
        .take(8);
  }

  Iterable<String> _authorOptions(TextEditingValue value) {
    final authors = normalizeBookItems(
      _bookDocs.expand((book) => authorsFromBook(book.data())),
    )..sort();
    final query = value.text.trim();
    if (query.isEmpty) return authors.take(8);
    return authors
        .where((author) => matchesBookSearchText(query, author))
        .take(8);
  }

  Iterable<String> _publisherOptions(TextEditingValue value) {
    final publishers = normalizeBookItems(
      _bookDocs.map((book) => book.data()['publisher']).whereType<String>(),
    )..sort();
    final query = value.text.trim();
    if (query.isEmpty) return publishers.take(8);
    return publishers
        .where((publisher) => matchesBookSearchText(query, publisher))
        .take(8);
  }

  Iterable<String> _genreOptions(TextEditingValue value) {
    final genres = <String>[..._defaultGenres];
    for (final book in _bookDocs) {
      final subjects = book.data()['subjects'];
      if (subjects is Iterable) genres.addAll(subjects.whereType<String>());
    }
    final options = normalizeGenres(genres)..sort();
    final query = value.text.trim();
    if (query.isEmpty) return options.take(8);
    return options
        .where((genre) => matchesBookSearchText(query, genre))
        .take(8);
  }

  Iterable<String> _languageOptions(TextEditingValue value) {
    final languages = <String>[..._defaultLanguages];
    for (final book in _bookDocs) {
      final language = book.data()['language'];
      if (language is String) languages.add(language);
    }
    final options = normalizeLanguages(languages)..sort();
    final query = value.text.trim();
    if (query.isEmpty) return options.take(8);
    return options
        .where((language) => matchesBookSearchText(query, language))
        .take(8);
  }

  String get pageTitle {
    if (tab == 2) return 'Loan tracking';
    if (tab == 3) return 'Your friends';
    if (tab == 4) return 'Profile';
    return switch (tab) {
      1 => 'Your library',
      2 => 'Your purchase list',
      3 => 'Loan tracking',
      4 => 'Your reading statistics',
      5 => 'Your friends',
      _ => 'Home',
    };
  }

  String get pageSubtitle {
    if (tab == 2) return 'See who has which book at a glance.';
    if (tab == 3) {
      return 'Discover your friends\' books, ratings, and scores.';
    }
    if (tab == 4) return 'Manage your reading goal and statistics.';
    return switch (tab) {
      1 => 'Manage all your books and libraries you have access to.',
      2 => 'Keep the books you want to buy here.',
      3 => 'See who has which book at a glance.',
      4 => 'Track your reading habits and progress.',
      5 => 'Discover your friends\' books, grades and scores.',
      _ => 'The books you are currently reading are here.',
    };
  }

  void _selectTab(int value) {
    _lastBackPress = null;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    setState(() {
      tab = value;
      _visibleBookCount = _booksPerPage;
    });
  }

  void _handleBack() {
    if (tab != 0) {
      _selectTab(0);
      return;
    }

    final now = DateTime.now();
    final lastBackPress = _lastBackPress;
    if (lastBackPress != null &&
        now.difference(lastBackPress) <= _backPressWindow) {
      unawaited(SystemNavigator.pop());
      return;
    }

    _lastBackPress = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Press Back again to exit.')),
      );
  }

  Widget _loadingScaffold() => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 960;
      final content = _loadingContent(wide);
      return Semantics(
        label: 'Loading books',
        liveRegion: true,
        child: Scaffold(
          body: SafeArea(
            child: wide
                ? Row(
                    children: [
                      _buildSidebar(),
                      Expanded(child: content),
                    ],
                  )
                : content,
          ),
          bottomNavigationBar: wide
              ? null
              : SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: 8),
                  child: _buildBottomNavigation(),
                ),
        ),
      );
    },
  );

  Widget _loadingContent(bool wide) => Column(
    children: [
      _loadingHeader(wide),
      Expanded(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            wide ? 34 : 20,
            tab == 1 ? 16 : 8,
            wide ? 34 : 20,
            32,
          ),
          children: [
            if (tab == 1) ...[
              _loadingFilterChips(),
              const SizedBox(height: 22),
            ],
            _loadingSectionHeading(),
            const SizedBox(height: 12),
            _loadingBookGrid(),
          ],
        ),
      ),
    ],
  );

  Widget _loadingHeader(bool wide) {
    if (tab == 1) {
      return Padding(
        padding: EdgeInsets.fromLTRB(wide ? 34 : 20, 18, wide ? 34 : 16, 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _shimmerBlock(width: 148, height: 24, borderRadius: 7),
                  const SizedBox(height: 4),
                  _shimmerBlock(width: 64, height: 12, borderRadius: 4),
                ],
              ),
            ),
            _shimmerBlock(width: 40, height: 40, borderRadius: 20),
            const SizedBox(width: 4),
            _shimmerBlock(width: 40, height: 40, borderRadius: 20),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 34 : 20, 22, wide ? 34 : 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _shimmerBlock(width: 176, height: 28, borderRadius: 7),
                const SizedBox(height: 5),
                _shimmerBlock(width: 238, height: 14, borderRadius: 4),
              ],
            ),
          ),
          if (wide) _shimmerBlock(width: 36, height: 36, borderRadius: 18),
        ],
      ),
    );
  }

  Widget _loadingFilterChips() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      _shimmerBlock(width: 82, height: 32, borderRadius: 18),
      _shimmerBlock(width: 104, height: 32, borderRadius: 18),
      _shimmerBlock(width: 76, height: 32, borderRadius: 18),
      _shimmerBlock(width: 96, height: 32, borderRadius: 18),
    ],
  );

  Widget _loadingSectionHeading() => Row(
    children: [
      _shimmerBlock(width: 142, height: 24, borderRadius: 6),
      const SizedBox(width: 8),
      _shimmerBlock(width: 28, height: 24, borderRadius: 20),
    ],
  );

  Widget _loadingBookGrid() => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 12.0;
      final columnCount = constraints.maxWidth >= 1100
          ? 6
          : constraints.maxWidth >= 800
          ? 5
          : constraints.maxWidth >= 560
          ? 4
          : 3;
      final cardWidth =
          (constraints.maxWidth - spacing * (columnCount - 1)) / columnCount;
      return Wrap(
        spacing: spacing,
        runSpacing: 14,
        children: [
          for (var index = 0; index < 8; index++)
            SizedBox(width: cardWidth, child: _loadingBookCard()),
        ],
      );
    },
  );
}
