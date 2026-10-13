import 'package:flutter/material.dart';

import '../data/book_metadata.dart';
import '../data/book_repository.dart';
import '../data/library_stats.dart';
import '../data/library_book_snapshot.dart';
import '../data/social_repository.dart';
import '../viewmodels/library_view_model.dart';
import 'library_page.dart';

const _allDiscoveries = '__all__';

enum _DiscoverSort {
  rank,
  title,
  author,
  genre,
  pages,
  publishedDate,
  addedDate,
}

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key, required this.uid, required this.viewModel});

  final String uid;
  final LibraryViewModel viewModel;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _search = TextEditingController();
  final _social = SocialRepository();
  final _movingBookIds = <String>{};
  late final Stream<List<CatalogBook>> _catalog = widget.viewModel
      .discoverCatalog();
  late final Stream<Set<String>> _ownedBookIds = widget.viewModel
      .libraryBookIds(widget.uid);
  String _author = _allDiscoveries;
  String _genre = _allDiscoveries;
  String _pageRange = _allDiscoveries;
  _DiscoverSort _sort = _DiscoverSort.rank;
  bool _showOwnedBooks = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _move(CatalogBook book) async {
    setState(() => _movingBookIds.add(book.id));
    try {
      final choices = await _libraryChoices();
      if (!mounted) return;
      final selection = await _showMoveSheet(book, choices);
      if (selection == null || !mounted) return;
      final metadata = book.metadata;
      final matches = await widget.viewModel.findDuplicates(
        uid: widget.uid,
        title: metadata.title,
        isbn: metadata.isbn,
      );
      if (matches.any((match) => match.blocksAdding)) {
        throw StateError(
          'This book is already in your library or reading history.',
        );
      }
      final relationId = await widget.viewModel.add(
        widget.uid,
        metadata.title,
        metadata.author,
        metadata: metadata,
        isbn: metadata.isbn.isEmpty ? null : metadata.isbn,
        inHomeLibrary: !selection.history,
        libraryIds: selection.history
            ? const []
            : selection.personalLibraryIds.toList(),
      );
      try {
        if (selection.history) {
          await widget.viewModel.updateStatus(relationId, readStatus);
        }
        if (selection.libraryIds.isNotEmpty) {
          await widget.viewModel.setLibraryTargets(
            widget.uid,
            relationId,
            choices
                .where((choice) => choice.editable)
                .map((choice) => choice.ownerId)
                .toSet(),
            selection.libraryIds,
          );
        }
      } catch (_) {
        try {
          await widget.viewModel.delete(widget.uid, relationId);
        } catch (_) {}
        rethrow;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              selection.history
                  ? 'The book has been added to the Other section.'
                  : 'The book has been added to your library.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _movingBookIds.remove(book.id));
    }
  }

  Future<
    List<
      ({String ownerId, String name, bool editable, String? personalLibraryId})
    >
  >
  _libraryChoices() async {
    final personalLibraries = await _social.personalLibraries(widget.uid);
    final links = await _social.friendLinks(widget.uid).first;
    final friendIds = <String>{
      for (final link in links.docs)
        if (link.data()['memberIds'] is Iterable)
          ...link.data()['memberIds'].whereType<String>().where(
            (id) => id != widget.uid,
          ),
    }.toList()..sort();
    final profiles = await Future.wait(friendIds.map(_social.profile));
    final editable = <String>{widget.uid};
    for (final link in links.docs) {
      final members = link.data()['memberIds'];
      final friendId = members is Iterable
          ? members.whereType<String>().firstWhere(
              (id) => id != widget.uid,
              orElse: () => '',
            )
          : '';
      final permissions = link.data()['permissions'];
      if (friendId.isNotEmpty &&
          permissions is Map &&
          permissions[widget.uid] == 'edit') {
        editable.add(friendId);
      }
    }
    return [
      for (final library in personalLibraries)
        (
          ownerId: widget.uid,
          name: library.name,
          editable: true,
          personalLibraryId: library.id,
        ),
      for (var index = 0; index < friendIds.length; index++)
        (
          ownerId: friendIds[index],
          name: profiles[index]?.libraryName ?? defaultLibraryName,
          editable: editable.contains(friendIds[index]),
          personalLibraryId: null,
        ),
    ];
  }

  Future<
    ({bool history, Set<String> libraryIds, Set<String> personalLibraryIds})?
  >
  _showMoveSheet(
    CatalogBook book,
    List<
      ({String ownerId, String name, bool editable, String? personalLibraryId})
    >
    choices,
  ) async {
    var history = false;
    final selected = <String>{};
    final personalChoices = choices
        .where((choice) => choice.personalLibraryId != null)
        .toList();
    final sharedChoices = choices
        .where((choice) => choice.personalLibraryId == null)
        .toList();
    final selectedPersonal = <String>{personalChoices.first.personalLibraryId!};
    return showModalBottomSheet<
      ({bool history, Set<String> libraryIds, Set<String> personalLibraryIds})
    >(
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
                    'carry the book',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    book.metadata.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ana hedef',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('My Libraries'),
                        avatar: const Icon(
                          Icons.local_library_outlined,
                          size: 18,
                        ),
                        selected: !history,
                        onSelected: (_) => update(() => history = false),
                      ),
                      ChoiceChip(
                        label: const Text('Other'),
                        avatar: const Icon(Icons.history_rounded, size: 18),
                        selected: history,
                        onSelected: (_) => update(() => history = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'My Libraries',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final choice in personalChoices)
                          CheckboxListTile(
                            value: selectedPersonal.contains(
                              choice.personalLibraryId,
                            ),
                            title: Text(choice.name),
                            onChanged: (value) => update(() {
                              final id = choice.personalLibraryId!;
                              if (value == true) {
                                selectedPersonal.add(id);
                              } else {
                                selectedPersonal.remove(id);
                              }
                            }),
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'Shared libraries',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        for (final choice in sharedChoices)
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
                        if (sharedChoices.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('There are no shared libraries yet.'),
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
                        onPressed: () => Navigator.pop(sheetContext, (
                          history: history,
                          libraryIds: Set<String>.from(selected),
                          personalLibraryIds: Set<String>.from(
                            selectedPersonal,
                          ),
                        )),
                        child: const Text('Move'),
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
  }

  List<CatalogBook> _visibleBooks(
    List<CatalogBook> catalog,
    Set<String> ownedBookIds,
  ) {
    final query = _search.text.trim();
    final visible = catalog.where((book) {
      if (!_showOwnedBooks && ownedBookIds.contains(book.id)) return false;
      final metadata = book.metadata;
      if (query.isNotEmpty &&
          !matchesBookSearchText(query, metadata.title) &&
          !matchesBookSearchText(query, metadata.author)) {
        return false;
      }
      if (_author != _allDiscoveries &&
          !authorsFromBook(metadata.toFirestoreFields())
              .any((author) => _sameLabel(author, _author))) {
        return false;
      }
      if (_genre != _allDiscoveries &&
          !metadata.subjects.any((genre) => _sameLabel(genre, _genre))) {
        return false;
      }
      return _pageMatches(metadata.pageCount);
    }).toList();
    visible.sort(_compare);
    return visible;
  }

  bool _pageMatches(int? pages) => switch (_pageRange) {
    _allDiscoveries => true,
    'short' => pages != null && pages <= 200,
    'medium' => pages != null && pages > 200 && pages <= 400,
    'long' => pages != null && pages > 400,
    _ => true,
  };

  int _compare(CatalogBook first, CatalogBook second) {
    final firstMetadata = first.metadata;
    final secondMetadata = second.metadata;
    return switch (_sort) {
      _DiscoverSort.rank => (first.rank ?? 1 << 30).compareTo(
        second.rank ?? 1 << 30,
      ),
      _DiscoverSort.title => _label(
        firstMetadata.title,
      ).compareTo(_label(secondMetadata.title)),
      _DiscoverSort.author => _label(
        firstMetadata.author,
      ).compareTo(_label(secondMetadata.author)),
      _DiscoverSort.genre => _label(
        _firstGenre(firstMetadata),
      ).compareTo(_label(_firstGenre(secondMetadata))),
      _DiscoverSort.pages => (secondMetadata.pageCount ?? 0).compareTo(
        firstMetadata.pageCount ?? 0,
      ),
      _DiscoverSort.publishedDate => _year(
        secondMetadata,
      ).compareTo(_year(firstMetadata)),
      _DiscoverSort.addedDate => (second.addedAt ?? DateTime(1970)).compareTo(
        first.addedAt ?? DateTime(1970),
      ),
    };
  }

  int _year(BookMetadata metadata) =>
      publishedYearOf(metadata.toFirestoreFields()) ?? 0;

  String _firstGenre(BookMetadata metadata) =>
      metadata.subjects.firstOrNull ?? '';

  bool _sameLabel(String first, String second) =>
      _label(first) == _label(second);

  String _label(String value) => normalizeBookSearchText(value);

  String _sortLabel(_DiscoverSort sort) => switch (sort) {
    _DiscoverSort.rank => 'Popularity',
    _DiscoverSort.title => 'book name',
    _DiscoverSort.author => 'Author',
    _DiscoverSort.genre => 'Genre',
    _DiscoverSort.pages => 'Number of pages',
    _DiscoverSort.publishedDate => 'Publication date',
    _DiscoverSort.addedDate => 'Date added',
  };

  IconData _sortIcon(_DiscoverSort sort) => switch (sort) {
    _DiscoverSort.rank => Icons.local_fire_department_rounded,
    _DiscoverSort.title => Icons.sort_by_alpha_rounded,
    _DiscoverSort.author => Icons.person_outline_rounded,
    _DiscoverSort.genre => Icons.category_outlined,
    _DiscoverSort.pages => Icons.menu_book_outlined,
    _DiscoverSort.publishedDate => Icons.event_available_outlined,
    _DiscoverSort.addedDate => Icons.new_releases_outlined,
  };

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CatalogBook>>(
    stream: _catalog,
    builder: (context, catalogSnapshot) {
      if (catalogSnapshot.hasError) {
        return _message('The Discover catalog failed to load.');
      }
      if (!catalogSnapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return StreamBuilder<Set<String>>(
        stream: _ownedBookIds,
        builder: (context, ownershipSnapshot) {
          if (ownershipSnapshot.hasError) {
            return _message('Could not load library matches.');
          }
          if (!ownershipSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final catalog = catalogSnapshot.data!;
          final visible = _visibleBooks(catalog, ownershipSnapshot.data!);
          return Column(
            children: [
              _header(catalog.length, visible.length),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search for a book or author',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'clear search',
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              _filterBar(catalog),
              const SizedBox(height: 8),
              Expanded(
                child: visible.isEmpty
                    ? _message('There are no books to show in these filters.')
                    : LayoutBuilder(
                        builder: (context, constraints) => GridView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                          gridDelegate:
                              SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 230,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 14,
                                childAspectRatio: constraints.maxWidth < 520
                                    ? .46
                                    : .52,
                              ),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final book = visible[index];
                            return buildLibraryBookCard(
                              doc: _libraryDocument(book),
                              busy: _movingBookIds.contains(book.id),
                              onLongPress: () => _move(book),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      );
    },
  );

  Widget _header(int catalogCount, int visibleCount) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withAlpha(22),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.explore_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Discover',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                '$visibleCount books · $catalogCount in catalog',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _filterBar(List<CatalogBook> catalog) {
    final activeFilters = [
      if (_author != _allDiscoveries) 'Author: $_author',
      if (_genre != _allDiscoveries) 'Genre: $_genre',
      if (_pageRange != _allDiscoveries) 'Pages: ${_pageLabel(_pageRange)}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withAlpha(120),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  selected: activeFilters.isNotEmpty,
                  avatar: const Icon(Icons.tune_rounded, size: 17),
                  label: Text(
                    activeFilters.isEmpty
                        ? 'Filter'
                        : 'Filters (${activeFilters.length})',
                  ),
                  showCheckmark: false,
                  onSelected: (_) => _openFilters(catalog),
                ),
                PopupMenuButton<_DiscoverSort>(
                  tooltip: 'Sort by',
                  onSelected: (value) => setState(() => _sort = value),
                  itemBuilder: (context) => [
                    for (final sort in _DiscoverSort.values)
                      PopupMenuItem(
                        value: sort,
                        child: Row(
                          children: [
                            Icon(_sortIcon(sort), size: 18),
                            const SizedBox(width: 10),
                            Text(_sortLabel(sort)),
                            if (sort == _sort) ...[
                              const Spacer(),
                              const Icon(Icons.check_rounded, size: 18),
                            ],
                          ],
                        ),
                      ),
                  ],
                  child: InputChip(
                    avatar: Icon(_sortIcon(_sort), size: 17),
                    label: Text(_sortLabel(_sort)),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Bende olanlar'),
                    Switch.adaptive(
                      value: _showOwnedBooks,
                      onChanged: (value) =>
                          setState(() => _showOwnedBooks = value),
                    ),
                  ],
                ),
              ],
            ),
            if (activeFilters.isNotEmpty) ...[
              const SizedBox(height: 2),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final filter in activeFilters)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Chip(
                          label: Text(filter),
                          deleteIcon: const Icon(Icons.close_rounded, size: 16),
                          onDeleted: () => _clearFilter(filter),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _pageLabel(String value) => switch (value) {
    'short' => '0–200',
    'medium' => '201–400',
    'long' => '401+',
    _ => 'All',
  };

  void _clearFilter(String filter) {
    setState(() {
      if (filter.startsWith('Author:')) _author = _allDiscoveries;
      if (filter.startsWith('Type:')) _genre = _allDiscoveries;
      if (filter.startsWith('Page:')) _pageRange = _allDiscoveries;
    });
  }

  Future<void> _openFilters(List<CatalogBook> catalog) async {
    final authors = <String>{
      for (final book in catalog) ...book.metadata.authors,
    }.where((value) => value.trim().isNotEmpty).toList()..sort();
    final genres = <String>{
      for (final book in catalog) ...book.metadata.subjects,
    }.where((value) => value.trim().isNotEmpty).toList()..sort();
    final selection =
        await showModalBottomSheet<
          ({String author, String genre, String pageRange})
        >(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (context) {
            var author = _author;
            var genre = _genre;
            var pageRange = _pageRange;
            return StatefulBuilder(
              builder: (context, update) => Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Edit filters',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: author,
                        decoration: const InputDecoration(
                          labelText: 'Author',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: _allDiscoveries,
                            child: Text('All authors'),
                          ),
                          for (final value in authors)
                            DropdownMenuItem(value: value, child: Text(value)),
                        ],
                        onChanged: (value) {
                          if (value != null) update(() => author = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: genre,
                        decoration: const InputDecoration(
                          labelText: 'Genre',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: _allDiscoveries,
                            child: Text('All genres'),
                          ),
                          for (final value in genres)
                            DropdownMenuItem(value: value, child: Text(value)),
                        ],
                        onChanged: (value) {
                          if (value != null) update(() => genre = value);
                        },
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Number of pages',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final value in [
                            _allDiscoveries,
                            'short',
                            'medium',
                            'long',
                          ])
                            ChoiceChip(
                              label: Text(
                                value == _allDiscoveries
                                    ? 'All'
                                    : _pageLabel(value),
                              ),
                              selected: pageRange == value,
                              onSelected: (_) =>
                                  update(() => pageRange = value),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              update(() {
                                author = _allDiscoveries;
                                genre = _allDiscoveries;
                                pageRange = _allDiscoveries;
                              });
                            },
                            child: const Text('Clear'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () => Navigator.pop(context, (
                              author: author,
                              genre: genre,
                              pageRange: pageRange,
                            )),
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Uygula'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
    if (!mounted || selection == null) return;
    setState(() {
      _author = selection.author;
      _genre = selection.genre;
      _pageRange = selection.pageRange;
    });
  }

  Widget _message(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );

  LibraryBookDocument _libraryDocument(CatalogBook book) {
    final metadata = book.metadata;
    return LibraryBookDocument.local(book.id, {
      ...metadata.toFirestoreFields(),
      'title': metadata.title,
      'author': metadata.author,
      'bookId': book.id,
      'libraryId': widget.uid,
      'status': null,
      'wishlist': false,
      'inHomeLibrary': true,
    });
  }
}
