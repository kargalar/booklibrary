part of 'reader_page.dart';

// ignore_for_file: invalid_use_of_protected_member
extension _ReaderSettings on _ReaderPageState {
  Future<void> settings() async {
    chromeTimer?.cancel();
    await showReaderSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          void change(VoidCallback action) {
            setState(action);
            update(() {});
            scheduleSave();
          }

          Widget slider(
            String title,
            double value,
            double min,
            double max,
            ValueChanged<double> onChange,
          ) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title)),
                  Text(
                    value.toStringAsFixed(
                      title == _ReaderLabels.lineSpacing ? 1 : 0,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Slider(
                value: value,
                min: min,
                max: max,
                onChanged: (value) => change(() => onChange(value)),
              ),
            ],
          );

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _ReaderLabels.comfortable,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isPdf
                        ? _ReaderLabels.pdfSettingsHint
                        : _ReaderLabels.epubSettingsHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    _ReaderLabels.pageAppearance,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _paletteChoices(
                    palette,
                    (value) => change(() => palette = value),
                  ),
                  const SizedBox(height: 24),
                  if (!isPdf) ...[
                    slider(
                      _ReaderLabels.fontSize,
                      fontSize,
                      _ReaderDefaults.minFontSize,
                      _ReaderDefaults.maxFontSize,
                      (value) => fontSize = value,
                    ),
                    slider(
                      _ReaderLabels.lineSpacing,
                      lineHeight,
                      _ReaderDefaults.minLineHeight,
                      _ReaderDefaults.maxLineHeight,
                      (value) => lineHeight = value,
                    ),
                    slider(
                      _ReaderLabels.pageMargins,
                      margin,
                      _ReaderDefaults.minMargin,
                      _ReaderDefaults.maxMargin,
                      (value) => margin = value,
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(_ReaderLabels.serifTypeface),
                      subtitle: const Text(_ReaderLabels.classicTypography),
                      value: serif,
                      onChanged: (value) => change(() => serif = value),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(_ReaderLabels.justifiedText),
                      value: justify,
                      onChanged: (value) => change(() => justify = value),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: zoomPdfOut,
                            icon: const Icon(Icons.zoom_out_rounded),
                            label: const Text(_ReaderLabels.zoomOut),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: zoomPdfIn,
                            icon: const Icon(Icons.zoom_in_rounded),
                            label: const Text(_ReaderLabels.zoomIn),
                          ),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: fitPdfPage,
                      icon: const Icon(Icons.fit_screen_rounded),
                      label: const Text(_ReaderLabels.fitPage),
                    ),
                  ],
                  const Divider(height: 24),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(_ReaderLabels.keepControls),
                    subtitle: const Text(_ReaderLabels.keepControlsHint),
                    value: alwaysShowChrome,
                    onChanged: (value) {
                      change(() {
                        alwaysShowChrome = value;
                        showChrome = true;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(context);
                      revealChrome(toggle: true);
                    },
                    icon: const Icon(Icons.fullscreen_rounded),
                    label: const Text(_ReaderLabels.enterFocusMode),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted && showChrome) revealChrome();
  }

  Widget _paletteChoices(int selected, ValueChanged<int> onChanged) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _readerPaletteNames.length; i++)
            ChoiceChip(
              avatar: Icon(
                selected == i ? Icons.check_rounded : _readerPaletteIcons[i],
                size: 18,
                color: i == 2
                    ? const Color(0xFFE0E3E7)
                    : const Color(0xFF292D32),
              ),
              label: Text(_readerPaletteNames[i]),
              showCheckmark: false,
              labelStyle: TextStyle(
                color: i == 2
                    ? const Color(0xFFE0E3E7)
                    : const Color(0xFF292D32),
              ),
              backgroundColor: const [
                Color(0xFFFAF9F6),
                Color(0xFFF3E9D6),
                Color(0xFF191D22),
              ][i],
              selectedColor: const [
                Color(0xFFFAF9F6),
                Color(0xFFF3E9D6),
                Color(0xFF191D22),
              ][i],
              side: BorderSide(
                color: selected == i
                    ? readerAccent
                    : readerForeground.withAlpha(40),
                width: selected == i ? 2 : 1,
              ),
              selected: selected == i,
              onSelected: (_) => onChanged(i),
            ),
        ],
      ),
    );
  }
}
