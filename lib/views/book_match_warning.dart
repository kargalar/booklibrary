part of 'library_page.dart';

class _BookMatchWarning extends StatelessWidget {
  const _BookMatchWarning({required this.matches});

  final List<BookMatch> matches;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              matches.any((match) => match.blocksAdding)
                  ? 'This book is already registered; You can add another one from the same book.'
                  : 'Similarity with recorded books found.',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final match in matches.take(3)) ...[
              Text(match.reason, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 2),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(Icons.menu_book_rounded),
                title: Text(
                  _bookText(match.book, 'title') ?? 'untitled book',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    _bookText(match.book, 'author'),
                    _bookText(match.book, 'publisher'),
                  ].whereType<String>().join(' • '),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
