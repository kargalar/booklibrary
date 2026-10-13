part of 'library_page.dart';

Future<bool?> _showBookMatchDialog(
  BuildContext context,
  List<BookMatch> matches,
) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(
      matches.any((match) => match.blocksAdding)
          ? 'The book is already attached'
          : 'Similar book found',
    ),
    content: SingleChildScrollView(child: _BookMatchWarning(matches: matches)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(
          matches.any((match) => match.blocksAdding)
              ? 'add 2nd time'
              : 'Add anyway',
        ),
      ),
    ],
  ),
);
