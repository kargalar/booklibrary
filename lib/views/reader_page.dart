import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:epubx_kuebiko/epubx_kuebiko.dart' hide Image;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/book_files.dart';

part 'reader_state_base.dart';
part 'reader_content_state.dart';
part 'reader_pdf_view.dart';
part 'reader_chrome.dart';
part 'reader_epub_view.dart';
part 'reader_epub_search.dart';
part 'reader_settings.dart';
part 'reader_notes.dart';
part 'reader_navigation_tools.dart';
part 'reader_labels.dart';
part 'reader_surfaces.dart';
part 'pdf_page_navigator.dart';
part 'pdf_page_thumbnail.dart';
part 'pdf_page_thumbnail_state.dart';

const _readerPaletteNames = ['Light', 'Sepia', 'Dark'];
const _readerPaletteIcons = [
  Icons.light_mode_outlined,
  Icons.wb_sunny_outlined,
  Icons.dark_mode_outlined,
];
const _pdfLoadingColor = Color(0xFFE3E6E4);

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
    appearance.dispose();
    if (loaded && !closing) unawaited(save());
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
          appBar: AppBar(
            title: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 2),
                SizedBox(height: 20),
                Text(_ReaderLabels.preparingBook),
              ],
            ),
          ),
        );
      }
      if (snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_stories_outlined, size: 48),
                    const SizedBox(height: 20),
                    Text(
                      _ReaderLabels.openFailed,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      _ReaderLabels.fileError,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => setState(() {
                        ready = load()..ignore();
                      }),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text(_ReaderLabels.tryAgain),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(closeReader());
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (!showChrome) {
                revealChrome();
              } else {
                unawaited(closeReader());
              }
            },
            const SingleActivator(LogicalKeyboardKey.arrowRight): next,
            const SingleActivator(LogicalKeyboardKey.arrowLeft): previous,
            const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
                unawaited(toggleBookmark()),
          },
          child: Focus(
            autofocus: true,
            child: Theme(
              data: readerTheme,
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value:
                    (palette == 2
                            ? SystemUiOverlayStyle.light
                            : SystemUiOverlayStyle.dark)
                        .copyWith(
                          statusBarColor: Colors.transparent,
                          systemNavigationBarColor: readerBackground,
                        ),
                child: Scaffold(
                  backgroundColor: readerBackground,
                  body: SafeArea(
                    child: Column(
                      children: [
                        if (showChrome) readerTopBar(),
                        Expanded(
                          child: isPdf ? _buildPdfReader() : buildEpubReader(),
                        ),
                        if (showChrome) readerBottomBar(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
