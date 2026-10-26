part of 'reader_page.dart';

// ignore_for_file: invalid_use_of_protected_member
extension _ReaderNotes on _ReaderPageState {
  bool get canAddText => selectedText.trim().isEmpty
      ? widget.onQuickNote != null
      : widget.onQuote != null;

  Future<void> addText() async {
    if (!canAddText || savingText) return;
    setState(() => savingText = true);
    try {
      await _addText();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_ReaderLabels.noteSaveError)),
        );
      }
    } finally {
      if (mounted) setState(() => savingText = false);
    }
  }

  Future<void> _addText() async {
    final selected = selectedText.trim();
    final text = selected.isEmpty
        ? await showReaderDialog<String>(
            context: context,
            builder: (context) {
              var value = quickNoteDraft;
              return AlertDialog(
                title: const Text(_ReaderLabels.quickNote),
                content: TextFormField(
                  initialValue: value,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 5,
                  onChanged: (next) {
                    value = next;
                    quickNoteDraft = next;
                  },
                  decoration: const InputDecoration(
                    labelText: _ReaderLabels.note,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(_ReaderLabels.cancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, value.trim()),
                    child: const Text(_ReaderLabels.save),
                  ),
                ],
              );
            },
          )
        : selected;
    if (text == null || text.trim().isEmpty || !mounted) return;
    if (selected.isEmpty) {
      await widget.onQuickNote?.call(text.trim());
      quickNoteDraft = '';
    } else {
      await widget.onQuote?.call(text.trim());
      if (isPdf && pdfController.isReady) {
        await pdfController.textSelectionDelegate.clearTextSelection();
      }
    }
    if (mounted) setState(() => selectedText = '');
  }
}
