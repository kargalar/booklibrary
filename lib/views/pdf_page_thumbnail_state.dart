part of 'reader_page.dart';

class _PdfPageThumbnailState extends State<_PdfPageThumbnail> {
  late final Future<ui.Image?> imageFuture = _loadImage();
  ui.Image? image;

  Future<ui.Image?> _loadImage() async {
    try {
      final loaded = await widget.controller.useDocument((document) async {
        if (widget.pageNumber > document.pages.length) return null;
        final rendered = await document.pages[widget.pageNumber - 1].render(
          width: 220,
        );
        if (rendered == null) return null;
        try {
          return await rendered.createImage(pixelSizeThreshold: 400);
        } finally {
          rendered.dispose();
        }
      });
      if (!mounted) {
        loaded?.dispose();
        return null;
      }
      image = loaded;
      return loaded;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image?>(
      future: imageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final pageImage = snapshot.data;
        return pageImage == null
            ? const Center(child: Icon(Icons.picture_as_pdf_outlined, size: 28))
            : RawImage(
                image: pageImage,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              );
      },
    );
  }
}
