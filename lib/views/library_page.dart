import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/book_files.dart';
import '../data/audio_book_files.dart';
import '../data/book_facets.dart';
import '../data/book_metadata.dart';
import '../data/cover_files.dart';
import '../data/borrower_repository.dart';
import '../data/library_stats.dart';
import '../data/library_book_snapshot.dart';
import '../data/local_book_store.dart';
import '../data/social_repository.dart';
import '../app/providers.dart';
import '../viewmodels/library_view_model.dart';
import 'book_notes_page.dart';
import 'book_items_field.dart';
import 'discover_page.dart';
import 'isbn_scanner_page.dart';
import 'reader_page.dart';
import 'audio_reader_page.dart';
import 'profile_page.dart';
import 'quote_scan_page.dart';
import 'social_page.dart';
import 'image_shimmer.dart';

part 'library_page_state_base.dart';
part 'library_book_sheet_form.dart';
part 'library_page_book_sync.dart';
part 'library_page_book_editor.dart';
part 'library_page_reading_actions.dart';
part 'library_page_book_management.dart';
part 'library_page_filters.dart';
part 'library_page_layout.dart';
part 'library_page_book_collection.dart';
part 'library_page_statistics.dart';
part 'rename_library_sheet.dart';
part 'rename_library_sheet_state.dart';
part 'brand_mark.dart';
part 'library_metric_card.dart';
part 'book_match_dialog.dart';
part 'catalog_book_picker.dart';
part 'book_match_warning.dart';
part 'book_text_helpers.dart';
part 'book_found_sheet.dart';
part 'rating_summary.dart';
part 'library_book_card_builder.dart';
part 'library_book_card.dart';
part 'book_file_button.dart';
part 'book_cover.dart';
part 'book_cover_state.dart';
part 'metadata_preview.dart';
part 'status_pill.dart';
part 'message_scaffold.dart';
part 'metadata_comparison_sheet_route.dart';
part 'metadata_comparison_sheet.dart';
part 'metadata_comparison_sheet_state.dart';
part 'metadata_field_values.dart';

const _selectedLibraryKey = 'library.selectedOwnerId';
const _selectedPersonalLibraryKey = 'library.selectedPersonalLibraryId';
const _renameLibraryAction = '__rename_library__';
const _newLibraryAction = '__new_library__';
const _personalLibraryActionPrefix = '__personal_library__:';
const _sharedPersonalLibraryActionPrefix = '__shared_personal_library__:';
const _booksPerPage = 24;
const _backPressWindow = Duration(seconds: 2);

const _coverColors = [
  Color(0xFF3E4CFF),
  Color(0xFFE76F51),
  Color(0xFF167D7F),
  Color(0xFF7B61FF),
  Color(0xFFE0A458),
  Color(0xFF2A9D8F),
];

const _coverCacheWidth = 320;
const _coverCacheHeight = 480;

const _defaultGenres = [
  'Fiction',
  'Biography',
  'Autobiography',
  'Essay',
  'Poetry',
  'Philosophy',
];

const _defaultLanguages = [
  'Turkish',
  'English',
  'German',
  'French',
  'Spanish',
  'Italian',
  'Russian',
  'Arabic',
  'Japanese',
];

const _timelineMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _clearStatusAction = '__clear_status__';
const _noStatusFilter = '__no_status__';

Color _bookStatusColor(String? status) => switch (status) {
  readStatus => Colors.green,
  readingStatus => Colors.amber.shade700,
  null => Colors.grey,
  _ => Colors.blue,
};

final _coverCache = <String, Future<File?>>{};

