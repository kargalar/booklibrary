part of 'library_page.dart';

// This extension keeps the legacy State API split by concern without duplicating state.
// ignore_for_file: invalid_use_of_protected_member
extension _LibraryPageStatePart8 on _LibraryPageState {
  Widget _timelineSection(List<LibraryBookDocument> docs) {
    final events = timelineEventsFromBooks(docs.map((doc) => doc.data()));
    final groups = <DateTime, List<LibraryTimelineEvent>>{};
    for (final event in events) {
      final month = DateTime(event.date.year, event.date.month);
      groups.putIfAbsent(month, () => []).add(event);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '5. Timeline',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          'Books are grouped by the month they were added or completed.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 22),
        Text(
          'My library',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 14),
        if (events.isEmpty)
          Text(
            'There are no books added or finished yet.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final entry in groups.entries) ...[
            Text(
              '${_timelineMonths[entry.key.month - 1]} ${entry.key.year}',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _timelineMonth(entry.value),
            if (entry.key != groups.keys.last) const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _timelineMonth(List<LibraryTimelineEvent> events) {
    final lineColor = Theme.of(context).colorScheme.outlineVariant;
    return Stack(
      children: [
        Positioned(
          left: 24,
          top: 0,
          bottom: 24,
          child: Container(width: 2, color: lineColor),
        ),
        Column(children: [for (final event in events) _timelineEvent(event)]),
      ],
    );
  }

  Widget _timelineEvent(LibraryTimelineEvent event) {
    final title = event.book['title'] as String? ?? 'Untitled book';
    final color =
        _coverColors[title.codeUnits.fold<int>(
              0,
              (total, char) => total + char,
            ) %
            _coverColors.length];
    final action = event.type == LibraryTimelineEventType.completed
        ? 'completed'
        : 'added';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            margin: const EdgeInsets.only(right: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withAlpha(38),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              _timelineInitials(title),
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_timelineMonths[event.date.month - 1]} ${event.date.day}, ${event.date.year} · $action',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _timelineInitials(String title) {
    final words = title.trim().split(RegExp(r'\s+'));
    if (words.length > 1) {
      return words
          .where((word) => word.isNotEmpty)
          .take(2)
          .map((word) => word[0])
          .join()
          .toUpperCase();
    }
    final value = words.firstOrNull ?? '';
    return value.isEmpty
        ? '?'
        : value.substring(0, value.length.clamp(1, 2)).toUpperCase();
  }

  Widget _ratingSummary(List<int> values) {
    final average =
        values.reduce((total, value) => total + value) / values.length;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.star_rounded),
        title: const Text('Average of your scores'),
        subtitle: Text('${values.length} books rated'),
        trailing: Text(
          '${average.toStringAsFixed(1)} / 5',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _distributionSection(
    String title,
    Map<String, int> values,
    IconData icon,
  ) {
    if (values.isEmpty) return const SizedBox.shrink();
    final entries = values.entries.toList()
      ..sort(
        (a, b) => b.value == a.value
            ? a.key.compareTo(b.key)
            : b.value.compareTo(a.value),
      );
    return Card(
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text('${entries.length} unique titles'),
        children: [
          for (final entry in entries)
            ListTile(
              dense: true,
              title: Text(entry.key),
              trailing: Text('${entry.value} books'),
            ),
        ],
      ),
    );
  }

  Widget _authorStatsSection(
    LibraryStats stats,
    Map<String, List<int>> authorRatings,
  ) {
    if (stats.byAuthor.isEmpty) return const SizedBox.shrink();
    final authors = stats.byAuthor.values.toList()
      ..sort(
        (a, b) => normalizeBookKey(a.name).compareTo(normalizeBookKey(b.name)),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Statistics by author',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        for (final author in authors) ...[
          _authorStatsCard(
            author,
            authorRatings[normalizeBookKey(author.name)],
          ),
          if (author != authors.last) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _authorStatsCard(AuthorStats author, List<int>? ratings) {
    final averagePages = author.booksWithPageCount == 0
        ? '—'
        : '${author.averagePageCount.round()}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    author.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text('${author.books} books'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _authorMetric('Average pages', averagePages),
                _authorMetric('Total pages', '${author.totalPages}'),
                _authorMetric(
                  'Reading rate',
                  '${(author.completionRate * 100).round()}%',
                ),
                _authorMetric('Completed', '${author.completed}'),
                if (ratings != null && ratings.isNotEmpty)
                  _authorMetric(
                    'Your score',
                    (ratings.reduce((total, value) => total + value) /
                            ratings.length)
                        .toStringAsFixed(1),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _authorMetric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      Text(
        label,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );

  Widget _completionCard(LibraryStats stats) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            height: 82,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: stats.completionRate,
                  strokeWidth: 8,
                  backgroundColor: scheme.onPrimary.withAlpha(35),
                  valueColor: AlwaysStoppedAnimation(scheme.onPrimary),
                ),
                Text(
                  '${(stats.completionRate * 100).round()}%',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your reading progress',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  stats.completed == 0
                      ? 'The books you read will appear here.'
                      : 'You have read ${stats.completed} books. Keep it up!',
                  style: TextStyle(color: scheme.onPrimary.withAlpha(210)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
