import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:booklibrary/views/reader_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  Future<void> waitForPdf(WidgetTester tester) async {
    for (var attempt = 0; attempt < 12; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openPdf(WidgetTester tester, {int page = 1}) async {
    SharedPreferences.setMockInitialValues({'pdf.position': page});
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          file: File('test/fixtures/reader_navigation.pdf'),
          title: 'The Art of Quiet Reading',
          storageKey: 'pdf',
        ),
      ),
    );
    await waitForPdf(tester);
  }

  testWidgets(
    'PDF page navigation persists and slider previews do not change the current page',
    (tester) async {
      await openPdf(tester);
      expect(find.text('Page 1 / 3'), findsOneWidget);
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(3);
      await tester.pump();
      expect(find.text('Page 1 / 3'), findsOneWidget);
      slider.onChangeEnd!(3);
      await waitForPdf(tester);
      expect(find.text('Page 3 / 3'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('pdf.position'), 3);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'PDF restores a saved page and clamps page jumps to document bounds',
    (tester) async {
      await openPdf(tester, page: 2);
      expect(find.text('Page 2 / 3'), findsOneWidget);
      await tester.tap(find.text('Page 2 / 3'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '999');
      await tester.tap(find.text('Go'));
      await waitForPdf(tester);
      expect(find.text('Page 3 / 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('PDF search stays available after closing the search sheet', (
    tester,
  ) async {
    await openPdf(tester);
    await tester.tap(find.byTooltip('Reading tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search in book'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'afternoon');
    await waitForPdf(tester);
    expect(find.text('3 results found'), findsOneWidget);
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    expect(find.text('1 / 3 matches'), findsOneWidget);
    await tester.tap(find.byTooltip('Next result'));
    await waitForPdf(tester);
    expect(find.text('Page 2 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Next result'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('PDF settings and search fit a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openPdf(tester);
    await tester.tap(find.byTooltip('Reading view'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reading tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search in book'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
