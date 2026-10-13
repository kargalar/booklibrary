import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('PDF engine opens and renders a local PDF', () async {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile('test/fixtures/sample.pdf');
    try {
      expect(document.pages, hasLength(1));
      final image = await document.pages.first.render();
      expect(image, isNotNull);
      expect(image!.width, greaterThan(0));
      image.dispose();
    } finally {
      await document.dispose();
    }
  });
}
