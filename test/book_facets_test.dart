import 'package:booklibrary/data/book_facets.dart';
import 'package:booklibrary/data/book_metadata.dart';
import 'package:booklibrary/views/audio_reader_page.dart';
import 'package:booklibrary/views/book_items_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'item lists round trip, deduplicate and filter without splitting names',
    () {
      final metadata = const BookMetadata(
        isbn: '',
        title: 'Kitap',
        author: '',
        tags: [' Ürpertici ', 'ürpertici', 'Gladyatör teması'],
        subjectPeople: ['Smith, John', 'Smith, John'],
        subjectPlaces: ['Roma'],
      );
      final book = metadata.toFirestoreFields();
      expect(BookMetadata.fromFirestore(book).tags, [
        'Ürpertici',
        'Gladyatör teması',
      ]);
      expect(bookFacetCounts([book, book], 'subjectPeople'), {
        'Smith, John': 2,
      });
      expect(
        matchesBookFacets(book, {'tags': 'ürpertici', 'subjectPlaces': 'Roma'}),
        isTrue,
      );
      expect(matchesBookFacets(book, {'subjectPlaces': 'Paris'}), isFalse);
    },
  );
  test('legacy Open Library tags use raw source labels and respect explicit removal', () {
    final book = <String, dynamic>{
      'metadataSource': 'Open Library',
      'subjects': ['Roman'],
      'isbnApiData': {
        'subjects': [
          {'name': 'Fiction'},
          {'name': 'Creepy'},
        ],
      },
    };
    expect(bookFacetItems(book, 'tags'), ['Fiction', 'Creepy']);
    expect(bookFacetItems({...book, 'tags': <String>[]}, 'tags'), isEmpty);
    expect(book['subjects'], ['Roman']);
  });
  test('audio timestamps retain hours in long books', () {
    expect(
      audioTimestamp(const Duration(hours: 27, minutes: 3, seconds: 9)),
      '27:03:09',
    );
  });
  test('audio timestamps follow playback speed', () {
    expect(audioPlaybackTimestamp(const Duration(minutes: 10), 1.5), '0:06:40');
  });

  testWidgets('item input clears after add and keeps items as chips', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Roma\nSmith, John');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookItemsField(controller: controller, label: 'People'),
        ),
      ),
    );
    expect(find.text('Roma'), findsOneWidget);
    expect(find.text('Smith, John'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Ürpertici');
    await tester.tap(find.byTooltip('Add item'));
    await tester.pump();
    expect(controller.text, 'Roma\nSmith, John\nÜrpertici');
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      isEmpty,
    );
    expect(find.widgetWithText(InputChip, 'Ürpertici'), findsOneWidget);
  });
}
