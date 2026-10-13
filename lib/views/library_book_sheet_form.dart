part of 'library_page.dart';

typedef _BookSheetAsyncAction = Future<void> Function(StateSetter update);
typedef _BookSheetSyncAction = void Function(StateSetter update);
typedef _BookSheetIsbnChanged = void Function(String value, StateSetter update);
typedef _BookSheetOptions<T> = Iterable<T> Function(TextEditingValue value);
typedef _BookSheetFieldBuilder = Widget Function(
  TextEditingController controller,
  String label, {
  int? maxLines,
  TextInputType? keyboardType,
  String? hintText,
  String? Function(String?)? validator,
});

class _BookSheetFormData {
  final BuildContext context;
  final LibraryBookDocument? doc;
  final String? initialIsbn;
  final List<PersonalLibrary> personalLibraries;
  final Set<String> selectedLibraryIds;
  final GlobalKey<FormState> form;
  final TextEditingController title;
  final TextEditingController author;
  final TextEditingController isbn;
  final TextEditingController subtitle;
  final TextEditingController description;
  final TextEditingController pageCount;
  final TextEditingController subjects;
  final TextEditingController tags;
  final TextEditingController subjectPlaces;
  final TextEditingController subjectPeople;
  final TextEditingController subjectTimes;
  final TextEditingController contributions;
  final TextEditingController publisher;
  final TextEditingController publishedDate;
  final TextEditingController firstPublishDate;
  final TextEditingController language;
  final TextEditingController languageCode;
  final TextEditingController origin;
  final TextEditingController coverUrl;
  final TextEditingController isbn10;
  final TextEditingController isbn13;
  final TextEditingController editionId;
  final TextEditingController workId;
  final TextEditingController previewUrl;
  final TextEditingController sourceUrl;
  final FocusNode titleFocusNode;
  final FocusNode authorFocusNode;
  final FocusNode publisherFocusNode;
  final FocusNode subjectsFocusNode;
  final FocusNode languageFocusNode;
  String? coverPath;
  String? coverStorageUrl;
  BookMetadata? metadata;
  BookMetadataLookupResult? lookupResult;
  bool lookupBusy;
  String? lookupError;
  bool lookupStarted;
  List<BookMatch> visibleMatches;
  File? pendingFile;
  File? pendingAudio;
  bool saveBusy;
  final bool canCaptureCover;
  final _BookSheetFieldBuilder field;
  final _BookSheetAsyncAction lookup;
  final _BookSheetAsyncAction lookupByTitleAuthor;
  final _BookSheetSyncAction refreshMatchWarning;
  final _BookSheetAsyncAction compare;
  final _BookSheetAsyncAction save;
  final _BookSheetAsyncAction pickBookFile;
  final _BookSheetAsyncAction pickAudioFile;
  final _BookSheetAsyncAction captureCover;
  final _BookSheetSyncAction removeCover;
  final _BookSheetAsyncAction pickGalleryCover;
  final _BookSheetIsbnChanged onIsbnChanged;
  final _BookSheetOptions<LibraryBookDocument> titleOptions;
  final _BookSheetOptions<String> authorOptions;
  final _BookSheetOptions<String> publisherOptions;
  final _BookSheetOptions<String> genreOptions;
  final _BookSheetOptions<String> languageOptions;
  final String Function(String key) textValue;

  _BookSheetFormData({
    required this.context,
    required this.doc,
    required this.initialIsbn,
    required this.personalLibraries,
    required this.selectedLibraryIds,
    required this.form,
    required this.title,
    required this.author,
    required this.isbn,
    required this.subtitle,
    required this.description,
    required this.pageCount,
    required this.subjects,
    required this.tags,
    required this.subjectPlaces,
    required this.subjectPeople,
    required this.subjectTimes,
    required this.contributions,
    required this.publisher,
    required this.publishedDate,
    required this.firstPublishDate,
    required this.language,
    required this.languageCode,
    required this.origin,
    required this.coverUrl,
    required this.isbn10,
    required this.isbn13,
    required this.editionId,
    required this.workId,
    required this.previewUrl,
    required this.sourceUrl,
    required this.titleFocusNode,
    required this.authorFocusNode,
    required this.publisherFocusNode,
    required this.subjectsFocusNode,
    required this.languageFocusNode,
    required this.coverPath,
    required this.coverStorageUrl,
    required this.metadata,
    required this.lookupResult,
    required this.lookupBusy,
    required this.lookupError,
    required this.lookupStarted,
    required this.visibleMatches,
    required this.pendingFile,
    required this.pendingAudio,
    required this.saveBusy,
    required this.canCaptureCover,
    required this.field,
    required this.lookup,
    required this.lookupByTitleAuthor,
    required this.refreshMatchWarning,
    required this.compare,
    required this.save,
    required this.pickBookFile,
    required this.pickAudioFile,
    required this.captureCover,
    required this.removeCover,
    required this.pickGalleryCover,
    required this.onIsbnChanged,
    required this.titleOptions,
    required this.authorOptions,
    required this.publisherOptions,
    required this.genreOptions,
    required this.languageOptions,
    required this.textValue,
  });
}

