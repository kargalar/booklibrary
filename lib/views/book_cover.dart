part of 'library_page.dart';

class _BookCover extends StatefulWidget {
  const _BookCover({
    required this.title,
    this.coverPath,
    this.coverUrl,
    this.coverStorageUrl,
    this.localCoverPath,
    this.borderRadius = 14,
    this.fit = BoxFit.cover,
  });
  final String title;
  final String? coverPath;
  final String? coverUrl;
  final String? coverStorageUrl;
  final String? localCoverPath;
  final double borderRadius;
  final BoxFit fit;

  @override
  State<_BookCover> createState() => _BookCoverState();
}