Future<File?> _cacheCover(String url) async {
  // ponytail: no eviction; add size-based cleanup if the cover cache grows materially.
  final uri = Uri.tryParse(url);
  if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return null;
  final directory = Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'cover_cache'),
  );
  final file = File(
    p.join(
      directory.path,
      '${base64Url.encode(utf8.encode(url)).replaceAll('=', '')}.cover',
    ),
  );
  if (await file.exists() && await file.length() > 0) return file;
  final response = await http.get(uri).timeout(const Duration(seconds: 15));
  if (response.statusCode < 200 ||
      response.statusCode >= 300 ||
      response.bodyBytes.isEmpty) {
    return null;
  }
  await directory.create(recursive: true);
  final pending = File('${file.path}.tmp');
  await pending.writeAsBytes(response.bodyBytes, flush: true);
  await pending.rename(file.path);
  return file;
}

const _allFileTypes = 'All';
const _readingFileType = 'PDF / EPUB';
const _audioFileType = 'audiobook';
const _homeCollection = 'home';
const _readingHistoryCollection = 'reading_history';
const _allCollections = 'all';

typedef _LibraryChoice = ({String ownerId, String name, bool editable});

bool _hasStoredFileFormat(Object? value) => switch (value) {
  String value => value.trim().isNotEmpty,
  Iterable values => values.whereType<String>().any(
    (value) => value.trim().isNotEmpty,
  ),
  _ => false,
};

class _LibraryFilterSelection {
  const _LibraryFilterSelection({
    this.author = 'All',
    this.genre = 'All',
    this.facets = const {},
    this.fileType = _allFileTypes,
    this.minPages,
    this.maxPages,
    this.minRating,
    this.fromYear,
    this.toYear,
  });

  final String author;
  final String genre;
  final Map<String, String> facets;
  final String fileType;
  final int? minPages;
  final int? maxPages;
  final int? minRating;
  final int? fromYear;
  final int? toYear;
}

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends _LibraryPageStateBase {
  @override
  void initState() {
    super.initState();
    vm = ref.read(libraryViewModelProvider);
    social = ref.read(socialRepositoryProvider);
    uid = FirebaseAuth.instance.currentUser!.uid;
    _localBookStore = LocalBookStore(uid);
    homeStream = vm.books(uid);
    libraryStream = vm.books(uid);
    selectedLibraryOwnerId = uid;
    unawaited(_restoreLocalBooks());
    unawaited(_restoreSelectedLibrary().catchError((Object _) {}));
  }

  @override
  void dispose() {
    search.dispose();
    searchFocusNode.dispose();
    _audioMiniOverlay?.remove();
    final player = _audioPlayer;
    if (player != null) {
      AudioNotification.detach(player);
      unawaited(player.dispose());
    }
    vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _handleBack();
    },
    child: StreamBuilder<LibraryBookSnapshot>(
      stream: tab == 1 ? libraryStream : homeStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _MessageScaffold(
            icon: Icons.cloud_off_rounded,
            title: 'Your library could not be loaded',
            message: 'Check your connection and try again.',
          );
        }
        if (!snapshot.hasData) return _loadingScaffold();

        final docs = selectedLibraryOwnerId == uid
            ? _mergeLocalBooks(snapshot.data!.docs)
            : snapshot.data!.docs;
        _bookDocs = docs;
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            return Scaffold(
              body: SafeArea(
                child: wide
                    ? Row(
                        children: [
                          _buildSidebar(),
                          Expanded(
                            child: _buildContent(
                              docs,
                              initialBooks: snapshot.data!,
                              wide: true,
                            ),
                          ),
                        ],
                      )
                    : _buildContent(docs, initialBooks: snapshot.data!),
              ),
              floatingActionButton: tab == 1
                  ? SafeArea(
                      top: false,
                      minimum: const EdgeInsets.only(bottom: 8),
                      child: FloatingActionButton(
                        onPressed: busy ? null : addBook,
                        tooltip: 'Add book',
                        child: const Icon(Icons.add_rounded),
                      ),
                    )
                  : null,
              bottomNavigationBar: wide
                  ? null
                  : SafeArea(
                      top: false,
                      minimum: const EdgeInsets.only(bottom: 8),
                      child: _buildBottomNavigation(),
                    ),
            );
          },
        );
      },
    ),
  );
}
