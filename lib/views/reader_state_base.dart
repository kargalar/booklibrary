part of 'reader_page.dart';

abstract class _ReaderPageStateBase extends State<ReaderPage>
    with WidgetsBindingObserver {
  final scroll = ScrollController();
  final pdfController = PdfViewerController();
  final searchController = TextEditingController();
  late final Future<void> ready;
  late SharedPreferences prefs;

  EpubBook? epub;
  List<EpubTextContentFile> sections = [];
  final sectionTitles = <String, String>{};
  final bookmarks = <int>{};

  int position = 0;
  int palette = 0;
  int pdfPages = 0;
  double fontSize = 20;
  double lineHeight = 1.6;
  double margin = 20;
  double offset = 0;
  bool serif = false;
  bool justify = false;
  bool loaded = false;
  bool showChrome = true;
  bool alwaysShowChrome = false;
  bool closing = false;
  String selectedText = '';
  String quickNoteDraft = '';
  Timer? saveTimer;
  Timer? chromeTimer;
  PdfTextSearcher? pdfSearcher;
}
