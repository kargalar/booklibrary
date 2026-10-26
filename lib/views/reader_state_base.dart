part of 'reader_page.dart';

abstract class _ReaderPageStateBase extends State<ReaderPage>
    with WidgetsBindingObserver {
  final scroll = ScrollController();
  final pdfController = PdfViewerController();
  final searchController = TextEditingController();
  late Future<void> ready;
  late SharedPreferences prefs;

  EpubBook? epub;
  List<EpubTextContentFile> sections = [];
  final sectionTitles = <String, String>{};
  final bookmarks = <int>{};

  final htmlKey = GlobalKey<HtmlWidgetState>();
  bool restoreEpubOffset = true;
  double? scrubPosition;
  double? epubScrollExtent;
  int position = 0;
  final appearance = ValueNotifier<int>(0);
  int get palette => appearance.value;
  set palette(int value) => appearance.value = value;
  int pdfPages = 0;
  double fontSize = _ReaderDefaults.fontSize;
  double lineHeight = _ReaderDefaults.lineHeight;
  double margin = _ReaderDefaults.margin;
  double offset = 0;
  bool serif = false;
  bool justify = false;
  bool loaded = false;
  bool showChrome = true;
  bool alwaysShowChrome = false;
  bool closing = false;
  String? highlightedEpubHtml;
  String selectedText = '';
  String quickNoteDraft = '';
  bool savingText = false;
  Timer? saveTimer;
  Timer? chromeTimer;
  PdfTextSearcher? pdfSearcher;
}

abstract final class _ReaderDefaults {
  static const fontSize = 20.0;
  static const minFontSize = 12.0;
  static const maxFontSize = 36.0;
  static const lineHeight = 1.6;
  static const minLineHeight = 1.0;
  static const maxLineHeight = 2.5;
  static const margin = 20.0;
  static const minMargin = 8.0;
  static const maxMargin = 48.0;
  static const contentWidth = 760.0;
  static const saveDelay = Duration(milliseconds: 450);
  static const chromeDelay = Duration(seconds: 5);
}
