import 'dart:io';

import 'package:booklibrary/views/reader_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
    await tester.tap(find.byTooltip('Contents'));
    await tester.pumpAndSettle();
    expect(find.text('1. Birinci bölüm'), findsOneWidget);
    expect(find.text('2. İkinci bölüm'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