Future<bool?> _showBookSheetForm(_BookSheetFormData data) {
  return showModalBottomSheet<bool>(
    context: data.context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(data.context).colorScheme.surface,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => Builder(
        builder: (context) {
          if (data.initialIsbn != null && !data.lookupStarted) {
            data.lookupStarted = true;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => data.lookup(update),
            );
          }
          final scheme = Theme.of(context).colorScheme;
          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    100 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Form(
                    key: data.form,
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              data.doc == null ? 'Add book' : 'Edit book',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            IconButton(
                              iconSize: 20,
                              visualDensity: VisualDensity.compact,
                              tooltip:
                                  data.lookupResult == null ||
                                      data.lookupResult!.candidates.length < 2
                                  ? 'Compare other sources'
                                  : 'Compare sources again',
                              onPressed: data.lookupBusy
                                  ? null
                                  : () => data.compare(update),
                              icon: const Icon(Icons.compare_arrows_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Temel bilgiler',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: data.isbn,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            labelText: 'ISBN',
                            hintText: '978... veya ISBN-10',
                            suffixIcon: IconButton(
                              tooltip: 'Search by ISBN',
                              onPressed: data.lookupBusy
                                  ? null
                                  : () => data.lookup(update),
                              icon: const Icon(Icons.search_rounded),
                            ),
                          ),
                          onChanged: (value) =>
                              data.onIsbnChanged(value, update),
                          onFieldSubmitted: (_) => data.lookup(update),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return null;
                            }
                            return normalizeIsbn(value) == null
                                ? 'Enter a valid ISBN.'
                                : null;
                          },
                        ),
                        if (data.lookupBusy || data.saveBusy) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(),
                        ],
                        if (data.lookupError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            data.lookupError!,
                            style: TextStyle(color: scheme.error),
                          ),
                        ],
                        if (data.metadata != null) ...[
                          const SizedBox(height: 16),
                          _MetadataPreview(metadata: data.metadata!),
                        ],
                        const SizedBox(height: 16),
                        RawAutocomplete<LibraryBookDocument>(
                          focusNode: data.titleFocusNode,
                          textEditingController: data.title,
                          optionsBuilder: data.titleOptions,
                          displayStringForOption: (book) =>
                              '${book.data()['data.title'] ?? ''}',
                          optionsViewBuilder: (context, onSelected, options) =>
                              Material(
                                elevation: 4,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 220,
                                  ),
                                  child: ListView(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    children: [
                                      for (final book in options)
                                        ListTile(
                                          dense: true,
                                          title: Text(
                                            '${book.data()['data.title'] ?? ''}',
                                          ),
                                          subtitle: Text(
                                            '${book.data()['data.author'] ?? ''}',
                                          ),
                                          onTap: () => onSelected(book),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          onSelected: (_) => data.refreshMatchWarning(update),
                          fieldViewBuilder:
                              (
                                context,
                                controller,
                                focusNode,
                                onFieldSubmitted,
                              ) => TextFormField(
                                controller: controller,
                                focusNode: focusNode,
                                autofocus:
                                    data.doc == null &&
                                    data.initialIsbn == null,
                                maxLength: 200,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'book name',
                                  hintText: 'You can also search among existing books',
                                  suffixIcon: IconButton(
                                    tooltip: 'Search by book name and author',
                                    onPressed: data.lookupBusy
                                        ? null
                                        : () =>
                                              data.lookupByTitleAuthor(update),
                                    icon: const Icon(Icons.search_rounded),
                                  ),
                                ),
                                onChanged: (_) =>
                                    data.refreshMatchWarning(update),
                                onFieldSubmitted: (_) {
                                  onFieldSubmitted();
                                  data.authorFocusNode.requestFocus();
                                },
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? 'Book name required.'
                                    : null,
                              ),
                        ),
                        const SizedBox(height: 8),
                        RawAutocomplete<String>(
                          focusNode: data.authorFocusNode,
                          textEditingController: data.author,
                          optionsBuilder: data.authorOptions,
                          optionsViewBuilder: (context, onSelected, options) =>
                              Material(
                                elevation: 4,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 220,
                                  ),
                                  child: ListView(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    children: [
                                      for (final name in options)
                                        ListTile(
                                          dense: true,
                                          title: Text(name),
                                          onTap: () => onSelected(name),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          onSelected: (_) => update(() {}),
                          fieldViewBuilder:
                              (
                                context,
                                controller,
                                focusNode,
                                onFieldSubmitted,
                              ) => TextFormField(
                                controller: controller,
                                focusNode: focusNode,
                                maxLength: 200,
                                decoration: const InputDecoration(
                                  labelText: 'Author',
                                  hintText: 'You can choose from the list or write a new author',
                                ),
                                onChanged: (_) => update(() {}),
                                onFieldSubmitted: (_) => onFieldSubmitted(),
                              ),
                        ),
                        const SizedBox(height: 8),
                        RawAutocomplete<String>(
                          focusNode: data.languageFocusNode,
                          textEditingController: data.language,
                          optionsBuilder: data.languageOptions,
                          optionsViewBuilder: (context, onSelected, options) =>
                              Material(
                                elevation: 4,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 220,
                                  ),
                                  child: ListView(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    children: [
                                      for (final item in options)
                                        ListTile(
                                          dense: true,
                                          title: Text(item),
                                          onTap: () => onSelected(item),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          onSelected: (_) => update(() {}),
                          fieldViewBuilder:
                              (
                                context,
                                controller,
                                focusNode,
                                onFieldSubmitted,
                              ) => TextFormField(
                                controller: controller,
                                focusNode: focusNode,
                                maxLength: 80,
                                decoration: const InputDecoration(
                                  labelText: 'Language',
                                  hintText: 'You can choose from the list or type a new language',
                                ),
                                onChanged: (_) => update(() {}),
                                onFieldSubmitted: (_) => onFieldSubmitted(),
                              ),
                        ),
                        if (data.visibleMatches.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _BookMatchWarning(matches: data.visibleMatches),
                        ],
                        const SizedBox(height: 8),
                        data.field(
                          data.pageCount,
                          'Number of pages',
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return null;
                            }
                            final count = int.tryParse(value.trim());
                            return count == null || count < 1
                                ? 'Enter a positive number.'
                                : null;
                          },
                        ),
                        if (data.personalLibraries.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Libraries',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          for (final library in data.personalLibraries)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: data.selectedLibraryIds.contains(
                                library.id,
                              ),
                              onChanged: data.lookupBusy
                                  ? null
                                  : (value) => update(() {
                                      if (value == true) {
                                        data.selectedLibraryIds.add(library.id);
                                      } else {
                                        data.selectedLibraryIds.remove(
                                          library.id,
                                        );
                                      }
                                    }),
                              title: Text(library.name),
                            ),
                          if (data.selectedLibraryIds.isEmpty)
                            const Text(
                              'Other: appears only in reading history.',
                            ),
                        ],
                        RawAutocomplete<String>(
                          focusNode: data.publisherFocusNode,
                          textEditingController: data.publisher,
                          optionsBuilder: data.publisherOptions,
                          optionsViewBuilder: (context, onSelected, options) =>
                              Material(
                                elevation: 4,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 220,
                                  ),
                                  child: ListView(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    children: [
                                      for (final name in options)
                                        ListTile(
                                          dense: true,
                                          title: Text(name),
                                          onTap: () => onSelected(name),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          onSelected: (_) => update(() {}),
                          fieldViewBuilder:
                              (
                                context,
                                controller,
                                focusNode,
                                onFieldSubmitted,
                              ) => TextFormField(
                                controller: controller,
                                focusNode: focusNode,
                                maxLength: 200,
                                decoration: const InputDecoration(
                                  labelText: 'Publisher',
                                  hintText: 'You can choose from the list or write a new publishing house.',
                                ),
                                onChanged: (_) => update(() {}),
                                onFieldSubmitted: (_) => onFieldSubmitted(),
                              ),
                        ),
                        const SizedBox(height: 4),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final coverWidth = constraints.maxWidth < 320
                                ? 72.0
                                : 84.0;
                            final fileButtonWidth =
                                ((constraints.maxWidth - coverWidth - 12 - 8) /
                                        2)
                                    .clamp(72.0, 100.0);
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: coverWidth,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'cover image',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      AspectRatio(
                                        aspectRatio: 2 / 3,
                                        child: InkWell(
                                          onTap:
                                              data.lookupBusy ||
                                                  !data.canCaptureCover
                                              ? null
                                              : () => data.captureCover(update),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          child: _BookCover(
                                            title: data.title.text,
                                            coverPath: data.coverPath,
                                            coverUrl: data.coverUrl.text,
                                            coverStorageUrl:
                                                data.coverStorageUrl,
                                            localCoverPath:
                                                data.coverPath?.startsWith(
                                                      'http',
                                                    ) ==
                                                    true
                                                ? data.textValue(
                                                    'legacyCoverPath',
                                                  )
                                                : data.coverPath,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 32,
                                            ),
                                            tooltip: 'select from gallery',
                                            onPressed:
                                                data.lookupBusy ||
                                                    !data.canCaptureCover
                                                ? null
                                                : () => data.pickGalleryCover(
                                                    update,
                                                  ),
                                            icon: const Icon(
                                              Icons.photo_library_outlined,
                                              size: 18,
                                            ),
                                          ),
                                          if (data.coverPath != null ||
                                              data.coverUrl.text.isNotEmpty)
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                              tooltip: 'Lift the cover',
                                              onPressed: data.lookupBusy
                                                  ? null
                                                  : () => data.removeCover(
                                                      update,
                                                    ),
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                                size: 18,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'reading file',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: fileButtonWidth,
                                            child: _BookFileButton(
                                              label: 'PDF / EPUB',
                                              icon: Icons.menu_book_rounded,
                                              file: data.pendingFile,
                                              selected:
                                                  data.pendingFile != null,
                                              onPressed: data.lookupBusy
                                                  ? null
                                                  : () => data.pickBookFile(
                                                      update,
                                                    ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: fileButtonWidth,
                                            child: _BookFileButton(
                                              label: 'audiobook',
                                              icon: Icons.headphones_rounded,
                                              file: data.pendingAudio,
                                              selected:
                                                  data.pendingAudio != null,
                                              onPressed: data.lookupBusy
                                                  ? null
                                                  : () => data.pickAudioFile(
                                                      update,
                                                    ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: const Text('Advanced information'),
                          subtitle: const Text('Additional book information'),
                          children: [
                            data.field(data.subtitle, 'subheading'),
                            data.field(
                              data.description,
                              'Description',
                              maxLines: 5,
                            ),
                            RawAutocomplete<String>(
                              focusNode: data.subjectsFocusNode,
                              textEditingController: data.subjects,
                              optionsBuilder: data.genreOptions,
                              optionsViewBuilder:
                                  (context, onSelected, options) => Material(
                                    elevation: 4,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxHeight: 220,
                                      ),
                                      child: ListView(
                                        padding: EdgeInsets.zero,
                                        shrinkWrap: true,
                                        children: [
                                          for (final genre in options)
                                            ListTile(
                                              dense: true,
                                              title: Text(genre),
                                              onTap: () => onSelected(genre),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                              onSelected: (_) => update(() {}),
                              fieldViewBuilder:
                                  (
                                    context,
                                    controller,
                                    focusNode,
                                    onFieldSubmitted,
                                  ) => TextFormField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    maxLength: 120,
                                    decoration: const InputDecoration(
                                      labelText: 'Genre',
                                      hintText: 'You can choose from the list or type a new type',
                                    ),
                                    onChanged: (_) => update(() {}),
                                    onFieldSubmitted: (_) => onFieldSubmitted(),
                                  ),
                            ),
                            for (final entry in <String, TextEditingController>{
                              'data.tags': data.tags,
                              'data.subjectPlaces': data.subjectPlaces,
                              'data.subjectPeople': data.subjectPeople,
                              'data.subjectTimes': data.subjectTimes,
                              'data.contributions': data.contributions,
                            }.entries)
                              BookItemsField(
                                controller: entry.value,
                                label: bookFacetLabels[entry.key]!,
                              ),
                            data.field(data.publishedDate, 'Publication date'),
                            data.field(data.firstPublishDate, 'First air date'),
                            data.field(data.languageCode, 'Language code'),
                            data.field(data.origin, 'origin'),
                            data.field(
                              data.coverUrl,
                              'Cover image URL',
                              keyboardType: TextInputType.url,
                            ),
                            data.field(data.isbn10, 'ISBN-10'),
                            data.field(data.isbn13, 'ISBN-13'),
                            data.field(data.editionId, 'Print ID'),
                            data.field(data.workId, 'Work ID'),
                            data.field(
                              data.previewUrl,
                              'Preview URL',
                              keyboardType: TextInputType.url,
                            ),
                            data.field(
                              data.sourceUrl,
                              'Source URL',
                              keyboardType: TextInputType.url,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
                  child: Material(
                    elevation: 6,
                    shadowColor: scheme.shadow.withValues(alpha: 0.2),
                    surfaceTintColor: scheme.surfaceTint,
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        spacing: 10,
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: data.saveBusy
                                  ? null
                                  : () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                          ),
                          Expanded(
                            child: FilledButton(
                              onPressed: data.saveBusy
                                  ? null
                                  : () => data.save(update),
                              child: const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
