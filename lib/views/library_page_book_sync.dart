part of 'library_page.dart';

// This extension keeps the legacy State API split by concern without duplicating state.
// ignore_for_file: invalid_use_of_protected_member
extension _LibraryPageStatePart1 on _LibraryPageState {
  Future<void> _restoreLocalBooks() async {
    final changes = await _localBookStore.load();
    if (!mounted) return;
    setState(() {
      for (final change in changes) {
        _localBookChanges[change.id] = change;
      }
    });
    for (final change in changes.where((change) => change.error == null)) {
      unawaited(_syncLocalBook(change));
    }
  }

  Future<void> _restoreSelectedLibrary() async {
    final preferences = await SharedPreferences.getInstance();
    final personalLibraries = await social.personalLibraries(uid);
    final ownerId = preferences.getString('$_selectedLibraryKey.$uid');
    final personalLibraryId = preferences.getString(
      '$_selectedPersonalLibraryKey.$uid',
    );
    if (!mounted) return;
    final selectedPersonalLibrary =
        personalLibraries.any((library) => library.id == personalLibraryId)
        ? personalLibraryId!
        : personalLibraries.first.id;
    setState(() {
      _personalLibraries = personalLibraries;
      selectedPersonalLibraryId = selectedPersonalLibrary;
    });
    if (ownerId == null || ownerId == uid) return;
    final links = await social.friendLinks(uid).first;
    final friendIds = _friendIds(links.docs);
    if (friendIds.contains(ownerId) && mounted) {
      final friend = await social.profile(ownerId);
      final friendLibraryId =
          friend?.personalLibraries.any(
                (library) => library.id == personalLibraryId,
              ) ==
              true
          ? personalLibraryId!
          : friend?.personalLibraries.first.id ?? defaultPersonalLibraryId;
      setState(() {
        selectedLibraryOwnerId = ownerId;
        selectedPersonalLibraryId = friendLibraryId;
        libraryStream = social.sharedBooks(ownerId);
        _visibleBookCount = _booksPerPage;
      });
    }
  }

  Set<String> _friendIds(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> links,
  ) => {
    for (final link in links)
      if (link.data()['memberIds'] is Iterable)
        ...link.data()['memberIds'].whereType<String>().where(
          (id) => id != uid,
        ),
  };

  Future<void> _selectLibrary(String ownerId) async {
    if (ownerId == selectedLibraryOwnerId && ownerId != uid) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('$_selectedLibraryKey.$uid', ownerId);
    if (ownerId == uid) {
      await preferences.setString(
        '$_selectedPersonalLibraryKey.$uid',
        selectedPersonalLibraryId,
      );
    } else {
      await preferences.remove('$_selectedPersonalLibraryKey.$uid');
    }
    if (!mounted) return;
    setState(() {
      selectedLibraryOwnerId = ownerId;
      if (ownerId != uid) selectedPersonalLibraryId = '';
      libraryStream = ownerId == uid
          ? vm.books(uid)
          : social.sharedBooks(ownerId);
      search.clear();
      filter = 'All';
      collectionFilter = _homeCollection;
      fileTypeFilter = _allFileTypes;
      authorFilter = 'All';
      genreFilter = 'All';
      facetFilters = {};
      minPageFilter = null;
      maxPageFilter = null;
      minRatingFilter = null;
      fromYearFilter = null;
      toYearFilter = null;
      _ratingAverages.clear();
      _ratingSummaries.clear();
      _localReadingFileIds.clear();
      _localAudioFileIds.clear();
      _visibleBookCount = _booksPerPage;
    });
  }

