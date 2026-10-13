part of 'library_page.dart';

// This extension keeps the legacy State API split by concern without duplicating state.
// ignore_for_file: invalid_use_of_protected_member
extension _LibraryPageStatePart3 on _LibraryPageState {
  bool get _canScanIsbn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _canCaptureCover =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<String?> _pickCoverPhoto({bool allowGalleryImport = false}) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormats: {DocumentFormat.jpeg},
          mode: ScannerMode.full,
          pageLimit: 1,
          isGalleryImport: allowGalleryImport,
        ),
      );
      try {
        final result = await scanner.scanDocument();
        final scanned = result.images?.firstOrNull;
        return scanned == null
            ? null
            : scanned.startsWith('file:')
            ? Uri.parse(scanned).toFilePath()
            : scanned;
      } finally {
        await scanner.close();
      }
    }
    return (await ImagePicker().pickImage(
      source: allowGalleryImport ? ImageSource.gallery : ImageSource.camera,
    ))?.path;
  }

  String date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

  Future<String?> _newBorrowerName(BuildContext context) async {
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create new contact',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Person name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Contact name required.'
                    : null,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      if (form.currentState!.validate()) {
                        Navigator.pop(context, controller.text.trim());
                      }
                    },
                    child: const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    return name;
  }

  Future<void> lend(LibraryBookDocument doc) async {
    final form = GlobalKey<FormState>();
    Borrower? selected;
    DateTime? due;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) =>
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: vm.borrowers(uid),
              builder: (context, snapshot) {
                final people = [
                  ...?snapshot.data?.docs.map(Borrower.fromDocument),
                ];
                if (selected != null &&
                    !people.any((person) => person.id == selected!.id)) {
                  people.add(selected!);
                }
                people.sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    4,
                    20,
                    20 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: SingleChildScrollView(
                    child: Form(
                      key: form,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'lend the book',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          if (snapshot.hasError)
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Failed to load contacts; You can create a new contact.',
                              ),
                            ),
                          DropdownButtonFormField<String>(
                            initialValue: selected?.id,
                            decoration: const InputDecoration(
                              labelText: 'Borrowed by',
                            ),
                            items: [
                              for (final person in people)
                                DropdownMenuItem(
                                  value: person.id,
                                  child: Text(person.name),
                                ),
                            ],
                            onChanged: (id) {
                              if (id == null) return;
                              update(() {
                                selected = people.firstWhere(
                                  (person) => person.id == id,
                                );
                              });
                            },
                            validator: (_) => selected == null
                                ? 'Select a contact or create a new contact.'
                                : null,
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: const Icon(Icons.person_add_alt_1_rounded),
                              label: const Text('Create new contact'),
                              onPressed: () async {
                                final name = await _newBorrowerName(context);
                                if (name == null || !context.mounted) return;
                                try {
                                  final created = await vm.addBorrower(
                                    uid,
                                    name,
                                  );
                                  if (context.mounted) {
                                    update(() => selected = created);
                                  }
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Could not create borrower: $error',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.calendar_month_rounded),
                            label: Text(
                              due == null
                                  ? 'Choose a return date (optional)'
                                  : date(due!),
                            ),
                            onPressed: () async {
                              final now = DateUtils.dateOnly(DateTime.now());
                              final selectedDate = await showDatePicker(
                                context: context,
                                initialDate: due ?? now,
                                firstDate: now,
                                lastDate: DateTime(now.year + 10),
                              );
                              if (selectedDate != null && context.mounted) {
                                update(() => due = selectedDate);
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () {
                                  if (form.currentState!.validate()) {
                                    Navigator.pop(context, true);
                                  }
                                },
                                child: const Text('lend'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      ),
    );
    if (accepted == true && selected != null) {
      final borrower = selected!;
      await _updateBookOptimistically(
        doc,
        {
          'borrowerId': borrower.id,
          'borrowerUserId': null,
          'loanRequestId': null,
          'returnedAt': null,
          'borrower': borrower.name,
          'loanDue': due == null ? null : Timestamp.fromDate(due!),
        },
        () => vm.update(doc.id, {
          'borrowerId': borrower.id,
          'borrowerUserId': null,
          'loanRequestId': null,
          'returnedAt': null,
          'borrower': borrower.name,
          'loanedAt': FieldValue.serverTimestamp(),
          'loanDue': due == null ? null : Timestamp.fromDate(due!),
        }),
        failureMessage: 'The loan transaction could not be completed.',
      );
    }
  }

  Future<void> openBook(LibraryBookDocument doc, {bool replace = false}) async {
    if (busy || _loadingReadingBookIds.contains(doc.id)) return;
    try {
      await run(() async {
        final data = doc.data();
        final ownerId = data['ownerId'] as String? ?? uid;
        final storedFormat = data['readingFormat'] as String?;
        File? file = replace
            ? null
            : await BookFiles.find(uid, doc.id, extension: storedFormat);
        if (file == null && mounted) {
          setState(() => _loadingReadingBookIds.add(doc.id));
        }
        if (file == null && !replace) {
          final formats = storedFormat == null
              ? const ['pdf', 'epub']
              : [storedFormat];
          for (final format in formats) {
            final downloaded = await BookFiles.download(
              localUid: uid,
              ownerId: ownerId,
              id: doc.id,
              extension: format,
            );
            if (downloaded != null) {
              file = downloaded;
              _localReadingFileIds.add(doc.id);
              _bookFiles.remove(doc.id);
              break;
            }
          }
        }
        if (file == null) {
          file = await BookFiles.import(uid, doc.id);
          if (file != null) {
            _localReadingFileIds.add(doc.id);
            _bookFiles.remove(doc.id);
          }
        }
        if (file == null || !mounted) return;
        final format = p
            .extension(file.path)
            .toLowerCase()
            .replaceFirst('.', '');
        if (data['readingFormat'] != format) {
          await vm.update(doc.id, {'readingFormat': format});
        }
        if (!mounted) return;
        setState(() => _loadingReadingBookIds.remove(doc.id));
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReaderPage(
              file: file!,
              title: doc.data()['title'] as String? ?? '',
              storageKey: '$uid.${doc.id}.${format == 'pdf' ? 'pdf' : 'epub'}',
              onProgress: (value) =>
                  vm.update(doc.id, {'readingProgress': value}),
              onQuickNote: (text) => vm.update(doc.id, {
                'notes': FieldValue.arrayUnion([text]),
              }),
              onQuote: (text) => vm.update(doc.id, {
                'quotes': FieldValue.arrayUnion([text]),
              }),
            ),
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _loadingReadingBookIds.remove(doc.id));
      }
    }
  }

  void _showAudioMini() {
    final overlay = Navigator.of(context).overlay;
    if (overlay == null) return;
    if (_audioMiniOverlay?.mounted == true) {
      _audioMiniOverlay!.markNeedsBuild();
      return;
    }
    _audioMiniOverlay = OverlayEntry(
      builder: (context) {
        final player = _audioPlayer;
        final file = _activeAudioFile;
        final bookId = _activeAudioBookId;
        final title = _activeAudioTitle;
        if (_audioReaderOpen ||
            player == null ||
            file == null ||
            bookId == null ||
            title == null) {
          return const SizedBox.shrink();
        }
        final mobile = MediaQuery.sizeOf(context).width < 600;
        return Positioned(
          left: 12,
          right: 12,
          bottom: mobile ? 76 : 16,
          child: SafeArea(
            top: false,
            child: AudioMiniPlayer(
              key: ValueKey('$bookId.${file.path}'),
              player: player,
              title: title,
              storageKey: '$uid.$bookId.audio.${p.basename(file.path)}',
              onProgress: (value) =>
                  vm.update(bookId, {'listeningProgress': value}),
              onOpen: _openActiveAudio,
              onClose: _closeAudio,
            ),
          ),
        );
      },
    );
    overlay.insert(_audioMiniOverlay!);
  }

  void _closeAudio() {
    final player = _audioPlayer;
    _audioMiniOverlay?.remove();
    _audioMiniOverlay = null;
    _audioPlayer = null;
    _activeAudioFile = null;
    _activeAudioBookId = null;
    _activeAudioTitle = null;
    _activeAudioCoverPath = null;
    _activeAudioCoverUrl = null;
    _activeAudioCoverStorageUrl = null;
    _activeAudioLocalCoverPath = null;
    if (player != null) {
      AudioNotification.detach(player);
      unawaited(player.dispose());
    }
  }

  Future<void> _openActiveAudio() async {
    final file = _activeAudioFile;
    final bookId = _activeAudioBookId;
    final title = _activeAudioTitle;
    if (file == null || bookId == null || title == null) return;
    await _pushAudioReader(
      file,
      bookId,
      title,
      coverPath: _activeAudioCoverPath,
      coverUrl: _activeAudioCoverUrl,
      coverStorageUrl: _activeAudioCoverStorageUrl,
      localCoverPath: _activeAudioLocalCoverPath,
    );
  }

  Future<void> _pushAudioReader(
    File file,
    String bookId,
    String title, {
    String? coverPath,
    String? coverUrl,
    String? coverStorageUrl,
    String? localCoverPath,
  }) async {
    final player = _audioPlayer;
    if (player == null || !mounted) return;
    _audioReaderOpen = true;
    _audioMiniOverlay?.markNeedsBuild();
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AudioReaderPage(
            file: file,
            title: title,
            player: player,
            storageKey: '$uid.$bookId.audio.${p.basename(file.path)}',
            coverPath: coverPath,
            coverUrl: coverUrl,
            coverStorageUrl: coverStorageUrl,
            localCoverPath: localCoverPath,
            onProgress: (value) =>
                vm.update(bookId, {'listeningProgress': value}),
            onQuickNote: (text) => vm.update(bookId, {
              'notes': FieldValue.arrayUnion([text]),
            }),
          ),
        ),
      );
    } finally {
      _audioReaderOpen = false;
      if (_audioMiniOverlay?.mounted == true) {
        _audioMiniOverlay!.markNeedsBuild();
      }
    }
  }

  Future<void> openAudio(LibraryBookDocument doc) async {
    if (busy || _loadingAudioBookIds.contains(doc.id)) return;
    try {
      await run(() async {
        final data = doc.data();
        final ownerId = data['ownerId'] as String? ?? uid;
        final storedFormat = data['audioFormat'] as String?;
        var file = await AudioBookFiles.find(uid, doc.id);
        if (file == null && mounted) {
          setState(() => _loadingAudioBookIds.add(doc.id));
        }
        if (file == null && storedFormat != null) {
          final downloaded = await AudioBookFiles.download(
            localUid: uid,
            ownerId: ownerId,
            id: doc.id,
            extension: storedFormat,
          );
          if (downloaded != null) {
            file = downloaded;
            _localAudioFileIds.add(doc.id);
            _audioFiles.remove(doc.id);
          }
        }
        if (file == null) {
          final selected = await AudioBookFiles.pick();
          if (selected == null) return;
          final format = p
              .extension(selected.path)
              .toLowerCase()
              .replaceFirst('.', '');
          file = await AudioBookFiles.save(uid, doc.id, selected);
          _localAudioFileIds.add(doc.id);
          _audioFiles.remove(doc.id);
          await vm.update(doc.id, {
            'audioFormat': format,
            'listeningProgress': 0.0,
          });
        } else {
          final format = p
              .extension(file.path)
              .toLowerCase()
              .replaceFirst('.', '');
          if (data['audioFormat'] != format) {
            await vm.update(doc.id, {'audioFormat': format});
          }
        }
        if (!mounted) return;
        setState(() => _loadingAudioBookIds.remove(doc.id));
        _audioPlayer ??= AudioPlayer();
        _activeAudioFile = file;
        _activeAudioBookId = doc.id;
        _activeAudioTitle = doc.data()['title'] as String? ?? '';
        _activeAudioCoverPath = data['coverPath'] as String?;
        _activeAudioCoverUrl = data['coverUrl'] as String?;
        _activeAudioCoverStorageUrl = data['coverStorageUrl'] as String?;
        _activeAudioLocalCoverPath = data['legacyCoverPath'] as String?;
        _showAudioMini();
        await _pushAudioReader(
          file,
          doc.id,
          _activeAudioTitle!,
          coverPath: _activeAudioCoverPath,
          coverUrl: _activeAudioCoverUrl,
          coverStorageUrl: _activeAudioCoverStorageUrl,
          localCoverPath: _activeAudioLocalCoverPath,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _loadingAudioBookIds.remove(doc.id));
      }
    }
  }

  Future<void> _chooseStatus(LibraryBookDocument doc) async {
    final data = doc.data();
    final canManage = _canManageBook(data);
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final status in bookStatuses)
                ListTile(
                  leading: Icon(
                    status == readStatus
                        ? Icons.check_circle_rounded
                        : status == readingStatus
                        ? Icons.menu_book_rounded
                        : status == null
                        ? Icons.remove_circle_outline_rounded
                        : Icons.bookmark_border_rounded,
                    color: _bookStatusColor(status),
                  ),
                  title: Text(
                    bookStatusLabel(status),
                    style: TextStyle(
                      color: _bookStatusColor(status),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  selected: canonicalBookStatus(data['status']) == status,
                  selectedTileColor: _bookStatusColor(status).withAlpha(20),
                  onTap: () =>
                      Navigator.pop(context, status ?? _clearStatusAction),
                ),
              if (canManage) ...[
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context, 'edit'),
                        icon: const Icon(Icons.edit_rounded),
                        label: const Text('Edit'),
                      ),
                    ),
                    if (!hasBorrower(data)) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context, 'lend'),
                          icon: const Icon(Icons.swap_horiz_rounded),
                          label: const Text('Lend'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (selected != null) await action(selected, doc);
  }
}
