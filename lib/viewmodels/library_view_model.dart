import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/book_metadata.dart';
import '../data/book_repository.dart';
import '../data/borrower_repository.dart';
import '../data/library_book_snapshot.dart';
import '../data/library_stats.dart';

class LibraryViewModel extends ChangeNotifier {
  LibraryViewModel({BookRepository? repository, BorrowerRepository? borrowers})
    : _repository = repository ?? BookRepository(),
      _borrowers = borrowers ?? BorrowerRepository();
  final BookRepository _repository;
  final BorrowerRepository _borrowers;
  Stream<LibraryBookSnapshot> books(String uid) => _repository.watch(uid);
  Stream<List<CatalogBook>> discoverCatalog() =>
      _repository.watchDiscoverCatalog();
  Stream<Set<String>> libraryBookIds(String uid) =>
      _repository.watchLibraryBookIds(uid);
  Future<List<BookMatch>> findDuplicates({
    required String uid,
    required String title,
    String? isbn,
  }) => _repository.findDuplicates(uid: uid, title: title, isbn: isbn);
  Future<List<BookMetadata>> searchCatalog({String? title, String? isbn}) =>
      _repository.searchCatalog(title: title, isbn: isbn);
  String newLibraryBookId() => _repository.newLibraryBookId();
  Stream<QuerySnapshot<Map<String, dynamic>>> borrowers(String uid) =>
      _borrowers.watch(uid);
  Future<Borrower> addBorrower(String uid, String name) =>
      _borrowers.add(ownerId: uid, name: name.trim());
  Future<String> add(
    String uid,
    String title,
    String author, {
    BookMetadata? metadata,
    String? isbn,
    String? coverPath,
    bool wishlist = false,
    bool inHomeLibrary = true,
    List<String>? libraryIds,
    String? relationId,
  }) => _repository.add(
    uid: uid,
    title: title.trim(),
    author: author.trim(),
    metadata: metadata,
    isbn: isbn,
    coverPath: coverPath,
    wishlist: wishlist,
    inHomeLibrary: inHomeLibrary,
    libraryIds: libraryIds,
    relationId: relationId,
  );
  Future<void> update(String id, Map<String, dynamic> data) =>
      _repository.update(id, data);
  Future<void> setLibraryTargets(
    String uid,
    String id,
    Set<String> availableLibraryIds,
    Set<String> selectedLibraryIds,
  ) => _repository.setLibraryTargets(
    uid: uid,
    id: id,
    availableLibraryIds: availableLibraryIds,
    selectedLibraryIds: selectedLibraryIds,
  );
  Future<void> updateStatus(String id, String? status) =>
      _repository.updateStatus(id, status);
  Future<void> delete(String uid, String id) => _repository.delete(uid, id);
}
