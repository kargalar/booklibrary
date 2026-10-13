part of 'library_page.dart';

abstract class _LibraryPageStateBase extends ConsumerState<LibraryPage> {
  late final LibraryViewModel vm;
  late final SocialRepository social;
  late final LocalBookStore _localBookStore;
  final search = TextEditingController();
  final searchFocusNode = FocusNode();
  late final String uid;
  late final Stream<LibraryBookSnapshot> homeStream;
  late Stream<LibraryBookSnapshot> libraryStream;
  List<LibraryBookDocument> _bookDocs = const [];
  String filter = 'All';
  String collectionFilter = _homeCollection;
  String authorFilter = 'All';
  String genreFilter = 'All';
  Map<String, String> facetFilters = {};
  int? minPageFilter;
  int? maxPageFilter;
  int? minRatingFilter;
  int? fromYearFilter;
  int? toYearFilter;
  final Map<String, double?> _ratingAverages = {};
  final Map<String, Future<_RatingSummary>> _ratingSummaries = {};
  final Map<String, Future<File?>> _bookFiles = {};
  final Map<String, Future<File?>> _audioFiles = {};
  final _loadingReadingBookIds = <String>{};
  final _loadingAudioBookIds = <String>{};
  final _localReadingFileIds = <String>{};
  final _localAudioFileIds = <String>{};
  AudioPlayer? _audioPlayer;
  OverlayEntry? _audioMiniOverlay;
  File? _activeAudioFile;
  String? _activeAudioBookId, _activeAudioTitle;
  String? _activeAudioCoverPath,
      _activeAudioCoverUrl,
      _activeAudioCoverStorageUrl,
      _activeAudioLocalCoverPath;
  bool _audioReaderOpen = false;
  final Map<String, Future<UserProfile?>> _libraryProfiles = {};
  final Map<String, bool> _editableLibraries = {};
  List<PersonalLibrary> _personalLibraries = const [
    PersonalLibrary(id: defaultPersonalLibraryId, name: defaultLibraryName),
  ];
  final Map<String, LocalBookChange> _localBookChanges = {};
  Future<void> _localBookSyncQueue = Future.value();
  String selectedLibraryOwnerId = '';
  String selectedPersonalLibraryId = defaultPersonalLibraryId;
  int tab = 0;
  int _visibleBookCount = _booksPerPage;
  String fileTypeFilter = _allFileTypes;
  bool busy = false;
  bool showWishlist = false;
  bool showLibrarySearch = false;
  DateTime? _lastBackPress;
}
