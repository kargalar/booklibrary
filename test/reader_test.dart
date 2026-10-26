import 'dart:io';

import 'package:booklibrary/views/reader_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> openReader(
    WidgetTester tester, {
    Map<String, Object> preferences = const {},
    String file = 'test/fixtures/sample.epub',
    Future<void> Function(String)? onQuote,
    Future<void> Function(String)? onQuickNote,
  }) async {
    SharedPreferences.setMockInitialValues(preferences);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderPage(
            file: File(file),
            title: 'A very long book title for the reading experience',
            storageKey: 'test',
            onQuote: onQuote,
            onQuickNote: onQuickNote,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
  }

  Future<void> openTool(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Reading tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('EPUB bookmarks are saved and navigate to the saved chapter', (
    tester,
  ) async {
    await openReader(tester);
    await tester.tap(find.byTooltip('Add bookmark'));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList('test.bookmarks'), ['0']);
    await tester.tap(find.byTooltip('Next chapter'));
    await tester.pumpAndSettle();
    await openTool(tester, 'Bookmarks');
    await tester.tap(find.textContaining('Birinci').last);
    await tester.pumpAndSettle();
    expect(find.text('Chapter 1 / 2'), findsOneWidget);
    expect(find.byTooltip('Remove bookmark'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('EPUB quotes save without accessing a PDF controller', (
    tester,
  ) async {
    String? quote;
    await openReader(
      tester,
      onQuote: (text) async {
        quote = text;
      },
    );
    final selection = tester.widget<SelectionArea>(find.byType(SelectionArea));
    selection.onSelectionChanged!(
      const SelectedContent(plainText: 'A selected passage'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add as quote'));
    await tester.pumpAndSettle();
    expect(quote, 'A selected passage');
    expect(find.text('Add as quote'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('EPUB search finds text and opens its chapter', (tester) async {
    await openReader(tester);
    await tester.tap(find.byTooltip('Next chapter'));
    await tester.pumpAndSettle();
    await openTool(tester, 'Search in book');
    await tester.enterText(find.byType(TextField), 'Kitap okuma');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Birinci').last);
    await tester.pumpAndSettle();
    expect(find.text('Chapter 1 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('focus mode hides and restores EPUB tools', (tester) async {
    await openReader(tester);
    await openTool(tester, 'Focus mode');
    expect(find.byTooltip('Reading view'), findsNothing);
    await tester.tap(find.text('Reading tools'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Reading view'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'narrow reader and settings support large text without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openReader(tester);
      await tester.tap(find.byTooltip('Reading view'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('EPUB restores the saved scroll position after layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openReader(
      tester,
      preferences: {'test.offset': 60.0, 'reader.fontSize': 36.0},
    );
    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('epub-reader-scroll')),
    );
    expect(scroll.controller!.offset, closeTo(60, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('EPUB search jumps to and highlights the matching passage', (
    tester,
  ) async {
    await openReader(tester, file: 'test/fixtures/reader_navigation.epub');
    await openTool(tester, 'Search in book');
    await tester.enterText(find.byType(TextField), 'smallest observation');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('epub-reader-scroll')),
    );
    expect(scroll.controller!.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('EPUB links navigate between chapters and to named anchors', (
    tester,
  ) async {
    await openReader(tester, file: 'test/fixtures/reader_navigation.epub');
    final link = find.text('Visit the next chapter', findRichText: true);
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.text('Chapter 2 / 2'), findsOneWidget);
    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('epub-reader-scroll')),
    );
    expect(scroll.controller!.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('invalid persisted EPUB bookmarks are discarded', (tester) async {
    await openReader(
      tester,
      preferences: {
        'test.bookmarks': ['-1', '0', '999', 'invalid'],
      },
    );
    await openTool(tester, 'Bookmarks');
    expect(find.text('Page 999'), findsNothing);
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('a missing book shows a recoverable error', (tester) async {
    await openReader(tester, file: 'test/fixtures/missing.epub');
    expect(find.text('Unable to open this book'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to open this book'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('failed quote saves preserve the selection for retry', (
    tester,
  ) async {
    var shouldFail = true;
    String? quote;
    await openReader(
      tester,
      onQuote: (text) async {
        if (shouldFail) throw StateError('Temporary write failure');
        quote = text;
      },
    );
    tester
        .widget<SelectionArea>(find.byType(SelectionArea))
        .onSelectionChanged!(
      const SelectedContent(plainText: 'Keep this passage'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add as quote'));
    await tester.pumpAndSettle();
    expect(find.text('Add as quote'), findsOneWidget);
    shouldFail = false;
    await tester.tap(find.text('Add as quote'));
    await tester.pumpAndSettle();
    expect(quote, 'Keep this passage');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('quick notes preserve drafts when the dialog is cancelled', (
    tester,
  ) async {
    String? note;
    await openReader(
      tester,
      onQuickNote: (text) async {
        note = text;
      },
    );
    await openTool(tester, 'Quick note');
    await tester.enterText(find.byType(TextFormField), 'An unfinished thought');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await openTool(tester, 'Quick note');
    expect(find.text('An unfinished thought'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(note, 'An unfinished thought');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('EPUB renders, changes chapters and saves appearance', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderPage(
            file: File('test/fixtures/sample.epub'),
            title: 'Deneme',
            storageKey: 'test',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.text('Chapter 1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Next chapter'));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 2 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Reading view'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sepia'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('test.position'), 1);
    expect(prefs.getInt('reader.palette'), 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderPage(
            file: File('test/fixtures/sample.epub'),
            title: 'Deneme',
            storageKey: 'test',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.text('Chapter 2 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Contents').last);
    await tester.pumpAndSettle();
    expect(find.text('1. Birinci bölüm'), findsOneWidget);
    expect(find.text('2. İkinci bölüm'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
