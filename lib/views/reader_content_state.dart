part of 'reader_page.dart';

// Split by reader concern while preserving the existing StatefulWidget state.
// ignore_for_file: invalid_use_of_protected_member
extension _ReaderContentState on _ReaderPageState {
  String get key => widget.storageKey;

  bool get isPdf => p.extension(widget.file.path).toLowerCase() == '.pdf';

  double get progress {
    if (isPdf) {
      if (pdfPages == 0) return 0;
      if (pdfPages == 1) return 1;
      return ((position - 1) / (pdfPages - 1)).clamp(0, 1).toDouble();
    }
    if (sections.isEmpty) return 0;
    final extent = scroll.hasClients
        ? scroll.position.maxScrollExtent
        : epubScrollExtent;
    final sectionProgress = extent == null
        ? 0.0
        : extent > 0
        ? (offset / extent).clamp(0, 1)
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
    if (!mounted) return;
    position = prefs.getInt('$key.position') ?? (isPdf ? 1 : 0);
    fontSize = (prefs.getDouble('reader.fontSize') ?? _ReaderDefaults.fontSize)
        .clamp(_ReaderDefaults.minFontSize, _ReaderDefaults.maxFontSize);
    lineHeight =
        (prefs.getDouble('reader.lineHeight') ?? _ReaderDefaults.lineHeight)
            .clamp(
              _ReaderDefaults.minLineHeight,
              _ReaderDefaults.maxLineHeight,
            );
    margin = (prefs.getDouble('reader.margin') ?? _ReaderDefaults.margin).clamp(
      _ReaderDefaults.minMargin,
      _ReaderDefaults.maxMargin,
    );
    palette = (prefs.getInt('reader.palette') ?? 0).clamp(0, 2);
    serif = prefs.getBool('reader.serif') ?? false;
    justify = prefs.getBool('reader.justify') ?? false;
    alwaysShowChrome = prefs.getBool('$key.alwaysShowChrome') ?? true;
    offset = prefs.getDouble('$key.offset') ?? 0;
    bookmarks
      ..clear()
      ..addAll(
        (prefs.getStringList('$key.bookmarks') ?? const <String>[])
            .map(int.tryParse)
            .whereType<int>(),
      );

    if (!isPdf) {
      epub = await EpubReader.readBook(await widget.file.readAsBytes());
      if (!mounted) return;
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
      bookmarks.removeWhere(
        (chapter) => chapter < 0 || chapter >= sections.length,
      );
    } else {
      position = position < 1 ? 1 : position;
    }

    loaded = true;
  }

  Future<void> save() async {
    if (!loaded) return;
    final savedPosition = position;
    final savedOffset = offset;
    final savedProgress = progress;
    try {
      await prefs.setInt('$key.position', savedPosition);
      await prefs.setDouble('$key.offset', savedOffset);
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
      await widget.onProgress?.call(savedProgress);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_ReaderLabels.settingsSaveError)),
        );
      }
    }
  }

  void scheduleSave() {
    saveTimer?.cancel();
    saveTimer = Timer(_ReaderDefaults.saveDelay, () => unawaited(save()));
  }

  void revealChrome({bool toggle = false}) {
    if (!mounted) return;
    chromeTimer?.cancel();
    _setChromeVisibility(toggle ? !showChrome : true);
    if (showChrome && !alwaysShowChrome && selectedText.trim().isEmpty) {
      chromeTimer = Timer(_ReaderDefaults.chromeDelay, () {
        if (mounted && !alwaysShowChrome) _setChromeVisibility(false);
      });
    }
  }

  void _setChromeVisibility(bool visible) {
    setState(() => showChrome = visible);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        showChrome ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
      ),
    );
  }

  void go(int index) {
    setState(() {
      position = index.clamp(0, sections.length - 1);
      restoreEpubOffset = true;
      epubScrollExtent = null;
      offset = 0;
      selectedText = '';
      highlightedEpubHtml = null;
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
    if (isPdf && pdfPages == 0) return;
    setState(() {
      if (!bookmarks.add(position)) bookmarks.remove(position);
    });
    await save();
  }
}
