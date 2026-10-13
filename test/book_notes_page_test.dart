import 'package:booklibrary/views/book_notes_page.dart';
import 'package:booklibrary/data/social_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('notes and quotes are saved in separate lists', (tester) async {
    List<String>? savedNotes;
    List<String>? savedQuotes;

    await tester.pumpWidget(
      MaterialApp(
        home: BookNotesPage(
          title: 'Deneme',
          notes: const [],
          quotes: const [],
          onSave: (notes, quotes) async {
            savedNotes = notes;
            savedQuotes = quotes;
          },
        ),
      ),
    );

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'İlk not');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add quote'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'İlk alıntı');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(savedNotes, ['İlk not']);
    expect(savedQuotes, ['İlk alıntı']);
    expect(find.text('İlk not'), findsOneWidget);
    expect(find.text('İlk alıntı'), findsOneWidget);
  });

  testWidgets('a scanned quote can be transferred into the quote editor', (
    tester,
  ) async {
    List<String>? savedQuotes;
    await tester.pumpWidget(
      MaterialApp(
        home: BookNotesPage(
          title: 'Deneme',
          notes: const [],
          quotes: const [],
          onSave: (_, quotes) async => savedQuotes = quotes,
          onScanQuote: () async => 'Fotoğraftan okunan alıntı',
        ),
      ),
    );

    await tester.tap(find.text('Add quote'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer from photo'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.controller?.text, 'Fotoğraftan okunan alıntı');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(savedQuotes, ['Fotoğraftan okunan alıntı']);
  });

  testWidgets('favorite button toggles and reports the new state', (
    tester,
  ) async {
    bool? favorite;
    await tester.pumpWidget(
      MaterialApp(
        home: BookNotesPage(
          title: 'Deneme',
          notes: const [],
          quotes: const [],
          onSave: (_, _) async {},
          onFavoriteChanged: (value) async => favorite = value,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Add to favorites'));
    await tester.pumpAndSettle();

    expect(favorite, isTrue);
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);
  });

  testWidgets('library move action is available in the book menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookNotesPage(
          title: 'Deneme',
          notes: const [],
          quotes: const [],
          onSave: (_, _) async {},
          onMoveToLibraries: () async {},
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Move to libraries'), findsOneWidget);
  });

  testWidgets('a reader can add a scored review', (tester) async {
    int? savedRating;
    String? savedReview;
    await tester.pumpWidget(
      MaterialApp(
        home: BookNotesPage(
          title: 'Deneme',
          notes: const [],
          quotes: const [],
          currentUserId: 'reader-1',
          myRating: 4,
          ratings: const [
            BookRating(userId: 'reader-1', userName: 'Okur', value: 4),
          ],
          onSave: (_, _) async {},
          onReview: (rating, review) async {
            savedRating = rating;
            savedReview = review;
          },
        ),
      ),
    );

    await tester.tap(find.text('Add review'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      'Çok akıcı bir kitaptı.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
    await tester.pumpAndSettle();

    expect(savedRating, 4);
    expect(savedReview, 'Çok akıcı bir kitaptı.');
  });
}
