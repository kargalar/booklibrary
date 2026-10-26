part of 'reader_page.dart';

// ignore_for_file: invalid_use_of_protected_member
extension _ReaderNavigationTools on _ReaderPageState {
  Future<void> showPageNavigator() async {
    revealChrome();
    if (!isPdf || pdfPages == 0) return;
    final selected = await showReaderSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _PdfPageNavigator(
        controller: pdfController,
        pageCount: pdfPages,
        currentPage: position,
        bookmarks: bookmarks,
        onSelect: (page) => Navigator.pop(context, page),
      ),
    );
    if (selected != null && mounted) await goToPdfPage(selected);
  }

  Future<void> showBookmarks() async {
    revealChrome();
    final selected = await showReaderSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (context) {
        final pages = bookmarks.toList()..sort();
        if (pages.isEmpty) {
          return const SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bookmark_border_rounded, size: 44),
                  SizedBox(height: 12),
                  Text(_ReaderLabels.noBookmarks),
                  SizedBox(height: 6),
                  Text(_ReaderLabels.bookmarksHint),
                ],
              ),
            ),
          );
        }
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .55,
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.bookmarks_rounded),
                  title: Text(_ReaderLabels.bookmarks),
                  subtitle: Text(_ReaderLabels.savedLocations),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: pages.length,
                    itemBuilder: (context, index) {
                      final page = pages[index];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text(isPdf ? 'Page $page' : chapterTitle(page)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.pop(context, page),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null && mounted) {
      if (isPdf) {
        await goToPdfPage(selected);
      } else {
        go(selected);
      }
    }
  }

  Future<void> showGoToPage() async {
    revealChrome();
    if (!isPdf || pdfPages == 0) return;
    var input = '$position';
    final page = await showReaderDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(_ReaderLabels.goToPage),
        content: TextFormField(
          initialValue: input,
          onChanged: (value) => input = value,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: _ReaderLabels.pageNumber,
            hintText: '1 â€“ $pdfPages',
          ),
          onFieldSubmitted: (_) => Navigator.pop(context, int.tryParse(input)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(_ReaderLabels.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(input)),
            child: const Text(_ReaderLabels.go),
          ),
        ],
      ),
    );
    if (page != null && mounted) await goToPdfPage(page);
  }

  Future<void> showPdfSearch() async {
    revealChrome();
    final searcher = pdfSearcher;
    if (searcher == null) return;
    await showReaderSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: StatefulBuilder(
          builder: (context, update) => ListenableBuilder(
            listenable: searcher,
            builder: (context, _) => SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.search_rounded),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _ReaderLabels.searchPdf,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: _ReaderLabels.close,
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: _ReaderLabels.typeSearch,
                        prefixIcon: const Icon(Icons.manage_search_rounded),
                        suffixIcon: searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: _ReaderLabels.clear,
                                onPressed: () {
                                  searchController.clear();
                                  searcher.resetTextSearch();
                                  update(() {});
                                },
                                icon: const Icon(Icons.clear_rounded),
                              ),
                      ),
                      onChanged: (value) {
                        searcher.startTextSearch(value.trim());
                        update(() {});
                      },
                      onSubmitted: (value) => searcher.startTextSearch(
                        value.trim(),
                        searchImmediately: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (searcher.isSearching)
                      const LinearProgressIndicator(minHeight: 2),
                    if (!searcher.isSearching &&
                        searchController.text.trim().isNotEmpty)
                      Text(
                        searcher.matches.isEmpty
                            ? _ReaderLabels.noResults
                            : '${searcher.matches.length} results found',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (searcher.matches.isNotEmpty)
                      Row(
                        children: [
                          Text(
                            '${(searcher.currentIndex ?? 0) + 1} / ${searcher.matches.length}',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'previous result',
                            onPressed: () =>
                                unawaited(searcher.goToPrevMatch()),
                            icon: const Icon(Icons.keyboard_arrow_up_rounded),
                          ),
                          IconButton(
                            tooltip: _ReaderLabels.nextResult,
                            onPressed: () =>
                                unawaited(searcher.goToNextMatch()),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}
