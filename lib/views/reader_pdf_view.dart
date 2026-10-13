part of 'reader_page.dart';

// Split by reader concern while preserving the existing StatefulWidget state.
// ignore_for_file: invalid_use_of_protected_member
extension _ReaderPageStatePart2 on _ReaderPageState {
  Widget _pdfViewer(bool dark) {
    final viewer = PdfViewer.file(
      widget.file.path,
      key: const ValueKey('pdf-reader-viewer'),
      controller: pdfController,
      initialPageNumber: position < 1 ? 1 : position,
      params: PdfViewerParams(
        margin: 18,
        backgroundColor: dark
            ? Colors.white
            : palette == 1
            ? const Color(0xFF9E907B)
            : _pdfLoadingColor,
        pageDropShadow: const BoxShadow(
          color: Colors.black45,
          blurRadius: 5,
          spreadRadius: 1,
          offset: Offset(1, 2),
        ),
        textSelectionParams: PdfTextSelectionParams(
          onTextSelectionChange: (selection) {
            unawaited(
              selection.getSelectedText().then((text) {
                if (mounted) {
                  setState(() => selectedText = text);
                  revealChrome();
                }
              }),
            );
          },
        ),
        pagePaintCallbacks: pdfSearcher == null
            ? null
            : [pdfSearcher!.pageTextMatchPaintCallback],
        onGeneralTap: (context, controller, details) {
          if (details.type == PdfViewerGeneralTapType.tap) {
            revealChrome(toggle: true);
            return true;
          }
          return false;
        },
        onViewerReady: (document, controller) {
          pdfPages = controller.pageCount;
          final resolvedPage = (controller.pageNumber ?? position)
              .clamp(1, pdfPages)
              .toInt();
          position = resolvedPage;
          pdfSearcher?.dispose();
          pdfSearcher = PdfTextSearcher(controller);
          if (mounted) {
            setState(() {});
            revealChrome();
          }
          scheduleSave();
        },
        onPageChanged: (page) {
          if (page != null && page != position) {
            setState(() => position = page);
            scheduleSave();
          }
        },
        loadingBannerBuilder: (context, downloaded, total) {
          final percent = total == null || total == 0
              ? null
              : downloaded / total;
          return Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(strokeWidth: 2.5),
                    const SizedBox(height: 12),
                    Text(
                      percent == null
                          ? 'PDF is being prepared…'
                          : 'Preparing PDF ${(percent * 100).round()}%',
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        errorBannerBuilder: (context, error, stackTrace, documentRef) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.picture_as_pdf_outlined, size: 42),
                    const SizedBox(height: 12),
                    const Text(
                      'PDF could not be opened',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The file may be corrupt, encrypted, or in an unsupported format.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (palette == 2) return _pdfColorFilter(viewer, dark: true);
    if (palette == 1) return _pdfColorFilter(viewer, dark: false);
    return viewer;
  }

  Widget _pdfColorFilter(Widget child, {required bool dark}) {
    final List<double> matrix = dark
        ? const <double>[
            -1.0,
            0,
            0,
            0,
            255,
            0,
            -1.0,
            0,
            0,
            255,
            0,
            0,
            -1.0,
            0,
            255,
            0,
            0,
            0,
            1,
            0,
          ]
        : const <double>[
            0.92,
            0.08,
            0,
            0,
            8,
            0.12,
            0.82,
            0.06,
            0,
            4,
            0,
            0.10,
            0.72,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ];
    return ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: child);
  }

  Widget _pdfTopBar() {
    final foreground = palette == 2 ? Colors.white : Colors.black87;
    final surface = palette == 2
        ? const Color(0xEE1C1F23)
        : Colors.white.withAlpha(242);
    return Material(
      color: surface,
      elevation: 5,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 6, 6),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Close',
              color: foreground,
              onPressed: closeReader,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    pdfPages == 0
                        ? 'PDF is being prepared…'
                        : 'Page $position / $pdfPages  •  ${(progress * 100).round()}% complete',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground.withAlpha(170),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (selectedText.trim().isNotEmpty)
              IconButton(
                tooltip: 'Add as quote',
                color: foreground,
                onPressed: addText,
                icon: const Icon(Icons.format_quote_rounded),
              ),
            IconButton(
              tooltip: 'Search in PDF',
              color: foreground,
              onPressed: showPdfSearch,
              icon: const Icon(Icons.search_rounded),
            ),
            IconButton(
              tooltip: bookmarks.contains(position)
                  ? 'remove bookmark'
                  : 'Add bookmark',
              color: foreground,
              onPressed: toggleBookmark,
              icon: Icon(
                bookmarks.contains(position)
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'reading tools',
              icon: Icon(Icons.more_vert_rounded, color: foreground),
              onSelected: (value) {
                switch (value) {
                  case 'pages':
                    unawaited(showPageNavigator());
                  case 'bookmarks':
                    unawaited(showBookmarks());
                  case 'goto':
                    unawaited(showGoToPage());
                  case 'settings':
                    unawaited(settings());
                  case 'zoomIn':
                    unawaited(zoomPdfIn());
                  case 'zoomOut':
                    unawaited(zoomPdfOut());
                  case 'fit':
                    unawaited(fitPdfPage());
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'pages',
                  child: ListTile(
                    leading: Icon(Icons.grid_view_rounded),
                    title: Text('All pages'),
                  ),
                ),
                PopupMenuItem(
                  value: 'bookmarks',
                  child: ListTile(
                    leading: Icon(Icons.bookmarks_rounded),
                    title: Text('Yer imleri'),
                  ),
                ),
                PopupMenuItem(
                  value: 'goto',
                  child: ListTile(
                    leading: Icon(Icons.find_in_page_rounded),
                    title: Text('Go to page'),
                  ),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    leading: Icon(Icons.tune_rounded),
                    title: Text('Reading settings'),
                  ),
                ),
                PopupMenuItem(
                  value: 'zoomIn',
                  child: ListTile(
                    leading: Icon(Icons.zoom_in_rounded),
                    title: Text('zoom in'),
                  ),
                ),
                PopupMenuItem(
                  value: 'zoomOut',
                  child: ListTile(
                    leading: Icon(Icons.zoom_out_rounded),
                    title: Text('zoom out'),
                  ),
                ),
                PopupMenuItem(
                  value: 'fit',
                  child: ListTile(
                    leading: Icon(Icons.fit_screen_rounded),
                    title: Text('Fit page'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pdfBottomBar() {
    final foreground = palette == 2 ? Colors.white : Colors.black87;
    final surface = palette == 2
        ? const Color(0xEE1C1F23)
        : Colors.white.withAlpha(242);
    final maxPage = pdfPages > 0 ? pdfPages.toDouble() : 1.0;
    final sliderPage = position
        .clamp(1, pdfPages > 0 ? pdfPages : 1)
        .toDouble();
    return Material(
      color: surface,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 3, 14, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: sliderPage,
                min: 1,
                max: maxPage,
                label: 'Page ${sliderPage.round()}',
                onChanged: pdfPages == 0
                    ? null
                    : (value) {
                        revealChrome();
                        setState(() => position = value.round());
                      },
                onChangeEnd: pdfPages == 0
                    ? null
                    : (value) => unawaited(goToPdfPage(value.round())),
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous page',
                  color: foreground,
                  onPressed: position > 1
                      ? () => unawaited(goToPdfPage(position - 1))
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Center(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: showGoToPage,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          pdfPages == 0
                              ? 'PDF loading…'
                              : 'Page $position / $pdfPages',
                          style: TextStyle(
                            color: foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next page',
                  color: foreground,
                  onPressed: position < pdfPages
                      ? () => unawaited(goToPdfPage(position + 1))
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                IconButton(
                  tooltip: 'Pages',
                  color: foreground,
                  onPressed: showPageNavigator,
                  icon: const Icon(Icons.grid_view_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfReader() {
    final dark = palette == 2;
    return ColoredBox(
      color: dark
          ? const Color(0xFF101214)
          : palette == 1
          ? const Color(0xFF8C806E)
          : const Color(0xFF42474D),
      child: Stack(
        children: [
          Positioned.fill(child: _pdfViewer(dark)),
          if (showChrome)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(bottom: false, child: _pdfTopBar()),
            ),
          if (showChrome)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(top: false, child: _pdfBottomBar()),
            ),
          if (!showChrome && selectedText.trim().isNotEmpty)
            Positioned(
              right: 18,
              bottom: 22,
              child: SafeArea(
                child: FloatingActionButton.extended(
                  heroTag: 'pdf-quote-action',
                  onPressed: addText,
                  icon: const Icon(Icons.format_quote_rounded),
                  label: const Text('Add quote'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> closeReader() async {
    if (closing) return;
    closing = true;
    chromeTimer?.cancel();
    saveTimer?.cancel();
    await save();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) Navigator.pop(context);
  }
}
