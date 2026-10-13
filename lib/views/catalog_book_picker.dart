part of 'library_page.dart';

Future<BookMetadata?> _showCatalogBookPicker(
  BuildContext context,
  List<BookMetadata> books,
) => showDialog<BookMetadata>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: const Text('Choose a book from the catalog'),
    content: SizedBox(
      width: 420,
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final book in books)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(book.title),
              subtitle: Text(
                [
                  if (book.author.isNotEmpty) book.author,
                  if (book.isbn.isNotEmpty) 'ISBN: ${book.isbn}',
                ].join(' · '),
              ),
              onTap: () => Navigator.pop(dialogContext, book),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Cancel'),
      ),
    ],
  ),
);
