part of 'book_notes_page.dart';

class _EntryEditorSheet extends StatefulWidget {
  const _EntryEditorSheet({
    required this.quote,
    required this.initialText,
    this.onScanQuote,
  });

  final bool quote;
  final String initialText;
  final Future<String?> Function()? onScanQuote;

  @override
  State<_EntryEditorSheet> createState() => _EntryEditorSheetState();
}

class _EntryEditorSheetState extends State<_EntryEditorSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  bool _scanning = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scanQuote() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final scanned = await widget.onScanQuote!();
      if (!mounted || scanned == null || scanned.trim().isEmpty) return;
      final text = scanned.trim();
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(_NotesLabels.scanFailed)));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.quote ? 'Quote' : 'Note';
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              widget.quote
                  ? Icons.format_quote_rounded
                  : Icons.edit_note_rounded,
              size: 32,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              widget.initialText.isEmpty ? 'Add $title' : 'Edit $title',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _controller,
              autofocus: true,
              minLines: 4,
              maxLines: 6,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: title,
                hintText: widget.quote
                    ? 'Write a quote from the book'
                    : 'Write your note',
              ),
            ),
            if (widget.quote && widget.onScanQuote != null) ...[
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _scanning ? null : _scanQuote,
                  icon: const Icon(Icons.document_scanner_rounded),
                  label: Text(
                    _scanning ? _NotesLabels.scanning : 'Transfer from photo',
                  ),
                ),
              ),
            ],
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
                  onPressed: _controller.text.trim().isEmpty || _scanning
                      ? null
                      : () => Navigator.pop(context, _controller.text.trim()),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
