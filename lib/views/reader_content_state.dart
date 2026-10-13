part of 'reader_page.dart';

// Split by reader concern while preserving the existing StatefulWidget state.
// ignore_for_file: invalid_use_of_protected_member
extension _ReaderPageStatePart1 on _ReaderPageState {
  String get key => widget.storageKey;

  bool get isPdf => p.extension(widget.file.path).toLowerCase() == '.pdf';

  double get progress {
    if (isPdf) {
      if (pdfPages == 0) return 0;
      if (pdfPages == 1) return 1;
      return ((position - 1) / (pdfPages - 1)).clamp(0, 1).toDouble();
    }
    if (sections.isEmpty) return 0;
    final sectionProgress =
        scroll.hasClients && scroll.position.maxScrollExtent > 0
        ? (offset / scroll.position.maxScrollExtent).clamp(0, 1)
        : 1.0;
    return ((position + sectionProgress) / sections.length)
        .clamp(0, 1)
        .toDouble();
  }

  Future<void> load() async {
    if (!await widget.file.exists()) {
      throw FileSystemException('File not found', widget.file.path);
    }

    prefs = await SharedPreferences.getInstance();
    position = prefs.getInt('$key.position') ?? (isPdf ? 1 : 0);
    fontSize = (prefs.getDouble('reader.fontSize') ?? 20).clamp(12, 36);
    lineHeight = (prefs.getDouble('reader.lineHeight') ?? 1.6).clamp(1, 2.5);
    margin = (prefs.getDouble('reader.margin') ?? 20).clamp(8, 48);
    palette = (prefs.getInt('reader.palette') ?? 0).clamp(0, 2);
    serif = prefs.getBool('reader.serif') ?? false;
    justify = prefs.getBool('reader.justify') ?? false;
    alwaysShowChrome = prefs.getBool('$key.alwaysShowChrome') ?? false;
    offset = prefs.getDouble('$key.offset') ?? 0;
    bookmarks
      ..clear()
      ..addAll(
        (prefs.getStringList('$key.bookmarks') ?? const <String>[])
            .map(int.tryParse)
            .whereType<int>(),
      );

    if (!isPdf) {
      // EPUBs are kept as a backwards-compatible fallback; PDF remains the primary reader.
      epub = await EpubReader.readBook(await widget.file.readAsBytes());
      sections = readingOrder(epub!);
      void collectTitles(List<EpubChapter> chapters) {
        for (final chapter in chapters) {
          if (chapter.ContentFileName != null && chapter.Title != null) {
            sectionTitles.putIfAbsent(
              chapter.ContentFileName!,
              () => chapter.Title!,
            );
          }
          collectTitles(chapter.SubChapters ?? []);
        }
      }

      collectTitles(epub!.Chapters ?? []);
      position = sections.isEmpty ? 0 : position.clamp(0, sections.length - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(offset.clamp(0, scroll.position.maxScrollExtent));
        }
      });
    } else {
      position = position < 1 ? 1 : position;
    }

    loaded = true;
  }

  Future<void> save() async {
    if (!loaded) return;
    try {
      await prefs.setInt('$key.position', position);
      await prefs.setDouble('$key.offset', offset);
      await prefs.setStringList(
        '$key.bookmarks',
        bookmarks.map((page) => '$page').toList()..sort(),
      );
      await prefs.setDouble('reader.fontSize', fontSize);
      await prefs.setDouble('reader.lineHeight', lineHeight);
      await prefs.setDouble('reader.margin', margin);
      await prefs.setInt('reader.palette', palette);
      await prefs.setBool('reader.serif', serif);
      await prefs.setBool('reader.justify', justify);
      await prefs.setBool('$key.alwaysShowChrome', alwaysShowChrome);
      await widget.onProgress?.call(progress);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reading settings could not be saved.')),
        );
      }
    }
  }

  void scheduleSave() {
    saveTimer?.cancel();
    saveTimer = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(save()),
    );
  }

  void revealChrome({bool toggle = false}) {
    if (!isPdf || alwaysShowChrome) return;
    chromeTimer?.cancel();
    setState(() => showChrome = toggle ? !showChrome : true);
    if (showChrome) {
      chromeTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && !alwaysShowChrome) setState(() => showChrome = false);
      });
    }
    SystemChrome.setEnabledSystemUIMode(
      showChrome ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  void go(int index) {
    setState(() {
      position = index;
      offset = 0;
      selectedText = '';
    });
    if (scroll.hasClients) scroll.jumpTo(0);
    scheduleSave();
  }

  Future<void> goToPdfPage(int page) async {
    if (!isPdf || pdfPages == 0 || !pdfController.isReady) return;
    final target = page.clamp(1, pdfPages).toInt();
    revealChrome();
    await pdfController.goToPage(pageNumber: target);
    if (!mounted) return;
    setState(() => position = target);
    scheduleSave();
  }

  Future<void> zoomPdfIn() async {
    if (!isPdf || !pdfController.isReady) return;
    revealChrome();
    await pdfController.zoomUp(loop: false);
  }

  Future<void> zoomPdfOut() async {
    if (!isPdf || !pdfController.isReady) return;
    revealChrome();
    await pdfController.zoomDown(loop: false);
  }

  Future<void> fitPdfPage() async {
    if (!isPdf || !pdfController.isReady) return;
    revealChrome();
    final matrix = pdfController.calcMatrixForFit(pageNumber: position);
    if (matrix != null) await pdfController.goTo(matrix);
  }

  Future<void> toggleBookmark() async {
    if (!isPdf || pdfPages == 0) return;
    setState(() {
      if (!bookmarks.add(position)) bookmarks.remove(position);
    });
    await save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1400),
        content: Text(
          bookmarks.contains(position)
              ? 'Page added to bookmarks.'
              : 'Bookmark removed.',
        ),
      ),
    );
  }

  Future<void> showPageNavigator() async {
    revealChrome();
    if (!isPdf || pdfPages == 0) return;
    final selected = await showModalBottomSheet<int>(
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
    final selected = await showModalBottomSheet<int>(
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
                  Text('No bookmarks yet.'),
                  SizedBox(height: 6),
                  Text('While reading, tap the bookmark icon in the top bar.'),
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
                  title: Text('Yer imleri'),
                  subtitle: Text('Saved pages in this PDF'),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: pages.length,
                    itemBuilder: (context, index) {
                      final page = pages[index];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text('Page $page'),
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
    if (selected != null && mounted) await goToPdfPage(selected);
  }

  Future<void> showGoToPage() async {
    revealChrome();
    if (!isPdf || pdfPages == 0) return;
    final input = TextEditingController(text: '$position');
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Page number',
            hintText: '1 – $pdfPages',
          ),
          onSubmitted: (_) => Navigator.pop(context, int.tryParse(input.text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(input.text)),
            child: const Text('Git'),
          ),
        ],
      ),
    );
    input.dispose();
    if (page != null && mounted) await goToPdfPage(page);
  }

  Future<void> showPdfSearch() async {
    revealChrome();
    final searcher = pdfSearcher;
    if (searcher == null) return;
    await showModalBottomSheet<void>(
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
                        Text(
                          'Search in PDF',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Close',
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
                        hintText: 'Type a word or phrase',
                        prefixIcon: const Icon(Icons.manage_search_rounded),
                        suffixIcon: searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
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
                            ? 'No results found.'
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
                            tooltip: 'Next result',
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
    searchController.clear();
    searcher.resetTextSearch();
    if (mounted) setState(() {});
  }

  Future<void> settings() async {
    if (isPdf) {
      await showPdfSettings();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          void change(VoidCallback action) {
            setState(action);
            update(() {});
            scheduleSave();
          }

          Widget slider(
            String title,
            double value,
            double min,
            double max,
            ValueChanged<double> onChange,
          ) => Column(
            children: [
              Text('$title: ${value.toStringAsFixed(1)}'),
              Slider(
                value: value,
                min: min,
                max: max,
                onChanged: (v) => change(() => onChange(v)),
              ),
            ],
          );

          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Reading view',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    slider('Font size', fontSize, 12, 36, (v) => fontSize = v),
                    slider(
                      'line spacing',
                      lineHeight,
                      1,
                      2.5,
                      (v) => lineHeight = v,
                    ),
                    slider('margin', margin, 8, 48, (v) => margin = v),
                    _paletteChoices(
                      palette,
                      (value) => change(() => palette = value),
                    ),
                    SwitchListTile(
                      title: const Text('serif font'),
                      value: serif,
                      onChanged: (v) => change(() => serif = v),
                    ),
                    SwitchListTile(
                      title: const Text('Justify'),
                      value: justify,
                      onChanged: (v) => change(() => justify = v),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> showPdfSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          void change(VoidCallback action) {
            setState(action);
            update(() {});
            scheduleSave();
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'PDF reading view',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Page color is applied to make PDF text easier to read.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                _paletteChoices(
                  palette,
                  (value) => change(() => palette = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keep the controls on'),
                  subtitle: const Text(
                    'Bottom and top bars should not be automatically hidden',
                  ),
                  value: alwaysShowChrome,
                  onChanged: (value) {
                    change(() {
                      alwaysShowChrome = value;
                      showChrome = true;
                    });
                    if (value) {
                      SystemChrome.setEnabledSystemUIMode(
                        SystemUiMode.edgeToEdge,
                      );
                    } else {
                      revealChrome();
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _paletteChoices(int selected, ValueChanged<int> onChanged) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _readerPaletteNames.length; i++)
            ChoiceChip(
              avatar: Icon(_readerPaletteIcons[i], size: 18),
              label: Text(_readerPaletteNames[i]),
              selected: selected == i,
              onSelected: (_) => onChanged(i),
            ),
        ],
      ),
    );
  }

  Future<void> addText() async {
    try {
      await _addText();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to save note/quote. The text is preserved; try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _addText() async {
    final selected = selectedText.trim();
    final text = selected.isEmpty
        ? await showDialog<String>(
            context: context,
            builder: (context) {
              var value = quickNoteDraft;
              return AlertDialog(
                title: const Text('Quick note'),
                content: TextFormField(
                  initialValue: value,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 5,
                  onChanged: (next) {
                    value = next;
                    quickNoteDraft = next;
                  },
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, value.trim()),
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          )
        : selected;
    if (text == null || text.trim().isEmpty || !mounted) return;
    if (selected.isEmpty) {
      await widget.onQuickNote?.call(text.trim());
      quickNoteDraft = '';
    } else {
      await widget.onQuote?.call(text.trim());
      await pdfController.textSelectionDelegate.clearTextSelection();
    }
    if (mounted) setState(() => selectedText = '');
  }
}
