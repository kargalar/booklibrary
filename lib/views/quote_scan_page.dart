import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class QuoteScanPage extends StatefulWidget {
  const QuoteScanPage({super.key});

  @override
  State<QuoteScanPage> createState() => _QuoteScanPageState();
}

class _QuoteScanPageState extends State<QuoteScanPage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _textController = TextEditingController();
  String? _imagePath;
  bool _busy = false;

  bool get _isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_busy || !_isSupported) return;
    setState(() => _busy = true);
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 2400,
        imageQuality: 95,
      );
      if (image == null || !mounted) return;

      setState(() => _imagePath = image.path);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final recognized = await recognizer.processImage(
          InputImage.fromFilePath(image.path),
        );
        if (!mounted) return;
        final text = recognized.text.trim();
        _setText(text);
        if (text.isEmpty) {
          _showMessage('No readable text was found in the photo.');
        }
      } finally {
        await recognizer.close();
      }
    } catch (error, stackTrace) {
      debugPrint('Quote OCR failed: $error\n$stackTrace');
      if (mounted) {
        _showMessage('The text could not be read. Try a brighter photo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setText(String value) {
    _textController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _copyAll() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _showMessage('The text has been copied to the clipboard.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quote from photo'),
        actions: [
          IconButton(
            onPressed: _busy || _textController.text.trim().isEmpty
                ? null
                : _copyAll,
            tooltip: 'Copy entire text',
            icon: const Icon(Icons.copy_all_rounded),
          ),
        ],
      ),
      body: !_isSupported
          ? _UnsupportedContent(scheme: scheme)
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Text(
                    'Photograph the text on the page',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Select a page from camera or gallery. You can select the detected text below, copy it, edit it and save it as a quote.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_rounded),
                          label: const Text('take photo'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_rounded),
                          label: const Text('select from gallery'),
                        ),
                      ),
                    ],
                  ),
                  if (_imagePath != null) ...[
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.file(
                        File(_imagePath!),
                        height: 210,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          height: 210,
                          color: scheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: const Text(
                            'The photo could not be previewed.',
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (_busy)
                    const LinearProgressIndicator()
                  else
                    Text(
                      'Detected text',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _textController,
                    minLines: 8,
                    maxLines: 16,
                    maxLength: 2000,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'The text will appear here',
                      helperText: 'Press and hold to select and copy text.',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy || _textController.text.trim().isEmpty
                        ? null
                        : () =>
                              Navigator.of(context)
                                  .pop(_textController.text.trim()),
                    icon: const Icon(Icons.format_quote_rounded),
                    label: const Text('Quote'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _UnsupportedContent extends StatelessWidget {
  const _UnsupportedContent({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.phone_android_rounded, size: 46, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            'Reading text from photo is only available on Android and iPhone.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );
}
