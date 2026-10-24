part of 'library_page.dart';

// This extension keeps the legacy State API split by concern without duplicating state.
// ignore_for_file: invalid_use_of_protected_member
extension _LibraryPageStatePart2 on _LibraryPageState {
  Future<void> _showBookSheet({
    LibraryBookDocument? doc,
    String? initialIsbn,
  }) async {
    final data = doc?.data();
    final personalLibraries = data == null || data['ownerId'] == uid
        ? await social.personalLibraries(uid)
        : const <PersonalLibrary>[];
    if (!mounted) return;
    final selectedLibraryIds = <String>{
      if (data == null)
        selectedPersonalLibraryId.isEmpty
            ? defaultPersonalLibraryId
            : selectedPersonalLibraryId
      else
        ...bookLibraryIds(data),
    };
    String textValue(String key) {
      final value = data?[key];
      return value == null ? '' : '$value';
    }

    List<String> listValues(String key) {
      final value = data?[key];
      return value is Iterable ? value.whereType<String>().toList() : const [];
    }

    String listValue(String key) => listValues(key).join('\n');
    final tags = TextEditingController(
      text: bookFacetItems(data ?? {}, 'tags').join('\n'),
    );

    final title = TextEditingController(text: textValue('title'));
    final author = TextEditingController(text: textValue('author'));
    final titleFocusNode = FocusNode();
    final authorFocusNode = FocusNode();
    final publisherFocusNode = FocusNode();
    final subjectsFocusNode = FocusNode();
    final languageFocusNode = FocusNode();
    final isbn = TextEditingController(
      text: textValue('isbn13').isNotEmpty
          ? textValue('isbn13')
          : textValue('isbn10').isNotEmpty
          ? textValue('isbn10')
          : textValue('isbn').isNotEmpty
          ? textValue('isbn')
          : initialIsbn ?? '',
    );
    final subtitle = TextEditingController(text: textValue('subtitle'));
    final description = TextEditingController(text: textValue('description'));
    final pageCount = TextEditingController(text: textValue('pageCount'));
    final subjects = TextEditingController(
      text: normalizeGenres(listValues('subjects')).join(', '),
    );
    final subjectPlaces = TextEditingController(
      text: listValue('subjectPlaces'),
    );
    final subjectPeople = TextEditingController(
      text: listValue('subjectPeople'),
    );
    final subjectTimes = TextEditingController(text: listValue('subjectTimes'));
    final contributions = TextEditingController(
      text: listValue('contributions'),
    );
    final publisher = TextEditingController(text: textValue('publisher'));
    final publishedDate = TextEditingController(
      text: textValue('publishedDate'),
    );
    final firstPublishDate = TextEditingController(
      text: textValue('firstPublishDate'),
    );
    final language = TextEditingController(text: textValue('language'));
    final languageCode = TextEditingController(text: textValue('languageCode'));
    final origin = TextEditingController(text: textValue('origin'));
    final coverUrl = TextEditingController(text: textValue('coverUrl'));
    final isbn10 = TextEditingController(text: textValue('isbn10'));
    final isbn13 = TextEditingController(text: textValue('isbn13'));
    final editionId = TextEditingController(text: textValue('editionId'));
    final workId = TextEditingController(text: textValue('workId'));
    final previewUrl = TextEditingController(text: textValue('previewUrl'));
    final sourceUrl = TextEditingController(text: textValue('sourceUrl'));
    String? coverPath = textValue('coverPath').isEmpty
        ? null
        : textValue('coverPath');
    String? coverStorageUrl = textValue('coverStorageUrl').isEmpty
        ? null
        : textValue('coverStorageUrl');
    final metadataControllers = <TextEditingController>[
      subtitle,
      description,
      pageCount,
      subjects,
      tags,
      subjectPlaces,
      subjectPeople,
      subjectTimes,
      contributions,
      publisher,
      publishedDate,
      firstPublishDate,
      language,
      languageCode,
      origin,
      coverUrl,
      isbn10,
      isbn13,
      editionId,
      workId,
      previewUrl,
      sourceUrl,
    ];
    final form = GlobalKey<FormState>();
    const metadataKeys = [
      'metadataSource',
      'subtitle',
      'description',
      'pageCount',
      'subjects',
      'tags',
      'subjectPlaces',
      'subjectPeople',
      'subjectTimes',
      'contributions',
      'publisher',
      'publishedDate',
      'firstPublishDate',
      'language',
      'languageCode',
      'origin',
      'coverUrl',
      'isbn10',
      'isbn13',
      'editionId',
      'workId',
      'previewUrl',
      'sourceUrl',
      'publisherLogoUrl',
      'isbnApiData',
      'isbnApiEditionData',
      'isbnApiWorkData',
    ];
    final hasMetadata =
        data != null && metadataKeys.any((key) => data.containsKey(key));
    BookMetadata? metadata = hasMetadata
        ? BookMetadata.fromFirestore(data)
        : null;
    BookMetadataLookupResult? lookupResult;
    var lookupBusy = false;
    String? lookupError;
    var sheetOpen = true;
    File? pendingFile;
    File? pendingAudio;
    var saveBusy = false;
    Timer? isbnLookupDebounce;

    List<String> values(String value) => value
        .split(RegExp(r'[,;\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();

    String? optional(TextEditingController controller) {
      final value = controller.text.trim();
      return value.isEmpty ? null : value;
    }

    List<BookMatch> currentMatches() => findBookMatches(
      _bookDocs.where((book) => book.id != doc?.id).map((book) => book.data()),
      title: title.text,
      isbn: normalizeIsbn(isbn.text),
    );
    var visibleMatches = <BookMatch>[];

    void refreshMatchWarning(StateSetter update) {
      visibleMatches = currentMatches();
      update(() {});
    }

    if (doc != null) visibleMatches = currentMatches();

    void fillMetadata(BookMetadata value) {
      subtitle.text = value.subtitle ?? '';
      description.text = value.description ?? '';
      pageCount.text = value.pageCount?.toString() ?? '';
      if (value.subjects.isNotEmpty) {
        subjects.text = normalizeGenres(value.subjects).join(', ');
      }
      tags.text = normalizeBookItems([...tags.text.split('\n'), ...value.tags])
          .join('\n');
      subjectPlaces.text = value.subjectPlaces.join('\n');
      subjectPeople.text = value.subjectPeople.join('\n');
      subjectTimes.text = value.subjectTimes.join('\n');
      contributions.text = value.contributions.join('\n');
      publisher.text = value.publisher ?? '';
      publishedDate.text = value.publishedDate ?? '';
      firstPublishDate.text = value.firstPublishDate ?? '';
      language.text = normalizeLanguages([value.language ?? '']).join(', ');
      languageCode.text = value.languageCode ?? '';
      origin.text = value.origin ?? '';
      coverUrl.text = value.coverUrl ?? '';
      isbn10.text = value.isbn10 ?? '';
      isbn13.text = value.isbn13 ?? '';
      editionId.text = value.editionId ?? '';
      workId.text = value.workId ?? '';
      previewUrl.text = value.previewUrl ?? '';
      sourceUrl.text = value.sourceUrl ?? '';
    }

    BookMetadata? editedMetadata() {
      final hasInput =
          metadata != null ||
          metadataControllers.any(
            (controller) => controller.text.trim().isNotEmpty,
          );
      if (!hasInput) return null;
      return BookMetadata(
        isbn: normalizeIsbn(isbn.text) ?? isbn.text.trim(),
        title: title.text.trim(),
        author: author.text.trim(),
        subtitle: optional(subtitle),
        authors: splitAuthorNames(author.text),
        description: optional(description),
        pageCount: int.tryParse(pageCount.text.trim()),
        subjects: normalizeGenres(values(subjects.text)),
        tags: normalizeBookItems(tags.text.split('\n')),
        subjectPlaces: normalizeBookItems(subjectPlaces.text.split('\n')),
        subjectPeople: normalizeBookItems(subjectPeople.text.split('\n')),
        subjectTimes: normalizeBookItems(subjectTimes.text.split('\n')),
        contributions: normalizeBookItems(contributions.text.split('\n')),
        publisher: optional(publisher),
        publishedDate: optional(publishedDate),
        firstPublishDate: optional(firstPublishDate),
        language: language.text.trim().isEmpty
            ? null
            : normalizeLanguages([language.text]).join(', '),
        languageCode: optional(languageCode),
        origin: optional(origin),
        coverUrl: optional(coverUrl),
        isbn10: optional(isbn10),
        isbn13: optional(isbn13),
        editionId: optional(editionId),
        workId: optional(workId),
        previewUrl: optional(previewUrl),
        sourceUrl: optional(sourceUrl),
        publisherLogoUrl: metadata?.publisherLogoUrl,
        metadataSource: metadata?.metadataSource,
        apiData: metadata?.apiData ?? const {},
        apiEditionData: metadata?.apiEditionData ?? const {},
        apiWorkData: metadata?.apiWorkData ?? const {},
        providerData: metadata?.providerData ?? const {},
      );
    }

    Widget field(
      TextEditingController controller,
      String label, {
      int maxLines = 1,
      TextInputType? keyboardType,
      String? hintText,
      String? Function(String?)? validator,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label, hintText: hintText),
        validator: validator,
      ),
    );

    void applyCatalogBook(BookMetadata value, StateSetter update) {
      metadata = value;
      lookupResult = null;
      isbn.text = value.isbn;
      title.text = value.title;
      author.text = value.author;
      fillMetadata(value);
      visibleMatches = currentMatches();
      update(() {});
    }

    Future<void> lookup(StateSetter update) async {
      if (!sheetOpen || lookupBusy) return;
      final normalized = normalizeIsbn(isbn.text);
      if (normalized == null) {
        update(() => lookupError = 'Enter a valid ISBN.');
        return;
      }
      update(() {
        lookupBusy = true;
        lookupError = null;
      });
      final service = BookMetadataLookup();
      try {
        try {
          final catalogBooks = await vm.searchCatalog(isbn: normalized);
          if (catalogBooks.isNotEmpty) {
            if (!mounted || !sheetOpen) return;
            final selected = catalogBooks.length == 1
                ? catalogBooks.first
                : await _showCatalogBookPicker(context, catalogBooks);
            if (selected == null || !sheetOpen) return;
            applyCatalogBook(selected, update);
            return;
          }
        } catch (_) {
          // External providers remain the fallback when the shared catalog is unavailable.
        }
        final result = await service.find(
          normalized,
          title: title.text,
          author: author.text,
        );
        if (!mounted || !sheetOpen || normalizeIsbn(isbn.text) != normalized) {
          return;
        }
        final value = result.primary!;
        lookupResult = result;
        metadata = value;
        isbn.text = value.isbn;
        title.text = value.title;
        author.text = value.author;
        fillMetadata(value);
        visibleMatches = currentMatches();
        if (sheetOpen) update(() {});
      } catch (error) {
        if (sheetOpen) {
          update(() {
            lookupError = error is FormatException ? error.message : 'Book information could not be obtained. Check your internet connection.';
          });
        }
      } finally {
        service.dispose();
        if (sheetOpen) {
          update(() => lookupBusy = false);
          if (normalizeIsbn(isbn.text) != normalized) {
            Future<void>.microtask(() => lookup(update));
          }
        }
      }
    }

    Future<void> lookupByTitleAuthor(StateSetter update) async {
      if (!sheetOpen || lookupBusy) return;
      final titleQuery = title.text.trim();
      final authorQuery = author.text.trim();
      if (titleQuery.isEmpty) {
        update(() => lookupError = 'First enter the book name.');
        return;
      }
      update(() {
        lookupBusy = true;
        lookupError = null;
      });
      final service = BookMetadataLookup();
      try {
        List<BookMetadata> catalogBooks = const [];
        try {
          catalogBooks = await vm.searchCatalog(title: titleQuery);
        } catch (_) {
          // The external title search remains the fallback when the catalog is unavailable.
        }
        if (catalogBooks.isNotEmpty) {
          if (!mounted || !sheetOpen) return;
          final selected = catalogBooks.length == 1
              ? catalogBooks.first
              : await _showCatalogBookPicker(context, catalogBooks);
          if (selected != null && sheetOpen) applyCatalogBook(selected, update);
          return;
        }
        final result = await service.findByTitleAuthor(
          title: titleQuery,
          author: authorQuery,
        );
        if (!mounted || !sheetOpen) return;
        final value = result.primary!;
        lookupResult = result;
        metadata = value;
        isbn.text = value.isbn;
        title.text = value.title;
        author.text = value.author;
        fillMetadata(value);
        visibleMatches = currentMatches();
        update(() {});
      } catch (error) {
        if (sheetOpen) {
          update(
            () => lookupError = error is FormatException ? error.message : 'Book information could not be obtained. Check your internet connection.',
          );
        }
      } finally {
        service.dispose();
        if (sheetOpen) update(() => lookupBusy = false);
      }
    }

    Future<void> compare(StateSetter update) async {
      if (!sheetOpen) return;
      final normalized = normalizeIsbn(isbn.text);
      if (normalized == null) {
        update(() => lookupError = 'Enter a valid ISBN.');
        return;
      }
      update(() {
        lookupBusy = true;
        lookupError = null;
      });
      final service = BookMetadataLookup();
      try {
        final result = await service.compare(
          normalized,
          title: title.text,
          author: author.text,
        );
        if (!mounted || !sheetOpen) return;
        final selection = await _showMetadataComparison(context, result);
        if (selection == null || !sheetOpen || metadata == null) return;
        final selected = <BookMetadataField, BookMetadata>{
          for (final entry in selection.entries)
            entry.key: result.candidates[entry.value]!,
        };
        BookMetadata value(BookMetadataField field) =>
            selected[field] ?? metadata!;
        metadata = metadata!.copyWith(
          title: value(BookMetadataField.title).title,
          author: value(BookMetadataField.author).author,
          subtitle: value(BookMetadataField.subtitle).subtitle,
          description: value(BookMetadataField.description).description,
          pageCount: value(BookMetadataField.pageCount).pageCount,
          subjects: value(BookMetadataField.subjects).subjects,
          publisher: value(BookMetadataField.publisher).publisher,
          publishedDate: value(BookMetadataField.publishedDate).publishedDate,
          language: value(BookMetadataField.language).language,
          languageCode: value(BookMetadataField.language).languageCode,
          coverUrl: value(BookMetadataField.coverUrl).coverUrl,
          publisherLogoUrl: value(BookMetadataField.publisherLogoUrl)
              .publisherLogoUrl,
          isbn10: value(BookMetadataField.isbn10).isbn10,
          isbn13: value(BookMetadataField.isbn13).isbn13,
          previewUrl: value(BookMetadataField.previewUrl).previewUrl,
          metadataSource:
              'Selected sources · ${selection.values.map((provider) => provider.label).toSet().join(', ')}',
          providerData: result.providerData,
        );
        lookupResult = result;
        isbn.text = metadata!.isbn;
        title.text = metadata!.title;
        author.text = metadata!.author;
        fillMetadata(metadata!);
        visibleMatches = currentMatches();
        if (sheetOpen) update(() {});
      } catch (error) {
        if (sheetOpen) {
          update(() {
            lookupError = error is FormatException
                ? error.message
                : 'Sources could not be compared.';
          });
        }
      } finally {
        service.dispose();
        if (sheetOpen) update(() => lookupBusy = false);
      }
    }

    Future<void> save(StateSetter update) async {
      if (!sheetOpen || saveBusy || !(form.currentState?.validate() ?? false)) {
        return;
      }
      final titleValue = title.text.trim();
      final authorValue = author.text.trim();
      final normalizedIsbn = normalizeIsbn(isbn.text);
      final edited = editedMetadata();
      final selectedFile = pendingFile;
      final selectedAudio = pendingAudio;
      final selectedCoverPath = coverPath;
      final selectedCoverStorageUrl = coverStorageUrl;
      final selectedLibraries = Set<String>.from(selectedLibraryIds);
      update(() {
        saveBusy = true;
        lookupError = null;
      });
      try {
        final matches = currentMatches();
        if (matches.isNotEmpty) {
          if (!mounted) return;
          final proceed = await _showBookMatchDialog(context, matches);
          if (proceed != true) {
            update(() => saveBusy = false);
            return;
          }
        }

        final id = doc?.id ?? vm.newLibraryBookId();
        var storedCoverPath = selectedCoverPath;
        final storedCoverStorageUrl = selectedCoverStorageUrl;
        final hasRemoteCover = storedCoverPath?.startsWith('http') == true;
        final hasLocalCover =
            storedCoverPath != null &&
            storedCoverPath.isNotEmpty &&
            !hasRemoteCover &&
            await File(storedCoverPath).exists();
        if (!hasLocalCover && !hasRemoteCover) storedCoverPath = null;
        String? readingFormat;
        if (selectedFile != null) {
          readingFormat = p
              .extension(selectedFile.path)
              .toLowerCase()
              .replaceFirst('.', '');
          await BookFiles.saveLocal(uid, id, selectedFile);
        }

        String? audioFormat;
        if (selectedAudio != null) {
          audioFormat = p
              .extension(selectedAudio.path)
              .toLowerCase()
              .replaceFirst('.', '');
          await AudioBookFiles.saveLocal(uid, id, selectedAudio);
        }

        final fileFields = <String, dynamic>{
          ...?readingFormat == null ? null : {'readingFormat': readingFormat},
          if (audioFormat != null) ...{
            'audioFormat': audioFormat,
            'listeningProgress': 0.0,
          },
        };
        final fields = <String, dynamic>{
          ...?edited?.toFirestoreFields(includeEmpty: true),
          if (edited == null && normalizedIsbn != null) 'isbn': normalizedIsbn,
          'coverPath': storedCoverPath,
          'coverStorageUrl': storedCoverStorageUrl,
          'title': titleValue,
          'author': authorValue,
          'authors': splitAuthorNames(authorValue),
          'inHomeLibrary': selectedLibraries.contains(defaultPersonalLibraryId),
          'libraryIds': selectedLibraries.toList(),
          ...fileFields,
        };
        final localData = doc == null
            ? {
                ...fields,
                'libraryId': uid,
                'ownerId': uid,
                'bookId': 'local_$id',
                'wishlist': false,
                'status': null,
                'createdAt': DateTime.now().toIso8601String(),
              }
            : {
                ...fields,
                'libraryId': uid,
                'ownerId': uid,
                'bookId': data?['bookId'] ?? 'local_$id',
                'wishlist': data?['wishlist'] == true,
                'status': data?['status'],
              };
        final change = LocalBookChange(
          id: id,
          isNew: doc == null || data?['bookId'] == 'local_$id',
          data: localData,
        );
        unawaited(_saveLocalBook(change));
        if (mounted && sheetOpen) {
          sheetOpen = false;
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('The book has been saved to the device.'),
            ),
          );
          unawaited(_syncLocalBook(change, showWarning: true));
        }
        return;
      } catch (error) {
        if (sheetOpen) {
          update(() {
            saveBusy = false;
            lookupError = error is FormatException ? error.message : 'The book could not be saved. Check your link or file and try again.';
          });
          return;
        }
      }
      if (mounted && sheetOpen) {
        sheetOpen = false;
        Navigator.pop(context, true);
      }
    }

