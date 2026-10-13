part of 'library_page.dart';

Widget buildLibraryBookCard({
  required LibraryBookDocument doc,
  required bool busy,
  required VoidCallback onLongPress,
  VoidCallback? onTap,
}) => _BookCard(
  doc: doc,
  busy: busy,
  compact: true,
  canManage: true,
  publisherCount: 0,
  ratingCount: 0,
  ratingAverage: null,
  onTap: onTap ?? () {},
  onLongPress: onLongPress,
  onRead: onTap ?? () {},
);
