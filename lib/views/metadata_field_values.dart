part of 'library_page.dart';

String? _metadataFieldValue(BookMetadata metadata, BookMetadataField field) {
  final value = switch (field) {
    BookMetadataField.title => metadata.title,
    BookMetadataField.author => metadata.author,
    BookMetadataField.subtitle => metadata.subtitle,
    BookMetadataField.description => metadata.description,
    BookMetadataField.pageCount => metadata.pageCount?.toString(),
    BookMetadataField.subjects => normalizeGenres(metadata.subjects).join(', '),
    BookMetadataField.publisher => metadata.publisher,
    BookMetadataField.publishedDate => metadata.publishedDate,
    BookMetadataField.language => metadata.language,
    BookMetadataField.coverUrl => metadata.coverUrl,
    BookMetadataField.publisherLogoUrl => metadata.publisherLogoUrl,
    BookMetadataField.isbn10 => metadata.isbn10,
    BookMetadataField.isbn13 => metadata.isbn13,
    BookMetadataField.previewUrl => metadata.previewUrl,
  };
  return value == null || value.trim().isEmpty ? null : value;
}
