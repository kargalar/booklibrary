part of 'library_page.dart';

class _MetadataPreview extends StatelessWidget {
  const _MetadataPreview({required this.metadata});

  final BookMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final details = <MapEntry<String, String>>[
      if (metadata.metadataSource != null)
        MapEntry('Source', metadata.metadataSource!),
      if (metadata.pageCount != null) MapEntry('Page', '${metadata.pageCount}'),
      if (metadata.subjects.isNotEmpty)
        MapEntry('Genre', normalizeGenres(metadata.subjects).join(', ')),
      if (metadata.tags.isNotEmpty)
        MapEntry('Etiketler', metadata.tags.join(', ')),
      if (metadata.publishedDate != null)
        MapEntry('Publication date', metadata.publishedDate!),
      if (metadata.firstPublishDate != null)
        MapEntry('first broadcast', metadata.firstPublishDate!),
      if (metadata.language != null) MapEntry('Language', metadata.language!),
      if (metadata.origin != null) MapEntry('origin', metadata.origin!),
      if (metadata.isbn10 != null) MapEntry('ISBN-10', metadata.isbn10!),
      if (metadata.isbn13 != null) MapEntry('ISBN-13', metadata.isbn13!),
      if (metadata.contributions.isNotEmpty)
        MapEntry('Contributors', metadata.contributions.join(', ')),
      if (metadata.subjectPlaces.isNotEmpty)
        MapEntry('Yerler', metadata.subjectPlaces.join(', ')),
      if (metadata.subjectPeople.isNotEmpty)
        MapEntry('Contacts', metadata.subjectPeople.join(', ')),
      if (metadata.subjectTimes.isNotEmpty)
        MapEntry('periods', metadata.subjectTimes.join(', ')),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                height: 140,
                child: _BookCover(
                  title: metadata.title,
                  coverUrl: metadata.coverUrl,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metadata.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    if (metadata.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(metadata.subtitle!),
                    ],
                    if (metadata.author.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        metadata.author,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (metadata.publisher != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (metadata.publisherLogoUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.network(
                                metadata.publisherLogoUrl!,
                                width: 28,
                                height: 28,
                                fit: BoxFit.contain,
                                loadingBuilder: (context, child, progress) =>
                                    progress == null
                                    ? child
                                    : const ImageShimmer(borderRadius: 4),
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.business_rounded,
                                  size: 24,
                                ),
                              ),
                            )
                          else
                            const Icon(Icons.business_rounded, size: 24),
                          const SizedBox(width: 8),
                          Expanded(child: Text(metadata.publisher!)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 6),
            ...details.map(
              (detail) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 112,
                      child: Text(
                        detail.key,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(detail.value)),
                  ],
                ),
              ),
            ),
          ],
          if (metadata.description != null) ...[
            const SizedBox(height: 10),
            Text(
              'Description',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              metadata.description!,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