  Future<void> _selectPersonalLibrary(String libraryId) async {
    if (!_personalLibraries.any((library) => library.id == libraryId)) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('$_selectedLibraryKey.$uid', uid);
    await preferences.setString('$_selectedPersonalLibraryKey.$uid', libraryId);
    if (!mounted) return;
    setState(() {
      selectedLibraryOwnerId = uid;
      selectedPersonalLibraryId = libraryId;
      libraryStream = vm.books(uid);
      search.clear();
      filter = 'All';
      collectionFilter = _homeCollection;
      fileTypeFilter = _allFileTypes;
      authorFilter = 'All';
      genreFilter = 'All';
      facetFilters = {};
      minPageFilter = null;
      maxPageFilter = null;
      minRatingFilter = null;
      fromYearFilter = null;
      toYearFilter = null;
      _ratingAverages.clear();
      _ratingSummaries.clear();
      _localReadingFileIds.clear();
      _localAudioFileIds.clear();
      _visibleBookCount = _booksPerPage;
    });
  }

  Future<void> _selectSharedPersonalLibrary(
    String ownerId,
    String libraryId,
  ) async {
    await _selectLibrary(ownerId);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('$_selectedPersonalLibraryKey.$uid', libraryId);
    if (!mounted) return;
    setState(() {
      selectedLibraryOwnerId = ownerId;
      selectedPersonalLibraryId = libraryId;
      collectionFilter = _homeCollection;
      _visibleBookCount = _booksPerPage;
    });
  }

  bool _canManageBook(Map<String, dynamic> data) {
    final ownerId = data['ownerId'];
    return ownerId == uid ||
        ownerId is String && _editableLibraries[ownerId] == true;
  }

  String _libraryName(String ownerId, String? fallback) =>
      fallback ?? defaultLibraryName;

  String _selectedPersonalLibraryName() =>
      _personalLibraries
          .where((library) => library.id == selectedPersonalLibraryId)
          .firstOrNull
          ?.name ??
      defaultLibraryName;

  Future<List<_LibraryChoice>> _libraryChoices() async {
    final links = await social.friendLinks(uid).first;
    final friendIds = _friendIds(links.docs).toList()..sort();
    final ownerIds = [uid, ...friendIds];
    final profiles = await Future.wait(ownerIds.map(_profileFor));
    final editable = <String>{uid};
    for (final link in links.docs) {
      final members = link.data()['memberIds'];
      final friendId = members is Iterable
          ? members.whereType<String>().firstWhere(
              (id) => id != uid,
              orElse: () => '',
            )
          : '';
      final permissions = link.data()['permissions'];
      if (friendId.isNotEmpty &&
          permissions is Map &&
          permissions[uid] == 'edit') {
        editable.add(friendId);
      }
    }
    return [
      for (var index = 0; index < ownerIds.length; index++)
        (
          ownerId: ownerIds[index],
          name: _libraryName(ownerIds[index], profiles[index]?.libraryName),
          editable: editable.contains(ownerIds[index]),
        ),
    ];
  }