    Future<void> saveCover(String path, StateSetter update) async {
      final directory = await getApplicationDocumentsDirectory();
      final covers = Directory(p.join(directory.path, 'covers'));
      await covers.create(recursive: true);
      final target = File(
        p.join(
          covers.path,
          'cover_${DateTime.now().microsecondsSinceEpoch}.jpg',
        ),
      );
      await File(path).copy(target.path);
      if (sheetOpen) {
        update(() {
          coverPath = target.path;
          coverStorageUrl = null;
        });
      }
    }

    Future<void> captureCover(StateSetter update) async {
      if (!sheetOpen || !_canCaptureCover) return;
      try {
        final path = await _pickCoverPhoto();
        if (path == null || !sheetOpen) return;
        await saveCover(path, update);
      } catch (_) {
        if (sheetOpen) {
          update(
            () => lookupError =
                'Could not retrieve cover photo. Please try again.',
          );
        }
      }
    }

    Future<void> pickGalleryCover(StateSetter update) async {
      if (!sheetOpen || !_canCaptureCover) return;
      try {
        final image = await _pickCoverPhoto(allowGalleryImport: true);
        if (image == null || !sheetOpen) return;
        await saveCover(image, update);
      } catch (_) {
        if (sheetOpen) {
          update(
            () => lookupError =
                'Could not select a cover from the gallery. Please try again.',
          );
        }
      }
    }

