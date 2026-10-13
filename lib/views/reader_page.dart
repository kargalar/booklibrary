import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:epubx_kuebiko/epubx_kuebiko.dart' hide Image;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/book_files.dart';

part 'reader_state_base.dart';
part 'reader_content_state.dart';
part 'reader_pdf_view.dart';
part 'pdf_page_navigator.dart';
part 'pdf_page_thumbnail.dart';
part 'pdf_page_thumbnail_state.dart';

const _readerPaletteNames = ['Light', 'Sepia', 'Dark'];
const _readerPaletteIcons = [
  Icons.light_mode_outlined,
  Icons.wb_sunny_outlined,
  Icons.dark_mode_outlined,
];
const _pdfLoadingColor = Color(0xFF4A4E55);

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.file,
    required this.title,
    required this.storageKey,
    this.onProgress,
    this.onQuickNote,
    this.onQuote,
  });

  final File file;
  final String title, storageKey;
  final Future<void> Function(double)? onProgress;
  final Future<void> Function(String text)? onQuickNote;
  final Future<void> Function(String text)? onQuote;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends _ReaderPageStateBase {
  @override
  void initState() {
    super.initState();
    ready = load();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (loaded && state != AppLifecycleState.resumed) {
      saveTimer?.cancel();
      unawaited(save());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    saveTimer?.cancel();
    chromeTimer?.cancel();
    searchController.dispose();
    scroll.dispose();
    pdfSearcher?.dispose();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: ready,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      if (snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'The file could not be opened. The file may be corrupt, encrypted, or in an unsupported format.',
              ),
            ),
          ),
        );
      }

      final background = [
        Colors.white,
        const Color(0xFFF4ECD8),
        const Color(0xFF181818),
      ][palette];
      final foreground = palette == 2 ? Colors.white70 : Colors.black87;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(closeReader());
        },
        child: Scaffold(
          backgroundColor: isPdf ? Colors.transparent : background,
          appBar: isPdf
              ? null
              : AppBar(
                  title: Text(widget.title),
                  actions: [
                    IconButton(
                      tooltip: 'Contents',
                      icon: const Icon(Icons.toc),
                      onPressed: () async {
                        final selected = await showModalBottomSheet<int>(
                          context: context,
                          builder: (context) => SafeArea(
                            child: ListView.builder(
                              itemCount: sections.length,
                              itemBuilder: (context, i) => ListTile(
                                selected: position == i,
                                title: Text(
                                  '${i + 1}. ${sectionTitles[sections[i].FileName] ?? p.basenameWithoutExtension(sections[i].FileName ?? 'Chapter')}',
                                ),
                                onTap: () => Navigator.pop(context, i),
                              ),
                            ),
                          ),
                        );
                        if (selected != null && mounted) go(selected);
                      },
                    ),
                    IconButton(
                      tooltip: 'Reading view',
                      icon: const Icon(Icons.text_fields),
                      onPressed: settings,
                    ),
                  ],
                ),
          body: isPdf
              ? _buildPdfReader()
              : NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification) {
                      offset = notification.metrics.pixels;
                      scheduleSave();
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: scroll,
                    padding: EdgeInsets.all(margin),
                    child: SelectionArea(
                      onSelectionChanged: (selection) => setState(
                        () => selectedText = selection?.plainText ?? '',
                      ),
                      child: sections.isEmpty
                          ? const Center(
                              child: Text(
                                'No readable chapters were found in this EPUB.',
                              ),
                            )
                          : HtmlWidget(
                              sections[position].Content ?? '',
                              textStyle: TextStyle(
                                fontSize: fontSize,
                                height: lineHeight,
                                color: foreground,
                                fontFamily: serif ? 'serif' : null,
                              ),
                              customStylesBuilder: (element) => {
                                'font-size': '${fontSize}px',
                                'line-height': '$lineHeight',
                                'color': palette == 2 ? '#dddddd' : '#222222',
                                'background-color': 'transparent',
                                if (justify) 'text-align': 'justify',
                              },
                              onTapUrl: (_) async => true,
                              customWidgetBuilder: (element) {
                                if ([
                                  'script',
                                  'iframe',
                                  'video',
                                  'audio',
                                  'object',
                                ].contains(element.localName)) {
                                  return const SizedBox.shrink();
                                }
                                if (element.localName != 'img') return null;
                                final src = element.attributes['src'] ?? '';
                                final path = p.posix.normalize(
                                  p.posix.join(
                                    p.posix.dirname(
                                      sections[position].FileName ?? '',
                                    ),
                                    Uri.decodeFull(src),
                                  ),
                                );
                                final bytes =
                                    epub?.Content?.Images?[path]?.Content;
                                return bytes == null
                                    ? const SizedBox.shrink()
                                    : Image.memory(Uint8List.fromList(bytes));
                              },
                            ),
                    ),
                  ),
                ),
          floatingActionButton: isPdf
              ? null
              : FloatingActionButton.extended(
                  onPressed: addText,
                  icon: Icon(
                    selectedText.trim().isEmpty
                        ? Icons.note_add_rounded
                        : Icons.format_quote_rounded,
                  ),
                  label: Text(
                    selectedText.trim().isEmpty ? 'Quick note' : 'Add as quote',
                  ),
                ),
          bottomNavigationBar: isPdf
              ? null
              : SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        tooltip: 'Previous chapter',
                        onPressed: position > 0 ? () => go(position - 1) : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text('Chapter ${position + 1} / ${sections.length}'),
                      IconButton(
                        tooltip: 'Next chapter',
                        onPressed: position + 1 < sections.length
                            ? () => go(position + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
        ),
      );
    },
  );
}