  void _releaseSearchFocus() {
    searchFocusNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) searchFocusNode.unfocus();
    });
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error, stackTrace) {
      developer.log(
        'Library operation failed',
        name: 'LibraryPage.run',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException ? error.message : 'The operation could not be completed. Check your link or file and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  List<LibraryBookDocument> _mergeLocalBooks(
    List<LibraryBookDocument> remoteDocs,
  ) {
    final merged = <String, LibraryBookDocument>{
      for (final doc in remoteDocs) doc.id: doc,
    };
    for (final change in _localBookChanges.values) {
      final remote = merged[change.id];
      final data = {
        ...?remote?.data(),
        ...change.data,
        'syncStatus': change.error == null ? 'pending' : 'failed',
        ...?change.error == null ? null : {'syncError': change.error},
      };
      merged[change.id] = LibraryBookDocument.local(change.id, data);
    }
    return merged.values.toList(growable: false);
  }

  Future<void> _saveLocalBook(LocalBookChange change) async {
    _localBookChanges[change.id] = change;
    if (mounted) setState(() {});
    try {
      await _localBookStore.save(change);
    } catch (error, stackTrace) {
      developer.log(
        'Local book save failed',
        name: 'LibraryPage.localBookSave',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> _syncLocalBook(
    LocalBookChange change, {
    bool showWarning = true,
  }) {
    final sync = _localBookSyncQueue.then(
      (_) => _syncLocalBookNow(change, showWarning: showWarning),
    );
    _localBookSyncQueue = sync.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return sync;
  }

  Future<bool> _syncLocalBookNow(
    LocalBookChange change, {
    required bool showWarning,
  }) async {
    final current = _localBookChanges[change.id];
    if (current == null || !identical(current, change)) return false;
    try {
      final data = current.data;
      final coverPath = data['coverPath'] as String?;
      final coverStorageUrl = data['coverStorageUrl'] as String?;
      final localCover =
          coverPath != null &&
          !coverPath.startsWith('http') &&
          await File(coverPath).exists();
      final needsCoverUpload =
          coverStorageUrl?.startsWith('http') != true &&
          (localCover || (data['coverUrl'] as String?)?.isNotEmpty == true);
      final readingFormat = _storedFormat(data['readingFormat']);
      final audioFormat = _storedFormat(data['audioFormat']);

      if (current.isNew) {
        await vm.add(
          uid,
          data['title'] as String? ?? '',
          data['author'] as String? ?? '',
          metadata: BookMetadata.fromFirestore(data),
          isbn: normalizeIsbn(data['isbn'] as String? ?? ''),
          coverPath: coverPath,
          wishlist: data['wishlist'] == true,
          inHomeLibrary: data['inHomeLibrary'] != false,
          libraryIds: bookLibraryIds(data),
          relationId: current.id,
        );
        final spotifyUrls = data['spotifyUrls'];
        final legacySpotifyUrl = data['spotifyUrl'];
        if (spotifyUrls is Iterable) {
          await vm.update(current.id, {
            'spotifyUrls': spotifyUrls.whereType<String>().toList(),
            'spotifyUrl': null,
          });
        } else if (legacySpotifyUrl is String && legacySpotifyUrl.isNotEmpty) {
          await vm.update(current.id, {
            'spotifyUrls': [legacySpotifyUrl],
            'spotifyUrl': null,
          });
        }
      } else {
        final updates = Map<String, dynamic>.from(data)
          ..remove('ownerId')
          ..remove('libraryId')
          ..remove('bookId')
          ..remove('syncStatus')
          ..remove('syncError');
        if (needsCoverUpload) updates.remove('coverStorageUrl');
        if (readingFormat != null) updates.remove('readingFormat');
        if (audioFormat != null) updates.remove('audioFormat');
        await vm.update(current.id, updates);
      }

      final uploaded = <String, dynamic>{};
      if (needsCoverUpload) {
        final uploadedCover = localCover
            ? await CoverFiles.saveFromFile(uid, current.id, File(coverPath))
            : await CoverFiles.saveFromUrl(
                uid,
                current.id,
                data['coverUrl'] as String,
              );
        uploaded['coverStorageUrl'] = uploadedCover;
      }
      if (readingFormat != null) {
        final file = await BookFiles.find(
          uid,
          current.id,
          extension: readingFormat,
        );
        if (file != null) {
          await BookFiles.upload(uid, current.id, file);
          uploaded['readingFormat'] = readingFormat;
        }
      }
      if (audioFormat != null) {
        final file = await AudioBookFiles.find(uid, current.id);
        if (file != null) {
          await AudioBookFiles.upload(uid, current.id, file);
          uploaded['audioFormat'] = audioFormat;
        }
      }
      if (uploaded.isNotEmpty) {
        if (audioFormat != null) uploaded['listeningProgress'] = 0.0;
        await vm.update(current.id, uploaded);
      }
      if (!identical(_localBookChanges[current.id], current)) return false;
      if (!await _localBookStore.remove(current.id, expected: current)) {
        return false;
      }
      if (!identical(_localBookChanges[current.id], current)) return false;
      _localBookChanges.remove(current.id);
      if (mounted) setState(() {});
      return true;
    } catch (error, stackTrace) {
      developer.log(
        'Local book cloud sync failed',
        name: 'LibraryPage.localBookSync',
        error: error,
        stackTrace: stackTrace,
      );
      if (identical(_localBookChanges[current.id], current)) {
        final failed = current.copyWith(error: _localSyncError(error));
        await _localBookStore.save(failed);
        _localBookChanges[current.id] = failed;
        if (mounted) {
          setState(() {});
          if (showWarning) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'The book was recorded on this device; Could not upload to cloud. You can try again from the details.',
                ),
              ),
            );
          }
        }
      }
      return false;
    } finally {
      final latest = _localBookChanges[change.id];
      if (latest != null && !identical(latest, current)) {
        unawaited(_syncLocalBook(latest));
      }
    }
  }

  Future<void> _retryLocalBook(String id) async {
    final change = _localBookChanges[id];
    if (change == null) return;
    if (!await _syncLocalBook(change, showWarning: false) &&
        _localBookChanges.containsKey(id)) {
      throw StateError('Upload to cloud failed.');
    }
  }

  String? _storedFormat(Object? value) {
    if (value is! String) return null;
    final format = value.toLowerCase().replaceFirst('.', '');
    return format.isEmpty ? null : format;
  }

  String _localSyncError(Object error) =>
      error is FormatException ? error.message : 'Upload to cloud failed.';

  Future<void> addBook() async {
    _releaseSearchFocus();
    String? scannedIsbn;
    if (_canScanIsbn) {
      scannedIsbn = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const IsbnScannerPage()),
      );
      if (!mounted) return;
    }
    if (_canScanIsbn && scannedIsbn == null) return;
    if (scannedIsbn == null || scannedIsbn.isEmpty) {
      await _showBookSheet();
      _releaseSearchFocus();
      return;
    }
    try {
      final catalogBooks = await vm.searchCatalog(isbn: scannedIsbn);
      if (!mounted) return;
      if (catalogBooks.isNotEmpty) {
        await _showBookFoundSheet(catalogBooks.first);
        _releaseSearchFocus();
        return;
      }
    } catch (_) {
      // The API lookup below remains the fallback when the catalog is unavailable.
    }
    await _showBookSheet(initialIsbn: scannedIsbn);
    _releaseSearchFocus();
  }

  Future<void> _showBookFoundSheet(BookMetadata metadata) async {
    final inHomeLibrary = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _BookFoundSheet(metadata: metadata),
    );
    if (inHomeLibrary == null || !mounted) return;
    final selectedBookLibraries = inHomeLibrary
        ? [
            selectedPersonalLibraryId.isEmpty
                ? defaultPersonalLibraryId
                : selectedPersonalLibraryId,
          ]
        : const <String>[];
    final isbn = normalizeIsbn(metadata.isbn);
    final matches = findBookMatches(
      _bookDocs.map((book) => book.data()),
      title: metadata.title,
      isbn: isbn,
    );
    if (matches.isNotEmpty) {
      final proceed = await _showBookMatchDialog(context, matches);
      if (proceed != true || !mounted) return;
    }
    final id = vm.newLibraryBookId();
    final change = LocalBookChange(
      id: id,
      isNew: true,
      data: {
        ...metadata.toFirestoreFields(includeEmpty: true),
        'title': metadata.title,
        'author': metadata.author,
        'libraryId': uid,
        'ownerId': uid,
        'bookId': 'local_$id',
        'wishlist': false,
        'inHomeLibrary': inHomeLibrary,
        'libraryIds': selectedBookLibraries,
        'status': null,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
    unawaited(_saveLocalBook(change));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The book has been saved to the device.')),
    );
    unawaited(_syncLocalBook(change, showWarning: true));
  }

  Future<void> editBook([LibraryBookDocument? doc]) => _showBookSheet(doc: doc);
}
