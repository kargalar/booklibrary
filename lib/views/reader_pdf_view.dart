part of 'reader_page.dart';

// Split by reader concern while preserving the existing StatefulWidget state.
// ignore_for_file: invalid_use_of_protected_member
extension _ReaderPdfView on _ReaderPageState {
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
            ? const Color(0xFFDFD3BF)
            : _pdfLoadingColor,
        pageDropShadow: const BoxShadow(
          color: Color(0x24000000),
          blurRadius: 8,
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
          bookmarks.removeWhere((page) => page < 1 || page > pdfPages);
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

  Widget _buildPdfReader() => Stack(
    children: [
      Positioned.fill(child: _pdfViewer(palette == 2)),
      if (!showChrome)
        Positioned(
          right: 16,
          bottom: 16,
          child: FilledButton.tonalIcon(
            onPressed: revealChrome,
            icon: const Icon(Icons.tune_rounded),
            label: Text('Page $position / $pdfPages'),
          ),
        ),
    ],
  );

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
