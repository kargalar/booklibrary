import 'dart:async';
import 'dart:io';

import 'package:booklibrary/app/providers.dart';
import 'package:booklibrary/data/book_metadata.dart';
import 'package:booklibrary/data/book_repository.dart';
import 'package:booklibrary/data/borrower_repository.dart';
import 'package:booklibrary/data/library_book_snapshot.dart';
import 'package:booklibrary/data/library_stats.dart';
import 'package:booklibrary/data/social_repository.dart';
import 'package:booklibrary/viewmodels/library_view_model.dart';
import 'package:booklibrary/views/library_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
// Platform interfaces allow the real page to run without native Firebase.
// ignore: depend_on_referenced_packages
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bookTitle = 'The Test Book';
const _bookAuthor = 'Test Author';
const _userId = 'sheet-test-reader';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory storage;
  late _BookRepository repository;

  setUpAll(() {
    FirebasePlatform.instance = _FirebasePlatform();
    FirebaseAuthPlatform.instance = _AuthPlatform();
  });

  setUp(() async {
    storage = await Directory.systemTemp.createTemp('book_editor_sheet_');
    repository = _BookRepository();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => storage.path,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await storage.delete(recursive: true);
  });

  Future<void> openEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryViewModelProvider.overrideWithValue(
            LibraryViewModel(
              repository: repository,
              borrowers: _BorrowerRepository(),
            ),
          ),
          socialRepositoryProvider.overrideWithValue(_SocialRepository()),
        ],
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await tester.tap(find.text(_bookTitle), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit book'), findsOneWidget);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  testWidgets('title suggestions show and select the stored title and author', (
    tester,
  ) async {
    await openEditor(tester);
    final titleField = field('book name');
    await tester.ensureVisible(titleField);
    await tester.enterText(titleField, 'The Test');
    await tester.pumpAndSettle();
    final suggestion = find.widgetWithText(ListTile, _bookTitle);
    expect(suggestion, findsOneWidget);
    expect(
      find.descendant(of: suggestion, matching: find.text(_bookAuthor)),
      findsOneWidget,
    );
    await tester.tap(suggestion);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(titleField).controller!.text, _bookTitle);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('search shows busy state before the request completes', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.tap(find.byTooltip('Search by book name and author'));
    await tester.pump();
    expect(repository.searchCalls, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Search by ISBN',
            ),
          )
          .onPressed,
      isNull,
    );

    repository.search.complete([
      const BookMetadata(
        isbn: '9780140328721',
        title: 'Updated title',
        author: 'Updated author',
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester.widget<TextField>(field('book name')).controller!.text,
      'Updated title',
    );
    expect(repository.searchCalls, 1);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard leaves actions visible and editing retains focus', (
    tester,
  ) async {
    await openEditor(tester);
    final titleField = field('book name');
    await tester.ensureVisible(titleField);
    await tester.tap(titleField);
    await tester.pumpAndSettle();
    final focus = tester.widget<TextField>(titleField).focusNode!;
    expect(focus.hasFocus, isTrue);
    await tester.tap(titleField);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);

    tester.view.viewInsets = FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(844 - 320));
    expect(save.hitTestable(), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Edit book'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a search finishing after dismissal leaves the editor closed', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.tap(find.byTooltip('Search by book name and author'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    repository.search.complete([
      const BookMetadata(
        isbn: '9780140328721',
        title: 'Late result',
        author: _bookAuthor,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Edit book'), findsNothing);
    expect(find.text('Late result'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _BookRepository extends Fake implements BookRepository {
  late final search = Completer<List<BookMetadata>>();
  int searchCalls = 0;

  @override
  Stream<LibraryBookSnapshot> watch(String uid, {bool completedOnly = false}) =>
      Stream.value(
        LibraryBookSnapshot(_Snapshot(), [
          const LibraryBookDocument.local('book-1', {
            'title': _bookTitle,
            'author': _bookAuthor,
            'ownerId': _userId,
            'bookId': 'catalog-book-1',
            'status': readingStatus,
          }),
        ]),
      );

  @override
  Future<List<BookMetadata>> searchCatalog({String? title, String? isbn}) {
    searchCalls++;
    return search.future;
  }
}

class _BorrowerRepository extends Fake implements BorrowerRepository {}

class _SocialRepository extends Fake implements SocialRepository {
  @override
  Future<List<PersonalLibrary>> personalLibraries(String uid) async => const [
    PersonalLibrary(id: defaultPersonalLibraryId, name: defaultLibraryName),
  ];

  @override
  Future<UserProfile?> profile(String uid) async => null;

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> friendLinks(String uid) =>
      Stream.value(_Snapshot());

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> ratings(String bookId) =>
      Stream.value(_Snapshot());
}

class _Snapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => const [];
}

class _FirebasePlatform extends FirebasePlatform {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) =>
      FirebaseAppPlatform(
        name,
        const FirebaseOptions(
          apiKey: 'test',
          appId: 'test',
          messagingSenderId: 'test',
          projectId: 'test',
        ),
      );
}

class _AuthPlatform extends FirebaseAuthPlatform {
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAuthPlatform setInitialValues({
    InternalUserDetails? currentUser,
    String? languageCode,
  }) => this;

  @override
  UserPlatform get currentUser => _UserPlatform(this);
}

class _UserPlatform extends UserPlatform {
  _UserPlatform(FirebaseAuthPlatform auth)
    : super(
        auth,
        _MultiFactorPlatform(auth),
        InternalUserDetails(
          userInfo: InternalUserInfo(
            uid: _userId,
            isAnonymous: false,
            isEmailVerified: true,
          ),
          providerData: [],
        ),
      );
}

class _MultiFactorPlatform extends MultiFactorPlatform {
  _MultiFactorPlatform(super.auth);
}
