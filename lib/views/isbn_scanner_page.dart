import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/book_metadata.dart';

class IsbnScannerPage extends StatefulWidget {
  const IsbnScannerPage({super.key});

  @override
  State<IsbnScannerPage> createState() => _IsbnScannerPageState();
}

class _IsbnScannerPageState extends State<IsbnScannerPage> {
  final controller = MobileScannerController();
  bool found = false;

  void _onDetect(BarcodeCapture capture) {
    if (found) return;
    for (final barcode in capture.barcodes) {
      final isbn = normalizeIsbn(barcode.rawValue ?? '');
      if (isbn == null) continue;
      found = true;
      controller.stop();
      Navigator.of(context).pop(isbn);
      return;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: const Text('Scan ISBN'),
      foregroundColor: Colors.white,
      backgroundColor: Colors.black,
      actions: [
        ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, state, child) => switch (state.torchState) {
            TorchState.on => IconButton(
              tooltip: 'turn off flash',
              onPressed: controller.toggleTorch,
              icon: const Icon(Icons.flash_on_rounded),
            ),
            TorchState.off || TorchState.auto => IconButton(
              tooltip: 'turn on flash',
              onPressed: controller.toggleTorch,
              icon: const Icon(Icons.flash_off_rounded),
            ),
            TorchState.unavailable => const SizedBox.shrink(),
          },
        ),
      ],
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: controller, onDetect: _onDetect),
        Center(
          child: Container(
            width: 300,
            height: 170,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        const Positioned(
          left: 24,
          right: 24,
          bottom: 86,
          child: Text(
            'Align the ISBN barcode on the back cover of the book to the frame.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(''),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            child: const Text('Atla'),
          ),
        ),
      ],
    ),
  );
}
