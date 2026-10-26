part of 'reader_page.dart';

extension _ReaderSurfaces on _ReaderPageState {
  ThemeData get readerTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: readerAccent,
      brightness: palette == 2 ? Brightness.dark : Brightness.light,
      surface: readerBackground,
    );
    return Theme.of(context).copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: readerBackground,
      cardTheme: Theme.of(context).cardTheme.copyWith(color: readerBackground),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: readerForeground.withAlpha(10),
        labelStyle: TextStyle(color: readerForeground),
        hintStyle: TextStyle(color: readerForeground.withAlpha(150)),
        prefixIconColor: readerAccent,
        suffixIconColor: readerAccent,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: readerForeground.withAlpha(50)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: readerAccent, width: 1.5),
        ),
      ),
      textTheme: Theme.of(context).textTheme
          .apply(bodyColor: readerForeground, displayColor: readerForeground),
      iconTheme: IconThemeData(color: readerForeground),
    );
  }

  Widget themedSurface(WidgetBuilder builder, {bool showDragHandle = false}) =>
      ValueListenableBuilder<int>(
        valueListenable: appearance,
        builder: (context, _, _) => Theme(
          data: readerTheme,
          child: Material(
            color: readerBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showDragHandle)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: readerForeground.withAlpha(50),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                Flexible(child: Builder(builder: builder)),
              ],
            ),
          ),
        ),
      );

  Future<T?> showReaderSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool useSafeArea = true,
    bool showDragHandle = false,
  }) async {
    chromeTimer?.cancel();
    final result = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      backgroundColor: Colors.transparent,
      builder: (_) => themedSurface(builder, showDragHandle: showDragHandle),
    );
    if (mounted && showChrome) revealChrome();
    return result;
  }

  Future<T?> showReaderDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) async {
    chromeTimer?.cancel();
    final result = await showDialog<T>(
      context: context,
      builder: (_) => Theme(
        data: readerTheme,
        child: Builder(builder: builder),
      ),
    );
    if (mounted && showChrome) revealChrome();
    return result;
  }
}
