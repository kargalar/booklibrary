part of 'reader_page.dart';

// Reader extensions share the lifecycle owned by ReaderPage.
// ignore_for_file: invalid_use_of_protected_member
extension _ReaderChrome on _ReaderPageState {
  Color get readerBackground =>
      const [Color(0xFFFAF9F6), Color(0xFFF3E9D6), Color(0xFF191D22)][palette];
  Color get readerForeground =>
      palette == 2 ? const Color(0xFFE0E3E7) : const Color(0xFF292D32);
  Color get readerAccent =>
      palette == 2 ? const Color(0xFFA8CCBE) : const Color(0xFF366453);
  String get locationLabel => isPdf
      ? (pdfPages == 0 ? 'Preparing PDF...' : 'Page $position / $pdfPages')
      : 'Chapter ${position + 1} / ${sections.length}';

  void previous() {
    if (isPdf) {
      if (position > 1) unawaited(goToPdfPage(position - 1));
    } else if (position > 0) {
      go(position - 1);
    }
  }

  void next() {
    if (isPdf) {
      if (position < pdfPages) unawaited(goToPdfPage(position + 1));
    } else if (position + 1 < sections.length) {
      go(position + 1);
    }
  }

  Widget readerTopBar() => Material(
    color: readerBackground,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: IconTheme(
        data: IconThemeData(color: readerForeground),
        child: Row(
          children: [
            IconButton(
              tooltip: _ReaderLabels.close,
              onPressed: closeReader,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPdf ? 'PDF \u00b7 READING' : 'EPUB \u00b7 READING',
                    style: TextStyle(
                      color: readerAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: readerForeground,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (MediaQuery.sizeOf(context).width >= 600) ...[
              IconButton(
                tooltip: isPdf
                    ? _ReaderLabels.allPages
                    : _ReaderLabels.contents,
                onPressed: isPdf ? showPageNavigator : showContents,
                icon: Icon(isPdf ? Icons.grid_view_rounded : Icons.toc_rounded),
              ),
              IconButton(
                tooltip: _ReaderLabels.searchBook,
                onPressed: isPdf ? showPdfSearch : showEpubSearch,
                icon: const Icon(Icons.search_rounded),
              ),
              if (canAddText)
                IconButton(
                  tooltip: selectedText.trim().isEmpty
                      ? _ReaderLabels.quickNote
                      : _ReaderLabels.addQuote,
                  onPressed: addText,
                  icon: const Icon(Icons.edit_note_rounded),
                ),
            ],
            IconButton(
              tooltip: bookmarks.contains(position)
                  ? _ReaderLabels.removeBookmark
                  : _ReaderLabels.addBookmark,
              onPressed: isPdf && pdfPages == 0 ? null : toggleBookmark,
              icon: Icon(
                bookmarks.contains(position)
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
              ),
            ),
            IconButton(
              tooltip: _ReaderLabels.readingView,
              onPressed: settings,
              icon: const Icon(Icons.text_fields_rounded),
            ),
            PopupMenuButton<String>(
              tooltip: _ReaderLabels.readingTools,
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (value) {
                switch (value) {
                  case 'contents':
                    if (isPdf) {
                      unawaited(showPageNavigator());
                    } else {
                      unawaited(showContents());
                    }
                  case 'bookmarks':
                    unawaited(showBookmarks());
                  case 'search':
                    if (isPdf) {
                      unawaited(showPdfSearch());
                    } else {
                      unawaited(showEpubSearch());
                    }
                  case 'note':
                    unawaited(addText());
                  case 'focus':
                    revealChrome(toggle: true);
                  case 'zoomIn':
                    unawaited(zoomPdfIn());
                  case 'zoomOut':
                    unawaited(zoomPdfOut());
                  case 'fit':
                    unawaited(fitPdfPage());
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'contents',
                  child: Text(
                    isPdf ? _ReaderLabels.allPages : _ReaderLabels.contents,
                  ),
                ),
                const PopupMenuItem(
                  value: 'search',
                  child: Text(_ReaderLabels.searchBook),
                ),
                const PopupMenuItem(
                  value: 'bookmarks',
                  child: Text(_ReaderLabels.bookmarks),
                ),
                if (canAddText)
                  PopupMenuItem(
                    value: 'note',
                    child: Text(
                      selectedText.trim().isEmpty
                          ? _ReaderLabels.quickNote
                          : _ReaderLabels.addQuote,
                    ),
                  ),
                const PopupMenuItem(
                  value: 'focus',
                  child: Text(_ReaderLabels.focusMode),
                ),
                if (isPdf) ...const [
                  PopupMenuItem(
                    value: 'zoomIn',
                    child: Text(_ReaderLabels.zoomIn),
                  ),
                  PopupMenuItem(
                    value: 'zoomOut',
                    child: Text(_ReaderLabels.zoomOut),
                  ),
                  PopupMenuItem(
                    value: 'fit',
                    child: Text(_ReaderLabels.fitPage),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget pdfSearchNavigation() => ListenableBuilder(
    listenable: pdfSearcher!,
    builder: (context, _) {
      final searcher = pdfSearcher!;
      if (searcher.matches.isEmpty) return const SizedBox.shrink();
      return Row(
        children: [
          Expanded(
            child: Text(
              '${(searcher.currentIndex ?? 0) + 1} / ${searcher.matches.length} matches',
              style: TextStyle(color: readerForeground, fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: _ReaderLabels.previousResult,
            onPressed: () => unawaited(searcher.goToPrevMatch()),
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
          IconButton(
            tooltip: _ReaderLabels.nextResult,
            onPressed: () => unawaited(searcher.goToNextMatch()),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          IconButton(
            tooltip: _ReaderLabels.clearSearch,
            onPressed: () {
              searchController.clear();
              searcher.resetTextSearch();
            },
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      );
    },
  );

  Widget readerBottomBar() {
    final count = isPdf ? pdfPages : sections.length;
    final first = isPdf ? 1 : 0;
    final last = count > 0 ? count - (isPdf ? 0 : 1) : first;
    final value = (scrubPosition ?? position.toDouble()).clamp(
      first.toDouble(),
      last.toDouble(),
    );
    return Material(
      color: readerBackground,
      child: Align(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _ReaderDefaults.contentWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isPdf && pdfSearcher != null) pdfSearchNavigation(),
                if (selectedText.trim().isNotEmpty && widget.onQuote != null)
                  TextButton.icon(
                    onPressed: addText,
                    icon: const Icon(Icons.format_quote_rounded),
                    label: const Text(_ReaderLabels.addQuote),
                  ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: readerAccent,
                    inactiveTrackColor: readerForeground.withAlpha(24),
                    thumbColor: readerAccent,
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                  ),
                  child: Slider(
                    value: value,
                    min: first.toDouble(),
                    max: last.toDouble(),
                    label:
                        '${isPdf ? 'Page' : 'Chapter'} ${value.round() + (isPdf ? 0 : 1)}',
                    onChanged: count <= 1
                        ? null
                        : (v) => setState(() => scrubPosition = v),
                    onChangeEnd: count <= 1
                        ? null
                        : (v) {
                            setState(() => scrubPosition = null);
                            if (isPdf) {
                              unawaited(goToPdfPage(v.round()));
                            } else {
                              go(v.round());
                            }
                          },
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: isPdf
                          ? _ReaderLabels.previousPage
                          : _ReaderLabels.previousChapter,
                      color: readerForeground,
                      onPressed: position > first ? previous : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: isPdf ? showGoToPage : showContents,
                        child: Column(
                          children: [
                            Text(
                              locationLabel,
                              style: TextStyle(
                                color: readerForeground,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${(progress * 100).round()}% complete',
                              style: TextStyle(
                                color: readerForeground.withAlpha(150),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: isPdf
                          ? _ReaderLabels.nextPage
                          : _ReaderLabels.nextChapter,
                      color: readerForeground,
                      onPressed: position < last ? next : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                    IconButton(
                      tooltip: isPdf
                          ? _ReaderLabels.pages
                          : _ReaderLabels.contents,
                      color: readerForeground,
                      onPressed: isPdf ? showPageNavigator : showContents,
                      icon: Icon(
                        isPdf ? Icons.grid_view_rounded : Icons.toc_rounded,
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
  }
}
