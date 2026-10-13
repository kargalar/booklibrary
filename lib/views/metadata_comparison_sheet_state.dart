part of 'library_page.dart';

class _MetadataComparisonSheetState extends State<_MetadataComparisonSheet> {
  late final Map<BookMetadataField, BookMetadataProvider> selected =
      _initialSelection();

  Map<BookMetadataField, BookMetadataProvider> _initialSelection() {
    final values = <BookMetadataField, BookMetadataProvider>{};
    for (final field in BookMetadataField.values) {
      final provider = _providerWithValue(field);
      if (provider != null) values[field] = provider;
    }
    return values;
  }

  BookMetadataProvider? _providerWithValue(BookMetadataField field) {
    for (final entry in widget.result.candidates.entries) {
      if (_metadataFieldValue(entry.value, field) != null) return entry.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Compare sources',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'You can see and select the incoming data and API source for each field. Empty fields do not change.',
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.result.candidates.length} APIs returned results.',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.result.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'APIs that failed or returned no data',
                      style: TextStyle(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...widget.result.errors.entries.map(
                      (entry) => Text(
                        '• ${entry.key.label}: ${entry.value}',
                        style: TextStyle(
                          color: scheme.onErrorContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            ...BookMetadataField.values.map(_fieldRow),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Apply selections'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldRow(BookMetadataField field) {
    final options = widget.result.candidates.entries
        .where((entry) => _metadataFieldValue(entry.value, field) != null)
        .toList();
    final provider = selected[field];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  field.label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (options.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: Text('No APIs returned data for this field.'),
                ),
              if (options.isNotEmpty)
                RadioGroup<BookMetadataProvider>(
                  groupValue: provider,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selected[field] = value);
                    }
                  },
                  child: Column(
                    children: [
                      for (final entry in options)
                        RadioListTile<BookMetadataProvider>(
                          value: entry.key,
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: Text(entry.key.label),
                          secondary: field == BookMetadataField.coverUrl
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.network(
                                    entry.value.coverUrl!,
                                    width: 48,
                                    height: 68,
                                    fit: BoxFit.cover,
                                    loadingBuilder:
                                        (context, child, progress) =>
                                            progress == null
                                            ? child
                                            : const ImageShimmer(
                                                borderRadius: 4,
                                              ),
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.menu_book_rounded,
                                      size: 32,
                                    ),
                                  ),
                                )
                              : null,
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _metadataFieldValue(entry.value, field)!,
                                maxLines: field == BookMetadataField.description
                                    ? 4
                                    : 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (entry.value.sourceUrl != null)
                                Text(
                                  entry.value.sourceUrl!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
