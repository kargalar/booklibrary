part of 'reader_page.dart';

// ignore_for_file: invalid_use_of_protected_member
extension _ReaderEpubView on _ReaderPageState {
  String chapterTitle(int index) =>
      sectionTitles[sections[index].FileName] ??
      p.posix.basenameWithoutExtension(
        sections[index].FileName ?? 'Chapter ${index + 1}',
      );

  Widget buildEpubReader() {
    if (restoreEpubOffset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scroll.hasClients) return;
        scroll.jumpTo(offset.clamp(0, scroll.position.maxScrollExtent));
        setState(() {
          offset = scroll.offset;
          epubScrollExtent = scroll.position.maxScrollExtent;
          restoreEpubOffset = false;
        });
        if (!alwaysShowChrome && showChrome) revealChrome();
      });
    }
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification &&
                !restoreEpubOffset) {
              setState(() {
                offset = notification.metrics.pixels;
                epubScrollExtent = notification.metrics.maxScrollExtent;
              });
              scheduleSave();
            }
            return false;
          },
          child: Scrollbar(
            controller: scroll,
            child: SingleChildScrollView(
              controller: scroll,
              key: const ValueKey('epub-reader-scroll'),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _ReaderDefaults.contentWidth,
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(margin, 32, margin, 80),
                    child: SelectionArea(
                      onSelectionChanged: (selection) {
                        setState(
                          () => selectedText = selection?.plainText ?? '',
                        );
                        if (selectedText.isNotEmpty) revealChrome();
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'CHAPTER ${position + 1}',
                            style: TextStyle(
                              color: readerAccent,
                              fontSize: 11,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (sections.isNotEmpty)
                            HtmlWidget(
                              highlightedEpubHtml ??
                                  sections[position].Content ??
                                  '',
                              key: htmlKey,
                              textStyle: TextStyle(
                                fontSize: fontSize,
                                height: lineHeight,
                                color: readerForeground,
                                fontFamily: serif ? 'Georgia' : null,
                              ),
                              customStylesBuilder: (element) => {
                                'color': element.localName == 'mark'
                                    ? '#292d32'
                                    : palette == 2
                                    ? '#e0e3e7'
                                    : '#292d32',
                                'background-color': element.localName == 'mark'
                                    ? '#e8cc80'
                                    : 'transparent',
                                if (element.localName == 'body') ...{
                                  'margin': '0',
                                  'padding': '0',
                                  'font-size': '${fontSize}px',
                                },
                                if (element.localName == 'p') ...{
                                  'font-size': '${fontSize}px',
                                  'line-height': '$lineHeight',
                                  'text-align': justify ? 'justify' : 'left',
                                  'margin-bottom': '1em',
                                },
                              },
                              onTapUrl: handleEpubLink,
                              customWidgetBuilder: (element) {
                                if (const [
                                  'script',
                                  'iframe',
                                  'video',
                                  'audio',
                                  'object',
                                ].contains(element.localName)) {
                                  return const SizedBox.shrink();
                                }
                                if (element.localName != 'img') return null;
                                final source = Uri.tryParse(
                                  element.attributes['src'] ?? '',
                                );
                                if (source == null || source.hasScheme) {
                                  return const SizedBox.shrink();
                                }
                                final path = resolveEpubPath(source.path);
                                final images = epub?.Content?.Images;
                                final bytes =
                                    (images?[path] ??
                                            images?[Uri.decodeFull(path)])
                                        ?.Content;
                                return bytes == null
                                    ? const SizedBox.shrink()
                                    : Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        child: Image.memory(
                                          Uint8List.fromList(bytes),
                                          fit: BoxFit.contain,
                                        ),
                                      );
                              },
                            ),
                          const SizedBox(height: 40),
                          Center(
                            child: Text(
                              '\u2022 \u2022 \u2022',
                              style: TextStyle(color: readerAccent),
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (position + 1 < sections.length)
                            Center(
                              child: OutlinedButton.icon(
                                onPressed: next,
                                icon: const Icon(Icons.arrow_forward_rounded),
                                label: const Text(
                                  _ReaderLabels.continueChapter,
                                ),
                              ),
                            )
                          else
                            Center(
                              child: Text(
                                _ReaderLabels.endOfBook,
                                style: TextStyle(
                                  color: readerForeground.withAlpha(160),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!showChrome)
          Positioned(
            right: 16,
            bottom: 16,
            child: FilledButton.tonalIcon(
              onPressed: revealChrome,
              icon: const Icon(Icons.tune_rounded),
              label: const Text(_ReaderLabels.readingTools),
            ),
          ),
      ],
    );
  }

  String resolveEpubPath(String path) => p.posix.normalize(
    p.posix.join(
      p.posix.dirname(sections[position].FileName ?? ''),
      Uri.decodeFull(path),
    ),
  );

  Future<bool> handleEpubLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.hasScheme) return true;
    if (uri.path.isEmpty) {
      return false; // Let HtmlWidget scroll to local anchors.
    }
    final path = resolveEpubPath(uri.path);
    final index = sections.indexWhere(
      (section) =>
          p.posix.normalize(Uri.decodeFull(section.FileName ?? '')) == path,
    );
    if (index < 0) return true;
    go(index);
    if (uri.fragment.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(htmlKey.currentState?.scrollToAnchor(uri.fragment));
        }
      });
    }
    return true;
  }

  Future<void> showContents() async {
    final selected = await showReaderSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          children: [
            ListTile(
              title: const Text(_ReaderLabels.contents),
              subtitle: Text('${sections.length} chapters'),
              trailing: IconButton(
                tooltip: _ReaderLabels.close,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: sections.length,
                itemBuilder: (context, index) => ListTile(
                  selected: position == index,
                  leading: Text('${index + 1}'.padLeft(2, '0')),
                  title: Text('${index + 1}. ${chapterTitle(index)}'),
                  trailing: bookmarks.contains(index)
                      ? const Icon(Icons.bookmark_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, index),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) go(selected);
  }
}
