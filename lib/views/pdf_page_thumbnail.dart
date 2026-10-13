part of 'reader_page.dart';

class _PdfPageThumbnail extends StatefulWidget {
  const _PdfPageThumbnail({required this.controller, required this.pageNumber});

  final PdfViewerController controller;
  final int pageNumber;

  @override
  State<_PdfPageThumbnail> createState() => _PdfPageThumbnailState();
}
