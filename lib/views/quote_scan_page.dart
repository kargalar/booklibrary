import 'dart:io';
import 'dart:ui' as ui;

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
  Size? _imageSize;
  List<TextLine> _lines = [];
  final Set<int> _selectedLines = {};

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

      final bytes = await File(image.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      if (!mounted) return;
      setState(() {
        _imagePath = image.path;
        _imageSize = size;
        _lines = [];
        _selectedLines.clear();
        _setText('');
      });
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final recognized = await recognizer.processImage(
          InputImage.fromFilePath(image.path),
        );
        if (!mounted) return;
        final lines = recognized.blocks.expand((block) => block.lines).toList();
        setState(() => _lines = lines);
        if (lines.isEmpty) {
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

  void _toggleLine(int index) {
    setState(() {
      if (!_selectedLines.add(index)) _selectedLines.remove(index);
      _setText(
        [
          for (var i = 0; i < _lines.length; i++)
            if (_selectedLines.contains(i)) _lines[i].text,
        ].join('\n'),
      );
    });
  }

  Widget _photoSelector(ColorScheme scheme) {
    final size = _imageSize!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final scale = width / size.width;
        return AspectRatio(
          aspectRatio: size.width / size.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(_imagePath!),
                  fit: BoxFit.fill,
                  errorBuilder: (_, _, _) =>
                      Center(child: Text('The photo could not be previewed.')),
                ),
                for (var i = 0; i < _lines.length; i++)
                  Positioned(
                    left: _lines[i].boundingBox.left * scale,
                    top: _lines[i].boundingBox.top * scale,
                    width: _lines[i].boundingBox.width * scale,
                    height: _lines[i].boundingBox.height * scale,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _busy ? null : () => _toggleLine(i),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _selectedLines.contains(i)
                              ? scheme.primary.withAlpha(100)
                              : scheme.primary.withAlpha(25),
                          border: Border.all(
                            color: scheme.primary.withAlpha(
                              _selectedLines.contains(i) ? 230 : 100,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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
                    'Take a photo or choose one from your gallery, then tap the text lines you want. Edit the selected text below before adding it as a quote.',
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
                    _photoSelector(scheme),
                    const SizedBox(height: 8),
                    Text(
                      'Tap highlighted lines to select or deselect them.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (_busy)
                    const LinearProgressIndicator()
                  else
                    Text(
                      'Selected text',
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
                      hintText: 'Selected text will appear here',
                      helperText: 'Review and edit the selected text before continuing.',
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