    void removeCover(StateSetter update) {
      update(() {
        coverPath = null;
        coverStorageUrl = null;
        coverUrl.clear();
      });
    }

    Future<void> pickBookFile(StateSetter update) async {
      try {
        final file = await BookFiles.pick();
        if (file != null && sheetOpen) update(() => pendingFile = file);
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }

    Future<void> pickAudioFile(StateSetter update) async {
      try {
        final file = await AudioBookFiles.pick();
        if (file != null && sheetOpen) update(() => pendingAudio = file);
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }

    void onIsbnChanged(String _, StateSetter update) {
      refreshMatchWarning(update);
      isbnLookupDebounce?.cancel();
      if (normalizeIsbn(isbn.text) == null) return;
      isbnLookupDebounce = Timer(
        const Duration(milliseconds: 500),
        () => lookup(update),
      );
    }

    late final _BookSheetFormData formData;

    void syncFormData() {
      formData
        ..lookupBusy = lookupBusy
        ..lookupError = lookupError
        ..lookupResult = lookupResult
        ..metadata = metadata
        ..visibleMatches = visibleMatches
        ..coverPath = coverPath
        ..coverStorageUrl = coverStorageUrl
        ..pendingFile = pendingFile
        ..pendingAudio = pendingAudio
        ..saveBusy = saveBusy;
    }

    StateSetter synchronizedUpdate(StateSetter update) => (change) {
      if (!mounted || !sheetOpen) return;
      update(() {
        change();
        syncFormData();
      });
    };

    formData = _BookSheetFormData(
      context: context,
      doc: doc,
      initialIsbn: initialIsbn,
      personalLibraries: personalLibraries,
      selectedLibraryIds: selectedLibraryIds,
      form: form,
      title: title,
      author: author,
      isbn: isbn,
      titleFocusNode: titleFocusNode,
      authorFocusNode: authorFocusNode,
      publisherFocusNode: publisherFocusNode,
      subjectsFocusNode: subjectsFocusNode,
      languageFocusNode: languageFocusNode,
      subtitle: subtitle,
      description: description,
      pageCount: pageCount,
      subjects: subjects,
      tags: tags,
      subjectPlaces: subjectPlaces,
      subjectPeople: subjectPeople,
      subjectTimes: subjectTimes,
      contributions: contributions,
      publisher: publisher,
      publishedDate: publishedDate,
      firstPublishDate: firstPublishDate,
      language: language,
      languageCode: languageCode,
      origin: origin,
      coverUrl: coverUrl,
      isbn10: isbn10,
      isbn13: isbn13,
      editionId: editionId,
      workId: workId,
      previewUrl: previewUrl,
      sourceUrl: sourceUrl,
      coverPath: coverPath,
      coverStorageUrl: coverStorageUrl,
      metadata: metadata,
      lookupResult: lookupResult,
      lookupBusy: lookupBusy,
      lookupError: lookupError,
      lookupStarted: false,
      visibleMatches: visibleMatches,
      pendingFile: pendingFile,
      pendingAudio: pendingAudio,
      saveBusy: saveBusy,
      canCaptureCover: _canCaptureCover,
      field:
          (
            controller,
            label, {
            int? maxLines,
            TextInputType? keyboardType,
            String? hintText,
            String? Function(String?)? validator,
          }) => field(
            controller,
            label,
            maxLines: maxLines ?? 1,
            keyboardType: keyboardType,
            hintText: hintText,
            validator: validator,
          ),
      lookup: (update) => lookup(synchronizedUpdate(update)),
      lookupByTitleAuthor: (update) =>
          lookupByTitleAuthor(synchronizedUpdate(update)),
      refreshMatchWarning: (update) =>
          refreshMatchWarning(synchronizedUpdate(update)),
      compare: (update) => compare(synchronizedUpdate(update)),
      save: (update) => save(synchronizedUpdate(update)),
      pickBookFile: (update) => pickBookFile(synchronizedUpdate(update)),
      pickAudioFile: (update) => pickAudioFile(synchronizedUpdate(update)),
      captureCover: (update) => captureCover(synchronizedUpdate(update)),
      removeCover: (update) => removeCover(synchronizedUpdate(update)),
      pickGalleryCover: (update) =>
          pickGalleryCover(synchronizedUpdate(update)),
      onIsbnChanged: (value, update) =>
          onIsbnChanged(value, synchronizedUpdate(update)),
      titleOptions: _titleOptions,
      authorOptions: _authorOptions,
      publisherOptions: _publisherOptions,
      genreOptions: _genreOptions,
      languageOptions: _languageOptions,
      textValue: textValue,
    );
    await _showBookSheetForm(
      formData,
      onClosing: () {
        sheetOpen = false;
        isbnLookupDebounce?.cancel();
      },
    );
    _releaseSearchFocus();
    if (doc != null) {
      _bookFiles.remove(doc.id);
      _audioFiles.remove(doc.id);
    }
    title.dispose();
    author.dispose();
    titleFocusNode.dispose();
    authorFocusNode.dispose();
    publisherFocusNode.dispose();
    subjectsFocusNode.dispose();
    languageFocusNode.dispose();
    isbn.dispose();
    for (final controller in metadataControllers) {
      controller.dispose();
    }
  }
}
