part of 'library_page.dart';

Future<Map<BookMetadataField, BookMetadataProvider>?> _showMetadataComparison(
  BuildContext context,
  BookMetadataLookupResult result,
) => showModalBottomSheet<Map<BookMetadataField, BookMetadataProvider>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _MetadataComparisonSheet(result: result),
);
